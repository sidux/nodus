import 'dart:convert';
import 'dart:io';

import 'package:nodus/src/tool/conformance_inventory.dart';
import 'package:test/test.dart';

void main() {
  test(
    'classifies every semantic migration shape from AST and graph metadata',
    () {
      final fixture = _InventoryFixture();
      addTearDown(fixture.dispose);

      final report = NodusConformanceInventory(root: fixture.root).scan();
      final rules = report.findings.map((finding) => finding.rule).toSet();

      expect(rules, containsAll(nodusConformanceRules.map((rule) => rule.id)));
      expect(
        report.findings
            .where((finding) => finding.rule == 'unbounded-use-all')
            .single
            .entity,
        'Task',
      );
      expect(
        report.findings
            .where((finding) => finding.rule == 'repeated-current-owner')
            .single
            .replacement,
        'TaskList.owned(this)',
      );
      expect(report.toMarkdown(), contains('Generated replacement'));
      expect(
        jsonDecode(report.toPrettyJson()),
        containsPair('graph', 'FixtureEntityGraph'),
      );
    },
  );

  test('rendering and finding order are deterministic', () {
    final fixture = _InventoryFixture();
    addTearDown(fixture.dispose);
    final inventory = NodusConformanceInventory(root: fixture.root);

    final first = inventory.scan();
    final second = inventory.scan();

    expect(second.toMarkdown(), first.toMarkdown());
    expect(second.toPrettyJson(), first.toPrettyJson());
    expect(
      second.findings.map((finding) => finding.path),
      orderedEquals(first.findings.map((finding) => finding.path)),
    );
  });
}

final class _InventoryFixture {
  _InventoryFixture()
    : root = Directory.systemTemp.createTempSync('nodus_inventory_') {
    _write('pubspec.yaml', 'name: fixture\n');
    _write(
      'lib/src/generated/nodus.explain.g.json',
      jsonEncode({
        'graph': 'FixtureEntityGraph',
        'package': 'fixture',
        'schemaVersion': 1,
        'targets': ['supabase'],
        'entities': [
          {
            'name': 'Task',
            'source': 'package:fixture/features/tasks/domain/task.dart',
            'table': 'tasks',
            'ownership': 'separate',
            'cardinality': 'unbounded',
            'sync': {'mode': 'replicated', 'target': 'supabase'},
            'capabilities': {'archivable': true},
            'fields': <Object?>[],
            'indexes': <Object?>[],
            'actions': [
              {
                'name': 'rename',
                'parameters': <Object?>[],
                'fields': ['title'],
              },
            ],
            'generatedApi': {
              'set': 'TaskSet',
              'setAccessor': 'tasks',
              'list': 'TaskList',
              'boundedListConstructors': ['forProject'],
              'draft': 'TaskMutationDraft',
              'create': true,
            },
          },
        ],
      }),
    );
    _write('lib/features/tasks/domain/task.dart', r'''
@Entity()
abstract class Task implements OwnedBy<Task, Account>, Archivable {
  abstract String title;
  abstract final List<String> labels;
  abstract final DateTime? archivedAt;
  Future<void> archive();
  Future<void> unarchive();
}
''');
    _write('lib/features/tasks/domain/task_operations.dart', r'''
extension TaskOperations on FixtureEntityGraph {
  Object exact() => TaskList.query(this, pageSize: 1);

  Object owned() => TaskList.forOwner(this, accountId);

  Future<void> wrapped() =>
      transaction(() async => tasks.create(title: 'One'));

  TaskList forwarded() => TaskList.owned(this);

  Future<void> bulk() => TaskList.owned(this).useAll((tasks) async {
    for (final task in tasks) {
      await task.remove();
    }
  });

  Future<int> bounded() {
    final selection = TaskList.forProject(this, projectId);
    return selection.useAll((tasks) => tasks.length);
  }

  Stream<Object?> legacy(Object query) => query.itemSnapshots;

  DateTime get currentTime => DateTime.now();
}

extension TaskIdentity on Task {
  String get userId => ownerId.value;
}

void recordPersistence(Logger logger) {
  logger.info('Task persistence completed successfully');
}
''');
    _write(
      'lib/features/tasks/domain/ignored.g.dart',
      'Object ignored() => TaskList.query(graph, pageSize: 1);\n',
    );
  }

  final Directory root;

  void _write(String relativePath, String contents) {
    final file = File('${root.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void dispose() => root.deleteSync(recursive: true);
}
