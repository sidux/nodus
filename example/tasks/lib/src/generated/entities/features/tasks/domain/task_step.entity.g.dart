// GENERATED FILE. DO NOT EDIT.
// Source: package:tasks_example/features/tasks/domain/task_step.dart
// ignore_for_file: invalid_null_aware_operator, type=lint

import 'package:drift/drift.dart';
import 'package:mobx/mobx.dart';
import 'package:nodus/nodus.dart';
import 'package:tasks_example/features/tasks/domain/task_step.dart';
import 'package:tasks_example/features/accounts/domain/account.dart';
import 'package:tasks_example/features/tasks/domain/task.dart';
import 'package:tasks_example/src/generated/entities/features/tasks/domain/task.entity.g.dart';

@TableIndex.sql(
  'CREATE INDEX task_steps_task_id_deleted_at_order_rank_id_idx ON task_steps (task_id, deleted_at, order_rank, id)',
)
@TableIndex.sql('CREATE INDEX task_steps_task_id_idx ON task_steps (task_id)')
@TableIndex.sql(
  'CREATE UNIQUE INDEX task_steps_task_id_title_active_idx ON task_steps (task_id, title) WHERE deleted_at IS NULL',
)
class TaskStepRows extends Table {
  @override
  String get tableName => 'task_steps';
  TextColumn get id => text().named('id')();
  TextColumn get ownerId => text().named('owner_id')();
  TextColumn get taskId => text().named('task_id')();
  TextColumn get title => text().named('title')();
  BoolColumn get done =>
      boolean().named('done').withDefault(const Constant(false))();
  TextColumn get orderRank => text()
      .named('order_rank')
      .withDefault(
        const Constant(
          '057896044618658097711785492504343953926634992332820282019728792003956564819967',
        ),
      )();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get serverVersion =>
      integer().named('server_version').withDefault(const Constant(0))();
  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(title)) >= 1)',
    'CHECK (length(title) <= 160)',
  ];
  IntColumn get localRevision => integer().named('local_revision')();
  TextColumn get acceptedSnapshot =>
      text().named('accepted_snapshot').nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

final class TaskStepDescriptor
    implements
        EntityDescriptor<TaskStep, TaskStepRecord>,
        EntityIdentityDescriptor<TaskStep>,
        EntityUniqueConstraintDescriptor,
        ActionPolicyProvider,
        ConvergentCreateDescriptor,
        OrderedDescriptor {
  const TaskStepDescriptor();

  @override
  EntityIdentity<TaskStep> nextIdentity(EntityIdGenerator generator) =>
      EntityIdentity(descriptor: this, id: generator.next<TaskStep>());
  @override
  EntityIdentity<TaskStep> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId(source));

  @override
  String get entityType => 'TaskStep';
  @override
  Cardinality get cardinality => Cardinality.unbounded;
  @override
  String get tableName => 'task_steps';
  @override
  String? get collaborationTableName => null;
  @override
  int get protocolVersion => 2;

  @override
  List<EntityFieldDescriptor> get orderScopeFields => const [
    TaskStepFields._ownerIdPersistence,
    TaskStepFields._taskIdPersistence,
  ];

  @override
  List<EntityFieldValueCondition> get orderMembershipConditions => const [
    EntityFieldValueCondition(
      field: TaskStepFields._deletedAtPersistence,
      value: null,
    ),
  ];

  @override
  bool isOrderMember(JsonMap fields) =>
      orderMembershipConditions.every((condition) => condition.matches(fields));

  @override
  String orderScopeKey(JsonMap fields) {
    if (!fields.containsKey('ownerId')) {
      throw const FormatException(
        'Expected TaskStep.ownerId in its ordered scope.',
      );
    }
    if (!fields.containsKey('taskId')) {
      throw const FormatException(
        'Expected TaskStep.taskId in its ordered scope.',
      );
    }
    return encodeOrderScopeKey([fields['ownerId'], fields['taskId']]);
  }

  @override
  List<EntityUniqueConstraint> get uniqueConstraints => const [
    EntityUniqueConstraint(
      name: 'task_steps_task_id_title_active_idx',
      fieldNames: ['taskId', 'title'],
      liveOnly: true,
    ),
  ];

  @override
  ActionPolicy get actionPolicy => const ActionPolicy(
    actions: [
      ActionDefinition(
        fieldNames: const ['done'],
        guardedFieldNames: const ['done'],
        assignments: [ActionAssignment.literal('done', true)],
      ),
      ActionDefinition(
        fieldNames: const ['done'],
        guardedFieldNames: const ['done'],
        assignments: [ActionAssignment.literal('done', false)],
      ),
    ],
    fixedInitialValues: {'done': false},
  );

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => switch (name) {
    'moveInOrder' => MoveOrderedCommand<TaskStep>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    _ => throw RejectedSyncException.validation(
      code: 'unsupported_command',
      message: 'Unsupported TaskStep semantic command.',
    ),
  };

  @override
  List<EntityFieldDescriptor> get fields => TaskStepFields._persistence;

  @override
  TaskStepRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) {
    return TaskStepRecord._(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: localRevision,
      id: TaskStepFields.id.decode(fields['id']),
      ownerId: TaskStepFields.ownerId.decode(fields['ownerId']),
      taskId: TaskStepFields.taskId.decode(fields['taskId']),
      title: TaskStepFields.title.decode(fields['title']),
      done: TaskStepFields.done.decode(fields['done']),
      orderRank: TaskStepFields._orderRank.decode(fields['orderRank']),
      deletedAt: TaskStepFields.deletedAt.decode(fields['deletedAt']),
      serverVersion: TaskStepFields.serverVersion.decode(
        fields['serverVersion'],
      ),
    );
  }
}

final class TaskStepRecord extends TaskStep
    implements
        TypedGeneratedEntityRecord<TaskStep>,
        GeneratedEntityAccess<TaskStep>,
        GeneratedOrderedEntityAccess<TaskStep> {
  TaskStepRecord._({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required int localRevision,
    required LocalId<TaskStep> id,
    required LocalId<Account> ownerId,
    required LocalId<Task> taskId,
    required String title,
    required bool done,
    required OrderRank orderRank,
    required DateTime? deletedAt,
    required ServerVersion serverVersion,
  }) : _mutationSink = mutationSink,
       _clock = clock,
       _localRevision = localRevision,
       id = id,
       _ownerIdStore = Observable(ownerId),
       _taskIdStore = Observable(taskId),
       _titleStore = Observable(title),
       _doneStore = Observable(done),
       _orderRankStore = Observable(orderRank),
       _deletedAtStore = Observable(deletedAt),
       _serverVersionStore = Observable(serverVersion) {
    if (title.trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'title',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (title.length > 160) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'title',
        message: 'Must contain at most 160 character(s).',
      );
    }
  }

  /// Creates an explicitly non-persisted preview or fixture.
  factory TaskStepRecord.detached({
    required LocalId<TaskStep> id,
    required LocalId<Account> ownerId,
    required LocalId<Task> taskId,
    required String title,
    bool done = false,
    DateTime? deletedAt,
    ServerVersion serverVersion = ServerVersion.zero,
    Clock clock = const SystemClock(),
    EntityMutationSink mutationSink = const DetachedEntityMutationSink(),
  }) {
    return const TaskStepDescriptor().instantiate(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: 0,
      fields: {
        'id': TaskStepFields.id.encode(id),
        'ownerId': TaskStepFields.ownerId.encode(ownerId),
        'taskId': TaskStepFields.taskId.encode(taskId),
        'title': TaskStepFields.title.encode(title),
        'done': TaskStepFields.done.encode(done),
        'orderRank': TaskStepFields._orderRank.encode(
          OrderRank.parse(
            '057896044618658097711785492504343953926634992332820282019728792003956564819967',
          ),
        ),
        'deletedAt': TaskStepFields.deletedAt.encode(deletedAt),
        'serverVersion': TaskStepFields.serverVersion.encode(serverVersion),
      },
    );
  }

  final EntityMutationSink _mutationSink;
  final Clock _clock;
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
  TaskStep get generatedDomain => this;
  @override
  GeneratedEntityAccess<TaskStep> get generatedAccess => this;
  @override
  GeneratedOrderedEntityAccess<TaskStep> get generatedOrderAccess => this;
  @override
  D? resolveGeneratedReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> descriptor,
    String? entityId,
  ) => _mutationSink.resolveReference(descriptor, entityId);
  @override
  Future<R> runGeneratedTransaction<R>(Future<R> Function() body) =>
      _mutationSink.runEntityTransaction(body);
  @override
  Future<void> recordGeneratedCommand(EntitySemanticCommand<TaskStep> command) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'command',
        message: 'Deleted entities cannot be changed.',
      );
    }
    _generatedLocalCommit = _mutationSink.recordEntityCommand<TaskStep>(
      entity: this,
      command: command,
      rollbackIfCurrent: () {},
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  void validateGeneratedDraft() {
    _mutationSink.validateDraftTarget(this);
  }

  @override
  Future<void> awaitGeneratedLocalCommit(int expectedRevision) async {
    if (_localRevision != expectedRevision) {
      throw EntityDraftStateException(
        entityType: 'TaskStep',
        entityId: generatedEntityId,
        reason: EntityDraftFailureReason.stale,
        message: 'Another mutation replaced the draft commit.',
      );
    }
    final result = await _generatedLocalCommit;
    result.throwIfFailed();
  }

  @override
  final LocalId<TaskStep> id;
  final Observable<LocalId<Account>> _ownerIdStore;
  @override
  LocalId<Account> get ownerId {
    assert(debugEntityFieldRead('TaskStep', 'ownerId'));
    return _ownerIdStore.value;
  }

  final Observable<LocalId<Task>> _taskIdStore;
  @override
  LocalId<Task> get taskId {
    assert(debugEntityFieldRead('TaskStep', 'taskId'));
    return _taskIdStore.value;
  }

  final Observable<String> _titleStore;
  @override
  String get title {
    assert(debugEntityFieldRead('TaskStep', 'title'));
    return _titleStore.value;
  }

  final Observable<bool> _doneStore;
  @override
  bool get done {
    assert(debugEntityFieldRead('TaskStep', 'done'));
    return _doneStore.value;
  }

  final Observable<OrderRank> _orderRankStore;
  @override
  OrderRank get generatedOrderRank => _orderRankStore.value;
  final Observable<DateTime?> _deletedAtStore;
  @override
  DateTime? get deletedAt {
    assert(debugEntityFieldRead('TaskStep', 'deletedAt'));
    return _deletedAtStore.value;
  }

  final Observable<ServerVersion> _serverVersionStore;
  @override
  ServerVersion get serverVersion {
    assert(debugEntityFieldRead('TaskStep', 'serverVersion'));
    return _serverVersionStore.value;
  }

  @override
  bool get generatedIsOrderMember => _deletedAtStore.value == null;

  @override
  String get generatedOrderScopeKey => encodeOrderScopeKey([
    TaskStepFields.ownerId.encode(_ownerIdStore.value),
    TaskStepFields.taskId.encode(_taskIdStore.value),
  ]);
  @override
  GeneratedOrderStateChange<TaskStep>? prepareGeneratedOrderRank(
    OrderRank rank,
  ) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final oldRank = _orderRankStore.value;
    if (oldRank == rank) return null;
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.update,
      principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
    );
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() => _orderRankStore.value = rank);
    final localPatch = TaskStepFields._orderRank.patch(rank);
    return GeneratedOrderStateChange(
      entity: this,
      scopeKey: generatedOrderScopeKey,
      patch: localPatch,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _orderRankStore.value = oldRank;
      },
      bindLocalCommit: (commit) => _generatedLocalCommit = commit,
    );
  }

  @override
  Future<void> recordGeneratedOrderMove({
    required OrderRank rank,
    required MoveOrderedCommand<TaskStep> command,
  }) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final change = prepareGeneratedOrderRank(rank);
    if (change == null) return Future.value();
    final commit = _mutationSink.recordEntityCommand<TaskStep>(
      entity: this,
      command: command,
      localPatch: change.patch,
      persistsEntityState: true,
      occurredAt: _clock.nowUtc(),
      rollbackIfCurrent: change.rollbackIfCurrent,
    );
    change.bindLocalCommit(commit);
    return _generatedMutationCompletion(commit);
  }

  @override
  Future<void> recordGeneratedExactOrder({
    required List<GeneratedOrderStateChange<TaskStep>> changes,
    required ReorderOrderedCommand<TaskStep> command,
  }) {
    if (changes.isEmpty) return Future.value();
    try {
      final commit = _mutationSink.recordEntityScopeCommand(
        entity: this,
        command: command,
        stateChanges: changes,
        scopeKey: generatedOrderScopeKey,
        occurredAt: _clock.nowUtc(),
      );
      for (final change in changes) {
        change.bindLocalCommit(commit);
      }
      return _generatedMutationCompletion(commit);
    } catch (_) {
      for (final change in changes.reversed) {
        change.rollbackIfCurrent();
      }
      rethrow;
    }
  }

  @override
  Future<void> check() {
    final _generatedActionTime = _clock.nowUtc();
    final oldDone = _doneStore.value;
    final nextDone = true;
    final doneChanged = oldDone != nextDone;
    if (!(doneChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'check',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (doneChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _doneStore.value = nextDone;
    });
    final syncPatch = TaskStepFields.done.patch(nextDone);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskStep>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _doneStore.value = oldDone;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> uncheck() {
    final _generatedActionTime = _clock.nowUtc();
    final oldDone = _doneStore.value;
    final nextDone = false;
    final doneChanged = oldDone != nextDone;
    if (!(doneChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'uncheck',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (doneChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _doneStore.value = nextDone;
    });
    final syncPatch = TaskStepFields.done.patch(nextDone);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskStep>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _doneStore.value = oldDone;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> remove() {
    final oldValue = _deletedAtStore.value;
    if (oldValue != null) return Future.value();
    final commandValue = _clock.nowUtc();
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.delete,
      principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
    );
    final mutationTime = commandValue;
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _deletedAtStore.value = commandValue;
    });
    final syncPatch = TaskStepFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskStep>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      operation: SyncMutationOperation.delete,
      kind: PushSyncWorkKind.semanticCommand,
      persistsEntityState: true,
      occurredAt: mutationTime,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _deletedAtStore.value = oldValue;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> restore() {
    final oldValue = _deletedAtStore.value;
    if (oldValue == null) return Future.value();
    const DateTime? commandValue = null;
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.delete,
      principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
    );
    final mutationTime = _clock.nowUtc();
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _deletedAtStore.value = commandValue;
    });
    final syncPatch = TaskStepFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskStep>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      operation: SyncMutationOperation.delete,
      kind: PushSyncWorkKind.semanticCommand,
      persistsEntityState: true,
      occurredAt: mutationTime,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _deletedAtStore.value = oldValue;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> applyGeneratedDraft({
    required TypedEntityPatch<TaskStep> base,
    required TypedEntityPatch<TaskStep> candidate,
  }) =>
      throw UnsupportedError('TaskStep has no ordinary draft-editable fields.');

  @override
  String get generatedEntityType => 'TaskStep';
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
    'id': TaskStepFields.id.encode(id),
    'ownerId': TaskStepFields.ownerId.encode(ownerId),
    'taskId': TaskStepFields.taskId.encode(taskId),
    'title': TaskStepFields.title.encode(title),
    'done': TaskStepFields.done.encode(done),
    'orderRank': TaskStepFields._orderRank.encode(generatedOrderRank),
  };

  @override
  JsonMap generatedSnapshot() => {
    'id': TaskStepFields.id.encode(id),
    'ownerId': TaskStepFields.ownerId.encode(ownerId),
    'taskId': TaskStepFields.taskId.encode(taskId),
    'title': TaskStepFields.title.encode(title),
    'done': TaskStepFields.done.encode(done),
    'orderRank': TaskStepFields._orderRank.encode(generatedOrderRank),
    'deletedAt': TaskStepFields.deletedAt.encode(deletedAt),
    'serverVersion': TaskStepFields.serverVersion.encode(serverVersion),
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
      remoteOwnerId = TaskStepFields.ownerId.decode(fields['ownerId']);
    }
    final hasTaskId = fields.containsKey('taskId');
    late final LocalId<Task> remoteTaskId;
    if (hasTaskId) {
      remoteTaskId = TaskStepFields.taskId.decode(fields['taskId']);
    }
    final hasTitle = fields.containsKey('title');
    late final String remoteTitle;
    if (hasTitle) {
      remoteTitle = TaskStepFields.title.decode(fields['title']);
      if (remoteTitle.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskStep',
          field: 'title',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteTitle.length > 160) {
        throw const EntityValidationException(
          entityType: 'TaskStep',
          field: 'title',
          message: 'Must contain at most 160 character(s).',
        );
      }
    }
    final hasDone = fields.containsKey('done');
    late final bool remoteDone;
    if (hasDone) {
      remoteDone = TaskStepFields.done.decode(fields['done']);
    }
    final hasOrderRank = fields.containsKey('orderRank');
    late final OrderRank remoteOrderRank;
    if (hasOrderRank) {
      remoteOrderRank = TaskStepFields._orderRank.decode(fields['orderRank']);
    }
    final hasDeletedAt = fields.containsKey('deletedAt');
    late final DateTime? remoteDeletedAt;
    if (hasDeletedAt) {
      remoteDeletedAt = TaskStepFields.deletedAt.decode(fields['deletedAt']);
    }
    runInAction(() {
      if (hasOwnerId) {
        _ownerIdStore.value = remoteOwnerId;
      }
      if (hasTaskId) {
        _taskIdStore.value = remoteTaskId;
      }
      if (hasTitle) {
        _titleStore.value = remoteTitle;
      }
      if (hasDone) {
        _doneStore.value = remoteDone;
      }
      if (hasOrderRank) {
        _orderRankStore.value = remoteOrderRank;
      }
      if (hasDeletedAt) {
        _deletedAtStore.value = remoteDeletedAt;
      }
      _serverVersionStore.value = serverVersion;
      _localRevision = localRevision;
    });
  }
}

extension TaskStepGeneratedEditing on TaskStep {
  TaskStepMutationDraft beginEdit() => TaskStepMutationDraft.edit(this);
}

final class TaskStepMutationDraft implements EntityMutationDraft<TaskStep> {
  TaskStepMutationDraft.create(
    this._set, {
    LocalId<TaskStep>? id,
    OrderedPlacement placement = OrderedPlacement.last,
  }) : _entity = null,
       _createId = id ?? _set!.allocateId(),
       _createPlacement = placement,
       _taskIdField = EntityDraftField<LocalId<Task>>.unset(),
       _titleField = EntityDraftField<String>.unset();
  TaskStepMutationDraft.edit(TaskStep entity)
    : _set = null,
      _entity = entity,
      _createId = null,
      _createPlacement = null,
      _taskIdField = EntityDraftField<LocalId<Task>>.value(
        entity.taskId,
        writable: false,
      ),
      _titleField = EntityDraftField<String>.value(
        entity.title,
        writable: false,
      );

  final TaskStepSet? _set;
  final TaskStep? _entity;
  final LocalId<TaskStep>? _createId;
  final OrderedPlacement? _createPlacement;
  bool _consumed = false;

  bool get isCreating => _entity == null;
  TaskStep? get entity => _entity;
  LocalId<TaskStep> get id => _entity?.id ?? _createId!;
  @override
  bool get isConsumed => _consumed;
  final EntityDraftField<LocalId<Task>> _taskIdField;
  EntityDraftField<LocalId<Task>> get taskIdField => _taskIdField;
  LocalId<Task> get taskId => _taskIdField.value;
  set taskId(LocalId<Task> value) => _taskIdField.value = value;
  final EntityDraftField<String> _titleField;
  EntityDraftField<String> get titleField => _titleField;
  String get title => _titleField.value;
  set title(String value) => _titleField.value = value;

  @override
  void discard() => _consumed = true;

  @override
  Future<TaskStep> save() async {
    if (_consumed) {
      throw EntityDraftStateException(
        entityType: 'TaskStep',
        entityId: _entity?.id.value ?? '<new>',
        reason: EntityDraftFailureReason.consumed,
        message: 'This mutation draft is already consumed.',
      );
    }
    final current = _entity;
    if (current == null) {
      final created = await _set!.createAt(
        id: _createId,
        placement: _createPlacement!,
        taskId: _taskIdField.requireValue(
          entityType: 'TaskStep',
          field: 'taskId',
        ),
        title: _titleField.requireValue(entityType: 'TaskStep', field: 'title'),
      );
      _consumed = true;
      return created;
    }
    current.generatedAccess.validateGeneratedDraft();
    await current.generatedAccess.runGeneratedTransaction(() async {});
    _consumed = true;
    return current;
  }
}

extension TaskStepGeneratedRelationships on TaskStep {
  Task? get task {
    return generatedAccess.resolveGeneratedReference(
      const TaskDescriptor(),
      this.taskId.value,
    );
  }
}

abstract final class TaskStepFields {
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
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final id = PersistedEqualityEntityField<TaskStep, LocalId<TaskStep>>(
    persistence: _idPersistence,
    read: (entity) => entity.id,
    encode: (value) => value.value,
    decode: (source) => parseLocalId<TaskStep>((source)! as String),
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
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final ownerId =
      PersistedEqualityEntityField<TaskStep, LocalId<Account>>(
        persistence: _ownerIdPersistence,
        read: (entity) => entity.ownerId,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<Account>((source)! as String),
      );
  static const _taskIdPersistence = EntityFieldDescriptor(
    name: 'taskId',
    columnName: 'task_id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    normalization: FieldNormalization.none,
    reference: EntityReferenceDescriptor(
      targetEntityType: 'Task',
      onDelete: ReferenceDeleteAction.cascade,
    ),
  );
  static final taskId = PersistedEqualityEntityField<TaskStep, LocalId<Task>>(
    persistence: _taskIdPersistence,
    read: (entity) => entity.taskId,
    encode: (value) => value.value,
    decode: (source) => parseLocalId<Task>((source)! as String),
  );
  static const _titlePersistence = EntityFieldDescriptor(
    name: 'title',
    columnName: 'title',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    normalization: FieldNormalization.none,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 160),
  );
  static final title = PersistedComparableEntityField<TaskStep, String>(
    persistence: _titlePersistence,
    read: (entity) => entity.title,
    encode: (value) => value,
    decode: (source) => (source)! as String,
  );
  static const _donePersistence = EntityFieldDescriptor(
    name: 'done',
    columnName: 'done',
    kind: EntityFieldKind.boolean,
    nullable: false,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: true,
    protocolDefault: false,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final done = PersistedEqualityEntityField<TaskStep, bool>(
    persistence: _donePersistence,
    read: (entity) => entity.done,
    encode: (value) => value,
    decode: (source) => (source)! as bool,
  );
  static const _orderRankPersistence = EntityFieldDescriptor(
    name: 'orderRank',
    columnName: 'order_rank',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 2,
    renamedFrom: null,
    hasProtocolDefault: true,
    protocolDefault:
        '057896044618658097711785492504343953926634992332820282019728792003956564819967',
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final _orderRank = PersistedComparableEntityField<TaskStep, OrderRank>(
    persistence: _orderRankPersistence,
    read: (entity) =>
        entity.generatedAccess.generatedOrderAccess!.generatedOrderRank,
    encode: (value) => value.value,
    decode: (source) => OrderRank.parse((source)! as String),
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
    inCreatePayload: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final deletedAt =
      PersistedNullableComparableEntityField<TaskStep, DateTime>(
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
    normalization: FieldNormalization.none,
    reference: null,
  );
  static final serverVersion =
      PersistedComparableEntityField<TaskStep, ServerVersion>(
        persistence: _serverVersionPersistence,
        read: (entity) => entity.serverVersion,
        encode: (value) => value.value,
        decode: (source) => parseServerVersion(source),
      );
  static final _persistence = <EntityFieldDescriptor>[
    id.persistence,
    ownerId.persistence,
    taskId.persistence,
    title.persistence,
    done.persistence,
    _orderRank.persistence,
    deletedAt.persistence,
    serverVersion.persistence,
  ];
}

final class TaskStepSet {
  TaskStepSet(LocalEntityEngine<TaskStep, TaskStepRecord> engine)
    : _engine = engine,
      _queries = LocalEntityQueryCache.database(
        loader: (spec, {required after, required limit}) =>
            engine.loadQueryPage(spec, after: after, limit: limit),
        invalidations: engine.projectionChanges,
      );
  final LocalEntityEngine<TaskStep, TaskStepRecord> _engine;
  final LocalEntityQueryCache<TaskStep> _queries;
  TaskStepMutationDraft beginCreate({
    LocalId<TaskStep>? id,
    OrderedPlacement placement = OrderedPlacement.last,
  }) => TaskStepMutationDraft.create(this, id: id, placement: placement);
  TaskStepMutationDraft beginEdit(TaskStep entity) => entity.beginEdit();
  Future<EntityLookupLease<TaskStep>?> loadById(
    LocalId<TaskStep> id, {
    bool refresh = false,
  }) => _engine.loadRawId(id.value, refresh: refresh);
  Future<EntityLookupLease<TaskStep>?> loadPresentById(
    LocalId<TaskStep> id, {
    bool refresh = false,
  }) async {
    final lease = await loadById(id, refresh: refresh);
    if (lease != null && lease.value.deletedAt != null) {
      lease.release();
      return null;
    }
    return lease;
  }

  Future<R> useById<R>(
    LocalId<TaskStep> id,
    LeaseAction<TaskStep, R> action, {
    bool refresh = false,
  }) => loadById(id, refresh: refresh).use(
    action,
    ifAbsent: () => throw EntityNotFoundException(
      entityType: 'TaskStep',
      entityId: id.value,
    ),
  );
  Future<R> usePresentById<R>(
    LocalId<TaskStep> id,
    LeaseAction<TaskStep, R> action, {
    bool refresh = false,
  }) => loadPresentById(id, refresh: refresh).use(
    action,
    ifAbsent: () => throw EntityNotFoundException(
      entityType: 'TaskStep',
      entityId: id.value,
    ),
  );
  Stream<TaskStep?> watchById(LocalId<TaskStep> id) =>
      _engine.watchLoadedRawId(id.value);
  EntityLookup<TaskStep> lookup(
    LocalId<TaskStep> id, {
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => EntityLookup(
    query(
      where: TaskStepFields.id.equals(id),
      tombstones: tombstones,
      pageSize: 1,
    ),
  );
  EntityExistence<TaskStep> exists({
    required EntityPredicate<TaskStep> where,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) =>
      EntityExistence(query(where: where, tombstones: tombstones, pageSize: 1));
  EntityFirst<TaskStep> first({
    EntityPredicate<TaskStep>? where,
    required EntityOrder<TaskStep> orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => EntityFirst(
    query(where: where, orderBy: orderBy, tombstones: tombstones, pageSize: 1),
  );
  LocalEntityQuery<TaskStep> query({
    EntityPredicate<TaskStep>? where,
    EntityOrder<TaskStep>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) => _queries.acquire(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskStep>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
  );
  EntityOrder<TaskStep> get canonicalOrder => TaskStepFields._orderRank
      .ascending(tieBreakBy: (entity) => entity.id.value);
  Future<void> prepend(LocalId<TaskStep> id) => _engine.moveInGeneratedOrder(
    entityId: id.value,
    placement: OrderedPlacement.first,
  );

  Future<void> append(LocalId<TaskStep> id) => _engine.moveInGeneratedOrder(
    entityId: id.value,
    placement: OrderedPlacement.last,
  );

  Future<void> moveBefore(LocalId<TaskStep> id, LocalId<TaskStep> neighborId) =>
      _engine.moveInGeneratedOrder(
        entityId: id.value,
        placement: OrderedPlacement.before,
        anchorId: neighborId.value,
      );

  Future<void> moveAfter(LocalId<TaskStep> id, LocalId<TaskStep> neighborId) =>
      _engine.moveInGeneratedOrder(
        entityId: id.value,
        placement: OrderedPlacement.after,
        anchorId: neighborId.value,
      );
  Stream<EntityQueryState<TaskStep>> watchQuery({
    EntityPredicate<TaskStep>? where,
    EntityOrder<TaskStep>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskStep>> observeFields = const [],
  }) => _queries.watch(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskStep>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  Stream<EntityQueryState<TaskStep>> watchCompleteQuery({
    EntityPredicate<TaskStep>? where,
    EntityOrder<TaskStep>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskStep>> observeFields = const [],
  }) => _queries.watchComplete(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskStep>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  LocalId<TaskStep> allocateId() => _engine.allocateId();
  Future<TaskStep> create({
    LocalId<TaskStep>? id,
    required LocalId<Task> taskId,
    required String title,
  }) => _create(first: false, id: id, taskId: taskId, title: title);
  Future<TaskStep> createFirst({
    LocalId<TaskStep>? id,
    required LocalId<Task> taskId,
    required String title,
  }) => _create(first: true, id: id, taskId: taskId, title: title);
  Future<TaskStep> createAt({
    LocalId<TaskStep>? id,
    OrderedPlacement placement = OrderedPlacement.last,
    required LocalId<Task> taskId,
    required String title,
  }) {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'order',
        message: 'Ordered creation supports only first or last placement.',
      );
    }
    return _create(
      first: placement == OrderedPlacement.first,
      id: id,
      taskId: taskId,
      title: title,
    );
  }

  Future<TaskStep> _create({
    required bool first,
    LocalId<TaskStep>? id,
    required LocalId<Task> taskId,
    required String title,
  }) {
    final ownershipSource = _engine.resolveReference(
      const TaskDescriptor(),
      taskId.value,
    );
    if (ownershipSource == null) {
      throw const EntityValidationException(
        entityType: 'TaskStep',
        field: 'taskId',
        message: 'Ownership reference is not loaded.',
      );
    }
    final inferredOwnerId = ownershipSource.ownerId;
    return _engine.createInGeneratedOrder(
      {
        'ownerId': TaskStepFields.ownerId.encode(inferredOwnerId),
        'taskId': TaskStepFields.taskId.encode(taskId),
        'title': TaskStepFields.title.encode(title),
        'done': TaskStepFields.done.encode(false),
      },
      principals: const [RlsPrincipal.owner, RlsPrincipal.reference],
      id: id,
      placement: first ? OrderedPlacement.first : OrderedPlacement.last,
    );
  }

  static EntityPredicate<TaskStep> _tombstonePredicate(
    TombstoneVisibility visibility,
  ) => switch (visibility) {
    TombstoneVisibility.exclude => TaskStepFields.deletedAt.isNull,
    TombstoneVisibility.include => EntityPredicate<TaskStep>.all(),
    TombstoneVisibility.only => TaskStepFields.deletedAt.isNotNull,
  };
  void dispose() => _queries.dispose();
}
