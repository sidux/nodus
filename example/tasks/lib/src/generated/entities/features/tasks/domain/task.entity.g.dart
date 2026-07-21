// GENERATED FILE. DO NOT EDIT.
// Source: package:tasks_example/features/tasks/domain/task.dart
// ignore_for_file: invalid_null_aware_operator, type=lint

import 'package:drift/drift.dart';
import 'package:mobx/mobx.dart';
import 'package:nodus/nodus.dart';
import 'package:tasks_example/features/tasks/domain/task.dart';
import 'package:tasks_example/features/accounts/domain/account.dart';
import 'package:tasks_example/features/tasks/domain/task_project.dart';
import 'package:tasks_example/src/generated/entities/features/tasks/domain/task_project.entity.g.dart';

@TableIndex.sql(
  'CREATE INDEX tasks_project_id_deleted_at_order_rank_id_idx ON tasks (project_id, deleted_at, order_rank, id)',
)
@TableIndex.sql('CREATE INDEX tasks_project_id_idx ON tasks (project_id)')
@TableIndex.sql(
  'CREATE INDEX tasks_owner_id_archived_at_idx ON tasks (owner_id, archived_at)',
)
@TableIndex.sql(
  'CREATE INDEX tasks_project_id_archived_at_deleted_at_status_due_at_id_idx ON tasks (project_id, archived_at, deleted_at, status, due_at, id)',
)
@TableIndex.sql(
  'CREATE INDEX tasks_project_id_archived_at_deleted_at_id_idx ON tasks (project_id, archived_at, deleted_at, id)',
)
class TaskRows extends Table {
  @override
  String get tableName => 'tasks';
  TextColumn get id => text().named('id')();
  TextColumn get ownerId => text().named('owner_id')();
  TextColumn get projectId => text().named('project_id').nullable()();
  TextColumn get title => text().named('title')();
  TextColumn get description => text().named('description').nullable()();
  TextColumn get status =>
      text().named('status').withDefault(const Constant('todo'))();
  TextColumn get priority =>
      text().named('priority').withDefault(const Constant('normal'))();
  TextColumn get dueAt => text().named('due_at').nullable()();
  TextColumn get completedAt => text().named('completed_at').nullable()();
  TextColumn get archivedAt => text().named('archived_at').nullable()();
  TextColumn get createdAt => text().named('created_at')();
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
    'CHECK (length(description) <= 1000)',
    'CHECK (status IN (\'todo\', \'in_progress\', \'done\'))',
    'CHECK (priority IN (\'low\', \'normal\', \'high\'))',
  ];
  IntColumn get localRevision => integer().named('local_revision')();
  TextColumn get acceptedSnapshot =>
      text().named('accepted_snapshot').nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

final class TaskDescriptor
    implements
        EntityDescriptor<Task, TaskRecord>,
        EntityIdentityDescriptor<Task>,
        ActionPolicyProvider,
        OrderedDescriptor,
        ActivityTrackedEntityDescriptor {
  const TaskDescriptor();

  @override
  EntityIdentity<Task> nextIdentity(EntityIdGenerator generator) =>
      EntityIdentity(descriptor: this, id: generator.next<Task>());
  @override
  EntityIdentity<Task> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId(source));

  @override
  String get entityType => 'Task';
  @override
  Cardinality get cardinality => Cardinality.unbounded;
  @override
  String get tableName => 'tasks';
  @override
  String? get collaborationTableName => 'task_members';
  @override
  int get protocolVersion => 3;

  @override
  String activityLabel(GeneratedEntityRecord entity) {
    if (entity is! TaskRecord) {
      throw StateError('Activity source does not belong to Task.');
    }
    final label = entity.activityLabel.trim();
    if (label.isEmpty || label.length > 240) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'activityLabel',
        message: 'An activity label must contain 1 to 240 characters.',
      );
    }
    return label;
  }

  @override
  List<EntityFieldDescriptor> get orderScopeFields => const [
    TaskFields._ownerIdPersistence,
    TaskFields._projectIdPersistence,
  ];

  @override
  List<EntityFieldValueCondition> get orderMembershipConditions => const [
    EntityFieldValueCondition(
      field: TaskFields._deletedAtPersistence,
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
        'Expected Task.ownerId in its ordered scope.',
      );
    }
    if (!fields.containsKey('projectId')) {
      throw const FormatException(
        'Expected Task.projectId in its ordered scope.',
      );
    }
    return encodeOrderScopeKey([fields['ownerId'], fields['projectId']]);
  }

  @override
  ActionPolicy get actionPolicy => const ActionPolicy(
    actions: [
      ActionDefinition(
        fieldNames: const ['status', 'completedAt'],
        guardedFieldNames: const ['status', 'completedAt'],
        assignments: [
          ActionAssignment.literal('status', 'in_progress'),
          ActionAssignment.clear('completedAt'),
        ],
      ),
      ActionDefinition(
        fieldNames: const ['status', 'completedAt'],
        guardedFieldNames: const ['status', 'completedAt'],
        assignments: [
          ActionAssignment.literal('status', 'done'),
          ActionAssignment.clockNow('completedAt', firstWriteOnly: true),
        ],
      ),
      ActionDefinition(
        fieldNames: const ['status', 'completedAt'],
        guardedFieldNames: const ['status', 'completedAt'],
        assignments: [
          ActionAssignment.literal('status', 'todo'),
          ActionAssignment.clear('completedAt'),
        ],
      ),
      ActionDefinition(
        fieldNames: const ['archivedAt'],
        guardedFieldNames: const ['archivedAt'],
        assignments: [
          ActionAssignment.clockNow('archivedAt', firstWriteOnly: true),
        ],
      ),
      ActionDefinition(
        fieldNames: const ['archivedAt'],
        guardedFieldNames: const ['archivedAt'],
        assignments: [ActionAssignment.clear('archivedAt')],
      ),
    ],
    fixedInitialValues: {'completedAt': null, 'archivedAt': null},
  );

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => switch (name) {
    'setCollaborator' => SetCollaboratorCommand<Task, Account>.fromWire(
      payload,
      parseId: parseLocalId<Account>,
    ),
    'moveInOrder' => MoveOrderedCommand<Task>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    'transferInOrder' => TransferOrderedCommand<Task>.fromWire(
      payload,
      entityType: 'Task',
      targetScopeFields: const [TaskFields._projectIdPersistence],
    ),
    _ => throw RejectedSyncException.validation(
      code: 'unsupported_command',
      message: 'Unsupported Task semantic command.',
    ),
  };

  @override
  List<EntityFieldDescriptor> get fields => TaskFields._persistence;

  @override
  TaskRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) {
    return TaskRecord._(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: localRevision,
      id: TaskFields.id.decode(fields['id']),
      ownerId: TaskFields.ownerId.decode(fields['ownerId']),
      projectId: TaskFields.projectId.decode(fields['projectId']),
      title: TaskFields.title.decode(fields['title']),
      description: TaskFields.description.decode(fields['description']),
      status: TaskFields.status.decode(fields['status']),
      priority: TaskFields.priority.decode(fields['priority']),
      dueAt: TaskFields.dueAt.decode(fields['dueAt']),
      completedAt: TaskFields.completedAt.decode(fields['completedAt']),
      archivedAt: TaskFields.archivedAt.decode(fields['archivedAt']),
      createdAt: TaskFields.createdAt.decode(fields['createdAt']),
      orderRank: TaskFields._orderRank.decode(fields['orderRank']),
      deletedAt: TaskFields.deletedAt.decode(fields['deletedAt']),
      serverVersion: TaskFields.serverVersion.decode(fields['serverVersion']),
    );
  }
}

final class TaskRecord extends Task
    implements
        TypedGeneratedEntityRecord<Task>,
        GeneratedEntityAccess<Task>,
        GeneratedOrderedEntityAccess<Task> {
  TaskRecord._({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required int localRevision,
    required LocalId<Task> id,
    required LocalId<Account> ownerId,
    required LocalId<TaskProject>? projectId,
    required String title,
    required String? description,
    required TaskStatus status,
    required TaskPriority priority,
    required DateTime? dueAt,
    required DateTime? completedAt,
    required DateTime? archivedAt,
    required DateTime createdAt,
    required OrderRank orderRank,
    required DateTime? deletedAt,
    required ServerVersion serverVersion,
  }) : _mutationSink = mutationSink,
       _clock = clock,
       _localRevision = localRevision,
       id = id,
       _ownerIdStore = Observable(ownerId),
       _projectIdStore = Observable(projectId),
       _titleStore = Observable(title),
       _descriptionStore = Observable(description),
       _statusStore = Observable(status),
       _priorityStore = Observable(priority),
       _dueAtStore = Observable(dueAt),
       _completedAtStore = Observable(completedAt),
       _archivedAtStore = Observable(archivedAt),
       _createdAtStore = Observable(createdAt),
       _orderRankStore = Observable(orderRank),
       _deletedAtStore = Observable(deletedAt),
       _serverVersionStore = Observable(serverVersion) {
    if (title.trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'title',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (title.length > 160) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'title',
        message: 'Must contain at most 160 character(s).',
      );
    }
    if (description != null && description.length > 1000) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'description',
        message: 'Must contain at most 1000 character(s).',
      );
    }
  }

  /// Creates an explicitly non-persisted preview or fixture.
  factory TaskRecord.detached({
    required LocalId<Task> id,
    required LocalId<Account> ownerId,
    LocalId<TaskProject>? projectId,
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
    DateTime? completedAt,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? deletedAt,
    ServerVersion serverVersion = ServerVersion.zero,
    Clock clock = const SystemClock(),
    EntityMutationSink mutationSink = const DetachedEntityMutationSink(),
  }) {
    final detachedNow = clock.nowUtc();
    return const TaskDescriptor().instantiate(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: 0,
      fields: {
        'id': TaskFields.id.encode(id),
        'ownerId': TaskFields.ownerId.encode(ownerId),
        'projectId': TaskFields.projectId.encode(projectId),
        'title': TaskFields.title.encode(title),
        'description': TaskFields.description.encode(description),
        'status': TaskFields.status.encode(status),
        'priority': TaskFields.priority.encode(priority),
        'dueAt': TaskFields.dueAt.encode(dueAt),
        'completedAt': TaskFields.completedAt.encode(completedAt),
        'archivedAt': TaskFields.archivedAt.encode(archivedAt),
        'createdAt': TaskFields.createdAt.encode(createdAt ?? detachedNow),
        'orderRank': TaskFields._orderRank.encode(
          OrderRank.parse(
            '057896044618658097711785492504343953926634992332820282019728792003956564819967',
          ),
        ),
        'deletedAt': TaskFields.deletedAt.encode(deletedAt),
        'serverVersion': TaskFields.serverVersion.encode(serverVersion),
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
  Task get generatedDomain => this;
  @override
  GeneratedEntityAccess<Task> get generatedAccess => this;
  @override
  GeneratedOrderedEntityAccess<Task> get generatedOrderAccess => this;
  @override
  D? resolveGeneratedReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> descriptor,
    String? entityId,
  ) => _mutationSink.resolveReference(descriptor, entityId);
  @override
  Future<R> runGeneratedTransaction<R>(Future<R> Function() body) =>
      _mutationSink.runEntityTransaction(body);
  @override
  Future<void> recordGeneratedCommand(EntitySemanticCommand<Task> command) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'command',
        message: 'Deleted entities cannot be changed.',
      );
    }
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.update,
      principals: const [RlsPrincipal.owner],
    );
    _generatedLocalCommit = _mutationSink.recordEntityCommand<Task>(
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
        entityType: 'Task',
        entityId: generatedEntityId,
        reason: EntityDraftFailureReason.stale,
        message: 'Another mutation replaced the draft commit.',
      );
    }
    final result = await _generatedLocalCommit;
    result.throwIfFailed();
  }

  @override
  final LocalId<Task> id;
  final Observable<LocalId<Account>> _ownerIdStore;
  @override
  LocalId<Account> get ownerId => _ownerIdStore.value;
  final Observable<LocalId<TaskProject>?> _projectIdStore;
  @override
  LocalId<TaskProject>? get projectId => _projectIdStore.value;
  final Observable<String> _titleStore;
  @override
  String get title => _titleStore.value;
  final Observable<String?> _descriptionStore;
  @override
  String? get description => _descriptionStore.value;
  final Observable<TaskStatus> _statusStore;
  @override
  TaskStatus get status => _statusStore.value;
  final Observable<TaskPriority> _priorityStore;
  @override
  TaskPriority get priority => _priorityStore.value;
  final Observable<DateTime?> _dueAtStore;
  @override
  DateTime? get dueAt => _dueAtStore.value;
  final Observable<DateTime?> _completedAtStore;
  @override
  DateTime? get completedAt => _completedAtStore.value;
  final Observable<DateTime?> _archivedAtStore;
  @override
  DateTime? get archivedAt => _archivedAtStore.value;
  final Observable<DateTime> _createdAtStore;
  @override
  DateTime get createdAt => _createdAtStore.value;
  final Observable<OrderRank> _orderRankStore;
  @override
  OrderRank get generatedOrderRank => _orderRankStore.value;
  final Observable<DateTime?> _deletedAtStore;
  @override
  DateTime? get deletedAt => _deletedAtStore.value;
  final Observable<ServerVersion> _serverVersionStore;
  @override
  ServerVersion get serverVersion => _serverVersionStore.value;
  @override
  bool get generatedIsOrderMember => _deletedAtStore.value == null;

  @override
  String get generatedOrderScopeKey => encodeOrderScopeKey([
    TaskFields.ownerId.encode(_ownerIdStore.value),
    TaskFields.projectId.encode(_projectIdStore.value),
  ]);
  @override
  GeneratedOrderStateChange<Task>? prepareGeneratedOrderRank(OrderRank rank) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final oldRank = _orderRankStore.value;
    if (oldRank == rank) return null;
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.update,
      principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
    );
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() => _orderRankStore.value = rank);
    final localPatch = TaskFields._orderRank.patch(rank);
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
    required MoveOrderedCommand<Task> command,
  }) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final change = prepareGeneratedOrderRank(rank);
    if (change == null) return Future.value();
    final commit = _mutationSink.recordEntityCommand<Task>(
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
    required List<GeneratedOrderStateChange<Task>> changes,
    required ReorderOrderedCommand<Task> command,
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
  Future<void> moveToProject({required LocalId<TaskProject>? projectId}) async {
    final _generatedActionTime = _clock.nowUtc();
    final oldProjectId = _projectIdStore.value;
    final nextProjectId = projectId;
    final projectIdChanged = oldProjectId != nextProjectId;
    if (!(projectIdChanged)) return;
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'moveToProject',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (projectIdChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final targetScope = EntityPatch.fromWire({
      'projectId': TaskFields.projectId.encode(nextProjectId),
    });
    final transferSink = switch (_mutationSink) {
      final OrderedTransferMutationSink value => value,
      _ => throw StateError(
        'The attached mutation sink does not support ordered scope transfers.',
      ),
    };
    final transferPlan = await transferSink.prepareEntityOrderTransfer<Task>(
      entity: this,
      targetScope: targetScope,
      placement: OrderedPlacement.last,
    );
    final oldOrderRank = _orderRankStore.value;
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _projectIdStore.value = nextProjectId;
      _orderRankStore.value = transferPlan.rank;
    });
    final localPatch = TaskFields.projectId
        .patch(nextProjectId)
        .merge(TaskFields._orderRank.patch(transferPlan.rank));
    final transferChange = GeneratedOrderStateChange(
      entity: this,
      scopeKey: transferPlan.targetScopeKey,
      patch: localPatch,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _projectIdStore.value = oldProjectId;
        _orderRankStore.value = oldOrderRank;
      },
      bindLocalCommit: (commit) => _generatedLocalCommit = commit,
    );
    try {
      final commit = transferSink.recordEntityOrderTransfer<Task>(
        entity: this,
        command: TransferOrderedCommand(
          targetScope: targetScope,
          placement: OrderedPlacement.last,
          sourceScopeBaseVersion: transferPlan.sourceScopeBaseVersion,
          targetScopeBaseVersion: transferPlan.targetScopeBaseVersion,
        ),
        transferChange: transferChange,
        targetRebalanceChanges: transferPlan.targetRebalanceChanges,
        occurredAt: _generatedActionTime,
      );
      transferChange.bindLocalCommit(commit);
      for (final change in transferPlan.targetRebalanceChanges) {
        change.bindLocalCommit(commit);
      }
      await _generatedMutationCompletion(commit);
      transferPlan.releasePreparedScopes();
      return;
    } catch (_) {
      transferChange.rollbackIfCurrent();
      transferPlan.rollbackPreparedChanges();
      rethrow;
    }
  }

  @override
  Future<void> start() {
    final _generatedActionTime = _clock.nowUtc();
    final oldStatus = _statusStore.value;
    final nextStatus = TaskStatus.inProgress;
    final statusChanged = oldStatus != nextStatus;
    final oldCompletedAt = _completedAtStore.value;
    final nextCompletedAt = null;
    final completedAtChanged = oldCompletedAt != nextCompletedAt;
    if (!(statusChanged || completedAtChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'start',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (statusChanged &&
        !((oldStatus == TaskStatus.todo &&
                nextStatus == TaskStatus.inProgress) ||
            (oldStatus == TaskStatus.todo && nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.todo) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.done && nextStatus == TaskStatus.todo))) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'status',
        message: 'State transition is not allowed.',
      );
    }
    if (statusChanged) {
      final _generatedStatusPrincipals = switch ((oldStatus, nextStatus)) {
        (TaskStatus.todo, TaskStatus.inProgress) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.todo, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.done, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        _ => const <RlsPrincipal>[],
      };
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: _generatedStatusPrincipals,
      );
    }
    if (completedAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _statusStore.value = nextStatus;
      _completedAtStore.value = nextCompletedAt;
    });
    final syncPatch = TaskFields.status
        .patch(nextStatus)
        .merge(TaskFields.completedAt.patch(nextCompletedAt));
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      activityOperation: ActivityOperation.action('start'),
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _statusStore.value = oldStatus;
        _completedAtStore.value = oldCompletedAt;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> complete() {
    final _generatedActionTime = _clock.nowUtc();
    final oldStatus = _statusStore.value;
    final nextStatus = TaskStatus.done;
    final statusChanged = oldStatus != nextStatus;
    final oldCompletedAt = _completedAtStore.value;
    final nextCompletedAt = oldCompletedAt ?? _generatedActionTime;
    final completedAtChanged = oldCompletedAt != nextCompletedAt;
    if (!(statusChanged || completedAtChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'complete',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (statusChanged &&
        !((oldStatus == TaskStatus.todo &&
                nextStatus == TaskStatus.inProgress) ||
            (oldStatus == TaskStatus.todo && nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.todo) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.done && nextStatus == TaskStatus.todo))) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'status',
        message: 'State transition is not allowed.',
      );
    }
    if (statusChanged) {
      final _generatedStatusPrincipals = switch ((oldStatus, nextStatus)) {
        (TaskStatus.todo, TaskStatus.inProgress) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.todo, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.done, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        _ => const <RlsPrincipal>[],
      };
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: _generatedStatusPrincipals,
      );
    }
    if (completedAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _statusStore.value = nextStatus;
      _completedAtStore.value = nextCompletedAt;
    });
    final syncPatch = TaskFields.status
        .patch(nextStatus)
        .merge(TaskFields.completedAt.patch(nextCompletedAt));
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      activityOperation: ActivityOperation.action('complete'),
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _statusStore.value = oldStatus;
        _completedAtStore.value = oldCompletedAt;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> reopen() {
    final _generatedActionTime = _clock.nowUtc();
    final oldStatus = _statusStore.value;
    final nextStatus = TaskStatus.todo;
    final statusChanged = oldStatus != nextStatus;
    final oldCompletedAt = _completedAtStore.value;
    final nextCompletedAt = null;
    final completedAtChanged = oldCompletedAt != nextCompletedAt;
    if (!(statusChanged || completedAtChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'reopen',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (statusChanged &&
        !((oldStatus == TaskStatus.todo &&
                nextStatus == TaskStatus.inProgress) ||
            (oldStatus == TaskStatus.todo && nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.todo) ||
            (oldStatus == TaskStatus.inProgress &&
                nextStatus == TaskStatus.done) ||
            (oldStatus == TaskStatus.done && nextStatus == TaskStatus.todo))) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'status',
        message: 'State transition is not allowed.',
      );
    }
    if (statusChanged) {
      final _generatedStatusPrincipals = switch ((oldStatus, nextStatus)) {
        (TaskStatus.todo, TaskStatus.inProgress) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.todo, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.inProgress, TaskStatus.done) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        (TaskStatus.done, TaskStatus.todo) => const [
          RlsPrincipal.owner,
          RlsPrincipal.collaborator,
        ],
        _ => const <RlsPrincipal>[],
      };
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: _generatedStatusPrincipals,
      );
    }
    if (completedAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _statusStore.value = nextStatus;
      _completedAtStore.value = nextCompletedAt;
    });
    final syncPatch = TaskFields.status
        .patch(nextStatus)
        .merge(TaskFields.completedAt.patch(nextCompletedAt));
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      activityOperation: ActivityOperation.action('reopen'),
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _statusStore.value = oldStatus;
        _completedAtStore.value = oldCompletedAt;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> archive() {
    final _generatedActionTime = _clock.nowUtc();
    final oldArchivedAt = _archivedAtStore.value;
    final nextArchivedAt = oldArchivedAt ?? _generatedActionTime;
    final archivedAtChanged = oldArchivedAt != nextArchivedAt;
    if (!(archivedAtChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'archive',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (archivedAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _archivedAtStore.value = nextArchivedAt;
    });
    final syncPatch = TaskFields.archivedAt.patch(nextArchivedAt);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      activityOperation: ActivityOperation.archived,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _archivedAtStore.value = oldArchivedAt;
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> unarchive() {
    final _generatedActionTime = _clock.nowUtc();
    final oldArchivedAt = _archivedAtStore.value;
    final nextArchivedAt = null;
    final archivedAtChanged = oldArchivedAt != nextArchivedAt;
    if (!(archivedAtChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'unarchive',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (archivedAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _archivedAtStore.value = nextArchivedAt;
    });
    final syncPatch = TaskFields.archivedAt.patch(nextArchivedAt);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: _generatedActionTime,
      activityOperation: ActivityOperation.unarchived,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        _archivedAtStore.value = oldArchivedAt;
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
      principals: const [RlsPrincipal.owner],
    );
    final mutationTime = commandValue;
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _deletedAtStore.value = commandValue;
    });
    final syncPatch = TaskFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      operation: SyncMutationOperation.delete,
      kind: PushSyncWorkKind.semanticCommand,
      persistsEntityState: true,
      occurredAt: mutationTime,
      activityOperation: ActivityOperation.removed,
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
      principals: const [RlsPrincipal.owner],
    );
    final mutationTime = _clock.nowUtc();
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _deletedAtStore.value = commandValue;
    });
    final syncPatch = TaskFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      operation: SyncMutationOperation.delete,
      kind: PushSyncWorkKind.semanticCommand,
      persistsEntityState: true,
      occurredAt: mutationTime,
      activityOperation: ActivityOperation.restored,
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
    required TypedEntityPatch<Task> base,
    required TypedEntityPatch<Task> candidate,
  }) {
    final baseTitle = TaskFields.title.decode(base['title']);
    final candidateTitle = TaskFields.title.decode(candidate['title']);
    final baseDescription = TaskFields.description.decode(base['description']);
    final candidateDescription = TaskFields.description.decode(
      candidate['description'],
    );
    final basePriority = TaskFields.priority.decode(base['priority']);
    final candidatePriority = TaskFields.priority.decode(candidate['priority']);
    final baseDueAt = TaskFields.dueAt.decode(base['dueAt']);
    final candidateDueAt = TaskFields.dueAt.decode(candidate['dueAt']);
    final nextTitle = candidateTitle;
    final titleDraftChanged = baseTitle != nextTitle;
    final titleCurrentChanged = baseTitle != _titleStore.value;
    final titleChanged = titleDraftChanged && _titleStore.value != nextTitle;
    final titleOverlaps = titleChanged && titleCurrentChanged;
    final nextDescription = candidateDescription;
    final descriptionDraftChanged = baseDescription != nextDescription;
    final descriptionCurrentChanged =
        baseDescription != _descriptionStore.value;
    final descriptionChanged =
        descriptionDraftChanged && _descriptionStore.value != nextDescription;
    final descriptionOverlaps = descriptionChanged && descriptionCurrentChanged;
    final nextPriority = candidatePriority;
    final priorityDraftChanged = basePriority != nextPriority;
    final priorityCurrentChanged = basePriority != _priorityStore.value;
    final priorityChanged =
        priorityDraftChanged && _priorityStore.value != nextPriority;
    final priorityOverlaps = priorityChanged && priorityCurrentChanged;
    final nextDueAt = candidateDueAt?.toUtc();
    final dueAtDraftChanged = baseDueAt != nextDueAt;
    final dueAtCurrentChanged = baseDueAt != _dueAtStore.value;
    final dueAtChanged = dueAtDraftChanged && _dueAtStore.value != nextDueAt;
    final dueAtOverlaps = dueAtChanged && dueAtCurrentChanged;
    if (titleOverlaps ||
        descriptionOverlaps ||
        priorityOverlaps ||
        dueAtOverlaps) {
      throw EntityDraftFieldConflictException(
        entityType: 'Task',
        entityId: generatedEntityId,
        fields: [
          if (titleOverlaps) 'title',
          if (descriptionOverlaps) 'description',
          if (priorityOverlaps) 'priority',
          if (dueAtOverlaps) 'dueAt',
        ],
      );
    }
    if (!(titleChanged ||
        descriptionChanged ||
        priorityChanged ||
        dueAtChanged))
      return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'Task',
        field: 'draft',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (titleChanged) {
      if (nextTitle.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'title',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (nextTitle.length > 160) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'title',
          message: 'Must contain at most 160 character(s).',
        );
      }
    }
    if (descriptionChanged) {
      if (nextDescription != null && nextDescription.length > 1000) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'description',
          message: 'Must contain at most 1000 character(s).',
        );
      }
    }
    if (titleChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    if (descriptionChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    if (priorityChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    if (dueAtChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
      );
    }
    final mutationTime = _clock.nowUtc();
    final oldTitle = _titleStore.value;
    final oldDescription = _descriptionStore.value;
    final oldPriority = _priorityStore.value;
    final oldDueAt = _dueAtStore.value;
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      if (titleChanged) {
        _titleStore.value = nextTitle;
      }
      if (descriptionChanged) {
        _descriptionStore.value = nextDescription;
      }
      if (priorityChanged) {
        _priorityStore.value = nextPriority;
      }
      if (dueAtChanged) {
        _dueAtStore.value = nextDueAt;
      }
    });
    var generatedDraftPatch = TypedEntityPatch<Task>.empty();
    if (titleChanged) {
      final fieldPatch = TaskFields.title.patch(nextTitle);
      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);
    }
    if (descriptionChanged) {
      final fieldPatch = TaskFields.description.patch(nextDescription);
      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);
    }
    if (priorityChanged) {
      final fieldPatch = TaskFields.priority.patch(nextPriority);
      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);
    }
    if (dueAtChanged) {
      final fieldPatch = TaskFields.dueAt.patch(nextDueAt);
      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);
    }
    final syncPatch = generatedDraftPatch;
    _generatedLocalCommit = _mutationSink.recordEntityMutation<Task>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: mutationTime,
      activityOperation: ActivityOperation.action('edit'),
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        if (titleChanged) {
          _titleStore.value = oldTitle;
        }
        if (descriptionChanged) {
          _descriptionStore.value = oldDescription;
        }
        if (priorityChanged) {
          _priorityStore.value = oldPriority;
        }
        if (dueAtChanged) {
          _dueAtStore.value = oldDueAt;
        }
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  Future<void> setCollaborator(
    LocalId<Account> collaboratorId, {
    required bool active,
  }) => recordGeneratedCommand(
    SetCollaboratorCommand<Task, Account>(
      collaboratorId: collaboratorId,
      active: active,
    ),
  );

  @override
  String get generatedEntityType => 'Task';
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
    'id': TaskFields.id.encode(id),
    'ownerId': TaskFields.ownerId.encode(ownerId),
    'projectId': TaskFields.projectId.encode(projectId),
    'title': TaskFields.title.encode(title),
    'description': TaskFields.description.encode(description),
    'status': TaskFields.status.encode(status),
    'priority': TaskFields.priority.encode(priority),
    'dueAt': TaskFields.dueAt.encode(dueAt),
    'completedAt': TaskFields.completedAt.encode(completedAt),
    'archivedAt': TaskFields.archivedAt.encode(archivedAt),
    'orderRank': TaskFields._orderRank.encode(generatedOrderRank),
  };

  @override
  JsonMap generatedSnapshot() => {
    'id': TaskFields.id.encode(id),
    'ownerId': TaskFields.ownerId.encode(ownerId),
    'projectId': TaskFields.projectId.encode(projectId),
    'title': TaskFields.title.encode(title),
    'description': TaskFields.description.encode(description),
    'status': TaskFields.status.encode(status),
    'priority': TaskFields.priority.encode(priority),
    'dueAt': TaskFields.dueAt.encode(dueAt),
    'completedAt': TaskFields.completedAt.encode(completedAt),
    'archivedAt': TaskFields.archivedAt.encode(archivedAt),
    'createdAt': TaskFields.createdAt.encode(createdAt),
    'orderRank': TaskFields._orderRank.encode(generatedOrderRank),
    'deletedAt': TaskFields.deletedAt.encode(deletedAt),
    'serverVersion': TaskFields.serverVersion.encode(serverVersion),
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
      remoteOwnerId = TaskFields.ownerId.decode(fields['ownerId']);
    }
    final hasProjectId = fields.containsKey('projectId');
    late final LocalId<TaskProject>? remoteProjectId;
    if (hasProjectId) {
      remoteProjectId = TaskFields.projectId.decode(fields['projectId']);
    }
    final hasTitle = fields.containsKey('title');
    late final String remoteTitle;
    if (hasTitle) {
      remoteTitle = TaskFields.title.decode(fields['title']);
      if (remoteTitle.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'title',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteTitle.length > 160) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'title',
          message: 'Must contain at most 160 character(s).',
        );
      }
    }
    final hasDescription = fields.containsKey('description');
    late final String? remoteDescription;
    if (hasDescription) {
      remoteDescription = TaskFields.description.decode(fields['description']);
      if (remoteDescription != null && remoteDescription.length > 1000) {
        throw const EntityValidationException(
          entityType: 'Task',
          field: 'description',
          message: 'Must contain at most 1000 character(s).',
        );
      }
    }
    final hasStatus = fields.containsKey('status');
    late final TaskStatus remoteStatus;
    if (hasStatus) {
      remoteStatus = TaskFields.status.decode(fields['status']);
    }
    final hasPriority = fields.containsKey('priority');
    late final TaskPriority remotePriority;
    if (hasPriority) {
      remotePriority = TaskFields.priority.decode(fields['priority']);
    }
    final hasDueAt = fields.containsKey('dueAt');
    late final DateTime? remoteDueAt;
    if (hasDueAt) {
      remoteDueAt = TaskFields.dueAt.decode(fields['dueAt']);
    }
    final hasCompletedAt = fields.containsKey('completedAt');
    late final DateTime? remoteCompletedAt;
    if (hasCompletedAt) {
      remoteCompletedAt = TaskFields.completedAt.decode(fields['completedAt']);
    }
    final hasArchivedAt = fields.containsKey('archivedAt');
    late final DateTime? remoteArchivedAt;
    if (hasArchivedAt) {
      remoteArchivedAt = TaskFields.archivedAt.decode(fields['archivedAt']);
    }
    final hasCreatedAt = fields.containsKey('createdAt');
    late final DateTime remoteCreatedAt;
    if (hasCreatedAt) {
      remoteCreatedAt = TaskFields.createdAt.decode(fields['createdAt']);
    }
    final hasOrderRank = fields.containsKey('orderRank');
    late final OrderRank remoteOrderRank;
    if (hasOrderRank) {
      remoteOrderRank = TaskFields._orderRank.decode(fields['orderRank']);
    }
    final hasDeletedAt = fields.containsKey('deletedAt');
    late final DateTime? remoteDeletedAt;
    if (hasDeletedAt) {
      remoteDeletedAt = TaskFields.deletedAt.decode(fields['deletedAt']);
    }
    runInAction(() {
      if (hasOwnerId) {
        _ownerIdStore.value = remoteOwnerId;
      }
      if (hasProjectId) {
        _projectIdStore.value = remoteProjectId;
      }
      if (hasTitle) {
        _titleStore.value = remoteTitle;
      }
      if (hasDescription) {
        _descriptionStore.value = remoteDescription;
      }
      if (hasStatus) {
        _statusStore.value = remoteStatus;
      }
      if (hasPriority) {
        _priorityStore.value = remotePriority;
      }
      if (hasDueAt) {
        _dueAtStore.value = remoteDueAt;
      }
      if (hasCompletedAt) {
        _completedAtStore.value = remoteCompletedAt;
      }
      if (hasArchivedAt) {
        _archivedAtStore.value = remoteArchivedAt;
      }
      if (hasCreatedAt) {
        _createdAtStore.value = remoteCreatedAt;
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

extension TaskGeneratedEditing on Task {
  TaskMutationDraft beginEdit() => TaskMutationDraft.edit(this);
}

final class TaskMutationDraft implements EntityMutationDraft<Task> {
  TaskMutationDraft.create(this._set)
    : _entity = null,
      _baseTitle = null,
      _baseDescription = null,
      _basePriority = null,
      _baseDueAt = null,
      _baseProjectId = null,
      _projectIdField = EntityDraftField<LocalId<TaskProject>?>.value(null),
      _titleField = EntityDraftField<String>.unset(),
      _descriptionField = EntityDraftField<String?>.value(null),
      _priorityField = EntityDraftField<TaskPriority>.value(
        TaskPriority.normal,
      ),
      _dueAtField = EntityDraftField<DateTime?>.value(null);
  TaskMutationDraft.edit(Task entity)
    : _set = null,
      _entity = entity,
      _baseTitle = entity.title,
      _baseDescription = entity.description,
      _basePriority = entity.priority,
      _baseDueAt = entity.dueAt,
      _baseProjectId = entity.projectId,
      _projectIdField = EntityDraftField<LocalId<TaskProject>?>.value(
        entity.projectId,
      ),
      _titleField = EntityDraftField<String>.value(entity.title),
      _descriptionField = EntityDraftField<String?>.value(entity.description),
      _priorityField = EntityDraftField<TaskPriority>.value(entity.priority),
      _dueAtField = EntityDraftField<DateTime?>.value(entity.dueAt);

  final TaskSet? _set;
  final Task? _entity;
  final String? _baseTitle;
  final String? _baseDescription;
  final TaskPriority? _basePriority;
  final DateTime? _baseDueAt;
  final LocalId<TaskProject>? _baseProjectId;
  bool _consumed = false;

  bool get isCreating => _entity == null;
  Task? get entity => _entity;
  @override
  bool get isConsumed => _consumed;
  final EntityDraftField<LocalId<TaskProject>?> _projectIdField;
  EntityDraftField<LocalId<TaskProject>?> get projectIdField => _projectIdField;
  LocalId<TaskProject>? get projectId => _projectIdField.value;
  set projectId(LocalId<TaskProject>? value) => _projectIdField.value = value;
  final EntityDraftField<String> _titleField;
  EntityDraftField<String> get titleField => _titleField;
  String get title => _titleField.value;
  set title(String value) => _titleField.value = value;
  final EntityDraftField<String?> _descriptionField;
  EntityDraftField<String?> get descriptionField => _descriptionField;
  String? get description => _descriptionField.value;
  set description(String? value) => _descriptionField.value = value;
  final EntityDraftField<TaskPriority> _priorityField;
  EntityDraftField<TaskPriority> get priorityField => _priorityField;
  TaskPriority get priority => _priorityField.value;
  set priority(TaskPriority value) => _priorityField.value = value;
  final EntityDraftField<DateTime?> _dueAtField;
  EntityDraftField<DateTime?> get dueAtField => _dueAtField;
  DateTime? get dueAt => _dueAtField.value;
  set dueAt(DateTime? value) => _dueAtField.value = value;

  @override
  void discard() => _consumed = true;

  @override
  Future<Task> save() async {
    if (_consumed) {
      throw EntityDraftStateException(
        entityType: 'Task',
        entityId: _entity?.id.value ?? '<new>',
        reason: EntityDraftFailureReason.consumed,
        message: 'This mutation draft is already consumed.',
      );
    }
    final current = _entity;
    if (current == null) {
      final created = await _set!.create(
        projectId: _projectIdField.requireValue(
          entityType: 'Task',
          field: 'projectId',
        ),
        title: _titleField.requireValue(entityType: 'Task', field: 'title'),
        description: _descriptionField.requireValue(
          entityType: 'Task',
          field: 'description',
        ),
        priority: _priorityField.requireValue(
          entityType: 'Task',
          field: 'priority',
        ),
        dueAt: _dueAtField.requireValue(entityType: 'Task', field: 'dueAt'),
      );
      _consumed = true;
      return created;
    }
    current.generatedAccess.validateGeneratedDraft();
    if (_baseProjectId != projectId &&
        _baseProjectId != current.projectId &&
        current.projectId != projectId) {
      throw EntityDraftFieldConflictException(
        entityType: 'Task',
        entityId: current.id.value,
        fields: [
          if (_baseProjectId != projectId &&
              _baseProjectId != current.projectId &&
              current.projectId != projectId)
            'projectId',
        ],
      );
    }
    await current.generatedAccess.runGeneratedTransaction(() async {
      final generatedDraftBase = TaskFields.title
          .patch(_baseTitle as String)
          .merge(TaskFields.description.patch(_baseDescription))
          .merge(TaskFields.priority.patch(_basePriority as TaskPriority))
          .merge(TaskFields.dueAt.patch(_baseDueAt));
      final generatedDraftCandidate = TaskFields.title
          .patch(title)
          .merge(TaskFields.description.patch(description))
          .merge(TaskFields.priority.patch(priority))
          .merge(TaskFields.dueAt.patch(dueAt));
      await current.generatedAccess.applyGeneratedDraft(
        base: generatedDraftBase,
        candidate: generatedDraftCandidate,
      );
      if (projectId != current.projectId) {
        await current.moveToProject(projectId: projectId);
      }
    });
    _consumed = true;
    return current;
  }
}

extension TaskGeneratedRelationships on Task {
  TaskProject? get project {
    return generatedAccess.resolveGeneratedReference(
      const TaskProjectDescriptor(),
      projectId?.value,
    );
  }
}

abstract final class TaskFields {
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
  static final id = PersistedEqualityEntityField<Task, LocalId<Task>>(
    persistence: _idPersistence,
    read: (entity) => entity.id,
    encode: (value) => value.value,
    decode: (source) => parseLocalId<Task>((source)! as String),
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
  static final ownerId = PersistedEqualityEntityField<Task, LocalId<Account>>(
    persistence: _ownerIdPersistence,
    read: (entity) => entity.ownerId,
    encode: (value) => value.value,
    decode: (source) => parseLocalId<Account>((source)! as String),
  );
  static const _projectIdPersistence = EntityFieldDescriptor(
    name: 'projectId',
    columnName: 'project_id',
    kind: EntityFieldKind.uuid,
    nullable: true,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: EntityReferenceDescriptor(
      targetEntityType: 'TaskProject',
      onDelete: ReferenceDeleteAction.setNull,
    ),
  );
  static final projectId =
      PersistedNullableEntityField<Task, LocalId<TaskProject>>(
        persistence: _projectIdPersistence,
        read: (entity) => entity.projectId,
        encode: (value) => value?.value,
        decode: (source) =>
            source == null ? null : parseLocalId<TaskProject>(source as String),
      );
  static const _titlePersistence = EntityFieldDescriptor(
    name: 'title',
    columnName: 'title',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 160),
  );
  static final title = PersistedComparableEntityField<Task, String>(
    persistence: _titlePersistence,
    read: (entity) => entity.title,
    encode: (value) => value,
    decode: (source) => (source)! as String,
  );
  static const _descriptionPersistence = EntityFieldDescriptor(
    name: 'description',
    columnName: 'description',
    kind: EntityFieldKind.text,
    nullable: true,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
    constraints: EntityFieldConstraints(maxLength: 1000),
  );
  static final description =
      PersistedNullableComparableEntityField<Task, String>(
        persistence: _descriptionPersistence,
        read: (entity) => entity.description,
        encode: (value) => value,
        decode: (source) => source as String?,
      );
  static const _statusPersistence = EntityFieldDescriptor(
    name: 'status',
    columnName: 'status',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: true,
    protocolDefault: 'todo',
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
    allowedTransitions: const [
      EntityValueTransition('todo', 'in_progress'),
      EntityValueTransition('todo', 'done'),
      EntityValueTransition('in_progress', 'todo'),
      EntityValueTransition('in_progress', 'done'),
      EntityValueTransition('done', 'todo'),
    ],
  );
  static final status = PersistedEqualityEntityField<Task, TaskStatus>(
    persistence: _statusPersistence,
    read: (entity) => entity.status,
    encode: (value) => switch (value) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.done => 'done',
    },
    decode: (source) => switch (source) {
      'todo' => TaskStatus.todo,
      'in_progress' => TaskStatus.inProgress,
      'done' => TaskStatus.done,
      _ => throw const FormatException('Invalid enum `status`.'),
    },
  );
  static const _priorityPersistence = EntityFieldDescriptor(
    name: 'priority',
    columnName: 'priority',
    kind: EntityFieldKind.text,
    nullable: false,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: true,
    protocolDefault: 'normal',
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final priority = PersistedEqualityEntityField<Task, TaskPriority>(
    persistence: _priorityPersistence,
    read: (entity) => entity.priority,
    encode: (value) => switch (value) {
      TaskPriority.low => 'low',
      TaskPriority.normal => 'normal',
      TaskPriority.high => 'high',
    },
    decode: (source) => switch (source) {
      'low' => TaskPriority.low,
      'normal' => TaskPriority.normal,
      'high' => TaskPriority.high,
      _ => throw const FormatException('Invalid enum `priority`.'),
    },
  );
  static const _dueAtPersistence = EntityFieldDescriptor(
    name: 'dueAt',
    columnName: 'due_at',
    kind: EntityFieldKind.timestamp,
    nullable: true,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final dueAt = PersistedNullableComparableEntityField<Task, DateTime>(
    persistence: _dueAtPersistence,
    read: (entity) => entity.dueAt,
    encode: (value) => value?.toUtc().toIso8601String(),
    decode: (source) =>
        source == null ? null : DateTime.parse(source as String).toUtc(),
  );
  static const _completedAtPersistence = EntityFieldDescriptor(
    name: 'completedAt',
    columnName: 'completed_at',
    kind: EntityFieldKind.timestamp,
    nullable: true,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final completedAt =
      PersistedNullableComparableEntityField<Task, DateTime>(
        persistence: _completedAtPersistence,
        read: (entity) => entity.completedAt,
        encode: (value) => value?.toUtc().toIso8601String(),
        decode: (source) =>
            source == null ? null : DateTime.parse(source as String).toUtc(),
      );
  static const _archivedAtPersistence = EntityFieldDescriptor(
    name: 'archivedAt',
    columnName: 'archived_at',
    kind: EntityFieldKind.timestamp,
    nullable: true,
    mutable: true,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: true,
    conflictPolicy: FieldConflictPolicy.localWins,
    reference: null,
  );
  static final archivedAt =
      PersistedNullableComparableEntityField<Task, DateTime>(
        persistence: _archivedAtPersistence,
        read: (entity) => entity.archivedAt,
        encode: (value) => value?.toUtc().toIso8601String(),
        decode: (source) =>
            source == null ? null : DateTime.parse(source as String).toUtc(),
      );
  static const _createdAtPersistence = EntityFieldDescriptor(
    name: 'createdAt',
    columnName: 'created_at',
    kind: EntityFieldKind.timestamp,
    nullable: false,
    mutable: false,
    sinceProtocolVersion: 1,
    renamedFrom: null,
    hasProtocolDefault: false,
    protocolDefault: null,
    inCreatePayload: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
    reference: null,
  );
  static final createdAt = PersistedComparableEntityField<Task, DateTime>(
    persistence: _createdAtPersistence,
    read: (entity) => entity.createdAt,
    encode: (value) => value.toUtc().toIso8601String(),
    decode: (source) => DateTime.parse((source)! as String).toUtc(),
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
    reference: null,
  );
  static final _orderRank = PersistedComparableEntityField<Task, OrderRank>(
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
    reference: null,
  );
  static final deletedAt =
      PersistedNullableComparableEntityField<Task, DateTime>(
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
      PersistedComparableEntityField<Task, ServerVersion>(
        persistence: _serverVersionPersistence,
        read: (entity) => entity.serverVersion,
        encode: (value) => value.value,
        decode: (source) => parseServerVersion(source),
      );
  static final _persistence = <EntityFieldDescriptor>[
    id.persistence,
    ownerId.persistence,
    projectId.persistence,
    title.persistence,
    description.persistence,
    status.persistence,
    priority.persistence,
    dueAt.persistence,
    completedAt.persistence,
    archivedAt.persistence,
    createdAt.persistence,
    _orderRank.persistence,
    deletedAt.persistence,
    serverVersion.persistence,
  ];
}

final class TaskSet {
  TaskSet(LocalEntityEngine<Task, TaskRecord> engine)
    : _engine = engine,
      _ownerId = engine.authenticatedOwnerId<Account>(),
      _queries = LocalEntityQueryCache.database(
        loader: (spec, {required after, required limit}) =>
            engine.loadQueryPage(spec, after: after, limit: limit),
        invalidations: engine.projectionChanges,
      );
  final LocalEntityEngine<Task, TaskRecord> _engine;
  final LocalEntityQueryCache<Task> _queries;
  TaskMutationDraft beginCreate() => TaskMutationDraft.create(this);
  TaskMutationDraft beginEdit(Task entity) => entity.beginEdit();
  final LocalId<Account> _ownerId;
  Future<EntityLookupLease<Task>?> loadById(
    LocalId<Task> id, {
    bool refresh = false,
  }) => _engine.loadRawId(id.value, refresh: refresh);
  Future<R> useById<R>(
    LocalId<Task> id,
    LeaseAction<Task, R> action, {
    bool refresh = false,
  }) => loadById(id, refresh: refresh).use(
    action,
    ifAbsent: () =>
        throw EntityNotFoundException(entityType: 'Task', entityId: id.value),
  );
  Stream<Task?> watchById(LocalId<Task> id) =>
      _engine.watchLoadedRawId(id.value);
  EntityLookup<Task> lookup(
    LocalId<Task> id, {
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.include,
  }) => EntityLookup(
    query(
      where: TaskFields.id.equals(id),
      tombstones: tombstones,
      archives: archives,
      pageSize: 1,
    ),
  );
  LocalEntityQuery<Task> query({
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) => _queries.acquire(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          _archivePredicate(archives) &
          (where ?? EntityPredicate<Task>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
  );
  EntityOrder<Task> get canonicalOrder =>
      TaskFields._orderRank.ascending(tieBreakBy: (entity) => entity.id.value);
  Future<void> prepend(LocalId<Task> id) => _engine.moveInGeneratedOrder(
    entityId: id.value,
    placement: OrderedPlacement.first,
  );

  Future<void> append(LocalId<Task> id) => _engine.moveInGeneratedOrder(
    entityId: id.value,
    placement: OrderedPlacement.last,
  );

  Future<void> moveBefore(LocalId<Task> id, LocalId<Task> neighborId) =>
      _engine.moveInGeneratedOrder(
        entityId: id.value,
        placement: OrderedPlacement.before,
        anchorId: neighborId.value,
      );

  Future<void> moveAfter(LocalId<Task> id, LocalId<Task> neighborId) =>
      _engine.moveInGeneratedOrder(
        entityId: id.value,
        placement: OrderedPlacement.after,
        anchorId: neighborId.value,
      );
  Stream<EntityQueryState<Task>> watchQuery({
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<Task>> observeFields = const [],
  }) => _queries.watch(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          _archivePredicate(archives) &
          (where ?? EntityPredicate<Task>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  Stream<EntityQueryState<Task>> watchCompleteQuery({
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<Task>> observeFields = const [],
  }) => _queries.watchComplete(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          _archivePredicate(archives) &
          (where ?? EntityPredicate<Task>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  LocalId<Task> allocateId() => _engine.allocateId();
  Future<Task> create({
    LocalId<Task>? id,
    LocalId<TaskProject>? projectId,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) => _create(
    first: false,
    id: id,
    projectId: projectId,
    title: title,
    description: description,
    priority: priority,
    dueAt: dueAt,
  );
  Future<Task> createFirst({
    LocalId<Task>? id,
    LocalId<TaskProject>? projectId,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) => _create(
    first: true,
    id: id,
    projectId: projectId,
    title: title,
    description: description,
    priority: priority,
    dueAt: dueAt,
  );
  Future<Task> _create({
    required bool first,
    LocalId<Task>? id,
    LocalId<TaskProject>? projectId,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) {
    return _engine.createInGeneratedOrder(
      {
        'ownerId': TaskFields.ownerId.encode(_ownerId),
        'projectId': TaskFields.projectId.encode(projectId),
        'title': TaskFields.title.encode(title),
        'description': TaskFields.description.encode(description),
        'status': TaskFields.status.encode(TaskStatus.todo),
        'priority': TaskFields.priority.encode(priority),
        'dueAt': TaskFields.dueAt.encode(dueAt),
        'completedAt': TaskFields.completedAt.encode(null),
        'archivedAt': TaskFields.archivedAt.encode(null),
      },
      principals: const [RlsPrincipal.owner],
      id: id,
      placement: first ? OrderedPlacement.first : OrderedPlacement.last,
    );
  }

  static EntityPredicate<Task> _tombstonePredicate(
    TombstoneVisibility visibility,
  ) => switch (visibility) {
    TombstoneVisibility.exclude => TaskFields.deletedAt.isNull,
    TombstoneVisibility.include => EntityPredicate<Task>.all(),
    TombstoneVisibility.only => TaskFields.deletedAt.isNotNull,
  };
  static EntityPredicate<Task> _archivePredicate(
    ArchiveVisibility visibility,
  ) => switch (visibility) {
    ArchiveVisibility.exclude => TaskFields.archivedAt.isNull,
    ArchiveVisibility.include => EntityPredicate<Task>.all(),
    ArchiveVisibility.only => TaskFields.archivedAt.isNotNull,
  };
  void dispose() => _queries.dispose();
}

extension TaskCollaborationApi on Task {
  Future<void> setCollaborator(
    LocalId<Account> collaboratorId, {
    required bool active,
  }) => generatedAccess.recordGeneratedCommand(
    SetCollaboratorCommand<Task, Account>(
      collaboratorId: collaboratorId,
      active: active,
    ),
  );
}
