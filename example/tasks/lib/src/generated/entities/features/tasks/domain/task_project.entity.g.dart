// GENERATED FILE. DO NOT EDIT.
// Source: package:tasks_example/features/tasks/domain/task_project.dart
// ignore_for_file: invalid_null_aware_operator, type=lint

import 'package:drift/drift.dart';
import 'package:mobx/mobx.dart';
import 'package:nodus/nodus.dart';
import 'package:tasks_example/features/tasks/domain/task_project.dart';
import 'package:tasks_example/features/accounts/domain/account.dart';

@TableIndex.sql(
  'CREATE INDEX task_projects_deleted_at_order_rank_id_idx ON task_projects (deleted_at, order_rank, id)',
)
@TableIndex.sql(
  'CREATE INDEX task_projects_deleted_at_title_id_idx ON task_projects (deleted_at, title, id)',
)
class TaskProjectRows extends Table {
  @override
  String get tableName => 'task_projects';
  TextColumn get id => text().named('id')();
  TextColumn get ownerId => text().named('owner_id')();
  TextColumn get title => text().named('title')();
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
    'CHECK (title = trim(title))',
    'CHECK (length(trim(title)) >= 1)',
    'CHECK (length(title) <= 80)',
  ];
  IntColumn get localRevision => integer().named('local_revision')();
  TextColumn get acceptedSnapshot =>
      text().named('accepted_snapshot').nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

final class TaskProjectDescriptor
    implements
        EntityDescriptor<TaskProject, TaskProjectRecord>,
        EntityIdentityDescriptor<TaskProject>,
        OrderedDescriptor {
  const TaskProjectDescriptor();

  @override
  EntityIdentity<TaskProject> nextIdentity(EntityIdGenerator generator) =>
      EntityIdentity(descriptor: this, id: generator.next<TaskProject>());
  @override
  EntityIdentity<TaskProject> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId(source));

  @override
  String get entityType => 'TaskProject';
  @override
  Cardinality get cardinality => Cardinality.bounded;
  @override
  String get tableName => 'task_projects';
  @override
  String? get collaborationTableName => null;
  @override
  int get protocolVersion => 2;

  @override
  List<EntityFieldDescriptor> get orderScopeFields => const [
    TaskProjectFields._ownerIdPersistence,
  ];

  @override
  List<EntityFieldValueCondition> get orderMembershipConditions => const [
    EntityFieldValueCondition(
      field: TaskProjectFields._deletedAtPersistence,
      value: null,
    ),
  ];

  @override
  bool isOrderMember(JsonMap fields) =>
      orderMembershipConditions.every((condition) => condition.matches(fields));

  @override
  String orderScopeKey(JsonMap fields) {
    final value = fields['ownerId'];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException(
      'Expected TaskProject.ownerId to identify its ordered scope.',
      value,
    );
  }

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => switch (name) {
    'moveInOrder' => MoveOrderedCommand<TaskProject>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    'reorder' => ReorderOrderedCommand<TaskProject>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    _ => throw RejectedSyncException.validation(
      code: 'unsupported_command',
      message: 'Unsupported TaskProject semantic command.',
    ),
  };

  @override
  List<EntityFieldDescriptor> get fields => TaskProjectFields._persistence;

  @override
  TaskProjectRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) {
    return TaskProjectRecord._(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: localRevision,
      id: TaskProjectFields.id.decode(fields['id']),
      ownerId: TaskProjectFields.ownerId.decode(fields['ownerId']),
      title: TaskProjectFields.title.decode(fields['title']),
      orderRank: TaskProjectFields._orderRank.decode(fields['orderRank']),
      deletedAt: TaskProjectFields.deletedAt.decode(fields['deletedAt']),
      serverVersion: TaskProjectFields.serverVersion.decode(
        fields['serverVersion'],
      ),
    );
  }
}

final class TaskProjectRecord extends TaskProject
    implements
        TypedGeneratedEntityRecord<TaskProject>,
        GeneratedEntityAccess<TaskProject>,
        GeneratedOrderedEntityAccess<TaskProject> {
  TaskProjectRecord._({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required int localRevision,
    required LocalId<TaskProject> id,
    required LocalId<Account> ownerId,
    required String title,
    required OrderRank orderRank,
    required DateTime? deletedAt,
    required ServerVersion serverVersion,
  }) : _mutationSink = mutationSink,
       _clock = clock,
       _localRevision = localRevision,
       id = id,
       _ownerIdStore = Observable(ownerId),
       _titleStore = Observable(title),
       _orderRankStore = Observable(orderRank),
       _deletedAtStore = Observable(deletedAt),
       _serverVersionStore = Observable(serverVersion) {
    if (title.trim().length < 1) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'title',
        message: 'Must contain at least 1 non-whitespace character(s).',
      );
    }
    if (title.length > 80) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'title',
        message: 'Must contain at most 80 character(s).',
      );
    }
  }

  /// Creates an explicitly non-persisted preview or fixture.
  factory TaskProjectRecord.detached({
    required LocalId<TaskProject> id,
    required LocalId<Account> ownerId,
    required String title,
    DateTime? deletedAt,
    ServerVersion serverVersion = ServerVersion.zero,
    Clock clock = const SystemClock(),
    EntityMutationSink mutationSink = const DetachedEntityMutationSink(),
  }) {
    return const TaskProjectDescriptor().instantiate(
      mutationSink: mutationSink,
      clock: clock,
      localRevision: 0,
      fields: {
        'id': TaskProjectFields.id.encode(id),
        'ownerId': TaskProjectFields.ownerId.encode(ownerId),
        'title': TaskProjectFields.title.encode(title),
        'orderRank': TaskProjectFields._orderRank.encode(
          OrderRank.parse(
            '057896044618658097711785492504343953926634992332820282019728792003956564819967',
          ),
        ),
        'deletedAt': TaskProjectFields.deletedAt.encode(deletedAt),
        'serverVersion': TaskProjectFields.serverVersion.encode(serverVersion),
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
  TaskProject get generatedDomain => this;
  @override
  GeneratedEntityAccess<TaskProject> get generatedAccess => this;
  @override
  GeneratedOrderedEntityAccess<TaskProject> get generatedOrderAccess => this;
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
    EntitySemanticCommand<TaskProject> command,
  ) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'command',
        message: 'Deleted entities cannot be changed.',
      );
    }
    _generatedLocalCommit = _mutationSink.recordEntityCommand<TaskProject>(
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
        entityType: 'TaskProject',
        entityId: generatedEntityId,
        reason: EntityDraftFailureReason.stale,
        message: 'Another mutation replaced the draft commit.',
      );
    }
    final result = await _generatedLocalCommit;
    result.throwIfFailed();
  }

  @override
  final LocalId<TaskProject> id;
  final Observable<LocalId<Account>> _ownerIdStore;
  @override
  LocalId<Account> get ownerId => _ownerIdStore.value;
  final Observable<String> _titleStore;
  @override
  String get title => _titleStore.value;
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
  String get generatedOrderScopeKey => _ownerIdStore.value.value;
  @override
  GeneratedOrderStateChange<TaskProject>? prepareGeneratedOrderRank(
    OrderRank rank,
  ) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final oldRank = _orderRankStore.value;
    if (oldRank == rank) return null;
    _mutationSink.validateMutationAuthorization(
      entity: this,
      operation: RlsOperation.update,
      principals: const [RlsPrincipal.owner],
    );
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() => _orderRankStore.value = rank);
    final localPatch = TaskProjectFields._orderRank.patch(rank);
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
    required MoveOrderedCommand<TaskProject> command,
  }) {
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'Deleted entities cannot be changed.',
      );
    }
    final change = prepareGeneratedOrderRank(rank);
    if (change == null) return Future.value();
    final commit = _mutationSink.recordEntityCommand<TaskProject>(
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
    required List<GeneratedOrderStateChange<TaskProject>> changes,
    required ReorderOrderedCommand<TaskProject> command,
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
    final syncPatch = TaskProjectFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskProject>(
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
      principals: const [RlsPrincipal.owner],
    );
    final mutationTime = _clock.nowUtc();
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      _deletedAtStore.value = commandValue;
    });
    final syncPatch = TaskProjectFields.deletedAt.patch(commandValue);
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskProject>(
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
    required TypedEntityPatch<TaskProject> base,
    required TypedEntityPatch<TaskProject> candidate,
  }) {
    final baseTitle = TaskProjectFields.title.decode(base['title']);
    final candidateTitle = TaskProjectFields.title.decode(candidate['title']);
    final nextTitle = (candidateTitle).trim();
    final titleDraftChanged = baseTitle != nextTitle;
    final titleCurrentChanged = baseTitle != _titleStore.value;
    final titleChanged = titleDraftChanged && _titleStore.value != nextTitle;
    final titleOverlaps = titleChanged && titleCurrentChanged;
    if (titleOverlaps) {
      throw EntityDraftFieldConflictException(
        entityType: 'TaskProject',
        entityId: generatedEntityId,
        fields: [if (titleOverlaps) 'title'],
      );
    }
    if (!(titleChanged)) return Future.value();
    if (_deletedAtStore.value != null) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'draft',
        message: 'Deleted entities cannot be changed.',
      );
    }
    if (titleChanged) {
      if (nextTitle.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskProject',
          field: 'title',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (nextTitle.length > 80) {
        throw const EntityValidationException(
          entityType: 'TaskProject',
          field: 'title',
          message: 'Must contain at most 80 character(s).',
        );
      }
    }
    if (titleChanged) {
      _mutationSink.validateMutationAuthorization(
        entity: this,
        operation: RlsOperation.update,
        principals: const [RlsPrincipal.owner],
      );
    }
    final mutationTime = _clock.nowUtc();
    final oldTitle = _titleStore.value;
    final previousRevision = _localRevision;
    final mutationRevision = ++_localRevision;
    runInAction(() {
      if (titleChanged) {
        _titleStore.value = nextTitle;
      }
    });
    var generatedDraftPatch = TypedEntityPatch<TaskProject>.empty();
    if (titleChanged) {
      final fieldPatch = TaskProjectFields.title.patch(nextTitle);
      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);
    }
    final syncPatch = generatedDraftPatch;
    _generatedLocalCommit = _mutationSink.recordEntityMutation<TaskProject>(
      entity: this,
      patch: syncPatch,
      syncPatch: syncPatch,
      occurredAt: mutationTime,
      rollbackIfCurrent: () {
        if (_localRevision != mutationRevision) return;
        _localRevision = previousRevision;
        if (titleChanged) {
          _titleStore.value = oldTitle;
        }
      },
    );
    return _generatedMutationCompletion(_generatedLocalCommit);
  }

  @override
  String get generatedEntityType => 'TaskProject';
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
    'id': TaskProjectFields.id.encode(id),
    'ownerId': TaskProjectFields.ownerId.encode(ownerId),
    'title': TaskProjectFields.title.encode(title),
    'orderRank': TaskProjectFields._orderRank.encode(generatedOrderRank),
  };

  @override
  JsonMap generatedSnapshot() => {
    'id': TaskProjectFields.id.encode(id),
    'ownerId': TaskProjectFields.ownerId.encode(ownerId),
    'title': TaskProjectFields.title.encode(title),
    'orderRank': TaskProjectFields._orderRank.encode(generatedOrderRank),
    'deletedAt': TaskProjectFields.deletedAt.encode(deletedAt),
    'serverVersion': TaskProjectFields.serverVersion.encode(serverVersion),
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
      remoteOwnerId = TaskProjectFields.ownerId.decode(fields['ownerId']);
    }
    final hasTitle = fields.containsKey('title');
    late final String remoteTitle;
    if (hasTitle) {
      remoteTitle = TaskProjectFields.title.decode(fields['title']);
      if (remoteTitle.trim().length < 1) {
        throw const EntityValidationException(
          entityType: 'TaskProject',
          field: 'title',
          message: 'Must contain at least 1 non-whitespace character(s).',
        );
      }
      if (remoteTitle.length > 80) {
        throw const EntityValidationException(
          entityType: 'TaskProject',
          field: 'title',
          message: 'Must contain at most 80 character(s).',
        );
      }
    }
    final hasOrderRank = fields.containsKey('orderRank');
    late final OrderRank remoteOrderRank;
    if (hasOrderRank) {
      remoteOrderRank = TaskProjectFields._orderRank.decode(
        fields['orderRank'],
      );
    }
    final hasDeletedAt = fields.containsKey('deletedAt');
    late final DateTime? remoteDeletedAt;
    if (hasDeletedAt) {
      remoteDeletedAt = TaskProjectFields.deletedAt.decode(fields['deletedAt']);
    }
    runInAction(() {
      if (hasOwnerId) {
        _ownerIdStore.value = remoteOwnerId;
      }
      if (hasTitle) {
        _titleStore.value = remoteTitle;
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

extension TaskProjectGeneratedEditing on TaskProject {
  TaskProjectMutationDraft beginEdit() => TaskProjectMutationDraft.edit(this);
}

final class TaskProjectMutationDraft
    implements EntityMutationDraft<TaskProject> {
  TaskProjectMutationDraft.create(
    this._set, {
    LocalId<TaskProject>? id,
    OrderedPlacement placement = OrderedPlacement.last,
  }) : _entity = null,
       _createId = id ?? _set!.allocateId(),
       _createPlacement = placement,
       _baseTitle = null,
       _titleField = EntityDraftField<String>.unset();
  TaskProjectMutationDraft.edit(TaskProject entity)
    : _set = null,
      _entity = entity,
      _createId = null,
      _createPlacement = null,
      _baseTitle = entity.title,
      _titleField = EntityDraftField<String>.value(entity.title);

  final TaskProjectSet? _set;
  final TaskProject? _entity;
  final LocalId<TaskProject>? _createId;
  final OrderedPlacement? _createPlacement;
  final String? _baseTitle;
  bool _consumed = false;

  bool get isCreating => _entity == null;
  TaskProject? get entity => _entity;
  LocalId<TaskProject> get id => _entity?.id ?? _createId!;
  @override
  bool get isConsumed => _consumed;
  final EntityDraftField<String> _titleField;
  EntityDraftField<String> get titleField => _titleField;
  String get title => _titleField.value;
  set title(String value) => _titleField.value = value;

  @override
  void discard() => _consumed = true;

  @override
  Future<TaskProject> save() async {
    if (_consumed) {
      throw EntityDraftStateException(
        entityType: 'TaskProject',
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
        title: _titleField.requireValue(
          entityType: 'TaskProject',
          field: 'title',
        ),
      );
      _consumed = true;
      return created;
    }
    current.generatedAccess.validateGeneratedDraft();
    await current.generatedAccess.runGeneratedTransaction(() async {
      final generatedDraftBase = TaskProjectFields.title.patch(
        _baseTitle as String,
      );
      final generatedDraftCandidate = TaskProjectFields.title.patch(title);
      await current.generatedAccess.applyGeneratedDraft(
        base: generatedDraftBase,
        candidate: generatedDraftCandidate,
      );
    });
    _consumed = true;
    return current;
  }
}

abstract final class TaskProjectFields {
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
  static final id =
      PersistedEqualityEntityField<TaskProject, LocalId<TaskProject>>(
        persistence: _idPersistence,
        read: (entity) => entity.id,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<TaskProject>((source)! as String),
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
      PersistedEqualityEntityField<TaskProject, LocalId<Account>>(
        persistence: _ownerIdPersistence,
        read: (entity) => entity.ownerId,
        encode: (value) => value.value,
        decode: (source) => parseLocalId<Account>((source)! as String),
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
    normalization: FieldNormalization.trim,
    reference: null,
    constraints: EntityFieldConstraints(minLength: 1, maxLength: 80),
  );
  static final title = PersistedComparableEntityField<TaskProject, String>(
    persistence: _titlePersistence,
    read: (entity) => entity.title,
    normalize: (value) => (value).trim(),
    encode: (value) => (value).trim(),
    decode: (source) => ((source)! as String).trim(),
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
  static final _orderRank =
      PersistedComparableEntityField<TaskProject, OrderRank>(
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
      PersistedNullableComparableEntityField<TaskProject, DateTime>(
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
      PersistedComparableEntityField<TaskProject, ServerVersion>(
        persistence: _serverVersionPersistence,
        read: (entity) => entity.serverVersion,
        encode: (value) => value.value,
        decode: (source) => parseServerVersion(source),
      );
  static final _persistence = <EntityFieldDescriptor>[
    id.persistence,
    ownerId.persistence,
    title.persistence,
    _orderRank.persistence,
    deletedAt.persistence,
    serverVersion.persistence,
  ];
}

final class TaskProjectSet {
  TaskProjectSet(LocalEntityEngine<TaskProject, TaskProjectRecord> engine)
    : _engine = engine,
      _ownerId = engine.authenticatedOwnerId<Account>(),
      _queries = LocalEntityQueryCache<TaskProject>(source: engine.all);
  final LocalEntityEngine<TaskProject, TaskProjectRecord> _engine;
  final LocalEntityQueryCache<TaskProject> _queries;
  TaskProjectMutationDraft beginCreate({
    LocalId<TaskProject>? id,
    OrderedPlacement placement = OrderedPlacement.last,
  }) => TaskProjectMutationDraft.create(this, id: id, placement: placement);
  TaskProjectMutationDraft beginEdit(TaskProject entity) => entity.beginEdit();
  final LocalId<Account> _ownerId;
  ReadOnlyObservableList<TaskProject> get all => _engine.all;
  Stream<TaskProject?> watchById(LocalId<TaskProject> id) =>
      _engine.watchRawId(id.value);
  TaskProject? byId(LocalId<TaskProject> id) => _engine.byRawId(id.value);
  TaskProject require(LocalId<TaskProject> id) =>
      _engine.requireRawId(id.value);
  TaskProject? byPresentId(LocalId<TaskProject> id) {
    final entity = byId(id);
    return entity == null || entity.deletedAt != null ? null : entity;
  }

  TaskProject requirePresent(LocalId<TaskProject> id) =>
      byPresentId(id) ??
      (throw EntityNotFoundException(
        entityType: 'TaskProject',
        entityId: id.value,
      ));
  EntityExistence<TaskProject> exists({
    required EntityPredicate<TaskProject> where,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) =>
      EntityExistence(query(where: where, tombstones: tombstones, pageSize: 1));
  EntityFirst<TaskProject> first({
    EntityPredicate<TaskProject>? where,
    required EntityOrder<TaskProject> orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => EntityFirst(
    query(where: where, orderBy: orderBy, tombstones: tombstones, pageSize: 1),
  );
  EntityExistence<TaskProject> existsOwned({
    EntityPredicate<TaskProject>? where,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => exists(
    where:
        TaskProjectFields.ownerId.equals(_ownerId) &
        (where ?? EntityPredicate<TaskProject>.all()),
    tombstones: tombstones,
  );
  EntityFirst<TaskProject> firstOwned({
    EntityPredicate<TaskProject>? where,
    required EntityOrder<TaskProject> orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) => first(
    where:
        TaskProjectFields.ownerId.equals(_ownerId) &
        (where ?? EntityPredicate<TaskProject>.all()),
    orderBy: orderBy,
    tombstones: tombstones,
  );
  LocalEntityQuery<TaskProject> query({
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) => _queries.acquire(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskProject>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
  );
  EntityOrder<TaskProject> get canonicalOrder => TaskProjectFields._orderRank
      .ascending(tieBreakBy: (entity) => entity.id.value);
  List<TaskProject> _canonicalOrderedItems(LocalId<TaskProject> id) {
    final target = _engine.byRawId(id.value);
    if (target == null ||
        !target.generatedAccess.generatedOrderAccess!.generatedIsOrderMember) {
      _validateOrderedMembers(-1);
    }
    final items = _engine.all
        .where(
          (entity) =>
              entity
                  .generatedAccess
                  .generatedOrderAccess!
                  .generatedIsOrderMember &&
              entity
                      .generatedAccess
                      .generatedOrderAccess!
                      .generatedOrderScopeKey ==
                  target!
                      .generatedAccess
                      .generatedOrderAccess!
                      .generatedOrderScopeKey,
        )
        .toList(growable: false);
    items.sort(canonicalOrder.compare);
    return items;
  }

  Future<void> reorder(Iterable<LocalId<TaskProject>> entityIds) {
    final ids = entityIds.toList(growable: false);
    if (ids.isEmpty) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message:
            'Exact reorder requires one complete non-empty canonical scope.',
      );
    }
    if (ids.toSet().length != ids.length) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'Exact reorder identities must be unique.',
      );
    }
    final items = _canonicalOrderedItems(ids.first);
    final canonicalIds = items.map((entity) => entity.id).toList();
    if (canonicalIds.length != ids.length ||
        !canonicalIds.toSet().containsAll(ids)) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message:
            'Exact reorder identities must match the complete active canonical scope.',
      );
    }
    if (_sameOrderedIds(canonicalIds, ids)) return Future.value();
    return _recordExactOrder(items, ids);
  }

  bool _sameOrderedIds(
    List<LocalId<TaskProject>> left,
    List<LocalId<TaskProject>> right,
  ) {
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> _recordExactOrder(
    List<TaskProject> items,
    List<LocalId<TaskProject>> ids,
  ) {
    final ranks = GeneratedOrderRanks.allocate(count: ids.length)!;
    final byId = <LocalId<TaskProject>, TaskProject>{
      for (final entity in items) entity.id: entity,
    };
    final changes = <GeneratedOrderStateChange<TaskProject>>[];
    try {
      for (final (index, id) in ids.indexed) {
        final entity = byId[id]!;
        final change = entity.generatedAccess.generatedOrderAccess!
            .prepareGeneratedOrderRank(ranks[index]);
        if (change != null) changes.add(change);
      }
    } catch (_) {
      for (final change in changes.reversed) {
        change.rollbackIfCurrent();
      }
      rethrow;
    }
    final target = byId[ids.first]!;
    return target.generatedAccess.generatedOrderAccess!
        .recordGeneratedExactOrder(
          changes: changes,
          command: ReorderOrderedCommand(
            orderedIds: ids,
            scopeBaseVersion: _engine.orderScopeVersionFor(
              target
                  .generatedAccess
                  .generatedOrderAccess!
                  .generatedOrderScopeKey,
            ),
          ),
        );
  }

  Future<void> prepend(LocalId<TaskProject> id) => _moveInCanonicalOrder(
    id,
    placement: OrderedPlacement.first,
    beforeId: _firstOtherId(id),
  );

  Future<void> append(LocalId<TaskProject> id) => _moveInCanonicalOrder(
    id,
    placement: OrderedPlacement.last,
    afterId: _lastOtherId(id),
  );

  Future<void> moveBefore(
    LocalId<TaskProject> id,
    LocalId<TaskProject> neighborId,
  ) {
    if (id == neighborId) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'An entity cannot be its own neighbor.',
      );
    }
    final items = _canonicalOrderedItems(id);
    final ids = items.map((entity) => entity.id).toList();
    final targetIndex = ids.indexOf(id);
    final neighborIndex = ids.indexOf(neighborId);
    _validateOrderedMembers(targetIndex, neighborIndex: neighborIndex);
    if (targetIndex + 1 == neighborIndex) return Future.value();
    ids.removeAt(targetIndex);
    final insertion = ids.indexOf(neighborId);
    final afterId = insertion == 0 ? null : ids[insertion - 1];
    return _moveInCanonicalOrder(
      id,
      afterId: afterId,
      beforeId: neighborId,
      placement: OrderedPlacement.before,
      anchorId: neighborId,
    );
  }

  Future<void> moveAfter(
    LocalId<TaskProject> id,
    LocalId<TaskProject> neighborId,
  ) {
    if (id == neighborId) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'An entity cannot be its own neighbor.',
      );
    }
    final items = _canonicalOrderedItems(id);
    final ids = items.map((entity) => entity.id).toList();
    final targetIndex = ids.indexOf(id);
    final neighborIndex = ids.indexOf(neighborId);
    _validateOrderedMembers(targetIndex, neighborIndex: neighborIndex);
    if (neighborIndex + 1 == targetIndex) return Future.value();
    ids.removeAt(targetIndex);
    final insertion = ids.indexOf(neighborId) + 1;
    final beforeId = insertion == ids.length ? null : ids[insertion];
    return _moveInCanonicalOrder(
      id,
      afterId: neighborId,
      beforeId: beforeId,
      placement: OrderedPlacement.after,
      anchorId: neighborId,
    );
  }

  LocalId<TaskProject>? _firstOtherId(LocalId<TaskProject> id) {
    final items = _canonicalOrderedItems(id);
    final targetIndex = items.indexWhere((item) => item.id == id);
    _validateOrderedMembers(targetIndex);
    if (targetIndex == 0) return null;
    return items.first.id;
  }

  LocalId<TaskProject>? _lastOtherId(LocalId<TaskProject> id) {
    final items = _canonicalOrderedItems(id);
    final targetIndex = items.indexWhere((item) => item.id == id);
    _validateOrderedMembers(targetIndex);
    if (targetIndex == items.length - 1) return null;
    return items.last.id;
  }

  void _validateOrderedMembers(int targetIndex, {int? neighborIndex}) {
    if (targetIndex >= 0 && (neighborIndex ?? 0) >= 0) return;
    throw const EntityValidationException(
      entityType: 'TaskProject',
      field: 'order',
      message: 'Ordered movement requires active canonical members.',
    );
  }

  Future<void> _moveInCanonicalOrder(
    LocalId<TaskProject> id, {
    required OrderedPlacement placement,
    LocalId<TaskProject>? anchorId,
    LocalId<TaskProject>? afterId,
    LocalId<TaskProject>? beforeId,
  }) async {
    if (afterId == null && beforeId == null) return;
    final items = _canonicalOrderedItems(id);
    final byId = <LocalId<TaskProject>, TaskProject>{
      for (final entity in items) entity.id: entity,
    };
    final target = byId[id];
    final after = afterId == null ? null : byId[afterId];
    final before = beforeId == null ? null : byId[beforeId];
    if (target == null ||
        (afterId != null && after == null) ||
        (beforeId != null && before == null)) {
      _validateOrderedMembers(-1);
    }
    final rank = GeneratedOrderRanks.between(
      after: after?.generatedAccess.generatedOrderAccess!.generatedOrderRank,
      before: before?.generatedAccess.generatedOrderAccess!.generatedOrderRank,
    );
    if (rank == null) {
      final ids = items.map((entity) => entity.id).toList();
      ids.remove(id);
      final insertion = switch (placement) {
        OrderedPlacement.first => 0,
        OrderedPlacement.last => ids.length,
        OrderedPlacement.before => ids.indexOf(anchorId!),
        OrderedPlacement.after => ids.indexOf(anchorId!) + 1,
      };
      ids.insert(insertion, id);
      await _recordExactOrder(items, ids);
      return;
    }
    await target!.generatedAccess.generatedOrderAccess!
        .recordGeneratedOrderMove(
          rank: rank,
          command: MoveOrderedCommand(
            placement: placement,
            anchorId: anchorId,
            scopeBaseVersion: _engine.orderScopeVersionFor(
              target
                  .generatedAccess
                  .generatedOrderAccess!
                  .generatedOrderScopeKey,
            ),
          ),
        );
  }

  Stream<EntityQueryState<TaskProject>> watchQuery({
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskProject>> observeFields =
        const [],
  }) => _queries.watch(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskProject>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  Stream<EntityQueryState<TaskProject>> watchCompleteQuery({
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
    Iterable<PersistedEntityFieldReference<TaskProject>> observeFields =
        const [],
  }) => _queries.watchComplete(
    EntityQuerySpec(
      where:
          _tombstonePredicate(tombstones) &
          (where ?? EntityPredicate<TaskProject>.all()),
      orderBy: orderBy,
      pageSize: pageSize,
    ),
    observeFields: observeFields,
  );
  LocalId<TaskProject> allocateId() => _engine.allocateId();
  Future<TaskProject> create({
    LocalId<TaskProject>? id,
    required String title,
  }) => _create(first: false, id: id, title: title);
  Future<TaskProject> createFirst({
    LocalId<TaskProject>? id,
    required String title,
  }) => _create(first: true, id: id, title: title);
  Future<TaskProject> createAt({
    LocalId<TaskProject>? id,
    OrderedPlacement placement = OrderedPlacement.last,
    required String title,
  }) {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw const EntityValidationException(
        entityType: 'TaskProject',
        field: 'order',
        message: 'Ordered creation supports only first or last placement.',
      );
    }
    return _create(
      first: placement == OrderedPlacement.first,
      id: id,
      title: title,
    );
  }

  Future<TaskProject> _create({
    required bool first,
    LocalId<TaskProject>? id,
    required String title,
  }) {
    return _engine.createInGeneratedOrder(
      {
        'ownerId': TaskProjectFields.ownerId.encode(_ownerId),
        'title': TaskProjectFields.title.encode(title),
      },
      principals: const [RlsPrincipal.owner],
      id: id,
      placement: first ? OrderedPlacement.first : OrderedPlacement.last,
    );
  }

  static EntityPredicate<TaskProject> _tombstonePredicate(
    TombstoneVisibility visibility,
  ) => switch (visibility) {
    TombstoneVisibility.exclude => TaskProjectFields.deletedAt.isNull,
    TombstoneVisibility.include => EntityPredicate<TaskProject>.all(),
    TombstoneVisibility.only => TaskProjectFields.deletedAt.isNotNull,
  };
  void dispose() => _queries.dispose();
}
