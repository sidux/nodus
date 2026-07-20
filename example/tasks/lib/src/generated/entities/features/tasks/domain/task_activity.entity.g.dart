// GENERATED FILE. DO NOT EDIT.
// Source: package:tasks_example/features/tasks/domain/task_activity.dart
// ignore_for_file: invalid_null_aware_operator, type=lint

import 'package:drift/drift.dart';
import 'package:mobx/mobx.dart';
import 'package:nodus/nodus.dart';
import 'package:tasks_example/features/tasks/domain/task_activity.dart';
import 'package:tasks_example/features/accounts/domain/account.dart';
import 'package:tasks_example/features/tasks/domain/task.dart';

@TableIndex.sql(
  'CREATE INDEX task_activities_subject_id_occurred_at_idx ON task_activities (subject_id, occurred_at)',
)
@TableIndex.sql(
  'CREATE INDEX task_activities_occurred_at_idx ON task_activities (occurred_at)',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX task_activities_source_operation_id_idx ON task_activities (source_operation_id)',
)
class TaskActivityRows extends Table {
  @override
  String get tableName => 'task_activities';
  TextColumn get id => text().named('id')();
  TextColumn get ownerId => text().named('owner_id')();
  TextColumn get subjectId => text().named('subject_id')();
  TextColumn get actorId => text().named('actor_id')();
  TextColumn get operation => text().named('operation')();
  TextColumn get label => text().named('label')();
  TextColumn get sourceOperationId => text().named('source_operation_id')();
  TextColumn get occurredAt => text().named('occurred_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get serverVersion =>
      integer().named('server_version').withDefault(const Constant(0))();
  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(operation)) >= 1)',
    'CHECK (length(trim(label)) >= 1)',
    'CHECK (length(trim(source_operation_id)) >= 1)',
    'CHECK (length(operation) <= 160)',
    'CHECK (length(label) <= 240)',
    'CHECK (length(source_operation_id) <= 64)',
  ];
  IntColumn get localRevision => integer().named('local_revision')();
  TextColumn get acceptedSnapshot =>
      text().named('accepted_snapshot').nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

final class TaskActivityDescriptor
    implements
        EntityDescriptor<TaskActivity, TaskActivityRecord>,
        EntityIdentityDescriptor<TaskActivity>,
        EntityUniqueConstraintDescriptor,
        ActivityEntryEntityDescriptor {
  const TaskActivityDescriptor();

  @override
  EntityIdentity<TaskActivity> nextIdentity(EntityIdGenerator generator) =>
      EntityIdentity(descriptor: this, id: generator.next<TaskActivity>());
  @override
  EntityIdentity<TaskActivity> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId(source));

  @override
  String get entityType => 'TaskActivity';
  @override
  Cardinality get cardinality => Cardinality.unbounded;
  @override
  String get tableName => 'task_activities';
  @override
  String? get collaborationTableName => null;
  @override
  int get protocolVersion => 1;

  @override
  List<EntityUniqueConstraint> get uniqueConstraints => const [
    EntityUniqueConstraint(
      name: 'task_activities_source_operation_id_idx',
      fieldNames: ['sourceOperationId'],
    ),
  ];

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => switch (name) {
    _ => throw RejectedSyncException.validation(
      code: 'unsupported_command',
      message: 'Unsupported TaskActivity semantic command.',
    ),
  };

  @override
  List<EntityFieldDescriptor> get fields => TaskActivityFields._persistence;

  @override
  TaskActivityRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) {
    return TaskActivityRecord._(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: localRevision,
      id: TaskActivityFields.id.decode(fields['id']),
      ownerId: TaskActivityFields.ownerId.decode(fields['ownerId']),
      subjectId: TaskActivityFields.subjectId.decode(fields['subjectId']),
      actorId: TaskActivityFields.actorId.decode(fields['actorId']),
      operation: TaskActivityFields.operation.decode(fields['operation']),
      label: TaskActivityFields.label.decode(fields['label']),
      sourceOperationId: TaskActivityFields.sourceOperationId.decode(
        fields['sourceOperationId'],
      ),
      occurredAt: TaskActivityFields.occurredAt.decode(fields['occurredAt']),
      deletedAt: TaskActivityFields.deletedAt.decode(fields['deletedAt']),
      serverVersion: TaskActivityFields.serverVersion.decode(
        fields['serverVersion'],
      ),
    );
  }
}

final class TaskActivityRecord extends TaskActivity
    implements
        TypedGeneratedEntityRecord<TaskActivity>,
        GeneratedEntityAccess<TaskActivity> {
  TaskActivityRecord._({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required int localRevision,
    required LocalId<TaskActivity> id,
    required LocalId<Account> ownerId,
    required LocalId<Task> subjectId,
    required LocalId<Account> actorId,
    required ActivityOperation operation,
    required String label,
    required String sourceOperationId,
    required DateTime occurredAt,
    required DateTime? deletedAt,
    required ServerVersion serverVersion,
  }) : _mutationSink = mutationSink,
       _localRevision = localRevision,
       id = id,
       _ownerIdStore = Observable(ownerId),
       _subjectIdStore = Observable(subjectId),
       _actorIdStore = Observable(actorId),
       _operationStore = Observable(operation),
       _labelStore = Observable(label),
       _sourceOperationIdStore = Observable(sourceOperationId),
       _occurredAtStore = Observable(occurredAt),
       _deletedAtStore = Observable(deletedAt),
       _serverVersionStore = Observable(serverVersion) {
    if (operation.toScalar().trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'operation',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (operation.toScalar().length > 160) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'operation',
        message: 'Must contain at most 160 character(s).',
      );
    }
    if (label.trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'label',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (label.length > 240) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'label',
        message: 'Must contain at most 240 character(s).',
      );
    }
    if (sourceOperationId.trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'sourceOperationId',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (sourceOperationId.length > 64) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'sourceOperationId',
        message: 'Must contain at most 64 character(s).',
      );
    }
  }

  /// Creates an explicitly non-persisted preview or fixture.
  factory TaskActivityRecord.detached({
    required LocalId<TaskActivity> id,
    required LocalId<Account> ownerId,
    required LocalId<Task> subjectId,
    required LocalId<Account> actorId,
    required ActivityOperation operation,
    required String label,
    required String sourceOperationId,
    required DateTime occurredAt,
    DateTime? deletedAt,
    ServerVersion serverVersion = ServerVersion.zero,
    Clock clock = const SystemClock(),
    EntityMutationSink mutationSink = const DetachedEntityMutationSink(),
  }) {
    return const TaskActivityDescriptor().instantiate(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: 0,
      fields: {
        'id': TaskActivityFields.id.encode(id),
        'ownerId': TaskActivityFields.ownerId.encode(ownerId),
        'subjectId': TaskActivityFields.subjectId.encode(subjectId),
        'actorId': TaskActivityFields.actorId.encode(actorId),
        'operation': TaskActivityFields.operation.encode(operation),
        'label': TaskActivityFields.label.encode(label),
        'sourceOperationId': TaskActivityFields.sourceOperationId.encode(
          sourceOperationId,
        ),
        'occurredAt': TaskActivityFields.occurredAt.encode(occurredAt),
        'deletedAt': TaskActivityFields.deletedAt.encode(deletedAt),
        'serverVersion': TaskActivityFields.serverVersion.encode(serverVersion),
      },
    );
  }

  final EntityMutationSink _mutationSink;
  int _localRevision;
  Future<LocalMutationCommitResult> _generatedLocalCommit = Future.value(
    const LocalMutationCommitResult.success(),
  );
  Future<void> _generatedMutationCompletion(
    Future<LocalMutationCommitResult> commit,
  ) => _mutationSink.isInMutationTransaction
      ? Future<void>.value()
      : LocalMutationCompletion(commit);

  @override
  TaskActivity get generatedDomain => this;
  @override
  GeneratedEntityAccess<TaskActivity> get generatedAccess => this;
  @override
  GeneratedOrderedEntityAccess<TaskActivity>? get generatedOrderAccess => null;
  @override
  D? resolveGeneratedReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> descriptor,
    String? entityId,
  ) => _mutationSink.resolveReference(descriptor, entityId);
  @override
  Future<R> runGeneratedTransaction<R>(Future<R> Function() body) =>
      _mutationSink.runEntityTransaction(body);
  @override
  Future<void> recordGeneratedCommand(
    EntitySemanticCommand<TaskActivity> command,
  ) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskActivity',
        field: 'command',
        message: 'Deleted entities cannot be changed.',
      );
    }
    _generatedLocalCommit = _mutationSink.recordEntityCommand<TaskActivity>(
      entity: this,
      command: command,
      rollbackIfCurrent: () {},
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  void validateGeneratedDraft(int expectedRevision) {
    if (_localRevision != expectedRevision) {
      throw EntityDraftStateException(
        entityType: 'TaskActivity',
        entityId: generatedEntityId,
        reason: EntityDraftFailureReason.stale,
        message: 'The entity changed after this draft was created.',
      );
    }
    _mutationSink.validateDraftTarget(this);
  }

  @override
  Future<void> awaitGeneratedLocalCommit(int expectedRevision) async {
    if (_localRevision != expectedRevision) {
      throw EntityDraftStateException(
        entityType: 'TaskActivity',
        entityId: generatedEntityId,
        reason: EntityDraftFailureReason.stale,
        message: 'Another mutation replaced the draft commit.',
      );
    }
    final result = await _generatedLocalCommit;
    result.throwIfFailed();
  }

  @override
  final LocalId<TaskActivity> id;
  final Observable<LocalId<Account>> _ownerIdStore;
  @override
  LocalId<Account> get ownerId => _ownerIdStore.value;
  final Observable<LocalId<Task>> _subjectIdStore;
  @override
  LocalId<Task> get subjectId => _subjectIdStore.value;
  final Observable<LocalId<Account>> _actorIdStore;
  @override
  LocalId<Account> get actorId => _actorIdStore.value;
  final Observable<ActivityOperation> _operationStore;
  @override
  ActivityOperation get operation => _operationStore.value;
  final Observable<String> _labelStore;
  @override
  String get label => _labelStore.value;
  final Observable<String> _sourceOperationIdStore;
  @override
  String get sourceOperationId => _sourceOperationIdStore.value;
  final Observable<DateTime> _occurredAtStore;
  @override
  DateTime get occurredAt => _occurredAtStore.value;
  final Observable<DateTime?> _deletedAtStore;
  @override
  DateTime? get deletedAt => _deletedAtStore.value;
  final Observable<ServerVersion> _serverVersionStore;
  @override
  ServerVersion get serverVersion => _serverVersionStore.value;

  @override
  String get generatedEntityType => 'TaskActivity';
  @override
  String get generatedEntityId => id.value;
  @override
  String get generatedOwnerId => ownerId.value;
  @override
  bool generatedHasParticipant(String principalId) => false;
  @override
  ServerVersion get generatedServerVersion => serverVersion;
  @override
  int get generatedLocalRevision => _localRevision;

  @override
  JsonMap generatedCreateSnapshot() => {
    'id': TaskActivityFields.id.encode(id),
    'ownerId': TaskActivityFields.ownerId.encode(ownerId),
    'subjectId': TaskActivityFields.subjectId.encode(subjectId),
    'actorId': TaskActivityFields.actorId.encode(actorId),
    'operation': TaskActivityFields.operation.encode(operation),
    'label': TaskActivityFields.label.encode(label),
    'sourceOperationId': TaskActivityFields.sourceOperationId.encode(
      sourceOperationId,
    ),
    'occurredAt': TaskActivityFields.occurredAt.encode(occurredAt),
    'deletedAt': TaskActivityFields.deletedAt.encode(deletedAt),
  };

  @override
  JsonMap generatedSnapshot() => {
    'id': TaskActivityFields.id.encode(id),
    'ownerId': TaskActivityFields.ownerId.encode(ownerId),
    'subjectId': TaskActivityFields.subjectId.encode(subjectId),
    'actorId': TaskActivityFields.actorId.encode(actorId),
    'operation': TaskActivityFields.operation.encode(operation),
    'label': TaskActivityFields.label.encode(label),
    'sourceOperationId': TaskActivityFields.sourceOperationId.encode(
      sourceOperationId,
    ),
    'occurredAt': TaskActivityFields.occurredAt.encode(occurredAt),
    'deletedAt': TaskActivityFields.deletedAt.encode(deletedAt),
    'serverVersion': TaskActivityFields.serverVersion.encode(serverVersion),
  };

  @override
  void generatedApplyRemote({
    required JsonMap fields,
    required ServerVersion serverVersion,
    required int localRevision,
  }) {
    final hasOwnerId = fields.containsKey('ownerId');
    late final LocalId<Account> remoteOwnerId;
    if (hasOwnerId) {
      remoteOwnerId = TaskActivityFields.ownerId.decode(fields['ownerId']);
    }
    final hasSubjectId = fields.containsKey('subjectId');
    late final LocalId<Task> remoteSubjectId;
    if (hasSubjectId) {
      remoteSubjectId = TaskActivityFields.subjectId.decode(
        fields['subjectId'],
      );
    }
    final hasActorId = fields.containsKey('actorId');
    late final LocalId<Account> remoteActorId;
    if (hasActorId) {
      remoteActorId = TaskActivityFields.actorId.decode(fields['actorId']);
    }
    final hasOperation = fields.containsKey('operation');
    late final ActivityOperation remoteOperation;
    if (hasOperation) {
      remoteOperation = TaskActivityFields.operation.decode(
        fields['operation'],
      );
      if (remoteOperation.toScalar().trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'operation',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteOperation.toScalar().length > 160) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'operation',
          message: 'Must contain at most 160 character(s).',
        );
      }
    }
    final hasLabel = fields.containsKey('label');
    late final String remoteLabel;
    if (hasLabel) {
      remoteLabel = TaskActivityFields.label.decode(fields['label']);
      if (remoteLabel.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'label',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteLabel.length > 240) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'label',
          message: 'Must contain at most 240 character(s).',
        );
      }
    }
    final hasSourceOperationId = fields.containsKey('sourceOperationId');
    late final String remoteSourceOperationId;
    if (hasSourceOperationId) {
      remoteSourceOperationId = TaskActivityFields.sourceOperationId.decode(
        fields['sourceOperationId'],
      );
      if (remoteSourceOperationId.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'sourceOperationId',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteSourceOperationId.length > 64) {
        throw const EntityValidationException(
          entityType: 'TaskActivity',
          field: 'sourceOperationId',
          message: 'Must contain at most 64 character(s).',
        );
      }
    }
    final hasOccurredAt = fields.containsKey('occurredAt');
    late final DateTime remoteOccurredAt;
    if (hasOccurredAt) {
      remoteOccurredAt = TaskActivityFields.occurredAt.decode(
        fields['occurredAt'],
      );
    }
    final hasDeletedAt = fields.containsKey('deletedAt');
    late final DateTime? remoteDeletedAt;
    if (hasDeletedAt) {
      remoteDeletedAt = TaskActivityFields.deletedAt.decode(
        fields['deletedAt'],
      );
    }
    runInAction(() {
      if (hasOwnerId) {
        _ownerIdStore.value = remoteOwnerId;
      }
      if (hasSubjectId) {
        _subjectIdStore.value = remoteSubjectId;
      }
      if (hasActorId) {
        _actorIdStore.value = remoteActorId;
      }
      if (hasOperation) {
        _operationStore.value = remoteOperation;
      }
      if (hasLabel) {
        _labelStore.value = remoteLabel;
      }
      if (hasSourceOperationId) {
        _sourceOperationIdStore.value = remoteSourceOperationId;
      }
      if (hasOccurredAt) {
        _occurredAtStore.value = remoteOccurredAt;
      }
      if (hasDeletedAt) {
        _deletedAtStore.value = remoteDeletedAt;
      }
      _serverVersionStore.value = serverVersion;
      _localRevision = localRevision;
    });
  }
}

abstract final class TaskActivityFields {
  static const _idPersistence = EntityFieldDescriptor(
    name: 'id',
    columnName: 'id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final id =
      PersistedEqualityEntityField<TaskActivity, LocalId<TaskActivity>>(
        persistence: _idPersistence,
        read: (entity) => entity.id,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<TaskActivity>((source)! as String),
      );
  static const _ownerIdPersistence = EntityFieldDescriptor(
    name: 'ownerId',
    columnName: 'owner_id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final ownerId =
      PersistedEqualityEntityField<TaskActivity, LocalId<Account>>(
        persistence: _ownerIdPersistence,
        read: (entity) => entity.ownerId,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<Account>((source)! as String),
      );
  static const _subjectIdPersistence = EntityFieldDescriptor(
    name: 'subjectId',
    columnName: 'subject_id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
  );
  static final subjectId =
      PersistedEqualityEntityField<TaskActivity, LocalId<Task>>(
        persistence: _subjectIdPersistence,
        read: (entity) => entity.subjectId,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<Task>((source)! as String),
      );
  static const _actorIdPersistence = EntityFieldDescriptor(
    name: 'actorId',
    columnName: 'actor_id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
  );
  static final actorId =
      PersistedEqualityEntityField<TaskActivity, LocalId<Account>>(
        persistence: _actorIdPersistence,
        read: (entity) => entity.actorId,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<Account>((source)! as String),
      );
  static const _operationPersistence = EntityFieldDescriptor(
    name: 'operation',
    columnName: 'operation',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 160),
  );
  static final operation =
      PersistedEqualityEntityField<TaskActivity, ActivityOperation>(
        persistence: _operationPersistence,
        read: (entity) => entity.operation,
        encode: (value) => value.toScalar(),
        decode: (source) => ActivityOperation.fromScalar((source)! as String),
      );
  static const _labelPersistence = EntityFieldDescriptor(
    name: 'label',
    columnName: 'label',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 240),
  );
  static final label = PersistedComparableEntityField<TaskActivity, String>(
    persistence: _labelPersistence,
    read: (entity) => entity.label,
    encode: (value) => value,
    decode: (source) => (source)! as String,
  );
  static const _sourceOperationIdPersistence = EntityFieldDescriptor(
    name: 'sourceOperationId',
    columnName: 'source_operation_id',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 64),
  );
  static final sourceOperationId =
      PersistedComparableEntityField<TaskActivity, String>(
        persistence: _sourceOperationIdPersistence,
        read: (entity) => entity.sourceOperationId,
        encode: (value) => value,
        decode: (source) => (source)! as String,
      );
  static const _occurredAtPersistence = EntityFieldDescriptor(
    name: 'occurredAt',
    columnName: 'occurred_at',
    kind: EntityFieldKind.timestamp,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
  );
  static final occurredAt =
      PersistedComparableEntityField<TaskActivity, DateTime>(
        persistence: _occurredAtPersistence,
        read: (entity) => entity.occurredAt,
        encode: (value) => value.toUtc().toIso8601String(),
        decode: (source) => DateTime.parse((source)! as String).toUtc(),
      );
  static const _deletedAtPersistence = EntityFieldDescriptor(
    name: 'deletedAt',
    columnName: 'deleted_at',
    kind: EntityFieldKind.timestamp,
    nullable: true,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final deletedAt =
      PersistedNullableComparableEntityField<TaskActivity, DateTime>(
        persistence: _deletedAtPersistence,
        read: (entity) => entity.deletedAt,
        encode: (value) => value?.toUtc().toIso8601String(),
        decode: (source) =>
            source == null ? null : DateTime.parse(source as String).toUtc(),
      );
  static const _serverVersionPersistence = EntityFieldDescriptor(
    name: 'serverVersion',
    columnName: 'server_version',
    kind: EntityFieldKind.integer,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: true,
    protocolDefault: 0,
    inCreatePayload: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final serverVersion =
      PersistedComparableEntityField<TaskActivity, ServerVersion>(
        persistence: _serverVersionPersistence,
        read: (entity) => entity.serverVersion,
        encode: (value) => value.value,
        decode: (source) => parseServerVersion(source),
      );
  static final _persistence = <EntityFieldDescriptor>[
    id.persistence,
    ownerId.persistence,
    subjectId.persistence,
    actorId.persistence,
    operation.persistence,
    label.persistence,
    sourceOperationId.persistence,
    occurredAt.persistence,
    deletedAt.persistence,
    serverVersion.persistence,
  ];
}

final class TaskActivitySet {
  TaskActivitySet(LocalEntityEngine<TaskActivity, TaskActivityRecord> engine)
    : _engine = engine,
      _queries = LocalEntityQueryCache.database(
        loader: (spec, {required after, required limit}) =>
            engine.loadQueryPage(spec, after: after, limit: limit),
        invalidations: engine.projectionChanges,
      );
  final LocalEntityEngine<TaskActivity, TaskActivityRecord> _engine;
  final LocalEntityQueryCache<TaskActivity> _queries;
  Future<EntityLookupLease<TaskActivity>?> loadById(
    LocalId<TaskActivity> id, {
    bool refresh = false,
  }) => _engine.loadRawId(id.value, refresh: refresh);
  Future<R> useById<R>(
    LocalId<TaskActivity> id,
    LeaseAction<TaskActivity, R> action, {
    bool refresh = false,
  }) => loadById(id, refresh: refresh).use(
    action,
    ifAbsent: () => throw EntityNotFoundException(
      entityType: 'TaskActivity',
      entityId: id.value,
    ),
  );
  Stream<TaskActivity?> watchById(LocalId<TaskActivity> id) =>
      _engine.watchLoadedRawId(id.value);
  EntityLookup<TaskActivity> lookup(
    LocalId<TaskActivity> id, {
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => EntityLookup(
    query(
      where: TaskActivityFields.id.equals(id),
      tombstones: tombstones,
      pageSize: 1,
    ),
  );
  LocalEntityQuery<TaskActivity> query({
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) => _queries.acquire(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskActivity>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
  );
  Stream<EntityQueryState<TaskActivity>> watchQuery({
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskActivity>> observeFields =
        const [],
  }) => _queries.watch(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskActivity>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  Stream<EntityQueryState<TaskActivity>> watchCompleteQuery({
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskActivity>> observeFields =
        const [],
  }) => _queries.watchComplete(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskActivity>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  static EntityPredicate<TaskActivity> _tombstonePredicate(
    TombstoneVisibility visibility,
  ) => switch (visibility) {
    TombstoneVisibility.exclude => TaskActivityFields.deletedAt.isNull,
    TombstoneVisibility.include => EntityPredicate<TaskActivity>.all(),
    TombstoneVisibility.only => TaskActivityFields.deletedAt.isNotNull,
  };
  void dispose() => _queries.dispose();
}
