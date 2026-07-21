import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:nodus/builder.dart';
import 'package:test/test.dart';

import 'support/test_package_config.dart';

void main() {
  initializeBuildTestEnvironment();

  test('Entity safely defaults to unbounded cardinality', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              'Cardinality get cardinality => '
              'Cardinality.unbounded',
            ),
            contains('LocalEntityQueryCache.database'),
            isNot(contains('ReadOnlyObservableList<Note> get all')),
          ]),
        ),
      },
    );
  });

  test('rejects an entity without a nominal ownership contract', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Note {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('@Entity classes must implement OwnedBy<Self, Owner>'),
    );
  });

  test('recognizes transitive ownership and lifecycle capabilities', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

abstract interface class AccountOwned<Self>
    implements OwnedBy<Self, Account> {}

abstract interface class Removable implements SoftDeletable {}

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements AccountOwned<Note>, Removable {}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('final LocalId<Note> id'),
            contains('LocalId<Account> get ownerId'),
            contains('Future<void> remove()'),
            contains('Future<void> restore()'),
          ]),
        ),
      },
    );
  });

  test('graph target infers one replicated binding per entity', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';
    final sources = _sources(source);

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains(
              "typeIdentity: 'package:nodus/nodus.g.dart#TestGraphSyncTarget'",
            ),
            contains("wireName: 'supabase'"),
            contains('entityType: \'Note\''),
            contains('mode: SyncMode.replicated'),
            contains('target: supabaseSyncTarget'),
            contains(
              'static final supabaseSyncDefinition = '
              'definition.syncSubgraphFor(',
            ),
            contains('required TestGraphSyncAdapters syncAdapters'),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
      },
    );
  });

  test('localOnly explicitly ignores a graph default target', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(sync: SyncMode.localOnly)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';
    final sources = _sources(source);

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('mode: SyncMode.localOnly'),
            isNot(contains('target: supabaseSyncTarget')),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
      },
    );
  });

  test('imported sync generates one minimal inbound adapter slot', () async {
    final sources = _sources(
      r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  sync: SyncMode.imported,
  grants: [RlsGrant(RlsOperation.select, RlsPrincipal.owner)],
)
abstract class ImportedNote implements OwnedBy<ImportedNote, Account> {}
''',
      fileName: 'imported_note.dart',
    )..['nodus|lib/account.dart'] = 'final class Account {}';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('final PullSyncAdapter supabase;'),
            isNot(contains('final PushSyncAdapter supabase;')),
            isNot(contains('final PushPullSyncAdapter')),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([contains('create table if not exists public.imported_notes')]),
        ),
      },
    );
  });

  test(
    'Supabase pull exposes only inbound entities on the same target',
    () async {
      final sources =
          _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  sync: SyncMode.imported,
  grants: [RlsGrant(RlsOperation.select, RlsPrincipal.owner)],
)
abstract class ImportedNote implements OwnedBy<ImportedNote, Account> {}
''', fileName: 'imported_note.dart')
            ..['nodus|lib/account.dart'] = 'final class Account {}'
            ..['nodus|lib/exported_note.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  sync: SyncMode.exported,
)
abstract class ExportedNote implements OwnedBy<ExportedNote, Account> {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains('create table if not exists public.imported_notes'),
              contains('create table if not exists public.exported_notes'),
              contains("when 'ImportedNote' then"),
              isNot(contains("when 'ExportedNote' then")),
            ]),
          ),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
        },
      );
    },
  );

  test('rejects an ad hoc sync-target enum outside nodus.lock', () async {
    const noteSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/sync_targets.dart';

@Entity(syncTarget: SecondaryTarget.convex)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';
    final sources = _sources(noteSource)
      ..['nodus|lib/sync_targets.dart'] = 'enum SecondaryTarget { convex }';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must use exactly one sync-target enum type'),
    );
  });

  test('rejects local mutation surfaces on imported projections', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  sync: SyncMode.imported,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
  ],
)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String title;
}

final class Account {}
''';
    final sources = _sources(source);

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('is imported and must be a read-only projection'),
    );
  });

  test('generates atomic typed domain actions for read-only fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

enum GoalStatus { active, completed }

@Entity(cardinality: Cardinality.bounded)
abstract class Goal implements OwnedBy<Goal, Account> {
  @Persisted(
    defaultValue: GoalStatus.active,
    transitions: [
      AllowedTransition(GoalStatus.active, GoalStatus.completed),
      AllowedTransition(GoalStatus.completed, GoalStatus.active),
    ],
  )
  abstract final GoalStatus status;

  abstract final DateTime? completedAt;
  abstract final DateTime? reviewedAt;
  abstract final String title;
  abstract final String? description;
  @Persisted(defaultValue: 0)
  abstract final int priority;
  abstract final DateTime updatedAt;

  @Action(values: [
    ActionValue(#status, GoalStatus.completed),
    ActionValue.clockNow(#completedAt),
  ])
  Future<void> complete();

  @Action(values: [
    ActionValue(#status, GoalStatus.active),
    ActionValue.clear(#completedAt),
  ])
  Future<void> reopen();

  @Action()
  Future<void> recordReview({required DateTime reviewedAt});
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'goal.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/goal.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<void> complete()'),
            contains('Future<void> reopen()'),
            isNot(contains('Future<void> edit({')),
            contains(
              'Future<void> recordReview({required DateTime reviewedAt})',
            ),
            contains(
              'return _generatedMutationCompletion(_generatedLocalCommit);',
            ),
            contains('ActionPolicyProvider'),
            contains('ActionPolicy get actionPolicy'),
            contains("fixedInitialValues: {'completedAt': null}"),
            isNot(contains("'description': null")),
            isNot(contains("'priority': 0")),
            contains('firstWriteOnly: true'),
            contains('final nextStatus = GoalStatus.completed;'),
            contains(
              'final nextCompletedAt = oldCompletedAt ?? _generatedActionTime;',
            ),
            contains('final syncPatch = GoalFields.status'),
            contains('.patch(nextStatus)'),
            contains('.merge(GoalFields.completedAt.patch(nextCompletedAt))'),
            contains('statusChanged &&'),
            contains('patch: syncPatch.merge(GoalFields.updatedAt.patch('),
            contains('mutable: true'),
            contains('LocalId<Goal> allocateId() => _engine.allocateId();'),
            contains(
              'Future<Goal> create({\n    LocalId<Goal>? id,\n    DateTime? reviewedAt,\n    required String title,\n    String? description,\n    int priority = 0,',
            ),
            contains("'ownerId': GoalFields.ownerId.encode(_ownerId),"),
            contains('principals: const [RlsPrincipal.owner],'),
            contains('id: id,'),
            contains("'completedAt': GoalFields.completedAt.encode(null)"),
            isNot(contains('set status(')),
            isNot(contains('set completedAt(')),
            contains('final class GoalMutationDraft'),
            contains('final EntityDraftField<String> _titleField;'),
            contains('set title(String value)'),
            contains('final EntityDraftField<String?> _descriptionField;'),
            contains('final EntityDraftField<int> _priorityField;'),
            contains('final EntityDraftField<DateTime?> _reviewedAtField;'),
          ]),
        ),
      },
    );
  });

  test(
    'infers ordinary drafts and keeps explicit creation facts read-only',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String title;

  @Persisted(editable: false)
  abstract final String importedSource;
}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains('NoteMutationDraft beginEdit()'),
              contains('final String? _baseTitle;'),
              isNot(contains('_baseImportedSource')),
              contains('entity.importedSource,'),
              contains('writable: false'),
              contains("name: 'importedSource'"),
              contains('mutable: false'),
            ]),
          ),
        },
      );
    },
  );

  test('rejects draft editability on fixed-action fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @Persisted(editable: true)
  abstract final String title;

  @Action(values: [ActionValue(#title, 'Untitled')])
  Future<void> resetTitle();
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('`title` cannot be draft-editable'),
    );
  });

  test('keeps ordinary action parameters draft-editable while guarding the '
      'exclusive action shape', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String title;

  @Persisted(editable: false)
  abstract final DateTime? reviewedAt;

  @Action(values: [ActionValue.clockNow(#reviewedAt)])
  Future<void> recordReview({required String title});
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('NoteMutationDraft beginEdit()'),
            contains('final EntityDraftField<String> _titleField;'),
            isNot(contains('_baseReviewedAt')),
            contains("fieldNames: const ['title', 'reviewedAt']"),
            contains("guardedFieldNames: const ['reviewedAt']"),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains("p_patch ? 'reviewedAt'"),
            isNot(contains("p_patch ? 'title'\n     and not")),
            contains("p_patch ?& array['title', 'reviewedAt']::text[]"),
          ]),
        ),
      },
    );
  });

  test('action targets use ordinary typed patches in generated SQL', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

enum GoalStatus { active, completed }

@Entity(cardinality: Cardinality.bounded)
abstract class Goal implements OwnedBy<Goal, Account> {
  @Persisted(
    defaultValue: GoalStatus.active,
    transitions: [
      AllowedTransition(GoalStatus.active, GoalStatus.completed),
    ],
  )
  abstract final GoalStatus status;
  abstract final DateTime? completedAt;

  @Action(values: [
    ActionValue(#status, GoalStatus.completed),
    ActionValue.clockNow(#completedAt),
  ])
  Future<void> complete();
}

final class Account {}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'goal.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              "status = case when p_operation = 'patch' and p_patch ? 'status'",
            ),
            contains(
              "completed_at = case when p_operation = 'patch' and p_patch ? 'completedAt'",
            ),
            contains("current_row.status = 'active'"),
            contains("(p_patch -> 'status' #>> '{}') = 'completed'"),
            contains("p_patch ?& array['status', 'completedAt']::text[]"),
            contains('current_row.completed_at is null'),
            contains('Invalid initial entity action state'),
            contains("Patch does not match a declared entity action"),
            isNot(contains('complete_goal')),
          ]),
        ),
      },
    );
  });

  test('rejects unsafe or ambiguous entity actions', () async {
    final cases = <(String, String)>[
      (
        'String title = "";\n  @Action()\n  Future<void> rename({required String title});',
        'Persisted entity field `title` must be declared final',
      ),
      (
        'abstract final String title;\n  @Action()\n  Future<void> rename({String title = ""});',
        'parameters must be required',
      ),
      (
        'abstract final String title;\n  @Action()\n  Future<void> rename({required int title});',
        'must match persisted field type',
      ),
      (
        'abstract final String title;\n  @Action()\n  Future<void> refresh();',
        'must mutate at least one field',
      ),
      (
        'abstract final String title;\n  @Action(values: [ActionValue.clockNow(#title)])\n  Future<void> stamp();',
        'clockNow requires a DateTime field',
      ),
      (
        'abstract final String title;\n  @Action(values: [ActionValue.clear(#title)])\n  Future<void> clearTitle();',
        'clear requires a nullable field',
      ),
      (
        '@Persisted(defaultValue: GoalStatus.active)\n  abstract final GoalStatus status;\n  @Action(values: [ActionValue(#status, OtherStatus.completed)])\n  Future<void> complete();',
        'must use its enum type `GoalStatus`',
      ),
      (
        'abstract final String title;\n  @Action()\n  void _rename({required String title});',
        'must be an abstract, non-generic Future<void> method',
      ),
      (
        'abstract final String title;\n  void beginEdit();\n  '
            '@Action()\n  Future<void> rename({required String title});',
        '`beginEdit` is reserved for the generated typed edit draft',
      ),
      (
        'abstract final String title;\n  '
            '@Action()\n  Future<void> edit({required String title});',
        '`edit` is not a semantic action name',
      ),
    ];

    for (final (declaration, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  $declaration
}

final class Account {}
enum GoalStatus { active, completed }
enum OtherStatus { completed }
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse, reason: declaration);
      expect(result.errors.join('\n'), contains(expected), reason: declaration);
    }
  });

  test('rejects private persisted fields across generated libraries', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String _secret;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Persisted entity fields must be public'),
    );
  });

  test('rejects an action that reuses the inferred remove command', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final bool archived;

  @Action(values: [ActionValue(#archived, true)])
  Future<void> remove();
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('conflicts with a SyncCommand method of the same name'),
    );
  });

  test('canonicalizes action timestamps before optimistic storage', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final DateTime? scheduledAt;

  @Action()
  Future<void> reschedule({required DateTime? scheduledAt});
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('final nextScheduledAt = scheduledAt?.toUtc();'),
            contains('_scheduledAtStore.value = nextScheduledAt;'),
          ]),
        ),
      },
    );
  });

  test('rejects persisted collection fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

enum ReminderInterval { oneDay, twoDays }

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  final List<String> labels = const [];
  final List<bool> flags = const [true];
  final List<int> ranks = const [1, 2];
  final List<ReminderInterval> reminders = const [ReminderInterval.oneDay];
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Persisted collection field `labels` is not supported'),
    );
  });

  test('rejects ambiguous or relational collection shapes', () async {
    final cases = <(String, String)>[
      (
        'final List<String?> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
      (
        'final List<double> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
      (
        'final List<DateTime> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
      (
        'final List<LocalId<Tag>> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
      (
        'final List<List<String>> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
      (
        '@Indexed()\n  final List<String> values = const [];',
        'Persisted collection field `values` is not supported',
      ),
    ];

    for (final (declaration, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  $declaration
}

final class Account {}
final class Tag {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse, reason: declaration);
      expect(result.errors.join('\n'), contains(expected), reason: declaration);
    }
  });

  test('rejects collection persistence before compound indexes', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [CompoundIndex([#values, #name])],
)
abstract class Note implements OwnedBy<Note, Account> {
  final List<String> values = const [];
  final String name = '';
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Persisted collection field `values` is not supported'),
    );
  });

  test(
    'infers every mechanical entity default from Dart declarations',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(sinceProtocolVersion: 2)
  final bool pinned = true;

}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains("String get tableName => 'notes'"),
              contains('int get protocolVersion => 2'),
              contains('Future<void> remove()'),
              contains('Future<void> restore()'),
              contains("name: 'serverVersion'"),
              isNot(contains('serverGenerated:')),
              isNot(contains('@DriftDatabase')),
            ]),
          ),
        },
      );
    },
  );

  test(
    'generates closed String value constraints from one annotation',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

const colors = ['red', 'blue'];

@Entity(cardinality: Cardinality.bounded)
abstract class Tag implements OwnedBy<Tag, Account> {
  @Persisted(allowedValues: colors)
  final String color = 'red';
}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'tag.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/tag.entity.g.dart': decodedMatches(
            allOf([
              contains(r"CHECK (color IN (\'red\', \'blue\'))"),
              contains("!(const {'red', 'blue'}).contains(color)"),
            ]),
          ),
        },
      );
    },
  );

  test('rejects invalid closed String value declarations', () async {
    final cases = <(String, String)>[
      (
        "@Persisted(allowedValues: const ['1'])\n  final int value = 1;",
        '`allowedValues` is only valid for String fields.',
      ),
      (
        "@Persisted(allowedValues: const ['one', 'one'])\n"
            "  final String value = 'one';",
        '`allowedValues` must not contain duplicates.',
      ),
      (
        "@Persisted(minLength: 2, allowedValues: const [''])\n"
            "  final String value = '';",
        'must satisfy its length bounds.',
      ),
      (
        "@Persisted(allowedValues: const ['one'])\n  final String value = 'two';",
        'must be in `allowedValues`.',
      ),
    ];

    for (final (declaration, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  $declaration
}

final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse, reason: declaration);
      expect(result.errors.join('\n'), contains(expected), reason: declaration);
    }
  });

  test('supports whitespace-significant text from one constraint', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Operation implements OwnedBy<Operation, Account> {
  @Persisted(minLength: 1, allowWhitespace: true)
  abstract final String text;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'operation.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/operation.entity.g.dart': decodedMatches(
          allOf([
            contains("'CHECK (length(text) >= 1)'"),
            contains('allowWhitespace: true'),
            contains('text.length < 1'),
            isNot(contains('text.trim().length < 1')),
          ]),
        ),
      },
    );
  });

  test(
    'accepts an exceptional complete grant set directly on Entity',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.delete, RlsPrincipal.owner),
  ],
)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {'nodus|lib/note.entity.g.dart': decodedMatches(anything)},
      );
    },
  );

  test('accepts an explicit authenticated graph-sync override', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  authenticatedReadSync: AuthenticatedReadSync.graph,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.authenticated),
  ],
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {'nodus|lib/note.entity.g.dart': decodedMatches(anything)},
    );
  });

  test('rejects authenticated sync config without its read grant', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  authenticatedReadSync: AuthenticatedReadSync.onDemand,
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        '`authenticatedReadSync` is only meaningful with an authenticated '
        'select grant.',
      ),
    );
  });

  test('infers computed getters as non-persistent domain behavior', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final String body;

  bool get isBlank => body.trim().isEmpty;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains("name: 'body'"),
            isNot(contains("name: 'isBlank'")),
            isNot(contains('get isBlank =>')),
          ]),
        ),
      },
    );
  });

  test('infers enum storage, codec, default, and constraints', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

enum NoteKind { idea, finalDecision }

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  final NoteKind kind = NoteKind.idea;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('NoteKind kind = NoteKind.idea'),
            contains('encode: (value) => switch (value)'),
            contains("'final_decision' => NoteKind.finalDecision"),
            contains("NoteKind.finalDecision => 'final_decision'"),
            contains('CHECK (kind IN ('),
            contains('idea'),
            contains('final_decision'),
            contains('PersistedEqualityEntityField<Note, NoteKind>'),
          ]),
        ),
      },
    );
  });

  test(
    'server-authoritative fields are read-only and omitted from creates',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

enum ReviewStatus { open, resolved }

@Entity(cardinality: Cardinality.bounded)
abstract class Review implements OwnedBy<Review, Account> {
  abstract final String message;

  @Persisted(authority: FieldAuthority.server)
  final ReviewStatus status = ReviewStatus.open;
}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'review.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/review.entity.g.dart': decodedMatches(
            allOf([
              contains("name: 'status'"),
              contains('inCreatePayload: false'),
              contains('protocolDefault: \'open\''),
              contains(
                'Future<Review> create({\n'
                '    LocalId<Review>? id,\n'
                '    required String message,\n'
                '    DateTime? deletedAt,\n'
                '  })',
              ),
              contains('ReviewStatus status = ReviewStatus.open'),
              isNot(contains('set status(')),
            ]),
          ),
        },
      );
    },
  );

  test(
    'supports server-maintained read-only entities without push RPCs',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [RlsGrant(RlsOperation.select, RlsPrincipal.owner)],
)
abstract class Progress implements OwnedBy<Progress, Account> {
  @Persisted(
    authority: FieldAuthority.server,
    defaultValue: 0,
    minValue: 0,
  )
  abstract final int count;
}

final class Account {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'progress.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains('create table if not exists public.progresses'),
              contains("when 'Progress' then (changes.owner_id = auth.uid())"),
              isNot(contains('push_progresses_operations')),
              isNot(contains('upcast_progresses_operation')),
            ]),
          ),
        },
      );
    },
  );

  test('rejects mutable persisted fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Review implements OwnedBy<Review, Account> {
  @Persisted(authority: FieldAuthority.server)
  String status = 'open';
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'review.dart'),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Persisted entity field `status` must be declared final'),
    );
  });

  test('rejects non-null server authority without a default', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Review implements OwnedBy<Review, Account> {
  @Persisted(authority: FieldAuthority.server)
  abstract final String status;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'review.dart'),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Non-null server-authoritative `status` needs a local and SQL default',
      ),
    );
  });

  test('generates nullable and required integer bounds', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(defaultValue: 0, minValue: 0, maxValue: 1439)
  abstract final int minute;

  @Persisted(minValue: 1, maxValue: 10)
  abstract final int? optionalRank;

}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains("'CHECK (minute >= 0)'"),
            contains("'CHECK (minute <= 1439)'"),
            contains('if (nextMinute < 0)'),
            contains('if (nextOptionalRank != null && nextOptionalRank < 1)'),
            contains('remoteMinute = NoteFields.minute.decode'),
          ]),
        ),
      },
    );
  });

  test('infers native finite real storage and numeric bounds', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(defaultValue: 50.0, minValue: 0, maxValue: 100)
  abstract final double score;

  @Persisted(minValue: 0, maxValue: 100)
  abstract final double? optionalScore;

}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('RealColumn get score =>'),
            contains("real().named('score')"),
            contains('kind: EntityFieldKind.real'),
            contains("'CHECK (score >= 0)'"),
            contains(
              'if (nextOptionalScore != null && nextOptionalScore > 100)',
            ),
            contains('required double? optionalScore'),
            contains('double score = 50.0'),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('score double precision not null default 50.0'),
            contains('optional_score double precision'),
            contains('check (score <= 100)'),
          ]),
        ),
      },
    );
  });

  test('generates a typed cross-field numeric invariant', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class TimeBlock implements OwnedBy<TimeBlock, Account>, SoftDeletable {
  abstract final int startMinutes;

  @Persisted(greaterThan: #startMinutes)
  abstract final int endMinutes;

}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains("'CHECK (end_minutes > start_minutes)'"),
            contains('if ((endMinutes) <= (startMinutes))'),
            contains(
              'if ((endMinutesChanged ? nextEndMinutes : endMinutes) <=',
            ),
            contains(
              '(startMinutesChanged ? nextStartMinutes : startMinutes))',
            ),
            contains('hasEndMinutes ? remoteEndMinutes : endMinutes'),
            contains('hasStartMinutes ? remoteStartMinutes : startMinutes'),
          ]),
        ),
      },
    );
  });

  test(
    'generates an inclusive nullable cross-field numeric invariant',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class NumericRange implements OwnedBy<NumericRange, Account>, SoftDeletable {
  abstract final double? minimum;

  @Persisted(greaterThanOrEqual: #minimum)
  abstract final double? maximum;

}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains("'CHECK (maximum >= minimum)'"),
              contains('_generatedCrossFieldMaximumValue != null &&'),
              contains('_generatedCrossFieldMinimumForMaximumValue != null &&'),
              contains('_generatedCrossFieldMaximumValue <'),
              contains(
                "message: 'Must be greater than or equal to `minimum`.'",
              ),
            ]),
          ),
        },
      );
      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            contains('check (maximum >= minimum)'),
          ),
        },
      );
    },
  );

  test(
    'promotes nullable cross-field values before numeric comparison',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class TimeBlock implements OwnedBy<TimeBlock, Account>, SoftDeletable {
  abstract final int? startMinutes;

  @Persisted(greaterThan: #startMinutes, requires: #startMinutes)
  abstract final int? endMinutes;

}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains('final _generatedCrossFieldEndMinutesValue ='),
              contains(
                'final _generatedCrossFieldStartMinutesForEndMinutesValue =',
              ),
              contains('(hasEndMinutes ? remoteEndMinutes : endMinutes)'),
              contains('(hasStartMinutes'),
              contains('? remoteStartMinutes'),
              contains(': startMinutes);'),
              contains('_generatedCrossFieldEndMinutesValue != null &&'),
              contains(
                '_generatedCrossFieldStartMinutesForEndMinutesValue != '
                'null &&',
              ),
              contains('_generatedCrossFieldEndMinutesValue <='),
              contains(
                "'CHECK (end_minutes IS NULL OR start_minutes IS NOT NULL)'",
              ),
              contains("message: 'Requires `startMinutes`.'"),
            ]),
          ),
        },
      );
    },
  );

  test('generates a typed cross-field inequality invariant', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Review implements OwnedBy<Review, Account> {
  @Persisted(notEqualTo: #ownerId)
  abstract final LocalId<Account> reviewerId;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              "'CHECK (reviewer_id IS NULL OR owner_id IS NULL OR reviewer_id <> owner_id)'",
            ),
            contains('if ((reviewerId) == (ownerId))'),
            contains('Must differ from `ownerId`.'),
          ]),
        ),
      },
    );
  });

  test('generates mutually exclusive nullable fields across storage', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  exclusiveFieldGroups: [ExclusiveFieldGroup([#goalId, #habitId])],
)
abstract class Reward implements OwnedBy<Reward, Account> {
  abstract final LocalId<Goal>? goalId;
  abstract final LocalId<Habit>? habitId;
}

final class Account {}
final class Goal {}
final class Habit {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              "'CHECK (CASE WHEN goal_id IS NOT NULL THEN 1 ELSE 0 END + "
              "CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END <= 1)'",
            ),
            contains(
              '((goalId) != null ? 1 : 0) + '
              '((habitId) != null ? 1 : 0) > 1',
            ),
            contains('hasGoalId'),
            contains('remoteGoalId'),
            contains('hasHabitId'),
            contains('remoteHabitId'),
          ]),
        ),
      },
    );
  });

  test('generates an exactly-one nullable field group', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  exclusiveFieldGroups: [
    ExclusiveFieldGroup([#taskId, #habitId], allowNone: false),
  ],
)
abstract class NextAction implements OwnedBy<NextAction, Account> {
  abstract final LocalId<Task>? taskId;
  abstract final LocalId<Habit>? habitId;
}

final class Account {}
final class Task {}
final class Habit {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              'CHECK (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END + '
              'CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END = 1)',
            ),
            contains('Exactly one of `taskId`, `habitId` may be set.'),
          ]),
        ),
      },
    );
  });

  test('generates a canonical date-only codec and typed field', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Plan implements OwnedBy<Plan, Account> {
  abstract final LocalDate planDate;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('kind: EntityFieldKind.date'),
            contains('encode: (value) => value.value'),
            contains('LocalDate.parse((source)! as String)'),
            contains('PersistedComparableEntityField<Plan, LocalDate>'),
          ]),
        ),
      },
    );
  });

  test('rejects invalid mutually exclusive field declarations', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  exclusiveFieldGroups: [ExclusiveFieldGroup([#goalId, #missing])],
)
abstract class Reward implements OwnedBy<Reward, Account> {
  abstract final LocalId<Goal> goalId;
}

final class Account {}
final class Goal {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      anyOf(contains('is not persisted'), contains('must be nullable')),
    );
  });

  test('rejects an invalid cross-field numeric invariant', () async {
    const missingSource = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(greaterThan: #missing)
  abstract final int rank;
}

final class Account {}
''';
    final missing = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(missingSource),
      rootPackage: 'nodus',
    );
    expect(missing.succeeded, isFalse);
    expect(missing.errors.join('\n'), contains('must name another'));

    const incompatibleSource = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final String title;

  @Persisted(greaterThan: #title)
  abstract final int rank;
}

final class Account {}
''';
    final incompatible = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(incompatibleSource),
      rootPackage: 'nodus',
    );
    expect(incompatible.succeeded, isFalse);
    expect(
      incompatible.errors.join('\n'),
      contains('between fields of the same numeric type'),
    );
  });

  test('rejects an incompatible inclusive numeric invariant', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class NumericRange implements OwnedBy<NumericRange, Account>, SoftDeletable {
  abstract final String minimum;

  @Persisted(greaterThanOrEqual: #minimum)
  abstract final double maximum;
}

final class Account {}
''';
    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('between fields of the same numeric type'),
    );
  });

  test('rejects an invalid nullable field dependency', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final int? start;

  @Persisted(requires: #missing)
  abstract final int? end;
}

final class Account {}
''';
    final missing = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(missing.succeeded, isFalse);
    expect(missing.errors.join('\n'), contains('must name another'));

    const nonNullableSource = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final int? start;

  @Persisted(requires: #start)
  abstract final int end;
}

final class Account {}
''';
    final nonNullable = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(nonNullableSource),
      rootPackage: 'nodus',
    );
    expect(nonNullable.succeeded, isFalse);
    expect(
      nonNullable.errors.join('\n'),
      contains('only meaningful between nullable fields'),
    );
  });

  test('rejects invalid numeric bounds and defaults', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(minValue: 10, maxValue: 5)
  final int rank = 0;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('cannot be less than'));
  });

  test('rejects persisted types without a complete generated codec', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final Money budget;
}

extension type Money(int cents) {}
final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Unsupported persisted type `Money`'),
    );
  });

  test('infers native storage for persisted scalar value objects', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

final class Money implements PersistedScalarValue<int> {
  const Money(this.cents);

  const Money.fromScalar(this.cents);

  final int cents;

  @override
  int toScalar() => cents;
}

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(defaultValue: 0, minValue: 0, maxValue: 1000000)
  abstract final Money budget;

  @Persisted(minValue: 0, maxValue: 1000000)
  abstract final Money? estimate;

}

final class Account {}
''';

    final sources = _sources(source);
    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('IntColumn get budget =>'),
            contains("integer().named('budget')"),
            contains('kind: EntityFieldKind.integer'),
            contains('Money budget = const Money.fromScalar(0)'),
            contains('Money.fromScalar(switch (source)'),
            contains('value.toScalar()'),
            contains('nextEstimate?.toScalar()'),
            contains('final validatedEstimate = remoteEstimate?.toScalar();'),
            contains('validatedEstimate != null &&'),
            contains('EqualityEntityField<Note, Money>'),
            isNot(contains('json_valid(budget)')),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('budget bigint not null default 0'),
            contains('check (budget >= 0)'),
            contains('check (budget <= 1000000)'),
            contains('estimate bigint'),
            isNot(contains('budget jsonb')),
          ]),
        ),
      },
    );
  });

  test('rejects incomplete persisted scalar value contracts', () async {
    final cases = <(String, String)>[
      (
        '''
final class Money implements PersistedScalarValue<int> {
  @override int toScalar() => 0;
}
''',
        'must expose exactly one named `fromScalar` constructor',
      ),
      (
        '''
final class Money implements PersistedScalarValue<List<Object?>> {
  Money.fromScalar(List<Object?> value);
  @override List<Object?> toScalar() => const [];
}
''',
        'Use String, bool, int, or double',
      ),
      (
        '''
final class Money implements PersistedScalarValue<int> {
  Money.fromScalar(num value);
  @override int toScalar() => 0;
}
''',
        'must accept one required positional',
      ),
      (
        '''
class Money implements PersistedScalarValue<int> {
  Money.fromScalar(int value);
  @override int toScalar() => 0;
}
''',
        'must be a concrete final value type',
      ),
      (
        '''
final class Money implements PersistedScalarValue<int> {
  Money.fromScalar(this.value);
  final int value;
  @override int toScalar() => value;
}
''',
        'must be const for the generated optional parameter default',
      ),
    ];

    for (final (valueDeclaration, message) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

$valueDeclaration

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(defaultValue: 0)
  abstract final Money budget;
}

final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse);
      expect(result.errors.join('\n'), contains(message));
    }
  });

  test('rejects JSON and object persistence', () async {
    const cases = <(String, String)>[
      ('JsonMap', 'Map<String, Object?>'),
      ('Metadata', 'Metadata'),
    ];
    for (final (fieldType, diagnosticType) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

final class Metadata {
  const Metadata();
}

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final $fieldType metadata;
}

final class Account {}
''';

      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('Unsupported persisted type `$diagnosticType`'),
      );
    }
  });

  test('rejects explicit defaults that disagree with the Dart type', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @Persisted(defaultValue: 1)
  abstract final String title;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('defaultValue must be a `String` constant'),
    );
  });

  test('generates entities without a handwritten graph declaration', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, includeGraph: false),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isTrue);
    expect(
      result.outputs,
      contains(AssetId('nodus', 'lib/note.entity.g.dart')),
    );
  });

  test('infers one package graph from nodus.lock', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';
    final sources = _sources(source, includeGraph: false)
      ..[r'nodus|$package$'] = ''
      ..['nodus|nodus.lock'] = '''
{
  "formatVersion": 1,
  "packageName": "nodus",
  "graphName": "Nodus",
  "schemaVersion": 1,
  "schemaFingerprint": null,
  "targets": ["supabase"],
  "defaultTarget": "supabase"
}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(
          allOf([
            contains("export 'package:nodus/nodus_flutter.dart';"),
            contains("export 'src/generated/nodus.runtime.g.dart';"),
            contains('// Schema fingerprint: '),
          ]),
        ),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('final class NodusEntityGraph'),
            contains('enum NodusSyncTarget { supabase }'),
            contains("part 'nodus.runtime.g.drift.dart';"),
            contains('static Future<NodusEntityGraph> openWithConnectors'),
            contains('static Future<NodusEntityGraph> openSupabase'),
            contains('definition: context.definition'),
            contains('// Schema fingerprint: '),
          ]),
        ),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          contains('"graph": "Nodus"'),
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(
          contains('final class NodusTestHarness'),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          contains('create table if not exists public.notes'),
        ),
      },
    );
  });

  test('infers a managed connector factory for a custom target', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';
    final sources = _sources(source, includeGraph: false)
      ..[r'nodus|$package$'] = ''
      ..['nodus|nodus.lock'] = '''
{
  "formatVersion": 1,
  "packageName": "nodus",
  "graphName": "Nodus",
  "schemaVersion": 1,
  "schemaFingerprint": null,
  "targets": ["rest_api"],
  "defaultTarget": "rest_api"
}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(
          contains("export 'src/generated/nodus.runtime.g.dart';"),
        ),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains("import 'package:nodus/nodus_flutter.dart';"),
            isNot(contains("package:nodus/nodus_supabase.dart")),
            contains('enum NodusSyncTarget { restApi }'),
            contains('static Future<NodusEntityGraph> openRestApi'),
            contains('required SyncConnector<PushPullSyncAdapter> connector'),
            contains('definition: NodusMetadata.restApiSyncDefinition'),
            contains('syncAdapters.bind()'),
          ]),
        ),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          allOf([contains('"targets"'), contains('"rest_api"')]),
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(
          contains('final InMemorySyncBackend restApi'),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          contains('No sync target named `supabase`'),
        ),
      },
    );
  });

  test('rejects collaborator grants without collaboration opt-in', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.collaborator),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.delete, RlsPrincipal.owner),
  ],
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('requires CollaborationAccess metadata'),
    );
  });

  test('accepts immutable typed participant access fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @AccessParticipant()
  abstract final LocalId<Account> inviteeId;

  @Persisted(defaultValue: InvitationStatus.pending, transitions: [
    AllowedTransition(
      InvitationStatus.pending,
      InvitationStatus.accepted,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(InvitationStatus.pending, InvitationStatus.declined),
  ])
  abstract final InvitationStatus status;

  @Action(values: [ActionValue(#status, InvitationStatus.accepted)])
  Future<void> accept();

  @Action(values: [ActionValue(#status, InvitationStatus.declined)])
  Future<void> decline();
}

final class Account {}
enum InvitationStatus { pending, accepted, declined }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  test(
    'composition derives one aggregate-owned component relationship',
    () async {
      final sources =
          _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/document.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Task implements OwnedBy<Task, Account> {
  @Composition(inverse: 'task')
  abstract final LocalId<Document> documentId;

  @Composition(inverse: 'summaryTask')
  abstract final LocalId<Document> summaryId;
}
''', fileName: 'task.dart')
            ..['nodus|lib/account.dart'] = 'final class Account {}'
            ..['nodus|lib/document.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity()
abstract class Document implements OwnedBy<Document, Account>, Component {
  abstract final String body;

}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/document.entity.g.dart': decodedMatches(
            allOf([
              contains('if (!_engine.isInMutationTransaction)'),
              contains('A Component must be created inside an entity-graph'),
              contains('Future<Document> create({'),
              contains('required String body'),
              contains('DateTime? get deletedAt => _deletedAtStore.value;'),
              contains('DocumentFields.deletedAt.isNull'),
              isNot(contains('OrderRank get generatedOrderRank')),
              contains('principals: const [RlsPrincipal.owner]'),
              contains('principals: const [RlsPrincipal.relationship]'),
            ]),
          ),
          'nodus|lib/task.entity.g.dart': decodedMatches(
            allOf([
              contains('composition: true'),
              contains('ReferenceDeleteAction.restrict'),
              contains(
                'CREATE UNIQUE INDEX tasks_document_id_idx ON tasks '
                '(document_id)',
              ),
            ]),
          ),
        },
      );

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains('CREATE TRIGGER tasks_document_id_composition_insert'),
              contains('Composition component owner mismatch'),
              contains('Component identity already belongs to an aggregate'),
              contains('CREATE TRIGGER tasks_document_id_composition_cleanup'),
              contains('WHERE NEW.summary_id = NEW.document_id'),
              contains('await configured.onCreate(m);'),
              contains('_installCompositionTriggers(replace: false)'),
              contains('await configured.onUpgrade(m, from, to);'),
              contains('_installCompositionTriggers(replace: true)'),
              contains(
                'DROP TRIGGER IF EXISTS tasks_document_id_composition_insert',
              ),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'document_id uuid not null references public.documents (id) '
                'on delete restrict',
              ),
              contains(
                'create unique index if not exists tasks_document_id_idx',
              ),
              contains(
                "public.is_documents_owner((current_operation -> 'patch' "
                "->> 'documentId')::uuid)",
              ),
              contains('public.is_documents_relationship_select'),
              contains('documents_insert_owner'),
              isNot(contains('documents_select_owner')),
              isNot(contains('documents_update_owner')),
              isNot(contains('documents_delete_owner')),
              contains('documents_select_relationship'),
              contains('documents_update_relationship'),
              contains('public.is_tasks_owner'),
              contains('public.is_tasks_collaborator'),
              contains('public.enforce_tasks_document_id_composition()'),
              contains('public.cleanup_tasks_document_id_composition()'),
              contains('where new.summary_id = new.document_id'),
              contains('pg_catalog.pg_advisory_xact_lock('),
              contains('pg_catalog.hashtextextended(new.document_id::text, 0)'),
              contains('pg_catalog.hashtextextended(old.document_id::text, 0)'),
            ]),
          ),
        },
      );
    },
  );

  test('renames Drift getters that collide with table members', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Paragraph implements OwnedBy<Paragraph, Account> {
  abstract final String text;
  abstract final String textColumn;
  abstract final int integer;
  abstract final double real;
  abstract final bool boolean;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'paragraph.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/paragraph.entity.g.dart': decodedMatches(
          allOf([
            contains("TextColumn get id => text().named('id')()"),
            contains(
              "TextColumn get textColumnColumn => text().named('text')()",
            ),
            contains(
              "TextColumn get textColumn => text().named('text_column')()",
            ),
            contains(
              "IntColumn get integerColumn => integer().named('integer')()",
            ),
            contains("RealColumn get realColumn => real().named('real')()"),
            contains(
              "BoolColumn get booleanColumn => boolean().named('boolean')()",
            ),
          ]),
        ),
      },
    );
  });

  test('rejects a composition target without Component capability', () async {
    final sources =
        _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/document.dart';

@Entity()
abstract class Task implements OwnedBy<Task, Account> {
  @Composition()
  abstract final LocalId<Document> documentId;
}
''', fileName: 'task.dart')
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/document.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity()
abstract class Document implements OwnedBy<Document, Account> {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('@Composition target `Document` must implement Component'),
    );
  });

  test('rejects an unattached Component in the entity graph', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Document implements OwnedBy<Document, Account>, Component {}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'document.dart'),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Component `Document` is not owned by any @Composition field'),
    );
  });

  test('derives relationship access and ownership from typed references', () async {
    const dependencySource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/project.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class ProjectDependency
    implements OwnedBy<ProjectDependency, Account>, SoftDeletable {
  @OwnerReference()
  @AccessReference()
  @Reference(
    inverse: 'dependencies',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Project> projectId;

  @AccessReference()
  @Reference(
    inverse: 'requiredBy',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Project> requiredProjectId;
}
''';
    final sources =
        _sources(dependencySource, fileName: 'project_dependency.dart')
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/project.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Project implements OwnedBy<Project, Account> {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/project.entity.g.dart': decodedMatches(anything),
        'nodus|lib/project_dependency.entity.g.dart': decodedMatches(
          allOf([
            contains(
              RegExp(
                r'Future<ProjectDependency> create\(\{\s*'
                r'LocalId<ProjectDependency>\? id,\s*'
                r'required LocalId<Project> projectId,\s*'
                r'required LocalId<Project> requiredProjectId,\s*\}\)',
              ),
            ),
            isNot(
              contains(
                "import 'package:nodus/project.entity.g.dart';\n"
                "import 'package:nodus/project.entity.g.dart';",
              ),
            ),
            contains('const ProjectDescriptor()'),
            contains('final inferredOwnerId = ownershipSource.ownerId;'),
            contains(
              "'ownerId': ProjectDependencyFields.ownerId.encode(inferredOwnerId)",
            ),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              'create or replace function '
              'public.is_project_dependencies_reference(p_id uuid)',
            ),
            contains('public.is_projects_owner(entity.project_id)'),
            contains('public.is_projects_collaborator(entity.project_id)'),
            contains('public.is_projects_owner(entity.required_project_id)'),
            contains(
              'entity.owner_id = (select target.owner_id from '
              'public.projects target where target.id = entity.project_id)',
            ),
            contains('project_dependencies_select_reference'),
            contains(
              'public.is_project_dependencies_reference(changes.entity_id)',
            ),
            contains(
              "(current_operation -> 'patch' ->> 'ownerId')::uuid = "
              '(select target.owner_id from public.projects target where '
              "target.id = (current_operation -> 'patch' ->> 'projectId')::uuid)",
            ),
            contains(
              'create or replace function '
              'public.publish_projects_reference_access(',
            ),
            contains("changes.entity_type = 'ProjectDependency'"),
            contains(
              'not (entity.owner_id = p_user_id or '
              '(exists (select 1 from public.projects access_project_id',
            ),
            contains('create trigger project_members_publish_reference_access'),
          ]),
        ),
      },
    );
  });

  test(
    'derives ownership from exactly-one targets and a referenced identity field',
    () async {
      const reviewSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/project.dart';
import 'package:nodus/project_member.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.insert, RlsPrincipal.reference),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
  exclusiveFieldGroups: [
    ExclusiveFieldGroup([#projectId, #projectMemberId], allowNone: false),
  ],
)
abstract class Review implements OwnedBy<Review, Account> {
  @OwnerReference()
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Project>? projectId;

  @OwnerReference(targetField: #memberId)
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<ProjectMember>? projectMemberId;

  @AccessParticipant()
  abstract final LocalId<Account> reviewerId;
}
''';
      final sources = _sources(reviewSource, fileName: 'review.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/project.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Project implements OwnedBy<Project, Account> {}
'''
        ..['nodus|lib/project_member.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/project.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
  ],
)
abstract class ProjectMember implements OwnedBy<ProjectMember, Account> {
  @OwnerReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Project> projectId;

  @AccessParticipant()
  abstract final LocalId<Account> memberId;
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'entity.owner_id = (select target.owner_id from '
                'public.projects target where target.id = entity.project_id)',
              ),
              contains(
                'entity.owner_id = (select target.member_id from '
                'public.project_members target where '
                'target.id = entity.project_member_id)',
              ),
              contains(
                '(public.is_projects_owner((current_operation -> '
                "'patch' ->> 'projectId')::uuid)) or",
              ),
            ]),
          ),
        },
      );

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/review.entity.g.dart': decodedMatches(
            allOf([
              contains('late final LocalId<Account> inferredOwnerId;'),
              contains('inferredOwnerId = ownershipSource.ownerId;'),
              contains('inferredOwnerId = ownershipSource.memberId;'),
            ]),
          ),
          'nodus|lib/project.entity.g.dart': decodedMatches(anything),
          'nodus|lib/project_member.entity.g.dart': decodedMatches(anything),
        },
      );
    },
  );

  test('guards actor-owned writes with referenced aggregate access', () async {
    const completionSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/habit.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.reference),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.delete, RlsPrincipal.owner),
  ],
  referenceAccessGuards: [
    RlsOperation.update,
    RlsOperation.delete,
  ],
)
abstract class HabitCompletion
    implements OwnedBy<HabitCompletion, Account>, SoftDeletable {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Habit> habitId;

  abstract final String note;
}
''';
    final sources =
        _sources(completionSource, fileName: 'habit_completion.dart')
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/habit.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Habit implements OwnedBy<Habit, Account> {}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              "if (current_operation -> 'patch') ? 'habitId' "
              'and jsonb_typeof',
            ),
            contains(
              "raise exception 'Referenced entity access denied' "
              "using errcode = '42501'",
            ),
            contains(
              'habit_completions_update_owner on public.habit_completions '
              'for update to authenticated using '
              '(((select auth.uid()) = owner_id) and '
              '((public.is_habits_owner(habit_completions.habit_id))))',
            ),
            contains(
              'habit_completions_delete_owner on public.habit_completions '
              'for delete to authenticated using '
              '(((select auth.uid()) = owner_id) and '
              '((public.is_habits_owner(habit_completions.habit_id))))',
            ),
            contains(
              'public.is_habit_completions_owner(p_id)) and '
              'public.is_habit_completions_reference(p_id)',
            ),
            contains(
              "public.is_habits_owner((current_operation -> 'patch' ->> "
              "'habitId')::uuid)",
            ),
          ]),
        ),
      },
    );
  });

  test('validates reference access write guards', () async {
    const cases = <(String, String)>[
      (
        'referenceAccessGuards: [RlsOperation.select],',
        'supports update and delete only',
      ),
      (
        'referenceAccessGuards: [RlsOperation.insert],',
        'create reference access is already inferred',
      ),
      (
        'referenceAccessGuards: [RlsOperation.update, RlsOperation.update],',
        'operations must be unique',
      ),
      (
        'referenceAccessGuards: [RlsOperation.update],',
        'requires at least one immutable @AccessReference',
      ),
    ];

    for (final (configuration, message) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: const [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
  ],
  $configuration
)
abstract class Item implements OwnedBy<Item, Account> {
  abstract final String name;
}

final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse);
      expect(result.errors.join('\n'), contains(message));
    }
  });

  test('rejects a reference guard for an ungranted write', () async {
    const source = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/parent.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [RlsGrant(RlsOperation.select, RlsPrincipal.reference)],
  referenceAccessGuards: [RlsOperation.update],
)
abstract class Item implements OwnedBy<Item, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Parent> parentId;
}
''';
    final sources = _sources(source)
      ..['nodus|lib/parent.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Parent implements OwnedBy<Parent, Account> {}
'''
      ..['nodus|lib/account.dart'] = 'final class Account {}';
    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('Missing grants: update'));
  });

  test('derives target access through an active normalized relationship', () async {
    const linkSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';
import 'package:nodus/task.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class GoalTaskLink
    implements OwnedBy<GoalTaskLink, Account> {
  @OwnerReference()
  @AccessReference()
  @Reference(
    inverse: 'taskLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Goal> goalId;

  @AccessTarget()
  @Reference(
    inverse: 'goalLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Task> taskId;

  @Persisted(defaultValue: true)
  abstract final bool active;
}
''';
    final sources = _sources(linkSource, fileName: 'goal_task_link.dart')
      ..['nodus|lib/account.dart'] = 'final class Account {}'
      ..['nodus|lib/goal.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Goal implements OwnedBy<Goal, Account> {}
'''
      ..['nodus|lib/task.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  collaboration: CollaborationAccess(),
)
abstract class Task implements OwnedBy<Task, Account>, SoftDeletable {
  abstract final String title;
}
'''
      ..['nodus|lib/task_event.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/task.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.reference),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
  ],
)
abstract class TaskEvent implements OwnedBy<TaskEvent, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;
}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              'create or replace function '
              'public.is_tasks_relationship_select(p_id uuid)',
            ),
            contains(
              'create or replace function '
              'public.is_tasks_relationship_update(p_id uuid)',
            ),
            contains(
              'create or replace function '
              'public.is_tasks_relationship_delete(p_id uuid)',
            ),
            contains(
              'from public.goal_task_links access_path_0 where '
              'access_path_0.task_id = p_id and access_path_0.active',
            ),
            contains('access_goal_id.owner_id = auth.uid()'),
            contains(
              'member.goal_id = access_goal_id.id and '
              'member.user_id = auth.uid()',
            ),
            contains('tasks_select_relationship'),
            contains('tasks_update_relationship'),
            contains('tasks_delete_relationship'),
            contains('public.is_tasks_relationship_select(changes.entity_id)'),
            contains(
              'public.is_tasks_relationship_select(task_events.task_id)',
            ),
            contains(
              "public.is_tasks_relationship_select((current_operation -> "
              "'patch' ->> 'taskId')::uuid)",
            ),
            contains(
              'create or replace function '
              'public.publish_tasks_relationship_access(',
            ),
            contains('create trigger goal_task_links_task_id_publish_access'),
            contains(
              'after insert or update of task_id, goal_id, active, '
              'deleted_at or delete',
            ),
            contains(
              'for audience_user_id in select distinct candidate.user_id',
            ),
            contains(
              'perform public.publish_tasks_relationship_access(\n'
              '    entity.task_id, p_user_id',
            ),
            contains(
              "public.is_tasks_owner((current_operation -> 'patch' ->> 'taskId')::uuid)",
            ),
            contains(
              "public.is_tasks_collaborator((current_operation -> 'patch' ->> 'taskId')::uuid)",
            ),
          ]),
        ),
      },
    );

    final missingSource = Map<String, String>.from(sources)
      ..['nodus|lib/goal_task_link.dart'] = linkSource.replaceFirst(
        '  @AccessReference()\n',
        '',
      );
    final invalid = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      missingSource,
      rootPackage: 'nodus',
    );
    expect(invalid.succeeded, isFalse);
    expect(
      invalid.errors.join('\n'),
      contains(
        'declares @AccessTarget but has no @AccessReference or '
        '@AccessParticipant source',
      ),
    );
  });

  test(
    'derives workflow target access from a finite participant audience',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/project.dart';

enum ReviewStatus { pending, accepted, declined, revoked }

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.insert, RlsPrincipal.reference),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class Review implements OwnedBy<Review, Account> {
  @OwnerReference()
  @AccessTarget(
    operations: [RlsOperation.select],
    activeStates: [ReviewStatus.pending, ReviewStatus.accepted],
  )
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Project> projectId;

  @AccessParticipant()
  abstract final LocalId<Account> reviewerId;

  @Persisted(
    defaultValue: ReviewStatus.pending,
    transitions: [
      AllowedTransition(
        ReviewStatus.pending,
        ReviewStatus.accepted,
        by: [RlsPrincipal.participant],
      ),
    ],
  )
  abstract final ReviewStatus status;

  @Action(values: [ActionValue(#status, ReviewStatus.accepted)])
  Future<void> accept();
}
''';
      final sources = _sources(source, fileName: 'review.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/project.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Project implements OwnedBy<Project, Account> {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains('access_path_0.reviewer_id = auth.uid()'),
              contains("access_path_0.status in ('pending', 'accepted')"),
              contains('select new.reviewer_id as user_id'),
              contains('auth.uid() = reviews.reviewer_id'),
              contains(
                "auth.uid() = (current_operation -> 'patch' ->> "
                "'reviewerId')::uuid",
              ),
              contains(
                'after insert or update of project_id, reviewer_id, status',
              ),
              contains(
                "public.is_projects_owner((current_operation -> 'patch' ->> "
                "'projectId')::uuid)",
              ),
            ]),
          ),
        },
      );
    },
  );

  test(
    'propagates relationship access through an acyclic entity chain',
    () async {
      final sources =
          _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';
import 'package:nodus/task.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class GoalTaskLink implements OwnedBy<GoalTaskLink, Account> {
  @OwnerReference()
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Goal> goalId;

  @AccessTarget()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;

  @Persisted(defaultValue: true)
  abstract final bool active;
}
''', fileName: 'goal_task_link.dart')
            ..['nodus|lib/account.dart'] = 'final class Account {}'
            ..['nodus|lib/goal.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Goal implements OwnedBy<Goal, Account> {}
'''
            ..['nodus|lib/task.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Task implements OwnedBy<Task, Account> {}
'''
            ..['nodus|lib/note.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}
'''
            ..['nodus|lib/note_task_link.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/note.dart';
import 'package:nodus/task.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class NoteTaskLink implements OwnedBy<NoteTaskLink, Account> {
  @OwnerReference()
  @AccessTarget(operations: [RlsOperation.select, RlsOperation.update])
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Note> noteId;

  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;

  @Persisted(defaultValue: true)
  abstract final bool active;
}
'''
            ..['nodus|lib/note_event.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/note.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  grants: [RlsGrant(RlsOperation.select, RlsPrincipal.reference)],
)
abstract class NoteEvent implements OwnedBy<NoteEvent, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Note> noteId;
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'create or replace function '
                'public.is_notes_relationship_select(p_id uuid)',
              ),
              contains(
                'grant execute on function '
                'public.is_notes_relationship_select(uuid) to authenticated',
              ),
              contains(
                'perform public.publish_tasks_reference_access(\n'
                '    p_target_id,\n'
                '    p_user_id',
              ),
              contains(
                'perform public.publish_notes_reference_access(\n'
                '    p_target_id,\n'
                '    p_user_id',
              ),
              predicate<String>(
                (sql) =>
                    RegExp(r'(?:from|join) public\.[a-z0-9_]+ ([a-z0-9_]+)')
                        .allMatches(sql)
                        .every((match) => match.group(1)!.length <= 63),
                'keeps every generated PostgreSQL alias within 63 bytes',
              ),
              contains('cross join lateral (select'),
              contains('.task_id = new.task_id'),
              isNot(
                contains(
                  'audience_note_task_links_1_path_1_goal_task_links_source_1_member',
                ),
              ),
            ]),
          ),
        },
      );
    },
  );

  test('derives access through an immutable referenced bridge field', () async {
    final sources =
        _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/task_member.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
  ],
)
abstract class Review implements OwnedBy<Review, Account> {
  @OwnerReference(targetField: #memberId)
  @AccessTarget(
    operations: [RlsOperation.select],
    targetField: #taskId,
  )
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<TaskMember> taskMemberId;

  @AccessParticipant()
  abstract final LocalId<Account> reviewerId;
}
''', fileName: 'review.dart')
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/task.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Task implements OwnedBy<Task, Account> {}
'''
          ..['nodus|lib/task_member.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/task.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
  ],
)
abstract class TaskMember implements OwnedBy<TaskMember, Account> {
  @OwnerReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;

  @AccessParticipant()
  abstract final LocalId<Account> memberId;
}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              'create or replace function '
              'public.is_task_members_relationship_select(p_id uuid)',
            ),
            contains('access_path_0.task_member_id = p_id'),
            contains(
              'create or replace function '
              'public.is_tasks_relationship_select(p_id uuid)',
            ),
            contains('from public.task_members access_bridge'),
            contains('access_bridge.task_id = p_id'),
            contains(
              'perform public.publish_task_members_relationship_access(',
            ),
            contains('perform public.publish_tasks_relationship_access('),
          ]),
        ),
      },
    );
  });

  test('rejects cycles in relationship-derived access', () async {
    final sources =
        _sources(r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/document.dart';
import 'package:nodus/project.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class ProjectDocumentLink
    implements OwnedBy<ProjectDocumentLink, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Project> projectId;

  @AccessTarget()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Document> documentId;
}
''', fileName: 'project_document_link.dart')
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/project.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Project implements OwnedBy<Project, Account> {}
'''
          ..['nodus|lib/document.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Document implements OwnedBy<Document, Account> {}
'''
          ..['nodus|lib/document_project_link.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/document.dart';
import 'package:nodus/project.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class DocumentProjectLink
    implements OwnedBy<DocumentProjectLink, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Document> documentId;

  @AccessTarget()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Project> projectId;
}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      allOf([
        contains('Relationship-derived access graph is cyclic:'),
        contains('Project'),
        contains('Document'),
      ]),
    );
  });

  test(
    'derives relationship ownership from its access target independently',
    () async {
      const linkSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/note.dart';
import 'package:nodus/task.dart';

@Entity(
  cardinality: Cardinality.unbounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.reference),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.reference),
  ],
)
abstract class NoteTaskLink implements OwnedBy<NoteTaskLink, Account> {
  @OwnerReference()
  @AccessTarget(operations: [RlsOperation.select, RlsOperation.update])
  @Reference(
    inverse: 'taskLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Note> noteId;

  @AccessReference()
  @Reference(
    inverse: 'noteLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Task> taskId;

  @Persisted(defaultValue: true)
  abstract final bool active;
}
''';
      final sources = _sources(linkSource, fileName: 'note_task_link.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/note.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}
'''
        ..['nodus|lib/task.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Task implements OwnedBy<Task, Account> {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'owner_id = (select ownership_target.owner_id from '
                'public.notes ownership_target where ownership_target.id = '
                'entity.note_id)',
              ),
              contains('is_notes_relationship_select'),
              contains('is_notes_relationship_update'),
              contains('access_path_0.task_id'),
            ]),
          ),
        },
      );
    },
  );

  test(
    'infers OR authorization for exactly-one reference alternatives',
    () async {
      const reviewSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';
import 'package:nodus/habit.dart';

@Entity(
  cardinality: Cardinality.bounded,
  exclusiveFieldGroups: [
    ExclusiveFieldGroup([#goalId, #habitId], allowNone: false),
  ],
)
abstract class Review implements OwnedBy<Review, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Goal>? goalId;

  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Habit>? habitId;
}
''';
      final sources = _sources(reviewSource, fileName: 'review.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/goal.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Goal implements OwnedBy<Goal, Account> {}
'''
        ..['nodus|lib/habit.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Habit implements OwnedBy<Habit, Account> {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                '(public.is_goals_owner(entity.goal_id)) or '
                '(public.is_habits_owner(entity.habit_id))',
              ),
              contains(
                "when 'Review' then (changes.owner_id = auth.uid() or "
                'public.is_reviews_reference(changes.entity_id))',
              ),
            ]),
          ),
        },
      );
    },
  );

  test(
    'rejects nullable access references without an exactly-one group',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Review implements OwnedBy<Review, Account> {
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Goal>? goalId;
}
''';
      final sources = _sources(source, fileName: 'review.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/goal.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Goal implements OwnedBy<Goal, Account> {}
''';

      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains(
          'must belong to an exactly-one ExclusiveFieldGroup containing only '
          'access references',
        ),
      );
    },
  );

  test('rejects access metadata on a non-reference field', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @AccessReference()
  abstract final String projectId;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('@AccessReference requires an immutable @Reference'),
    );
  });

  test('rejects transition actors without matching update grants', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
  ],
)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(defaultValue: InvitationStatus.pending, transitions: [
    AllowedTransition(
      InvitationStatus.pending,
      InvitationStatus.accepted,
      by: [RlsPrincipal.participant],
    ),
  ])
  abstract final InvitationStatus status;

  @Action(values: [ActionValue(#status, InvitationStatus.accepted)])
  Future<void> accept();
}

final class Account {}
enum InvitationStatus { pending, accepted }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('without a matching update RLS grant'),
    );
  });

  test(
    'accepts field-specific update principals with matching grants',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class Friendship implements OwnedBy<Friendship, Account> {
  @AccessParticipant()
  abstract final LocalId<Account> friendId;

  @Persisted(updateBy: [RlsPrincipal.owner])
  abstract final bool ownerShares;

  @Action()
  Future<void> configure({required bool ownerShares});
}

final class Account {}
''';

      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    },
  );

  test('rejects field update principals without matching grants', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Friendship implements OwnedBy<Friendship, Account> {
  @Persisted(updateBy: [RlsPrincipal.participant])
  abstract final bool ownerShares;

  @Action()
  Future<void> configure({required bool ownerShares});
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('without a matching update RLS grant'),
    );
  });

  test('infers an update grant for an ordinary draft field', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Friendship implements OwnedBy<Friendship, Account> {
  @Persisted(updateBy: [RlsPrincipal.owner])
  abstract final bool ownerShares;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isTrue);
  });

  test('requires a single inferred initial state for transitions', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(transitions: [
    AllowedTransition(InvitationStatus.pending, InvitationStatus.accepted),
  ])
  abstract final InvitationStatus status;
}

final class Account {}
enum InvitationStatus { pending, accepted }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must declare its single initial state'),
    );
  });

  test('rejects malformed enum transition graphs', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(transitions: [
    AllowedTransition(InvitationStatus.pending, InvitationStatus.pending),
  ])
  final InvitationStatus status = InvitationStatus.pending;
}

final class Account {}
enum InvitationStatus { pending, accepted }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('cannot declare a no-op'));
  });

  test('rejects transitions on non-enum fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(transitions: [AllowedTransition('pending', 'accepted')])
  abstract final String status;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('require a non-null enum field'));
  });

  test('rejects read-only transitions without a generated action', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(
    defaultValue: InvitationStatus.pending,
    transitions: [
      AllowedTransition(InvitationStatus.pending, InvitationStatus.accepted),
    ],
  )
  abstract final InvitationStatus status;
}

final class Account {}
enum InvitationStatus { pending, accepted }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must be mutable or targeted by an Action'),
    );
  });

  test('rejects transition values from a different enum type', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @Persisted(transitions: [
    AllowedTransition(OtherStatus.pending, InvitationStatus.accepted),
  ])
  final InvitationStatus status = InvitationStatus.pending;
}

final class Account {}
enum InvitationStatus { pending, accepted }
enum OtherStatus { pending, accepted }
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must use values from `InvitationStatus`'),
    );
  });

  test('rejects participant grants without a participant field', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
  ],
)
abstract class Invitation implements OwnedBy<Invitation, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('requires at least one immutable @AccessParticipant'),
    );
  });

  test('rejects participant fields without a participant grant', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @AccessParticipant()
  abstract final LocalId<Account> inviteeId;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('has no effect without a participant RLS grant'),
    );
  });

  test('rejects participant inserts under owner-scoped creation', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.participant),
  ],
)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @AccessParticipant()
  abstract final LocalId<Account> inviteeId;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Participant inserts are not supported'),
    );
  });

  test('rejects mutable or incorrectly typed participant fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
  ],
)
abstract class Invitation implements OwnedBy<Invitation, Account> {
  @AccessParticipant()
  abstract final LocalId<OtherAccount> inviteeId;
}

final class Account {}
final class OtherAccount {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('@AccessParticipant requires LocalId<Account>'),
    );
  });

  test('rejects a non-nominal OwnedBy self type', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Account, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must use the declaring entity as its exact Self type'),
    );
  });

  test('infers field sync commands as delete operations', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @SyncCommand(
    targetField: 'deletedAt',
    value: SyncCommandValue.clockNow,
  )
  Future<void> withdraw();
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<void> withdraw()'),
            contains('operation: SyncMutationOperation.delete'),
            contains('final commandValue = _clock.nowUtc()'),
            isNot(contains('RlsOperation.update')),
          ]),
        ),
      },
    );
  });

  test('generates a reversible conventional tombstone lifecycle', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<void> remove()'),
            contains('Future<void> restore()'),
            contains('if (oldValue != null) return Future.value();'),
            contains('if (oldValue == null) return Future.value();'),
            contains('const DateTime? commandValue = null;'),
            predicate<String>(
              (output) =>
                  'operation: SyncMutationOperation.delete'
                      .allMatches(output)
                      .length ==
                  2,
              'uses ordered delete-authorized operations for remove and restore',
            ),
          ]),
        ),
      },
    );
  });

  test('supports an explicit clear-valued tombstone command', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  @SyncCommand(targetField: 'deletedAt', value: SyncCommandValue.clear)
  Future<void> recover();
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<void> recover()'),
            contains('const DateTime? commandValue = null;'),
            contains('operation: SyncMutationOperation.delete'),
          ]),
        ),
      },
    );
  });

  test('rejects clear-valued commands for non-null fields', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, SoftDeletable {
  abstract final String state;

  @SyncCommand(targetField: 'state', value: SyncCommandValue.clear)
  Future<void> clearState();
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must declare no parameters and target a nullable field'),
    );
  });

  test('rejects malformed clock-valued commands at generation time', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @SyncCommand(
    targetField: 'deletedAt',
    value: SyncCommandValue.clockNow,
  )
  Future<void> removeAt(DateTime now);
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must declare no parameters and target a timestamp field'),
    );
  });

  test('rejects command signatures the generator cannot preserve', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @SyncCommand(
    targetField: 'deletedAt',
    value: SyncCommandValue.clockNow,
  )
  void removeLater();
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must be a non-generic Future<void> method'),
    );
  });

  test('rejects named command values at generation time', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @SyncCommand(targetField: 'deletedAt')
  Future<void> removeAt({required DateTime value});
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must use one required positional parameter'),
    );
  });

  test('rejects mutable command targets as persisted state', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract String status;

  @SyncCommand(targetField: 'status')
  Future<void> withdraw(String value);
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Persisted entity field `status` must be declared final'),
    );
  });

  test('rejects names reserved by generated collaboration APIs', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess(),
)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String collaborators;

}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('reserved for the generated collaboration API'),
    );
  });

  test(
    'identity ownership derives owner from id and omits unsupported APIs',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  ownership: Ownership.identity,
)
abstract class Profile implements OwnedBy<Profile, Profile> {
  abstract final String displayName;
}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains('LocalId<Profile> get ownerId => id;'),
              isNot(contains("name: 'ownerId'")),
              isNot(contains('Profile create({')),
              isNot(contains('Future<void> remove()')),
            ]),
          ),
        },
      );
    },
  );

  test('identity ownership rejects a distinct owner type', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  ownership: Ownership.identity,
)
abstract class Profile implements OwnedBy<Profile, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must use the declaring entity as the exact OwnedBy Owner'),
    );
  });

  test('non-deletable entities reject delete grants', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.delete, RlsPrincipal.owner),
  ],
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Delete RLS grants require SoftDeletable'),
    );
  });

  test(
    'updatedAt is maintained locally but excluded from trusted sync',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final String body;
  abstract final DateTime updatedAt;

}

final class Account {}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(
            allOf([
              contains(
                'syncPatch.merge(NoteFields.updatedAt.patch(mutationTime))',
              ),
              contains('syncPatch: syncPatch'),
              contains('_updatedAtStore.value = mutationTime'),
              contains('_updatedAtStore.value = oldUpdatedAt'),
              isNot(contains('set updatedAt(')),
              isNot(contains('required DateTime updatedAt,\n  }) {')),
            ]),
          ),
        },
      );
    },
  );
  test('rejects owner-scoped indexes for identity-owned entities', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  ownership: Ownership.identity,
)
abstract class Note implements OwnedBy<Note, Note> {
  @Indexed(unique: true, scope: IndexScope.owner)
  abstract final String key;
}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('cannot use an owner-scoped index'),
    );
  });

  test('generates compound indexes from persisted field symbols', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [
    CompoundIndex.query([#createdAt]),
    CompoundIndex.query([#deletedAt, #createdAt]),
  ],
)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final DateTime createdAt;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              'CREATE INDEX notes_created_at_id_idx '
              'ON notes (created_at, id)',
            ),
            contains(
              'CREATE INDEX notes_deleted_at_created_at_id_idx '
              'ON notes (deleted_at, created_at, id)',
            ),
          ]),
        ),
      },
    );
  });

  test('generates one unordered owner-pair uniqueness contract', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [CompoundIndex.unorderedWithOwner(#friendId)],
)
abstract class Friendship
    implements OwnedBy<Friendship, Account>, SoftDeletable {
  abstract final LocalId<Account> friendId;
}

final class Account {}
''';
    final sources = _sources(source, fileName: 'friendship.dart');

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/friendship.entity.g.dart': decodedMatches(
          allOf([
            contains(
              'CREATE UNIQUE INDEX '
              'friendships_unordered_owner_id_friend_id_active_idx '
              'ON friendships (min(owner_id, friend_id), '
              'max(owner_id, friend_id)) WHERE deleted_at IS NULL',
            ),
            contains('unordered: true'),
            contains("fieldName: 'deletedAt'"),
            contains('values: [null]'),
            contains("'CHECK (owner_id <> friend_id)'"),
            contains("message: 'Must differ from the owner.'"),
            contains('if ((hasOwnerId ? remoteOwnerId : ownerId) =='),
            contains('(hasFriendId ? remoteFriendId : friendId))'),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              'create unique index if not exists '
              'friendships_unordered_owner_id_friend_id_active_idx on '
              'public.friendships (least(owner_id, friend_id), '
              'greatest(owner_id, friend_id)) where deleted_at is null;',
            ),
            contains('check (owner_id <> friend_id)'),
          ]),
        ),
      },
    );
  });

  test('rejects unordered owner pairs with another nominal identity', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [CompoundIndex.unorderedWithOwner(#targetId)],
)
abstract class Friendship implements OwnedBy<Friendship, Account> {
  abstract final LocalId<Target> targetId;
}

final class Account {}
final class Target {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'friendship.dart'),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'requires one immutable, non-null LocalId<Owner> field on a '
        'separately owned entity',
      ),
    );
  });

  test('generates typed conditional unique indexes', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [
    CompoundIndex(
      [#taskKey],
      unique: true,
      condition: IndexCondition.oneOf(
        #status,
        [AssignmentStatus.pending, AssignmentStatus.accepted],
      ),
    ),
  ],
)
abstract class Assignment implements OwnedBy<Assignment, Account> {
  final String taskKey = '';
  final AssignmentStatus status = AssignmentStatus.pending;
}

enum AssignmentStatus { pending, accepted, declined, revoked }
final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains(
              'CREATE UNIQUE INDEX '
              'assignments_task_key_where_status_values_',
            ),
            contains(r"WHERE status IN (\'pending\', \'accepted\')"),
            contains('EntityUniqueConstraintCondition('),
            contains("fieldName: 'status'"),
            contains("values: const ['pending', 'accepted']"),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains(
              'create unique index if not exists '
              'assignments_task_key_where_status_values_',
            ),
            contains("where status in ('pending', 'accepted')"),
          ]),
        ),
      },
    );
  });

  test('rejects invalid conditional index declarations', () async {
    final cases = <(String, String)>[
      (
        'IndexCondition.oneOf(#missing, [AssignmentStatus.pending])',
        'field must be a persisted field symbol',
      ),
      ('IndexCondition.oneOf(#status, [])', 'values must be a non-empty set'),
      (
        'IndexCondition.oneOf(#status, [AssignmentStatus.pending, AssignmentStatus.pending])',
        'values must be a non-empty set',
      ),
      (
        'IndexCondition.oneOf(#status, [OtherStatus.pending])',
        'constants of its exact persisted type',
      ),
    ];

    for (final (condition, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [
    CompoundIndex([#taskKey], unique: true, condition: $condition),
  ],
)
abstract class Assignment implements OwnedBy<Assignment, Account> {
  final String taskKey = '';
  final AssignmentStatus status = AssignmentStatus.pending;
}

enum AssignmentStatus { pending, accepted, declined, revoked }
enum OtherStatus { pending }
final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse, reason: condition);
      expect(result.errors.join('\n'), contains(expected), reason: condition);
    }
  });

  test('rejects invalid compound index declarations', () async {
    final cases = <(String, String)>[
      ('CompoundIndex([#createdAt])', 'requires at least two field symbols'),
      ('CompoundIndex.query([])', 'requires at least one field symbol'),
      (
        'CompoundIndex([#createdAt, #missing])',
        'field `missing` is not persisted',
      ),
      ('CompoundIndex([#createdAt, #createdAt])', 'cannot repeat a field'),
      (
        'CompoundIndex.query([#createdAt, #id])',
        'do not declare it explicitly',
      ),
    ];

    for (final (declaration, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [$declaration],
)
abstract class Note implements OwnedBy<Note, Account> {
  abstract final DateTime createdAt;
}

final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse, reason: declaration);
      expect(result.errors.join('\n'), contains(expected), reason: declaration);
    }
  });

  test('rejects owner-scoped compound indexes for identity entities', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  ownership: Ownership.identity,
  indexes: [
    CompoundIndex([#createdAt, #updatedAt], scope: IndexScope.owner),
  ],
)
abstract class Note implements OwnedBy<Note, Note> {
  abstract final DateTime createdAt;
  abstract final DateTime updatedAt;
}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'cannot use owner scope when entity ownership is identity-based',
      ),
    );
  });

  test(
    'rejects inferred entity-set accessors that collide with graph APIs',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class PersistenceFailure
    implements OwnedBy<PersistenceFailure, Account> {}

final class Account {}
''';

      final result = await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'persistence_failure.dart'),
        rootPackage: 'nodus',
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains(
          'Entity-set accessor `persistenceFailures` conflicts with a '
          'generated entity-graph member',
        ),
      );
    },
  );

  test('rejects multiple authenticated owner types in one graph', () async {
    const first = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/accounts.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}
''';
    const second = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/accounts.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Audit implements OwnedBy<Audit, Admin> {}
''';
    final sources = _sources(first, fileName: 'note.dart')
      ..['nodus|lib/audit.dart'] = second
      ..['nodus|lib/accounts.dart'] =
          'final class Account {}\nfinal class Admin {}';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Every separately owned entity in one graph must use the same '
        'OwnedBy Owner type',
      ),
    );
  });

  test(
    'accepts an explicit entity-set accessor for an inferred collision',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  setAccessor: 'domainFailures',
)
abstract class PersistenceFailure
    implements OwnedBy<PersistenceFailure, Account> {}

final class Account {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'persistence_failure.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            contains('final PersistenceFailureSet domainFailures;'),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            isNot(contains("'commandName' = 'replaceRelationship'")),
          ),
        },
      );
    },
  );

  test('rejects entity names that collide with generated list types', () async {
    const taskSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Task implements OwnedBy<Task, Account> {}
''';
    const taskListSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class TaskList implements OwnedBy<TaskList, Account> {}
''';
    final sources = _sources(taskSource, fileName: 'task.dart')
      ..['nodus|lib/task_list.dart'] = taskListSource
      ..['nodus|lib/account.dart'] = 'final class Account {}';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Generated collection type `TaskList` conflicts'),
    );
  });

  test(
    'derives an irregular entity-set accessor from table vocabulary',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  table: 'people',
)
abstract class Person implements OwnedBy<Person, Account> {}

final class Account {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'person.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains('final PersonSet people;'),
              isNot(contains('final PersonSet persons;')),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
        },
      );
    },
  );

  test('reuses table vocabulary for inferred inverse accessors', () async {
    const personSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/group.dart';

@Entity(
  cardinality: Cardinality.bounded,
  table: 'people',
)
abstract class Person implements OwnedBy<Person, Account> {
  @Reference(onDelete: ReferenceDeleteAction.restrict)
  abstract final LocalId<Group> groupId;
}
''';
    final sources = _sources(personSource, fileName: 'person.dart')
      ..['nodus|lib/account.dart'] = 'final class Account {}'
      ..['nodus|lib/group.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Group implements OwnedBy<Group, Account> {}
''';

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('final class GroupPeople extends EntityList<Person>'),
            contains('GroupPeople people('),
            contains('return GroupPeople('),
            contains('Future<Person> create('),
            contains('groupId: _groupId'),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
      },
    );
  });

  test(
    'accepts a typed self-reference without treating it as a graph cycle',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Goal implements OwnedBy<Goal, Account> {
  @Reference(
    inverse: 'subgoals',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Goal>? parentGoalId;
}

final class Account {}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'goal.dart'),
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains('extension GoalGoalParentGoalIdInverseRelationship'),
              contains('final class GoalSubgoals extends EntityList<Goal>'),
              contains('GoalSubgoals subgoals('),
              contains('return GoalSubgoals('),
              contains('parentGoalId: _parentGoalId'),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            contains(
              'parent_goal_id uuid references public.goals (id) '
              'on delete set null deferrable initially deferred',
            ),
          ),
        },
      );
    },
  );

  test('binds inverse references in generated child creation APIs', () async {
    const parentSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Parent implements OwnedBy<Parent, Account> {}
''';
    const childSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/parent.dart';

@Entity(orderScope: [#parentId])
abstract class Child implements OwnedBy<Child, Account>, Ordered {
  @OwnerReference()
  @Reference(inverse: 'parentChildren', onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Parent> parentId;

  abstract final String label;

  @Persisted(defaultValue: false)
  abstract final bool highlighted;
}
''';
    final sources = _sources(childSource, fileName: 'child.dart')
      ..['nodus|lib/account.dart'] = 'final class Account {}'
      ..['nodus|lib/parent.dart'] = parentSource;

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('final class ParentChildren extends EntityList<Child>'),
            isNot(contains('final class ParentParentChildren')),
            contains('Future<Child> create({'),
            contains('Future<Child> createFirst({'),
            contains('required String label'),
            contains('bool highlighted = false'),
            contains('parentId: _parentId'),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
      },
    );

    final collisionSources =
        _sources(
            childSource.replaceFirst(
              "inverse: 'parentChildren'",
              "inverse: 'list'",
            ),
            fileName: 'child.dart',
          )
          ..['nodus|lib/account.dart'] = 'final class Account {}'
          ..['nodus|lib/parent.dart'] = parentSource;
    final collision = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      collisionSources,
      rootPackage: 'nodus',
    );
    expect(collision.succeeded, isFalse);
    expect(
      collision.errors.join('\n'),
      contains('Generated inverse creation type `ParentList`'),
    );
  });

  test(
    'generates one durable mutation handle for conventional active relationships',
    () async {
      const noteSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}
''';
      final sources = _sources(noteSource, fileName: 'note.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/task_tag.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class TaskTag implements OwnedBy<TaskTag, Account> {}
'''
        ..['nodus|lib/note_tag_link.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/note.dart';
import 'package:nodus/task_tag.dart';

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [CompoundIndex([#noteId, #taskTagId], unique: true)],
)
abstract class NoteTagLink
    implements OwnedBy<NoteTagLink, Account>, Activatable, Ordered {
  @OwnerReference()
  @Reference(
    inverse: 'tagLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Note> noteId;

  @Reference(
    inverse: 'noteLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<TaskTag> taskTagId;

}
''';

      await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/note.entity.g.dart': decodedMatches(anything),
          'nodus|lib/task_tag.entity.g.dart': decodedMatches(anything),
          'nodus|lib/note_tag_link.entity.g.dart': decodedMatches(
            allOf([
              contains('_engine.createInGeneratedOrder('),
              contains('required LocalId<Note> noteId'),
              contains('noteId: noteId'),
              contains('Future<NoteTagLink> createFirst('),
              contains("final value = fields['noteId']"),
              contains(
                'field: NoteTagLinkFields._activePersistence,\n'
                '      value: true,',
              ),
              contains(
                'bool get generatedIsOrderMember =>\n'
                '      _deletedAtStore.value == null && _activeStore.value;',
              ),
              contains(
                'String get generatedOrderScopeKey => '
                '_noteIdStore.value.value',
              ),
            ]),
          ),
        },
      );

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains(
                'final class NoteTagLinkRelationship '
                'extends EntityList<NoteTagLink>',
              ),
              contains(
                'static const noteTagLinkRelationship = '
                'RelationshipDefinition(',
              ),
              contains('RelationshipCardinalityResolution.boundedByLinkEntity'),
              contains('Future<void> link(LocalId<TaskTag> targetId)'),
              contains('Future<void> unlink(LocalId<TaskTag> targetId)'),
              contains(
                'Future<void> replace(Iterable<LocalId<TaskTag>> targetIds)',
              ),
              contains(
                'ReplaceActiveRelationshipCommand<NoteTagLink, Note, TaskTag>',
              ),
              contains('_coordinator.replaceActiveRelationship('),
              contains('.recordGeneratedExactOrder('),
              isNot(contains('await _entityGraph.noteTagLinks.reorder(')),
              contains('Future<void> moveBefore('),
              contains('Future<void> moveAfter('),
              contains('await _entityGraph.noteTagLinks.create('),
              contains('await existing.activate();'),
              contains('await existing.deactivate();'),
              contains('noteId: _noteId'),
              contains('taskTagId: targetId'),
              contains('NoteTagLinkRelationship tagLinks('),
              contains('NoteTagLinkList noteLinks('),
              contains('NoteTagLinkFields.active.equals(true)'),
              contains('NoteTagLinkFields.deletedAt.isNull'),
              contains('orderBy ?? entityGraph.noteTagLinks.canonicalOrder'),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains('note_tag_links_note_id_task_tag_id_idx'),
              contains('(note_id, deleted_at, active, order_rank, id)'),
              contains('select note_id::text into order_scope_key'),
              contains('candidate.note_id::text = order_scope_key'),
              contains('member.deleted_at is null and member.active is true'),
              contains("array['deletedAt', 'active']"),
              contains("'commandName' = 'replaceRelationship'"),
              contains("hashtextextended('NoteTagLink:relationship:'"),
              contains('Exact relationship membership changed'),
              contains("'relatedChanges', related_changes"),
            ]),
          ),
        },
      );
    },
  );

  test(
    'omits exact replacement for an unbounded active relationship',
    () async {
      const noteSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {}
''';
      final sources = _sources(noteSource, fileName: 'note.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/task.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity()
abstract class Task implements OwnedBy<Task, Account> {}
'''
        ..['nodus|lib/note_task_link.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/note.dart';
import 'package:nodus/task.dart';

@Entity(
  indexes: [CompoundIndex([#noteId, #taskId], unique: true)],
)
abstract class NoteTaskLink
    implements OwnedBy<NoteTaskLink, Account>, Activatable, Ordered {
  @OwnerReference()
  @Reference(
    inverse: 'taskLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Note> noteId;

  @Reference(
    inverse: 'noteLinks',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Task> taskId;
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains('final class NoteTaskLinkRelationship'),
              contains('RelationshipCardinalityResolution.unboundedByDefault'),
              contains('Future<void> moveBefore('),
              contains('Future<void> moveAfter('),
              isNot(contains('Future<void> replace(')),
              isNot(contains('await _entityGraph.noteTaskLinks.reorder(')),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
        },
      );
    },
  );

  test('generates the complete Archivable capability surface', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, Archivable {
  abstract final String title;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('DateTime? get archivedAt => _archivedAtStore.value;'),
            contains('Future<void> archive()'),
            contains('Future<void> unarchive()'),
            contains('ArchiveVisibility archives = ArchiveVisibility.exclude'),
            contains('_archivePredicate(archives)'),
            contains(
              'ArchiveVisibility.only => NoteFields.archivedAt.isNotNull',
            ),
            contains('notes_owner_id_archived_at_idx'),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('NoteList.active('),
            contains('NoteList.archived('),
            contains('archives: ArchiveVisibility.only'),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(anything),
      },
    );
  });

  test('rejects members repeated by Archivable', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, Archivable {
  abstract final DateTime? archivedAt;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Archivable supplies `archivedAt`, `archive`, and `unarchive`'),
    );
  });

  test('generates ActivityTracked source and immutable ActivityOf entry', () async {
    const taskSource = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Task implements OwnedBy<Task, Account>, ActivityTracked {
  abstract final String title;

  @override
  String get activityLabel => title;

  @Persisted(defaultValue: false)
  abstract final bool status;

  @Action(values: [ActionValue(#status, true)])
  Future<void> complete();
}

final class Account {}
''';
    const activitySource = r'''
import 'package:nodus/nodus.dart';
import 'task.dart';

@Entity()
abstract class TaskActivity
    implements OwnedBy<TaskActivity, Account>, ActivityOf<Task, Account> {}
''';
    final sources = _sources(taskSource, fileName: 'task.dart')
      ..addAll(_sources(activitySource, fileName: 'task_activity.dart'));

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/task.entity.g.dart': decodedMatches(
          allOf([
            contains('ActivityTrackedEntityDescriptor'),
            contains("activityOperation: ActivityOperation.action('complete')"),
          ]),
        ),
        'nodus|lib/task_activity.entity.g.dart': decodedMatches(
          allOf([
            contains('ActivityEntryEntityDescriptor'),
            contains('LocalId<Task> get subjectId'),
            contains('ActivityOperation get operation'),
            contains('String get sourceOperationId'),
            isNot(contains('Future<TaskActivity> create(')),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('ActivityTrackingDefinition('),
            contains("sourceEntityType: 'Task'"),
            contains("activityEntityType: 'TaskActivity'"),
            contains('TaskActivityList.forTask('),
            contains('TaskActivityFields.subjectId.equals(taskId)'),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('task_activities_select_source'),
            contains('task_activities_insert_source_operation'),
            contains("source_receipt.entity_type = 'Task'"),
            contains(
              "source_receipt.user_id = (current_operation -> 'patch' ->> 'actorId')::uuid",
            ),
            contains(
              "source_receipt.operation_id = (current_operation -> 'patch' ->> 'sourceOperationId')::uuid",
            ),
            contains(
              "when 'TaskActivity' then (exists (select 1 from public.task_activities activity",
            ),
          ]),
        ),
      },
    );
  });

  test('requires exactly one ActivityOf entry for a tracked source', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Task implements OwnedBy<Task, Account>, ActivityTracked {
  abstract final String title;

  @override
  String get activityLabel => title;
}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'task.dart'),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('requires exactly one @Entity implementing ActivityOf'),
    );
  });

  test('infers direct collaboration from Collaborative', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note
    implements OwnedBy<Note, Account>, Collaborative<Account> {}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<void> setCollaborator('),
            contains('SetCollaboratorCommand<Note, Account>'),
            isNot(contains('NoteCollaborators get collaborators')),
          ]),
        ),
      },
    );
  });

  test('requires Collaborative to use the owner principal type', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note
    implements OwnedBy<Note, Account>, Collaborative<OtherAccount> {}

final class Account {}
final class OtherAccount {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Collaborative<Principal> must use the entity owner type'),
    );
  });

  test('rejects members repeated by Activatable', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note
    implements OwnedBy<Note, Account>, Activatable {
  @Persisted(defaultValue: true)
  abstract final bool active;
}

final class Account {}
''';

    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('Activatable supplies `active`, `activate`, and `deactivate`'),
    );
  });

  test('generates internal ranked ordering from the Ordered capability', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

final class Account {}

@Entity(
  cardinality: Cardinality.bounded,
  indexes: [CompoundIndex.query([#deletedAt, #title])],
)
abstract class Note
    implements OwnedBy<Note, Account>, SoftDeletable, Ordered {
  abstract final String title;
}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('int get protocolVersion => 2'),
            contains(
              'static final _orderRank = '
              'PersistedComparableEntityField<Note, OrderRank>',
            ),
            contains("columnName: 'order_rank'"),
            contains(
              'OrderRank get generatedOrderRank => _orderRankStore.value',
            ),
            contains('EntityOrder<Note> get canonicalOrder =>'),
            contains('NoteFields._orderRank.ascending'),
            contains('tieBreakBy: (entity) => entity.id.value'),
            contains('_engine.createInGeneratedOrder('),
            contains('required bool first'),
            contains("'moveInOrder' => MoveOrderedCommand<Note>"),
            contains("'reorder' => ReorderOrderedCommand<Note>"),
            contains('OrderedDescriptor {'),
            contains("String orderScopeKey(JsonMap fields)"),
            contains("final value = fields['ownerId']"),
            contains('String get generatedOrderScopeKey =>'),
            contains('Future<void> moveBefore('),
            contains('Future<void> moveAfter('),
            contains('Future<void> prepend('),
            contains('Future<void> append('),
            contains('Future<void> reorder('),
            contains('prepareGeneratedOrderRank'),
            contains('recordGeneratedExactOrder'),
            contains('localPatch: change.patch'),
            contains('persistsEntityState: true'),
            contains('scopeBaseVersion: _engine.orderScopeVersionFor('),
            contains("'orderRank': NoteFields._orderRank.encode("),
            contains(
              'Future<Note> create({LocalId<Note>? id, required String title})',
            ),
            contains(
              'Future<Note> createFirst({LocalId<Note>? id, required String title})',
            ),
            contains(
              'placement: first ? OrderedPlacement.first : '
              'OrderedPlacement.last',
            ),
            isNot(contains('OrderRank get orderRank')),
            isNot(contains('static final orderRank')),
            contains('renamedFrom: null'),
            isNot(contains('int get sortOrder')),
            isNot(contains('moveTo')),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          allOf([
            contains('orderBy ?? entityGraph.notes.canonicalOrder'),
            isNot(contains('NoteFields.orderRank')),
            isNot(contains('moveTo')),
          ]),
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('order_rank text not null'),
            contains('(owner_id, deleted_at, order_rank, id)'),
            contains('(owner_id, deleted_at, title, id)'),
            contains("commandName' = 'moveInOrder'"),
            contains('pg_advisory_xact_lock'),
            contains(
              "order_scope_key := current_operation -> 'patch' ->> "
              "'ownerId';",
            ),
            contains('order_scope_membership_changed boolean;'),
            contains('if order_scope_membership_changed then'),
            contains('set version = version + 1'),
            matches(
              RegExp(
                r'select owner_id::text into order_scope_key.*'
                r'pg_advisory_xact_lock.*select candidate\.\* into canonical.*'
                r'for update;',
                dotAll: true,
              ),
            ),
            contains('candidate.owner_id::text = order_scope_key'),
            contains('local_entity_order_scopes'),
            contains('scopeBaseVersion'),
            contains("current_operation ? 'orderedCreate'"),
            contains(
              "not (current_operation ? 'orderedCreate') and not "
              "((current_operation -> 'patch') ? 'orderRank')",
            ),
            contains("array['placement', 'scopeBaseVersion']"),
            contains("current_operation -> 'orderedCreate' ->> 'placement'"),
            contains("'{patch,orderRank}'"),
            contains("array['placement', 'anchorId', 'scopeBaseVersion']"),
            contains("in ('before', 'after', 'first', 'last')"),
            contains("'commandName' = 'reorder'"),
            contains("array['orderedIds', 'scopeBaseVersion']"),
            contains('Exact ordered membership changed'),
            contains("'relatedChanges', related_changes"),
            contains('current_order_scope_version'),
            contains("lpad(next_order_rank::text, 78, '0')"),
            contains('with ordered_scope as ('),
            isNot(contains("array['afterId', 'beforeId'")),
          ]),
        ),
      },
    );
  });

  test('uses the complete bounded root for identity-owned ordering', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  ownership: Ownership.identity,
)
abstract class Account implements OwnedBy<Account, Account>, Ordered {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'account.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/account.entity.g.dart': decodedMatches(
          allOf([
            contains('.generatedIsOrderMember'),
            isNot(contains('entity.ownerId != _ownerId')),
            isNot(contains('entity.ownerId == target!.ownerId')),
          ]),
        ),
      },
    );
  });

  test('generates a null-safe composite sibling ordering scope', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  orderScope: [#parentNodeId],
)
abstract class Node implements OwnedBy<Node, Account>, Ordered {
  @Reference(
    inverse: 'children',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? parentNodeId;

  abstract final String title;

  @Action()
  Future<void> reparent({required LocalId<Node>? parentNodeId});
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'node.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/node.entity.g.dart': decodedMatches(
          allOf([
            contains('nodes_parent_node_id_deleted_at_order_rank_id_idx'),
            contains("if (!fields.containsKey('ownerId'))"),
            contains("if (!fields.containsKey('parentNodeId'))"),
            contains(
              'List<EntityFieldDescriptor> get orderScopeFields => const [',
            ),
            contains('NodeFields._ownerIdPersistence'),
            contains('NodeFields._parentNodeIdPersistence'),
            contains('return encodeOrderScopeKey(['),
            contains("fields['ownerId']"),
            contains("fields['parentNodeId']"),
            contains(
              'String get generatedOrderScopeKey => encodeOrderScopeKey([',
            ),
            contains('required LocalId<Node>? parentNodeId'),
            contains('_engine.createInGeneratedOrder('),
            contains('NodeFields.ownerId.encode(_ownerId)'),
            contains('NodeFields.parentNodeId.encode(parentNodeId)'),
            contains('parentNodeId: parentNodeId'),
            contains(
              "'transferInOrder' => TransferOrderedCommand<Node>.fromWire(",
            ),
            contains(
              'Future<void> reparent({required LocalId<Node>? parentNodeId})',
            ),
            contains('prepareEntityOrderTransfer<Node>('),
            contains('recordEntityOrderTransfer<Node>('),
            contains(
              'targetScopeBaseVersion: transferPlan.targetScopeBaseVersion',
            ),
            contains('int get protocolVersion => 3'),
          ]),
        ),
      },
    );

    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'node.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('(owner_id, parent_node_id, deleted_at, order_rank, id)'),
            contains(
              "jsonb_build_array(current_operation -> 'patch' -> "
              "'ownerId', current_operation -> 'patch' -> "
              "'parentNodeId')::text",
            ),
            contains(
              'jsonb_build_array(candidate.owner_id, '
              'candidate.parent_node_id)::text = order_scope_key',
            ),
            contains(
              'member.owner_id is not distinct from canonical.owner_id and '
              'member.parent_node_id is not distinct from '
              'canonical.parent_node_id',
            ),
            contains('member.parent_node_id is not distinct from'),
            contains("'commandName' = 'transferInOrder'"),
            contains(
              "hashtextextended('Node:hierarchy:' || "
              'jsonb_build_array(canonical.owner_id)::text, 0)',
            ),
            contains('least(source_order_scope_key, target_order_scope_key)'),
            contains('with recursive ancestors(entity_id, parent_id) as ('),
            contains(
              "jsonb_build_object('scope', source_order_scope, 'version', "
              'source_order_scope_version)',
            ),
            contains(
              "jsonb_build_object('scope', target_order_scope, 'version', "
              'target_order_scope_version)',
            ),
            isNot(matches(RegExp(r'[ \t]+$', multiLine: true))),
          ]),
        ),
      },
    );
  });

  test('generates indexed transfer for an unbounded hierarchy', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(orderScope: [#parentNodeId])
abstract class Node implements OwnedBy<Node, Account>, Ordered {
  @Reference(
    inverse: 'children',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? parentNodeId;

  @Action()
  Future<void> reparent({required LocalId<Node>? parentNodeId});
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'node.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/node.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<Node> create('),
            contains('Future<void> reparent('),
            contains(') async {'),
            contains('await transferSink.prepareEntityOrderTransfer<Node>('),
            contains('_engine.moveInGeneratedOrder('),
            isNot(contains("'reorder' => ReorderOrderedCommand<Node>")),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'node.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains("'commandName' = 'transferInOrder'"),
            contains("hashtextextended('Node:hierarchy:'"),
            contains('rebalance_window_size := 8;'),
            contains('from unnest(rebalance_member_ids) with ordinality'),
          ]),
        ),
      },
    );
  });

  test('an empty scope override selects the inferred owner lane', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded, orderScope: [])
abstract class Node implements OwnedBy<Node, Account>, Ordered {
  @Reference(
    inverse: 'children',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? parentNodeId;
}

final class Account {}
''';

    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'node.dart'),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/node.entity.g.dart': decodedMatches(
          allOf([
            contains('NodeFields._ownerIdPersistence'),
            isNot(contains('NodeFields._parentNodeIdPersistence,')),
            contains('_engine.createInGeneratedOrder('),
            contains("'ownerId': NodeFields.ownerId.encode(_ownerId)"),
          ]),
        ),
      },
    );
  });

  test('rejects ambiguous or mutable explicit ordering scopes', () async {
    final cases = <(String, String, String)>[
      ('', '', 'Set the smallest explicit Entity.orderScope tuple'),
      ('orderScope: [#ownerId],', '', 'must omit inferred #ownerId'),
      (
        'orderScope: [#parentNodeId, #parentNodeId],',
        '',
        'cannot repeat a field',
      ),
      (
        'orderScope: [#missing],',
        '',
        'field `missing` must be a persisted scalar field',
      ),
      (
        'orderScope: [#parentNodeId],',
        '@Action()\n  Future<void> reparent({required '
            'LocalId<Node>? parentNodeId});\n  @Action()\n  '
            'Future<void> moveParent({required LocalId<Node>? parentNodeId});',
        'only one action that transfers its scope',
      ),
    ];
    for (final (scope, action, expected) in cases) {
      final source =
          '''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded, $scope)
abstract class Node implements OwnedBy<Node, Account>, Ordered {
  @Reference(
    inverse: 'children',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? parentNodeId;
  $action
}

final class Account {}
''';
      final result = await testBuilder(
        localEntityBuilder(BuilderOptions.empty),
        _sources(source, fileName: 'node.dart'),
        rootPackage: 'nodus',
      );
      expect(result.succeeded, isFalse);
      expect(result.errors.join('\n'), contains(expected));
    }

    const withoutCapability = r'''
import 'package:nodus/nodus.dart';

@Entity(orderScope: [])
abstract class Item implements OwnedBy<Item, Account> {}

final class Account {}
''';
    final result = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(withoutCapability, fileName: 'item.dart'),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('valid only when the entity implements Ordered'),
    );

    const multipleRecursiveScopes = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  orderScope: [#primaryParentId, #secondaryParentId],
)
abstract class Node implements OwnedBy<Node, Account>, Ordered {
  @Reference(
    inverse: 'primaryChildren',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? primaryParentId;

  @Reference(
    inverse: 'secondaryChildren',
    onDelete: ReferenceDeleteAction.setNull,
  )
  abstract final LocalId<Node>? secondaryParentId;

  @Action()
  Future<void> reparent({
    required LocalId<Node>? primaryParentId,
    required LocalId<Node>? secondaryParentId,
  });
}

final class Account {}
''';
    final recursiveResult = await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(multipleRecursiveScopes, fileName: 'node.dart'),
      rootPackage: 'nodus',
    );
    expect(recursiveResult.succeeded, isFalse);
    expect(
      recursiveResult.errors.join('\n'),
      contains('multiple ancestry axes are ambiguous'),
    );
  });

  test(
    'rejects authored storage and movement APIs on Ordered entities',
    () async {
      final cases = <(String, String)>[
        (
          '@Persisted(defaultValue: 0)\n  abstract final int sortOrder;',
          'remove the public `sortOrder` field',
        ),
        (
          'abstract final String title;\n  @Action()\n  '
              'Future<void> moveTo({required String title});',
          'remove the entity-level `moveTo` method',
        ),
      ];

      for (final (declaration, expected) in cases) {
        final source =
            '''
import 'package:nodus/nodus.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account>, Ordered {
  $declaration
}

final class Account {}
''';
        final result = await testBuilder(
          localEntityBuilder(BuilderOptions.empty),
          _sources(source),
          rootPackage: 'nodus',
        );
        expect(result.succeeded, isFalse, reason: declaration);
        expect(
          result.errors.join('\n'),
          contains(expected),
          reason: declaration,
        );
      }
    },
  );

  test('generates indexed operations for an unbounded Ordered scope', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity()
abstract class Note implements OwnedBy<Note, Account>, Ordered {}

final class Account {}
''';
    await testBuilder(
      localEntityBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/note.entity.g.dart': decodedMatches(
          allOf([
            contains('Future<Note> create('),
            contains('Future<Note> createFirst('),
            contains('_engine.createInGeneratedOrder('),
            contains('_engine.moveInGeneratedOrder('),
            contains('placement: OrderedPlacement.before'),
            contains('placement: OrderedPlacement.after'),
            isNot(contains('Future<void> reorder(')),
            isNot(contains("'reorder' => ReorderOrderedCommand<Note>")),
            isNot(contains('_canonicalOrderedItems(')),
          ]),
        ),
      },
    );
    await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
      outputs: {
        'nodus|lib/nodus.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
          anything,
        ),
        'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
        'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
          anything,
        ),
        'nodus|supabase/nodus/schema.sql': decodedMatches(
          allOf([
            contains('rebalance_window_size := 8;'),
            contains('limit rebalance_window_size + 1'),
            contains('from unnest(rebalance_member_ids) with ordinality'),
            contains("'commandName' = 'moveInOrder'"),
            isNot(contains("'commandName' = 'reorder'")),
          ]),
        ),
      },
    );
  });

  test(
    'generates atomic collection operations for conventional ordering',
    () async {
      const source = r'''
import 'package:nodus/nodus.dart';

final class Account {}

@Entity(cardinality: Cardinality.bounded)
abstract class Note implements OwnedBy<Note, Account> {
  @Persisted(defaultValue: 0, minValue: 0)
  abstract final int sortOrder;

  @Action()
  Future<void> moveTo({required int sortOrder});
}

''';
      final sources = _sources(source)
        ..['nodus|lib/activity.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/note.dart';

@Entity(cardinality: Cardinality.unbounded)
abstract class Activity implements OwnedBy<Activity, Account> {
  @Persisted(defaultValue: 0, minValue: 0)
  abstract final int sortOrder;

  @Action()
  Future<void> moveTo({required int sortOrder});
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            allOf([
              contains('final TestGraphEntityGraph _entityGraph;'),
              contains(
                'Future<void> reorder(Iterable<LocalId<Note>> entityIds)',
              ),
              contains('The ordered identities must exactly match'),
              contains('unawaited(byId[id]!.moveTo(sortOrder: index));'),
              contains('orderBy: orderBy ?? NoteFields.sortOrder.ascending()'),
              contains('Future<Note> prepend(Note Function() create)'),
              contains(
                'unawaited(entity.moveTo(sortOrder: entity.sortOrder + 1));',
              ),
              contains('if (!spec.where.test(created))'),
              contains('if (created.sortOrder != 0)'),
              contains(
                'orderBy: orderBy ?? ActivityFields.sortOrder.ascending()',
              ),
              isNot(contains('reorder(Iterable<LocalId<Activity>> entityIds)')),
              isNot(contains('prepend(Activity Function() create)')),
            ]),
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            isNot(contains('local_entity_order_scopes')),
          ),
        },
      );
    },
  );

  test(
    'derives entity-backed collaboration from one workflow declaration',
    () async {
      const goalSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess.workflow(),
)
abstract class Goal implements OwnedBy<Goal, Account> {
  final String title = '';
}
''';
      final sources = _sources(goalSource, fileName: 'goal.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/goal_member.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class GoalMember implements OwnedBy<GoalMember, Account> {
  @OwnerReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Goal> goalId;

  @AccessParticipant()
  abstract final LocalId<Account> memberId;

  @Persisted(defaultValue: MembershipStatus.pending, transitions: [
    AllowedTransition(
      MembershipStatus.pending,
      MembershipStatus.accepted,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(
      MembershipStatus.pending,
      MembershipStatus.declined,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(
      MembershipStatus.accepted,
      MembershipStatus.declined,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(
      MembershipStatus.accepted,
      MembershipStatus.revoked,
      by: [RlsPrincipal.owner],
    ),
    AllowedTransition(
      MembershipStatus.declined,
      MembershipStatus.pending,
      by: [RlsPrincipal.owner],
    ),
    AllowedTransition(
      MembershipStatus.revoked,
      MembershipStatus.pending,
      by: [RlsPrincipal.owner],
    ),
  ])
  abstract final MembershipStatus status;

  @Action(values: [ActionValue(#status, MembershipStatus.accepted)])
  Future<void> accept();

  @Action(values: [ActionValue(#status, MembershipStatus.declined)])
  Future<void> decline();

  @Action(values: [ActionValue(#status, MembershipStatus.revoked)])
  Future<void> revoke();

  @Action(values: [ActionValue(#status, MembershipStatus.pending)])
  Future<void> reinvite();
}

enum MembershipStatus { pending, accepted, declined, revoked }
'''
        ..['nodus|lib/goal_requirement.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class GoalRequirement
    implements OwnedBy<GoalRequirement, Account>, SoftDeletable {
  @OwnerReference()
  @AccessReference()
  @Reference(
    inverse: 'requirements',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Goal> goalId;

  @AccessReference()
  @Reference(
    inverse: 'requiredBy',
    onDelete: ReferenceDeleteAction.cascade,
  )
  abstract final LocalId<Goal> requiredGoalId;
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'member_id uuid not null references auth.users (id) '
                'on delete cascade',
              ),
              contains(
                'create unique index if not exists '
                'goal_members_goal_id_member_id_idx '
                'on public.goal_members (goal_id, member_id)',
              ),
              contains(
                'member.goal_id = p_id\n'
                '      and member.member_id = auth.uid()\n'
                "      and member.status = 'accepted'",
              ),
              contains('create trigger goal_members_publish_access'),
              contains('after insert or update of status, deleted_at'),
              contains(
                "was_active := old.status = 'accepted'\n"
                '      and old.deleted_at is null;',
              ),
              contains("and audience_user_id = new.member_id"),
              contains('not is_active'),
              contains(
                "(current_operation -> 'patch' ->> 'ownerId')::uuid = "
                '(select target.owner_id from public.goals target where '
                "target.id = (current_operation -> 'patch' ->> 'goalId')::uuid)",
              ),
              isNot(contains('public.is_goal_members_reference')),
              contains(
                'create or replace function '
                'public.publish_goals_reference_access(',
              ),
              contains(
                'perform public.publish_goals_reference_access(\n'
                '    new.goal_id,\n'
                '    new.member_id\n'
                '  );',
              ),
              isNot(contains("commandName <> 'setCollaborator'")),
            ]),
          ),
        },
      );
    },
  );

  test(
    'separates workflow target preview from accepted collaborator access',
    () async {
      const taskSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/membership_status.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess.workflow(
    additionalReadableStates: [MembershipStatus.pending],
  ),
)
abstract class Task implements OwnedBy<Task, Account> {
  abstract final String title;

}
''';
      final sources = _sources(taskSource, fileName: 'task.dart')
        ..['nodus|lib/account.dart'] = 'final class Account {}'
        ..['nodus|lib/membership_status.dart'] =
            'enum MembershipStatus { pending, accepted, revoked }'
        ..['nodus|lib/task_member.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/membership_status.dart';
import 'package:nodus/task.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class TaskMember implements OwnedBy<TaskMember, Account> {
  @OwnerReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;

  @AccessParticipant()
  abstract final LocalId<Account> memberId;

  @Persisted(defaultValue: MembershipStatus.pending, transitions: [
    AllowedTransition(
      MembershipStatus.pending,
      MembershipStatus.accepted,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(
      MembershipStatus.accepted,
      MembershipStatus.revoked,
      by: [RlsPrincipal.owner],
    ),
  ])
  abstract final MembershipStatus status;

  @Action(values: [ActionValue(#status, MembershipStatus.accepted)])
  Future<void> accept();

  @Action(values: [ActionValue(#status, MembershipStatus.revoked)])
  Future<void> revoke();
}
'''
        ..['nodus|lib/task_attachment.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/task.dart';

@Entity(cardinality: Cardinality.bounded)
abstract class TaskAttachment
    implements OwnedBy<TaskAttachment, Account> {
  @OwnerReference()
  @AccessReference()
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Task> taskId;
}
''';

      await testBuilder(
        inferredEntityGraphBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'nodus',
        outputs: {
          'nodus|lib/nodus.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.explain.g.json': decodedMatches(
            anything,
          ),
          'nodus|test/nodus_test_harness.g.dart': decodedMatches(anything),
          'nodus|lib/src/generated/nodus.runtime.g.dart': decodedMatches(
            anything,
          ),
          'nodus|supabase/nodus/schema.sql': decodedMatches(
            allOf([
              contains(
                'create or replace function public.is_tasks_viewer(p_id uuid)',
              ),
              contains("and member.status in ('accepted', 'pending')"),
              contains(
                'tasks_select_collaborator on public.tasks for select to '
                'authenticated using (public.is_tasks_viewer(tasks.id))',
              ),
              contains(
                'tasks_update_collaborator on public.tasks for update to '
                'authenticated using (public.is_tasks_collaborator(tasks.id))',
              ),
              contains(
                "when 'Task' then (changes.owner_id = auth.uid() or "
                'public.is_tasks_viewer(changes.entity_id))',
              ),
              contains("was_visible := old.status in ('accepted', 'pending')"),
              contains(
                'after insert or update of status, deleted_at\n'
                'on public.task_members',
              ),
              contains('not is_visible'),
              contains(
                'if was_active = is_active and was_visible = is_visible then',
              ),
              contains(
                'if was_active is distinct from is_active then\n'
                '    perform public.publish_tasks_reference_access(',
              ),
              contains(
                "member.status = 'accepted' and member.deleted_at is null",
              ),
            ]),
          ),
        },
      );
    },
  );

  test('rejects non-enum workflow readable states', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess.workflow(
    additionalReadableStates: [1],
  ),
)
abstract class Goal implements OwnedBy<Goal, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'goal.dart'),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('additionalReadableStates must contain enum constants'),
    );
  });

  test('rejects a workflow target without its membership entity', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess.workflow(),
)
abstract class Goal implements OwnedBy<Goal, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source, fileName: 'goal.dart'),
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('workflow collaboration requires one synchronized'),
    );
  });

  test('rejects a workflow accepted state from another enum', () async {
    const goalSource = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/access_status.dart';

@Entity(
  cardinality: Cardinality.bounded,
  collaboration: CollaborationAccess.workflow(
    acceptedState: AccessStatus.approved,
  ),
)
abstract class Goal implements OwnedBy<Goal, Account> {}
''';
    final sources = _sources(goalSource, fileName: 'goal.dart')
      ..['nodus|lib/account.dart'] = 'final class Account {}'
      ..['nodus|lib/access_status.dart'] = 'enum AccessStatus { approved }'
      ..['nodus|lib/goal_member.dart'] = r'''
import 'package:nodus/nodus.dart';
import 'package:nodus/account.dart';
import 'package:nodus/goal.dart';

@Entity(
  cardinality: Cardinality.bounded,
  grants: [
    RlsGrant(RlsOperation.select, RlsPrincipal.owner),
    RlsGrant(RlsOperation.select, RlsPrincipal.participant),
    RlsGrant(RlsOperation.insert, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.owner),
    RlsGrant(RlsOperation.update, RlsPrincipal.participant),
  ],
)
abstract class GoalMember implements OwnedBy<GoalMember, Account> {
  @Reference(onDelete: ReferenceDeleteAction.cascade)
  abstract final LocalId<Goal> goalId;

  @AccessParticipant()
  abstract final LocalId<Account> memberId;

  @Persisted(defaultValue: MembershipStatus.pending, transitions: [
    AllowedTransition(
      MembershipStatus.pending,
      MembershipStatus.approved,
      by: [RlsPrincipal.participant],
    ),
    AllowedTransition(
      MembershipStatus.approved,
      MembershipStatus.revoked,
      by: [RlsPrincipal.owner],
    ),
  ])
  abstract final MembershipStatus status;

  @Action(values: [ActionValue(#status, MembershipStatus.approved)])
  Future<void> approve();

  @Action(values: [ActionValue(#status, MembershipStatus.revoked)])
  Future<void> revoke();
}

enum MembershipStatus { pending, approved, revoked }
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'nodus',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('requires an immutable enum `status`'),
    );
  });

  test('rejects reserved Dart words as entity-set accessors', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  setAccessor: 'switch',
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Invalid entity-set accessor `switch`. Use a lowerCamelCase Dart identifier.',
      ),
    );
  });

  test('rejects table vocabulary that resolves to a Dart keyword', () async {
    const source = r'''
import 'package:nodus/nodus.dart';

@Entity(
  cardinality: Cardinality.bounded,
  table: 'switch',
)
abstract class Note implements OwnedBy<Note, Account> {}

final class Account {}
''';

    final result = await testBuilder(
      inferredEntityGraphBuilder(BuilderOptions.empty),
      _sources(source),
      rootPackage: 'nodus',
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Invalid entity-set accessor `switch`. Use a lowerCamelCase Dart identifier.',
      ),
    );
  });
}

Map<String, String> _sources(
  String source, {
  bool includeGraph = true,
  String fileName = 'note.dart',
}) => {
  'nodus|lib/$fileName': source,
  if (includeGraph) r'nodus|$package$': '',
  if (includeGraph)
    'nodus|nodus.lock': '''
{
  "formatVersion": 1,
  "packageName": "nodus",
  "graphName": "TestGraph",
  "schemaVersion": 1,
  "schemaFingerprint": null,
  "targets": ["supabase"],
  "defaultTarget": "supabase"
}
''',
  'nodus|lib/nodus.dart': '''
export 'src/annotations.dart';

typedef JsonMap = Map<String, Object?>;

abstract interface class PersistedScalarValue<Wire extends Object> {
  Wire toScalar();
}

abstract interface class GeneratedEntityAccess<E> {}

abstract interface class OwnedBy<Self, Owner> {
  LocalId<Self> get id;
  LocalId<Owner> get ownerId;
  DateTime? get deletedAt;
  ServerVersion get serverVersion;
  GeneratedEntityAccess<Self> get generatedAccess;
}

abstract interface class SoftDeletable {
  DateTime? get deletedAt;
  Future<void> remove();
  Future<void> restore();
}

abstract interface class Archivable {
  DateTime? get archivedAt;
  Future<void> archive();
  Future<void> unarchive();
}

abstract interface class Ordered {}

abstract interface class Component {}

abstract interface class Activatable {
  bool get active;
  Future<void> activate();
  Future<void> deactivate();
}

abstract interface class Collaborative<Principal> {
  Future<void> setCollaborator(
    LocalId<Principal> collaboratorId, {
    required bool active,
  });
}

abstract interface class ActivityTracked {
  String get activityLabel;
}

abstract interface class ActivityOf<Subject, Actor> {
  LocalId<Subject> get subjectId;
  LocalId<Actor> get actorId;
  ActivityOperation get operation;
  String get label;
  String get sourceOperationId;
  DateTime get occurredAt;
}

final class ActivityOperation implements PersistedScalarValue<String> {
  const ActivityOperation.fromScalar(this.value);

  final String value;

  @override
  String toScalar() => value;
}
''',
  'nodus|lib/src/annotations.dart': File(
    'lib/src/annotations.dart',
  ).readAsStringSync(),
};
