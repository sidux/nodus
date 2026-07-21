import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

import 'package:nodus/src/entity_generator/dart_emitter.dart';
import 'package:nodus/src/entity_generator/graph_emitter.dart';
import 'package:nodus/src/entity_generator/graph_sql_emitter.dart';
import 'package:nodus/src/entity_generator/model.dart';
import 'package:nodus/src/entity_generator/sql_emitter.dart';

void main() {
  test('unordered generated lookup keys have symmetric value identity', () {
    const first = UnorderedEntityPairKey('left', 'right');
    const reversed = UnorderedEntityPairKey('right', 'left');
    const different = UnorderedEntityPairKey('left', 'other');

    expect(first, reversed);
    expect(first.hashCode, reversed.hashCode);
    expect(first, isNot(different));
  });

  test('inferred names preserve acronym word boundaries', () {
    expect(snakeCase('APIKey'), 'api_key');
    expect(pluralSnakeCase('APIKey'), 'api_keys');
    expect(lowerCamelCase(pluralSnakeCase('APIKey')), 'apiKeys');
  });

  test('generated index names are deterministic and PostgreSQL-safe', () {
    const tableName = 'extremely_descriptive_synchronized_activity_records';
    const columns = [
      'equally_descriptive_first_relationship_identifier',
      'equally_descriptive_second_relationship_identifier',
    ];

    final first = generatedIndexName(tableName: tableName, columns: columns);
    final second = generatedIndexName(tableName: tableName, columns: columns);
    final different = generatedIndexName(
      tableName: tableName,
      columns: [...columns, 'status'],
    );

    expect(first, second);
    expect(first.length, lessThanOrEqualTo(63));
    expect(first, matches(RegExp(r'_[0-9a-f]{16}_idx$')));
    expect(different, isNot(first));
    expect(
      generatedIndexName(tableName: 'work_items', columns: ['statement']),
      'work_items_statement_idx',
    );
  });

  const spec = EntitySpec(
    className: 'WorkItem',
    packageName: 'example',
    inputImport: 'package:example/work_item.dart',
    tableName: 'work_items',
    ownership: Ownership.separate,
    cardinality: Cardinality.bounded,
    authenticatedReadSync: AuthenticatedReadSync.inferred,
    compoundIndexes: [
      CompoundIndexSpec(
        fields: ['deletedAt', 'sortOrder'],
        unique: false,
        scope: IndexScope.owner,
        keyset: true,
      ),
      CompoundIndexSpec(
        fields: ['sortOrder', 'statement'],
        unique: true,
        scope: IndexScope.field,
      ),
    ],
    fields: [
      FieldSpec(
        name: 'id',
        columnName: 'id',
        dartType: 'LocalId<WorkItem>',
        sqlType: SqlType.uuid,
        nullable: false,
        isFinal: true,
        defaultValue: null,
        conflict: ConflictStrategy.serverWins,
        minLength: null,
        maxLength: null,
        indexed: false,
        unique: false,
      ),
      FieldSpec(
        name: 'ownerId',
        columnName: 'owner_id',
        dartType: 'LocalId<Account>',
        sqlType: SqlType.uuid,
        nullable: false,
        isFinal: true,
        defaultValue: null,
        conflict: ConflictStrategy.serverWins,
        minLength: null,
        maxLength: null,
        indexed: false,
        unique: false,
      ),
      FieldSpec(
        name: 'statement',
        columnName: 'statement',
        dartType: 'String',
        sqlType: SqlType.text,
        nullable: false,
        isFinal: true,
        defaultValue: null,
        conflict: ConflictStrategy.localWins,
        minLength: 1,
        maxLength: 280,
        allowedValues: ['Rule A', 'Rule B'],
        indexed: true,
        unique: true,
        indexScope: IndexScope.owner,
        updatePrincipals: [RlsPrincipal.owner],
      ),
      FieldSpec(
        name: 'sortOrder',
        columnName: 'sort_order',
        dartType: 'int',
        sqlType: SqlType.integer,
        nullable: false,
        isFinal: true,
        defaultValue: 0,
        conflict: ConflictStrategy.serverWins,
        minLength: null,
        maxLength: null,
        minValue: 0,
        maxValue: 100,
        indexed: false,
        unique: false,
      ),
      FieldSpec(
        name: 'deletedAt',
        columnName: 'deleted_at',
        dartType: 'DateTime?',
        sqlType: SqlType.timestampWithTimeZone,
        nullable: true,
        isFinal: true,
        defaultValue: null,
        conflict: ConflictStrategy.serverWins,
        minLength: null,
        maxLength: null,
        indexed: false,
        unique: false,
      ),
      FieldSpec(
        name: 'serverVersion',
        columnName: 'server_version',
        dartType: 'ServerVersion',
        sqlType: SqlType.integer,
        nullable: false,
        isFinal: true,
        defaultValue: 0,
        conflict: ConflictStrategy.serverWins,
        minLength: null,
        maxLength: null,
        indexed: false,
        unique: false,
      ),
    ],
    security: SecuritySpec(
      grants: [
        GrantSpec(
          operation: RlsOperation.select,
          principal: RlsPrincipal.owner,
        ),
        GrantSpec(
          operation: RlsOperation.select,
          principal: RlsPrincipal.collaborator,
        ),
        GrantSpec(
          operation: RlsOperation.insert,
          principal: RlsPrincipal.owner,
        ),
        GrantSpec(
          operation: RlsOperation.update,
          principal: RlsPrincipal.owner,
        ),
        GrantSpec(
          operation: RlsOperation.update,
          principal: RlsPrincipal.collaborator,
        ),
        GrantSpec(
          operation: RlsOperation.delete,
          principal: RlsPrincipal.owner,
        ),
      ],
      collaboration: CollaborationSpec(
        lifecycle: CollaborationLifecycle.direct,
        membershipTable: 'work_item_members',
        entityForeignKey: 'work_item_id',
        userForeignKey: 'user_id',
        activeField: 'active',
      ),
    ),
    commands: [
      CommandSpec(
        methodName: 'remove',
        targetField: 'deletedAt',
        parameterName: null,
        parameterType: null,
        value: SyncCommandValue.clockNow,
      ),
      CommandSpec(
        methodName: 'restore',
        targetField: 'deletedAt',
        parameterName: null,
        parameterType: null,
        value: SyncCommandValue.clear,
      ),
    ],
  );

  test('Dart output is deterministic and delegates schema typing to Drift', () {
    final first = emitDart(spec);
    expect(emitDart(spec), first);
    expect(first, isNot(contains('@DriftDatabase')));
    expect(first, isNot(contains("part 'work_item.entity.g.drift.dart';")));
    expect(
      first,
      contains('// ignore_for_file: invalid_null_aware_operator, type=lint'),
    );
    expect(first, contains('PushSyncWorkKind.semanticCommand'));
    expect(first, contains('persistsEntityState: true'));
    expect(first, contains('generatedCreateSnapshot'));
    expect(
      first,
      contains(
        'EntityIdentity(descriptor: this, id: generator.next<WorkItem>())',
      ),
    );
    expect(first, contains('EntityIdentity<WorkItem> parseIdentity'));
    expect(first, contains('EntityIdentityDescriptor<WorkItem>'));
    expect(first, isNot(contains('get idFieldName')));
    expect(first, isNot(contains('get serverVersionFieldName')));
    expect(first, contains('abstract final class WorkItemFields'));
    expect(
      first,
      contains(
        'List<EntityFieldDescriptor> get fields => '
        'WorkItemFields._persistence;',
      ),
    );
    expect(
      first,
      contains('PersistedComparableEntityField<WorkItem, String>('),
    );
    expect(first, contains('persistence: _statementPersistence'));
    expect(first, contains('constraints: EntityFieldConstraints('));
    expect(first, contains('minLength: 1'));
    expect(first, contains('maxLength: 280'));
    expect(first, contains("allowedValues: const ['Rule A', 'Rule B']"));
    expect(first, contains('minValue: 0'));
    expect(first, contains('maxValue: 100'));
    expect(first, contains('statement.persistence,'));
    expect(first, contains('decode: (source) =>'));
    expect(first, contains('WorkItemFields.statement.encode(statement)'));
    expect(
      first,
      contains("WorkItemFields.statement.decode(fields['statement'])"),
    );
    expect(RegExp("name: 'statement'").allMatches(first), hasLength(1));
    expect(
      RegExp(r'EntityFieldDescriptor\(').allMatches(first),
      hasLength(spec.fields.length),
    );
    expect(first, contains('encode: (value) =>'));
    expect(first, contains('TypedGeneratedEntityRecord<WorkItem>,'));
    expect(first, contains('factory WorkItemRecord.detached({'));
    expect(first, contains('const DetachedEntityMutationSink()'));
    expect(first, isNot(contains('final detachedNow = clock.nowUtc();')));
    expect(first, contains('EntityDescriptor<WorkItem, WorkItemRecord>'));
    expect(first, contains('EntityUniqueConstraintDescriptor'));
    expect(first, contains("fieldNames: ['ownerId', 'statement']"));
    expect(
      first,
      contains("!(const {'Rule A', 'Rule B'}).contains(statement)"),
    );
    expect(first, contains(r"CHECK (statement IN (\'Rule A\', \'Rule B\'))"));
    expect(first, contains("fieldNames: ['sortOrder', 'statement']"));
    expect(
      first,
      contains(
        'CREATE UNIQUE INDEX work_items_owner_id_statement_idx '
        'ON work_items (owner_id, statement)',
      ),
    );
    expect(
      first,
      contains(
        'CREATE INDEX work_items_owner_id_deleted_at_sort_order_id_idx '
        'ON work_items (owner_id, deleted_at, sort_order, id)',
      ),
    );
    expect(
      first,
      contains(
        'CREATE UNIQUE INDEX work_items_sort_order_statement_idx '
        'ON work_items (sort_order, statement)',
      ),
    );
    expect(first, contains('WorkItem get generatedDomain => this;'));
    expect(
      first,
      contains('GeneratedEntityAccess<WorkItem> get generatedAccess => this;'),
    );
    expect(first, contains('generatedAccess.recordGeneratedCommand('));
    expect(first, isNot(contains(' as WorkItemRecord')));
    expect(first, contains('recordEntityMutation<WorkItem>('));
    expect(first, contains('final syncPatch = generatedDraftPatch;'));
    expect(first, contains('patch: syncPatch'));
    expect(first, isNot(contains("patch: {'statement': value}")));
    expect(first, contains('LocalEntityQuery<WorkItem> query'));
    expect(first, contains('Stream<EntityQueryState<WorkItem>> watchQuery'));
    expect(
      first,
      contains('Stream<EntityQueryState<WorkItem>> watchCompleteQuery'),
    );
    expect(
      first,
      contains('LocalEntityEngine<WorkItem, WorkItemRecord> _engine'),
    );
    expect(first, isNot(contains('loadQueryPage<WorkItem>')));
    expect(
      first,
      contains('LocalEntityQueryCache<WorkItem>(source: engine.all)'),
    );
    expect(
      first,
      contains('_ownerId = engine.authenticatedOwnerId<Account>(),'),
    );
    expect(first, contains('final LocalId<Account> _ownerId;'));
    expect(
      first,
      isNot(
        contains(
          'WorkItem create({\n'
          '    LocalId<WorkItem>? id,\n'
          '    required LocalId<Account> ownerId,',
        ),
      ),
    );
    expect(
      first,
      contains("'ownerId': WorkItemFields.ownerId.encode(_ownerId),"),
    );
    expect(first, contains('principals: const [RlsPrincipal.owner],'));
    expect(first, isNot(contains('required after')));
    expect(first, isNot(contains('required offset')));
    expect(first, isNot(contains('final SyncQueue syncQueue')));
    expect(first, isNot(contains('WorkItemLocalDatabase')));
    expect(first, isNot(contains('WorkItemModel')));
    expect(first, contains('Future<void> setCollaborator('));
    expect(first, isNot(contains('WorkItemCollaborators get collaborators')));
    expect(first, contains('SetCollaboratorCommand<WorkItem, Account>'));
    expect(first, contains('decodeSemanticCommand('));
    expect(first, isNot(contains("payload: {'userId':")));
    expect(first, contains('Future<void> remove()'));
    expect(first, contains('if (oldValue != null) return Future.value();'));
    expect(first, contains('Future<void> restore()'));
    expect(first, contains('if (oldValue == null) return Future.value();'));
    expect(first, contains('const DateTime? commandValue = null;'));
    expect(first, contains("message: 'Deleted entities cannot be changed.'"));
    expect(first, contains("field: 'statement'"));
    expect(first, contains("field: 'command'"));
    expect(first, contains('final commandValue = _clock.nowUtc();'));
    expect(first, contains('_mutationSink.recordEntityMutation<WorkItem>('));
    expect(first, contains('final mutationTime = commandValue;'));
    expect(first, contains('occurredAt: mutationTime,'));
    expect(
      first,
      isNot(contains('operationId: const UuidV7EntityIdGenerator')),
    );
    expect(first, contains('parseLocalId<WorkItem>'));
    expect(
      first,
      contains(
        'WorkItem? byStatementForOwner({\n'
        '    required LocalId<Account> ownerId,\n'
        '    required String statement,',
      ),
    );
    expect(
      first,
      contains(
        '(ownerId: entity.ownerId, statement: entity.statement): entity,',
      ),
    );
    expect(
      first,
      contains(
        '_byStatementForOwnerIndex.value['
        '(ownerId: ownerId, statement: statement)]',
      ),
    );
    expect(
      first,
      contains(
        'Future<WorkItem> createOrGetByStatementForOwner({\n'
        '    LocalId<WorkItem>? id,',
      ),
    );
    expect(
      first,
      contains(
        'final existing = byStatementForOwner(\n'
        '      ownerId: _ownerId,\n'
        '      statement: statement,',
      ),
    );
    expect(first, contains('if (existing != null) return existing;'));
    expect(
      first,
      contains(
        'Future<WorkItem> createOrGetBySortOrderAndStatement({\n'
        '    LocalId<WorkItem>? id,',
      ),
    );
    expect(
      first,
      contains(
        'WorkItem? bySortOrderAndStatement({\n'
        '    required int sortOrder,\n'
        '    required String statement,',
      ),
    );
    expect(
      first,
      contains('ServerVersion get generatedServerVersion => serverVersion;'),
    );
    expect(first, contains('required ServerVersion serverVersion'));
    expect(first, contains('value.isFinite && value == value.truncate()'));
    expect(
      first,
      isNot(contains("fields.containsKey('serverVersion')")),
      reason: 'The authoritative version argument must be assigned only once.',
    );
    expect(first, contains("'CHECK (sort_order >= 0)'"));
    expect(first, contains("'CHECK (sort_order <= 100)'"));
    expect(first, contains('if (nextSortOrder < 0)'));
    expect(first, contains('if (nextSortOrder > 100)'));
    expect(
      first.indexOf('remoteStatement ='),
      lessThan(
        first.indexOf(
          'runInAction(() {',
          first.indexOf('generatedApplyRemote'),
        ),
      ),
    );
  });

  test('unbounded entities omit all and generate Drift-paged queries', () {
    final unbounded = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: Cardinality.unbounded,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: spec.fields,
      security: spec.security,
      commands: spec.commands,
    );

    final output = emitDart(unbounded);

    expect(
      output,
      contains(
        'Cardinality get cardinality => '
        'Cardinality.unbounded',
      ),
    );
    expect(output, contains('LocalEntityQueryCache.database'));
    expect(output, isNot(contains('ReadOnlyObservableList<WorkItem> get all')));
    expect(output, contains('EntityLookup<WorkItem> lookup('));
    expect(output, contains('}) => EntityLookup('));
    expect(output, contains('EntityExistence<WorkItem> exists('));
    expect(output, contains('EntityFirst<WorkItem> first('));
    expect(output, contains('required EntityOrder<WorkItem> orderBy'));
    expect(output, contains('WorkItemFields.id.equals(id)'));
    expect(output, contains('Future<EntityLookupLease<WorkItem>?> loadById('));
    expect(output, contains('Future<R> useById<R>('));
    expect(output, contains('LeaseAction<WorkItem, R> action'));
    expect(output, contains("entityType: 'WorkItem'"));
    expect(output, contains('entityId: id.value'));
    expect(
      output,
      contains(
        'Stream<WorkItem?> watchById(LocalId<WorkItem> id) =>\n'
        '      _engine.watchLoadedRawId(id.value);',
      ),
    );
    expect(output, isNot(contains('WorkItem? byId(')));
    expect(output, isNot(contains('WorkItem require(')));
  });

  test('ordinary fields generate one typed locally durable draft API', () {
    final editable = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: spec.fields,
      security: spec.security,
      commands: spec.commands,
    );

    final output = emitDart(editable);

    expect(output, contains('extension WorkItemGeneratedEditing on WorkItem'));
    expect(
      output,
      contains(
        'WorkItemMutationDraft beginEdit() => WorkItemMutationDraft.edit(this);',
      ),
    );
    expect(output, contains('final class WorkItemMutationDraft'));
    expect(output, contains('final EntityDraftField<String> _statementField;'));
    expect(output, contains('String get statement => _statementField.value;'));
    expect(output, contains('set statement(String value)'));
    expect(output, contains('final EntityDraftField<int> _sortOrderField;'));
    expect(output, contains('Future<WorkItem> save() async'));
    expect(
      output,
      contains('current.generatedAccess.validateGeneratedDraft();'),
    );
    expect(
      output,
      contains('await current.generatedAccess.applyGeneratedDraft('),
    );
    expect(output, contains('WorkItemFields.statement.patch('));
    expect(output, contains('_baseStatement as String'));
    expect(output, contains('WorkItemFields.sortOrder.patch(sortOrder)'));
    expect(output, contains('EntityDraftFieldConflictException'));
    expect(output, contains('EntityDraftFailureReason.consumed'));
    expect(output, contains('principals: const [RlsPrincipal.owner],'));
    expect(
      output,
      contains(
        'principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],',
      ),
    );
    expect(output, contains('String get generatedOwnerId => ownerId.value;'));
    expect(
      output,
      contains('bool generatedHasParticipant(String principalId)'),
    );
  });

  test('identity ownership and updated timestamps are structural SQL', () {
    final profile = EntitySpec(
      className: 'Profile',
      packageName: spec.packageName,
      inputImport: 'package:example/profile.dart',
      tableName: 'profiles',
      ownership: Ownership.identity,
      cardinality: Cardinality.bounded,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: [
        FieldSpec(
          name: EntityConventions.idFieldName,
          columnName: EntityConventions.idColumnName,
          dartType: 'LocalId<Profile>',
          sqlType: SqlType.uuid,
          nullable: false,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        FieldSpec(
          name: 'displayName',
          columnName: 'display_name',
          dartType: 'String',
          sqlType: SqlType.text,
          nullable: false,
          isFinal: false,
          defaultValue: null,
          conflict: ConflictStrategy.localWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        FieldSpec(
          name: EntityConventions.updatedAtFieldName,
          columnName: EntityConventions.updatedAtColumnName,
          dartType: 'DateTime',
          sqlType: SqlType.timestampWithTimeZone,
          nullable: false,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        FieldSpec(
          name: EntityConventions.deletedAtFieldName,
          columnName: EntityConventions.deletedAtColumnName,
          dartType: 'DateTime?',
          sqlType: SqlType.timestampWithTimeZone,
          nullable: true,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        FieldSpec(
          name: EntityConventions.serverVersionFieldName,
          columnName: EntityConventions.serverVersionColumnName,
          dartType: 'ServerVersion',
          sqlType: SqlType.integer,
          nullable: false,
          isFinal: true,
          defaultValue: 0,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
      ],
      security: const SecuritySpec(
        grants: [
          GrantSpec(
            operation: RlsOperation.select,
            principal: RlsPrincipal.owner,
          ),
          GrantSpec(
            operation: RlsOperation.update,
            principal: RlsPrincipal.owner,
          ),
        ],
        collaboration: null,
      ),
      commands: const [],
    );

    final dart = emitDart(profile);
    final sql = emitSupabaseSql(profile);

    expect(dart, contains('LocalId<Profile> get ownerId => id;'));
    expect(dart, contains('final detachedNow = clock.nowUtc();'));
    expect(dart, isNot(contains('Profile create({')));
    expect(
      sql,
      isNot(contains('owner_id uuid not null references auth.users')),
    );
    expect(sql, contains('(select auth.uid()) = id'));
    expect(sql, contains('updated_at timestamptz not null default now()'));
    expect(sql, contains('create trigger profiles_touch_updated_at'));
    expect(
      sql,
      contains(
        'revoke all on function public.touch_profiles_updated_at() '
        'from public, anon, authenticated, service_role;',
      ),
    );
    expect(sql, contains("current_operation ->> 'operation' not in ('patch')"));
    expect(sql, contains("if p_operation not in ('patch')"));
    expect(
      sql,
      contains(
        'revoke all on function public.capture_profiles_change() '
        'from public, anon, authenticated, service_role;',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on function public.apply_profiles_patch('
        'uuid, bigint, text, jsonb) '
        'from public, anon, authenticated, service_role;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.push_profiles_operations(jsonb) '
        'to authenticated;',
      ),
    );
    expect(
      sql,
      isNot(contains("current_operation ->> 'operation' = 'create'")),
    );
    expect(sql, isNot(contains("p_operation = 'delete'")));
    expect(sql, isNot(contains("operation' = 'command'")));
    expect(
      dart,
      contains(
        'Stream<Profile?> watchById(LocalId<Profile> id) =>\n'
        '      _engine.watchRawId(id.value);',
      ),
    );
    expect(
      dart,
      contains('LocalEntityQueryCache<Profile>(source: engine.all)'),
    );
    expect(dart, isNot(contains('LocalEntityQueryCache.database')));
    expect(
      dart,
      isNot(contains('Future<EntityLookupLease<Profile>?> loadById(')),
    );
    expect(
      dart,
      isNot(contains('_engine.loadRawId(id.value, refresh: refresh);')),
    );
  });

  test('entity graph deterministically derives one database and registry', () {
    final graph = EntityGraphSpec(
      className: 'ExampleGraph',
      packageName: 'example',
      inputImport: 'package:example/app/example_graph.dart',
      schemaVersion: 2,
      entities: const [spec],
    );

    final output = emitEntityGraph(graph);
    final entityOutput = emitDart(spec);

    expect(emitEntityGraph(graph), output);
    expect(output, contains('// ignore_for_file: unused_field, type=lint'));
    expect(
      output,
      contains("import 'package:example/work_item.entity.g.dart';"),
    );
    expect(output, contains('final class ExampleGraphDatabase'));
    expect(output, contains('WorkItemRows,'));
    expect(output, contains('ExampleGraphSyncWorkRows,'));
    expect(
      output,
      contains('static final definition = EntityGraphDefinition('),
    );
    expect(output, contains('schemaVersion: 2'));
    expect(output, contains('descriptors: ['));
    expect(
      output,
      contains('static const workItemDescriptor = WorkItemDescriptor();'),
    );
    expect(output, contains('descriptors: [workItemDescriptor]'));
    expect(
      output,
      contains('descriptor: ExampleGraphMetadata.workItemDescriptor,'),
    );
    expect('WorkItemDescriptor()'.allMatches(output), hasLength(1));
    expect(output, contains('final class ExampleGraphSyncAdapters'));
    expect(
      output,
      contains(
        'ExampleGraphSyncAdapters syncAdapters = '
        'const ExampleGraphSyncAdapters()',
      ),
    );
    expect(output, contains('final adapterRegistry = syncAdapters.bind()'));
    expect(output, contains('final WorkItemSet workItems;'));
    expect(output, contains('workItems = WorkItemSet(_workItemEngine)'));
    expect(output, contains('final LocalId<Account> accountId;'));
    expect(output, contains('required LocalId<Account> accountId,'));
    expect(
      output,
      contains('static Future<ExampleGraphEntityGraph> openInMemory'),
    );
    expect(output, contains('authenticatedPrincipalId: accountId.value,'));
    expect(
      output,
      contains('final class WorkItemList extends EntityList<WorkItem>'),
    );
    expect(output, contains('WorkItemList.all('));
    expect(output, contains('WorkItemList.owned('));
    expect(output, contains('WorkItemList.forOwner('));
    expect(
      output,
      contains('TombstoneVisibility tombstones = TombstoneVisibility.exclude'),
    );
    expect(output, contains('tombstones: tombstones'));
    expect(
      entityOutput,
      contains(
        'TombstoneVisibility.include => '
        'EntityPredicate<WorkItem>.all()',
      ),
    );
    expect(
      entityOutput,
      contains(
        'TombstoneVisibility.only => WorkItemFields.deletedAt.isNotNull',
      ),
    );
    expect(
      output,
      contains('WorkItemFields.ownerId.equals(entityGraph.accountId)'),
    );
    expect(output, contains('WorkItemFields.ownerId.equals(ownerId)'));
    expect(output, isNot(contains('WorkItemList.forSortOrderAndStatement(')));
    expect(output, isNot(contains('workItemSet')));
    expect(output, contains('pull_example_graph_graph_changes'));
    expect(output, contains('Future<R> transaction<R>'));
    expect(
      output,
      contains('DateTime nowUtc() => _coordinator.clock.nowUtc();'),
    );
    expect('idGenerator: idGenerator'.allMatches(output), hasLength(3));
    expect(output, contains('LocalEntityDiagnostics diagnostics ='));
    expect(output, contains('diagnostics: diagnostics'));
    expect(output, contains('Future<void>? _closeFuture;'));
    expect(
      output,
      contains('Future<void> close() => _closeFuture ??= _close()'),
    );

    final sql = emitEntityGraphSupabaseSql(
      _supabaseGraph(
        className: graph.className,
        inputImport: graph.inputImport,
        schemaVersion: graph.schemaVersion,
        entities: graph.entities,
      ),
    );
    expect(sql, contains('pull_example_graph_graph_changes'));
    expect(sql, isNot(contains('pull_work_items_changes')));
    expect(
      'create table if not exists public.local_entity_changes'.allMatches(sql),
      hasLength(1),
    );
    expect(
      sql,
      contains(
        'alter table public.local_entity_changes enable row level security;',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.local_entity_changes from anon, authenticated;',
      ),
    );
    expect(sql, contains('changes.audience_user_id is null'));
    expect(sql, contains('or changes.audience_user_id = auth.uid()'));
    expect(
      sql,
      contains(
        'revoke all on function public.pull_example_graph_graph_changes('
        'bigint) from public, anon, authenticated, service_role;',
      ),
    );
  });

  test('exact lookup constructors require unconditional uniqueness', () {
    final unsafe = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: spec.fields,
      security: spec.security,
      commands: spec.commands,
      compoundIndexes: const [
        CompoundIndexSpec(
          fields: ['deletedAt', 'statement'],
          unique: true,
          scope: IndexScope.field,
        ),
        CompoundIndexSpec(
          fields: ['sortOrder', 'statement'],
          unique: true,
          scope: IndexScope.field,
          condition: IndexConditionSpec(field: 'statement', values: ['Rule A']),
        ),
        CompoundIndexSpec(
          fields: ['sortOrder', 'statement'],
          unique: true,
          scope: IndexScope.field,
          unordered: true,
        ),
      ],
    );
    final graph = EntityGraphSpec(
      className: 'UnsafeGraph',
      packageName: 'example',
      inputImport: 'package:example/app/unsafe_graph.dart',
      schemaVersion: 1,
      entities: [unsafe],
    );

    final output = emitEntityGraph(graph);

    expect(output, isNot(contains('WorkItemList.forDeletedAtAndStatement(')));
    expect(output, isNot(contains('WorkItemList.forSortOrderAndStatement(')));
    expect(output, isNot(contains('final class WorkItemLookup')));
  });

  test(
    'unbounded unique indexes generate singular lookup leases, not lists',
    () {
      final unbounded = EntitySpec(
        className: spec.className,
        packageName: spec.packageName,
        inputImport: spec.inputImport,
        tableName: spec.tableName,
        ownership: spec.ownership,
        cardinality: Cardinality.unbounded,
        authenticatedReadSync: spec.authenticatedReadSync,
        fields: spec.fields,
        security: spec.security,
        commands: spec.commands,
        compoundIndexes: spec.compoundIndexes,
      );
      final output = emitEntityGraph(
        EntityGraphSpec(
          className: 'UnboundedGraph',
          packageName: 'example',
          inputImport: 'package:example/app/unbounded_graph.dart',
          schemaVersion: 1,
          entities: [unbounded],
        ),
      );

      expect(
        output,
        contains('final class WorkItemLookup extends EntityLookup<WorkItem>'),
      );
      expect(output, contains('WorkItemLookup.byOwnerAndStatement('));
      expect(output, contains('WorkItemLookup.bySortOrderAndStatement('));
      expect(output, contains('pageSize: 1'));
      expect(output, isNot(contains('createOrGetBy')));
      expect(output, isNot(contains('WorkItemList.forOwnerAndStatement(')));
      expect(output, isNot(contains('WorkItemList.forSortOrderAndStatement(')));
    },
  );

  test('entity graph honors an explicit entity-set accessor override', () {
    final graph = EntityGraphSpec(
      className: 'ExampleGraph',
      packageName: 'example',
      inputImport: 'package:example/app/example_graph.dart',
      schemaVersion: 1,
      entities: [
        EntitySpec(
          className: spec.className,
          packageName: spec.packageName,
          inputImport: spec.inputImport,
          tableName: spec.tableName,
          ownership: spec.ownership,
          cardinality: spec.cardinality,
          authenticatedReadSync: spec.authenticatedReadSync,
          fields: spec.fields,
          security: spec.security,
          commands: spec.commands,
          setAccessorOverride: 'personalRules',
        ),
      ],
    );

    final output = emitEntityGraph(graph);

    expect(output, contains('final WorkItemSet personalRules;'));
    expect(output, isNot(contains('final WorkItemSet workItems;')));
  });

  test('inferred custom targets get managed connector factories', () {
    const target = SyncTargetSpec(
      enumType: 'ExampleSyncTarget',
      enumImport: 'package:example/nodus.g.dart',
      valueName: 'restApi',
      wireName: 'rest_api',
    );
    final graph = EntityGraphSpec(
      className: 'Example',
      packageName: 'example',
      inputImport: 'package:example/nodus.lock',
      schemaVersion: 1,
      entities: const [spec],
      defaultSyncTarget: target,
      syncBindings: const [
        SyncBindingSpec(
          entity: spec,
          mode: SyncMode.replicated,
          target: target,
        ),
      ],
      emitsSyncTargetEnum: true,
    );

    final output = emitEntityGraph(graph, privateEntityOutputs: true);

    expect(output, contains("import 'package:nodus/nodus_flutter.dart';"));
    expect(output, isNot(contains("package:nodus/nodus_supabase.dart")));
    expect(output, contains('static Future<ExampleEntityGraph> openRestApi'));
    expect(
      output,
      contains('required SyncConnector<PushPullSyncAdapter> connector'),
    );
    expect(output, contains('openWithConnectors('));
    expect(output, contains('restApi: connector'));
    expect(
      output,
      contains('definition: ExampleMetadata.restApiSyncDefinition'),
    );
    expect(output, contains('syncAdapters.bind()'));
    expect(output, contains('final executor = await localStore.open('));
  });

  test('unbounded authenticated reads stay out of graph pull by default', () {
    EntitySpec publicEntity({
      required Cardinality cardinality,
      required AuthenticatedReadSync sync,
    }) => EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: cardinality,
      authenticatedReadSync: sync,
      fields: spec.fields,
      security: const SecuritySpec(
        grants: [
          GrantSpec(
            operation: RlsOperation.select,
            principal: RlsPrincipal.authenticated,
          ),
          GrantSpec(
            operation: RlsOperation.update,
            principal: RlsPrincipal.owner,
          ),
        ],
        collaboration: null,
      ),
      commands: spec.commands,
    );
    String graphSql({
      required Cardinality cardinality,
      AuthenticatedReadSync sync = AuthenticatedReadSync.inferred,
    }) {
      final entity = publicEntity(cardinality: cardinality, sync: sync);
      return emitEntityGraphSupabaseSql(
        _supabaseGraph(
          className: 'ExampleGraph',
          inputImport: 'package:example/app/example_graph.dart',
          schemaVersion: 2,
          entities: [entity],
        ),
      );
    }

    expect(
      emitSupabaseSql(
        publicEntity(
          cardinality: Cardinality.unbounded,
          sync: AuthenticatedReadSync.inferred,
        ),
      ),
      contains(
        'create policy work_items_select_authenticated on '
        'public.work_items for select to authenticated using '
        '((select auth.uid()) is not null);',
      ),
    );
    expect(
      graphSql(cardinality: Cardinality.unbounded),
      contains("when 'WorkItem' then (changes.owner_id = auth.uid())"),
    );
    expect(
      graphSql(cardinality: Cardinality.bounded),
      contains("when 'WorkItem' then (true)"),
    );
    expect(
      graphSql(
        cardinality: Cardinality.unbounded,
        sync: AuthenticatedReadSync.graph,
      ),
      contains("when 'WorkItem' then (true)"),
    );
    expect(
      graphSql(
        cardinality: Cardinality.bounded,
        sync: AuthenticatedReadSync.onDemand,
      ),
      contains("when 'WorkItem' then (changes.owner_id = auth.uid())"),
    );
  });

  test('SQL derives operation-specific security and collaboration protocol', () {
    final sql = emitSupabaseSql(spec);
    expect(
      sql,
      contains(
        'create unique index if not exists '
        'work_items_owner_id_statement_idx '
        'on public.work_items (owner_id, statement);',
      ),
    );
    expect(sql, contains("check (statement in ('Rule A', 'Rule B'))"));
    expect(
      sql,
      contains(
        'create index if not exists '
        'work_items_owner_id_deleted_at_sort_order_id_idx '
        'on public.work_items (owner_id, deleted_at, sort_order, id);',
      ),
    );
    expect(
      sql,
      contains(
        'create unique index if not exists '
        'work_items_sort_order_statement_idx '
        'on public.work_items (sort_order, statement);',
      ),
    );
    expect(
      sql,
      contains('revoke all on public.work_items from authenticated;'),
    );
    expect(
      sql,
      contains('revoke all on public.work_item_members from authenticated;'),
    );
    expect(
      sql,
      contains('grant select on public.work_items to authenticated;'),
    );
    expect(
      sql,
      contains(
        "p_operation = 'delete' and not (public.is_work_items_owner(p_id))",
      ),
    );
    expect(
      sql,
      contains(
        "p_patch ? 'statement'\n"
        '     and not (public.is_work_items_owner(p_id))',
      ),
    );
    expect(
      sql,
      contains(
        "p_operation = 'patch' and not (public.is_work_items_owner(p_id) or public.is_work_items_collaborator(p_id))",
      ),
    );
    expect(
      "raise exception 'Entity access denied' using errcode = '42501';"
          .allMatches(sql),
      hasLength(2),
      reason: 'Patch and delete authorization each emit one rejection.',
    );
    expect(sql, contains('Patch contains a forbidden field'));
    expect(sql, contains('server_version bigint not null default 1'));
    expect(sql, contains('check (sort_order >= 0)'));
    expect(sql, contains('check (sort_order <= 100)'));
    expect(sql, contains('Create contains missing or forbidden fields'));
    expect(sql, contains('Create entity ID mismatch'));
    expect(sql, contains("commandName' <> 'setCollaborator"));
    expect(
      sql,
      contains('(select count(*) from jsonb_object_keys(p_patch)) <> 1'),
    );
    expect(sql, contains('Delete requires exactly one command field'));
    expect(sql, contains('Collaboration command has invalid field types'));
    expect(sql, contains('audience_user_id'));
    expect(
      'delete from public.local_entity_changes'.allMatches(sql),
      hasLength(2),
      reason: 'Entity and audience histories each retain one latest snapshot.',
    );
    expect(sql, contains('local_entity_changes_identity_idx'));
    expect(sql, contains('changes.audience_user_id is null'));
    expect(sql, contains('or changes.audience_user_id = auth.uid()'));
    expect(sql, contains("'nextSequence', next_cursor"));
    expect(sql, contains('drop policy if exists work_item_members_select'));
  });

  test('participant grants derive indexed RLS and graph visibility', () {
    final participant = EntitySpec(
      className: 'Invitation',
      packageName: spec.packageName,
      inputImport: 'package:example/invitation.dart',
      tableName: 'invitations',
      ownership: Ownership.separate,
      cardinality: Cardinality.bounded,
      authenticatedReadSync: AuthenticatedReadSync.inferred,
      fields: [
        FieldSpec(
          name: 'id',
          columnName: 'id',
          dartType: 'LocalId<Invitation>',
          sqlType: SqlType.uuid,
          nullable: false,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        spec.ownerField,
        FieldSpec(
          name: 'inviteeId',
          columnName: 'invitee_id',
          dartType: 'LocalId<Account>',
          sqlType: SqlType.uuid,
          nullable: false,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: true,
          unique: false,
          isParticipant: true,
        ),
        FieldSpec(
          name: 'status',
          columnName: 'status',
          dartType: 'InvitationStatus',
          sqlType: SqlType.text,
          nullable: false,
          isFinal: false,
          defaultValue: 'pending',
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
          enumValues: ['pending', 'accepted', 'declined'],
          transitions: [
            ValueTransitionSpec(
              from: 'pending',
              to: 'accepted',
              principals: [RlsPrincipal.participant],
            ),
            ValueTransitionSpec(from: 'pending', to: 'declined'),
          ],
        ),
        spec.fields.singleWhere((field) => field.name == 'deletedAt'),
        spec.serverVersionField,
      ],
      security: const SecuritySpec(
        grants: [
          GrantSpec(
            operation: RlsOperation.select,
            principal: RlsPrincipal.owner,
          ),
          GrantSpec(
            operation: RlsOperation.select,
            principal: RlsPrincipal.participant,
          ),
          GrantSpec(
            operation: RlsOperation.insert,
            principal: RlsPrincipal.owner,
          ),
          GrantSpec(
            operation: RlsOperation.update,
            principal: RlsPrincipal.owner,
          ),
          GrantSpec(
            operation: RlsOperation.update,
            principal: RlsPrincipal.participant,
          ),
          GrantSpec(
            operation: RlsOperation.delete,
            principal: RlsPrincipal.owner,
          ),
        ],
        collaboration: null,
      ),
      commands: spec.commands,
    );

    final sql = emitSupabaseSql(participant);
    final dart = emitDart(participant);
    final graphDart = emitEntityGraph(
      EntityGraphSpec(
        className: 'Example',
        packageName: spec.packageName,
        inputImport: 'package:example/entity_graph.dart',
        schemaVersion: 1,
        entities: [participant],
      ),
    );
    final graphSql = emitEntityGraphSupabaseSql(
      _supabaseGraph(
        className: 'Example',
        inputImport: 'package:example/entity_graph.dart',
        schemaVersion: 1,
        entities: [participant],
      ),
    );

    expect(
      sql,
      contains(
        'invitee_id uuid not null references auth.users (id) '
        'on delete cascade',
      ),
    );
    expect(
      sql,
      contains(
        'create index if not exists invitations_invitee_id_idx '
        'on public.invitations (invitee_id);',
      ),
    );
    expect(sql, contains('entity.invitee_id = auth.uid()'));
    expect(sql, contains('public.is_invitations_participant(p_id)'));
    expect(
      sql,
      contains(
        'grant execute on function '
        'public.is_invitations_participant(uuid) to authenticated',
      ),
    );
    expect(dart, contains("EntityValueTransition('pending', 'accepted')"));
    expect(
      dart,
      contains(
        "'status': InvitationFields.status.encode(InvitationStatus.pending)",
      ),
    );
    expect(dart, contains('factory InvitationRecord.detached({'));
    expect(graphDart, contains('InvitationList.forInvitee('));
    expect(graphDart, contains('InvitationFields.inviteeId.equals(inviteeId)'));
    expect(graphDart, contains('InvitationList.visibleTo('));
    expect(
      graphDart,
      matches(
        RegExp(
          r'\(\s*InvitationFields\.ownerId\.equals\(accountId\)\s*\|\s*'
          r'InvitationFields\.inviteeId\.equals\(accountId\)\s*\)\s*&\s*'
          r'\(where \?\? EntityPredicate<Invitation>\.all\(\)\)',
          multiLine: true,
        ),
      ),
    );
    expect(graphDart, contains('tombstones: tombstones'));
    expect(
      dart,
      allOf(
        contains('oldValue == InvitationStatus.pending'),
        contains('value == InvitationStatus.accepted'),
      ),
    );
    expect(
      sql,
      contains(
        "current_row.status = 'pending' and "
        "(p_patch -> 'status' #>> '{}') = 'accepted' and "
        '(public.is_invitations_participant(p_id))',
      ),
    );
    expect(
      sql,
      contains(
        "(current_operation -> 'patch' -> 'status' #>> '{}') is distinct from "
        "'pending'",
      ),
    );
    expect(
      sql,
      contains(
        "p_operation = 'patch' and not "
        '(public.is_invitations_owner(p_id) or '
        'public.is_invitations_participant(p_id))',
      ),
    );
    expect(
      graphSql,
      contains(
        "when 'Invitation' then (changes.owner_id = auth.uid() or "
        'public.is_invitations_participant(changes.entity_id))',
      ),
    );
  });

  test('create-only entities omit unreachable patch infrastructure', () {
    final createOnly = EntitySpec(
      className: 'AppRating',
      packageName: spec.packageName,
      inputImport: 'package:example/app_rating.dart',
      tableName: 'app_ratings',
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: [
        ...spec.fields,
        const FieldSpec(
          name: 'status',
          columnName: 'status',
          dartType: 'String',
          sqlType: SqlType.text,
          nullable: false,
          isFinal: true,
          defaultValue: 'open',
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: true,
          unique: false,
          authority: FieldAuthority.server,
        ),
      ],
      security: const SecuritySpec(
        grants: [
          GrantSpec(
            operation: RlsOperation.select,
            principal: RlsPrincipal.owner,
          ),
          GrantSpec(
            operation: RlsOperation.insert,
            principal: RlsPrincipal.owner,
          ),
        ],
        collaboration: null,
      ),
      commands: const [],
    );

    final sql = emitSupabaseSql(createOnly);

    expect(sql, contains("operation' not in ('create')"));
    expect(sql, contains('push_app_ratings_operations'));
    expect(sql, isNot(contains('apply_app_ratings_patch')));
    expect(sql, isNot(contains('p_operation not in ()')));
    expect(sql, isNot(contains('update public.app_ratings')));
    expect(sql, contains("status text not null default 'open'"));
    expect(sql, contains('version_app_ratings_server_changes()'));
    expect(sql, contains('new.status is distinct from old.status'));
    expect(sql, contains('new.server_version := old.server_version + 1'));
    expect(
      sql,
      isNot(contains('insert into public.app_ratings (id, owner_id, status')),
    );
  });

  test('cross-field comparisons share one Dart, Drift, and SQL rule', () {
    final crossFieldSpec = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: [
        ...spec.fields.take(4),
        const FieldSpec(
          name: 'startMinutes',
          columnName: 'start_minutes',
          dartType: 'int',
          sqlType: SqlType.integer,
          nullable: false,
          isFinal: false,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        const FieldSpec(
          name: 'endMinutes',
          columnName: 'end_minutes',
          dartType: 'int',
          sqlType: SqlType.integer,
          nullable: false,
          isFinal: false,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          greaterThan: 'startMinutes',
          indexed: false,
          unique: false,
        ),
        ...spec.fields.skip(4),
      ],
      security: spec.security,
      commands: spec.commands,
      typeImports: spec.typeImports,
      protocolVersion: spec.protocolVersion,
    );

    expect(
      emitDart(crossFieldSpec),
      contains("'CHECK (end_minutes > start_minutes)'"),
    );
    expect(
      emitSupabaseSql(crossFieldSpec),
      contains('check (end_minutes > start_minutes)'),
    );
  });

  test('exclusive fields share one Dart, Drift, and SQL rule', () {
    final exclusiveSpec = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: [
        ...spec.fields.take(4),
        const FieldSpec(
          name: 'goalId',
          columnName: 'goal_id',
          dartType: 'LocalId<Goal>?',
          sqlType: SqlType.uuid,
          nullable: true,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        const FieldSpec(
          name: 'habitId',
          columnName: 'habit_id',
          dartType: 'LocalId<Habit>?',
          sqlType: SqlType.uuid,
          nullable: true,
          isFinal: true,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: false,
          unique: false,
        ),
        ...spec.fields.skip(4),
      ],
      security: spec.security,
      commands: spec.commands,
      exclusiveFieldGroups: const [
        ExclusiveFieldGroupSpec(fields: ['goalId', 'habitId'], allowNone: true),
      ],
      typeImports: spec.typeImports,
      protocolVersion: spec.protocolVersion,
    );

    expect(
      emitDart(exclusiveSpec),
      contains(
        'CHECK (CASE WHEN goal_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END <= 1)',
      ),
    );
    expect(
      emitSupabaseSql(exclusiveSpec),
      contains(
        'check ((((goal_id is not null)::integer) + '
        '((habit_id is not null)::integer)) <= 1)',
      ),
    );

    final requiredSpec = EntitySpec(
      className: exclusiveSpec.className,
      packageName: exclusiveSpec.packageName,
      inputImport: exclusiveSpec.inputImport,
      tableName: exclusiveSpec.tableName,
      ownership: exclusiveSpec.ownership,
      cardinality: exclusiveSpec.cardinality,
      authenticatedReadSync: exclusiveSpec.authenticatedReadSync,
      fields: exclusiveSpec.fields,
      security: exclusiveSpec.security,
      commands: exclusiveSpec.commands,
      exclusiveFieldGroups: const [
        ExclusiveFieldGroupSpec(
          fields: ['goalId', 'habitId'],
          allowNone: false,
        ),
      ],
      typeImports: exclusiveSpec.typeImports,
      protocolVersion: exclusiveSpec.protocolVersion,
    );
    expect(
      emitDart(requiredSpec),
      contains(
        'CHECK (CASE WHEN goal_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END = 1)',
      ),
    );
    expect(
      emitSupabaseSql(requiredSpec),
      contains(
        'check ((((goal_id is not null)::integer) + '
        '((habit_id is not null)::integer)) = 1)',
      ),
    );
  });

  test('date-only fields retain date semantics in PostgreSQL', () {
    final dateSpec = EntitySpec(
      className: spec.className,
      packageName: spec.packageName,
      inputImport: spec.inputImport,
      tableName: spec.tableName,
      ownership: spec.ownership,
      cardinality: spec.cardinality,
      authenticatedReadSync: spec.authenticatedReadSync,
      fields: [
        ...spec.fields.take(4),
        const FieldSpec(
          name: 'scheduledFor',
          columnName: 'scheduled_for',
          dartType: 'LocalDate?',
          sqlType: SqlType.date,
          nullable: true,
          isFinal: false,
          defaultValue: null,
          conflict: ConflictStrategy.serverWins,
          minLength: null,
          maxLength: null,
          indexed: true,
          unique: false,
        ),
        ...spec.fields.skip(4),
      ],
      security: spec.security,
      commands: spec.commands,
      typeImports: spec.typeImports,
      protocolVersion: spec.protocolVersion,
    );

    expect(emitSupabaseSql(dateSpec), contains('scheduled_for date'));
    expect(
      emitSupabaseSql(dateSpec),
      contains(
        "(current_operation -> 'patch' -> 'scheduledFor' #>> '{}')::date",
      ),
    );
    expect(emitDart(dateSpec), contains('EntityFieldKind.date'));
  });
}

const _supabaseTarget = SyncTargetSpec(
  enumType: 'TestSyncTarget',
  enumImport: 'package:example/sync_targets.dart',
  valueName: 'supabase',
  wireName: 'supabase',
);

EntityGraphSpec _supabaseGraph({
  required String className,
  required String inputImport,
  required int schemaVersion,
  required List<EntitySpec> entities,
}) => EntityGraphSpec(
  className: className,
  packageName: 'example',
  inputImport: inputImport,
  schemaVersion: schemaVersion,
  entities: entities,
  defaultSyncTarget: _supabaseTarget,
  syncBindings: [
    for (final entity in entities)
      SyncBindingSpec(
        entity: entity,
        mode: SyncMode.replicated,
        target: _supabaseTarget,
      ),
  ],
);
