import 'dart:async';
import 'dart:math' as math;

import 'package:nodus/nodus.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

import 'support/test_descriptor.dart';

void main() {
  test(
    'query state streams expose immutable resolved item snapshots',
    () async {
      final values = await Stream<EntityQueryState<int>>.fromIterable(const [
        EntityQueryInitialLoading<int>(),
        EntityQueryData<int>(items: [1, 2], hasMore: false),
        EntityQueryEmpty<int>(),
        EntityQueryDisposed<int>(),
      ]).itemSnapshots.toList();

      expect(values, const [
        [1, 2],
        <int>[],
      ]);
      expect(() => values.first.add(3), throwsUnsupportedError);
    },
  );

  test('field constraints validate canonical transport values', () {
    const text = EntityFieldDescriptor(
      name: 'title',
      columnName: 'title',
      kind: EntityFieldKind.text,
      nullable: false,
      mutable: true,
      conflictPolicy: FieldConflictPolicy.localWins,
      constraints: EntityFieldConstraints(
        minLength: 2,
        maxLength: 5,
        allowedValues: ['Focus', 'Rest'],
      ),
    );
    const count = EntityFieldDescriptor(
      name: 'count',
      columnName: 'count',
      kind: EntityFieldKind.integer,
      nullable: false,
      mutable: true,
      conflictPolicy: FieldConflictPolicy.localWins,
      constraints: EntityFieldConstraints(minValue: 1, maxValue: 3),
    );
    const score = EntityFieldDescriptor(
      name: 'score',
      columnName: 'score',
      kind: EntityFieldKind.real,
      nullable: false,
      mutable: true,
      conflictPolicy: FieldConflictPolicy.localWins,
      constraints: EntityFieldConstraints(minValue: 0, maxValue: 100),
    );

    expect(text.decodeWireValue('Focus', entityType: 'Rule'), 'Focus');
    expect(count.decodeWireValue(2.0, entityType: 'Rule'), 2);
    expect(score.sqliteType, 'REAL');
    expect(score.decodeWireValue(42, entityType: 'Rule'), 42.0);
    expect(score.toDatabase(42), 42.0);
    expect(score.fromDatabase(42), 42.0);
    expect(
      () => text.decodeWireValue(' ', entityType: 'Rule'),
      throwsFormatException,
    );
    expect(
      () => text.decodeWireValue('Other', entityType: 'Rule'),
      throwsFormatException,
    );
    expect(
      () => count.decodeWireValue(4, entityType: 'Rule'),
      throwsFormatException,
    );
    expect(
      () => score.decodeWireValue(double.infinity, entityType: 'Rule'),
      throwsFormatException,
    );
    expect(
      () => score.decodeWireValue(101, entityType: 'Rule'),
      throwsFormatException,
    );
  });

  test('field predicates canonicalize expected String values', () {
    final title = ComparableEntityField<_TextItem, String>(
      name: 'title',
      read: (item) => item.title,
      encode: normalizeTrimmedString,
      normalize: normalizeTrimmedString,
    );
    final summary = NullableComparableEntityField<_TextItem, String>(
      name: 'summary',
      read: (item) => item.summary,
      encode: normalizeTrimmedStringToNull,
      normalize: normalizeTrimmedStringToNull,
    );
    const item = _TextItem(title: 'Focus', summary: null);

    expect(title.equals('  Focus ').test(item), isTrue);
    expect(title.isIn([' Rest ', ' Focus ']).test(item), isTrue);
    expect(title.canonicalize('  Focus '), 'Focus');
    expect(summary.equals('   ').test(item), isTrue);
    expect(normalizeTrimmedStringToNull('  note  '), 'note');
  });

  test(
    'field descriptors normalize before transport constraints and storage',
    () {
      const title = EntityFieldDescriptor(
        name: 'title',
        columnName: 'title',
        kind: EntityFieldKind.text,
        nullable: false,
        mutable: true,
        conflictPolicy: FieldConflictPolicy.localWins,
        constraints: EntityFieldConstraints(minLength: 2, maxLength: 5),
        normalization: FieldNormalization.trim,
      );
      const summary = EntityFieldDescriptor(
        name: 'summary',
        columnName: 'summary',
        kind: EntityFieldKind.text,
        nullable: true,
        mutable: true,
        conflictPolicy: FieldConflictPolicy.localWins,
        normalization: FieldNormalization.trimToNull,
      );

      expect(title.decodeWireValue('  Focus  ', entityType: 'Rule'), 'Focus');
      expect(title.toDatabase('  Focus  '), 'Focus');
      expect(title.fromDatabase('  Focus  '), 'Focus');
      expect(summary.decodeWireValue('   ', entityType: 'Rule'), isNull);
      expect(summary.toDatabase('   '), isNull);
      expect(summary.fromDatabase('   '), isNull);
    },
  );

  test('persisted scalar values use their native wire identity', () {
    final first = _ScalarValue.fromScalar(7);
    const equivalent = _ScalarValue(7);
    const different = _ScalarValue(8);

    expect(entityValuesEqual(first, equivalent), isTrue);
    expect(entityValueHash(first), entityValueHash(equivalent));
    expect(entityValuesEqual(first, different), isFalse);
    expect(entityValueHash(first), isNot(entityValueHash(different)));
  });

  test('sync operation IDs validate and canonicalize UUID wire values', () {
    expect(
      parseSyncOperationId('  A0000000-0000-7000-8000-000000000001  '),
      SyncOperationId('a0000000-0000-7000-8000-000000000001'),
    );
    expect(tryParseSyncOperationId('not-an-operation-id'), isNull);
    expect(
      () => parseSyncOperationId('not-an-operation-id'),
      throwsFormatException,
    );
    expect(() => SyncOperationId('not-an-operation-id'), throwsFormatException);
  });

  test('server sequences are nominal, non-negative protocol positions', () {
    expect(parseServerSequence('42'), ServerSequence(42));
    expect(parseServerSequence(42.0), ServerSequence(42));
    expect(() => ServerSequence(-1), throwsRangeError);
    expect(() => parseServerSequence(-1), throwsFormatException);
    expect(() => parseServerSequence(1.5), throwsFormatException);
  });

  test('server versions are nominal validated concurrency values', () {
    expect(parseServerVersion('7'), ServerVersion(7));
    expect(parseServerVersion(7.0), ServerVersion(7));
    expect(ServerVersion.zero.value, 0);
    expect(() => ServerVersion(-1), throwsRangeError);
    expect(() => parseServerVersion(-1), throwsFormatException);
    expect(() => parseServerVersion(1.5), throwsFormatException);
  });

  test('merge keeps pending server-wins fields at their acknowledged base', () {
    final acknowledged = mergeRemoteFields(
      visibleFields: const {'state': 'declined'},
      pendingPatch: const {'state': 'pending'},
      remoteFields: const {'state': 'declined'},
      policies: const {'state': FieldConflictPolicy.serverWins},
      remoteVersion: ServerVersion(2),
      pendingBaseVersion: ServerVersion(2),
    );
    expect(acknowledged.visibleFields['state'], 'pending');
    expect(acknowledged.rebasedPendingPatch, {'state': 'pending'});

    final concurrent = mergeRemoteFields(
      visibleFields: acknowledged.visibleFields,
      pendingPatch: acknowledged.rebasedPendingPatch,
      remoteFields: const {'state': 'accepted'},
      policies: const {'state': FieldConflictPolicy.serverWins},
      remoteVersion: ServerVersion(3),
      pendingBaseVersion: ServerVersion(2),
    );
    expect(concurrent.visibleFields['state'], 'accepted');
    expect(concurrent.rebasedPendingPatch, isEmpty);
  });

  test('schema transitions are positive and contiguous', () {
    expect(NodusSchemaTransition(from: 2, to: 3).toString(), '2->3');
    expect(() => NodusSchemaTransition(from: 0, to: 1), throwsRangeError);
    expect(() => NodusSchemaTransition(from: 2, to: 4), throwsArgumentError);
  });

  test('database boolean decoding rejects corrupted storage values', () {
    final booleanField = TestDescriptor<_Item>().fields[1];

    expect(booleanField.fromDatabase(0), isFalse);
    expect(booleanField.fromDatabase(1), isTrue);
    expect(booleanField.fromDatabase(false), isFalse);
    expect(booleanField.fromDatabase(true), isTrue);
    expect(() => booleanField.fromDatabase(2), throwsFormatException);
    expect(() => booleanField.fromDatabase('false'), throwsFormatException);
  });

  test('retained protocol versions reject fractional numeric coercion', () {
    final descriptor = TestDescriptor<_Item>();

    for (final value in [1.5, double.infinity, double.nan]) {
      expect(
        () => upcastSyncOperation(descriptor, {'protocolVersion': value}),
        throwsA(
          isA<RejectedSyncException>().having(
            (error) => error.category,
            'category',
            SyncRejectionCategory.protocol,
          ),
        ),
      );
    }
  });

  test('explicit compatible field mappings upcast the same wire type', () {
    final descriptor = TestDescriptor<_Item>(
      fields: [
        const EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        const EntityFieldDescriptor(
          name: 'title',
          columnName: 'title',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
          sinceProtocolVersion: 2,
          renamedFrom: 'name',
        ),
      ],
    );

    final upgraded = upcastSyncOperation(descriptor, const {
      'operation': 'create',
      'protocolVersion': 1,
      'patch': {
        'id': 'a0000000-0000-7000-8000-000000000013',
        'name': 'Legacy title',
      },
    });
    final patch = upgraded['patch']! as Map<String, Object?>;

    expect(upgraded['protocolVersion'], 3);
    expect(patch, isNot(contains('name')));
    expect(patch['title'], 'Legacy title');
  });

  test('pull results enforce a monotonic immutable server envelope', () {
    final descriptor = TestDescriptor<_Item>();
    RemoteEntityChange change(int sequence) => RemoteEntityChange(
      identity: descriptor.parseIdentity(
        'a0000000-0000-7000-8000-000000000001',
      ),
      serverVersion: ServerVersion(1),
      fields: RemoteEntityFields.decode(descriptor, const {
        'id': 'a0000000-0000-7000-8000-000000000001',
      }, complete: false),
      serverSequence: ServerSequence(sequence),
    );

    final changes = [change(7)];
    final result = PullResult(
      requestedAfter: ServerSequence(5),
      changes: changes,
      nextSequence: ServerSequence(10),
      hasMore: false,
    );
    changes.clear();

    expect(result.changes, hasLength(1));
    expect(
      () => PullResult(
        requestedAfter: ServerSequence(5),
        changes: const [],
        nextSequence: ServerSequence(4),
        hasMore: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => PullResult(
        requestedAfter: ServerSequence(5),
        changes: [change(7), change(6)],
        nextSequence: ServerSequence(7),
        hasMore: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => PullResult(
        requestedAfter: ServerSequence(5),
        changes: [change(7)],
        nextSequence: ServerSequence(8),
        hasMore: true,
      ),
      throwsArgumentError,
    );
  });

  test(
    'sync worker rejects a pull page for a different durable cursor',
    () async {
      final persistence = _PullPersistence();
      final worker = SyncWorker(
        target: SyncTargetId.testOnly,
        persistence: persistence,
        backend: _MismatchedPullBackend(),
        scheduleWake: (_, _) {},
      );

      await worker.drain();

      expect(persistence.completed, isFalse);
      expect(
        persistence.failure,
        isA<RejectedSyncException>()
            .having(
              (error) => error.category,
              'category',
              SyncRejectionCategory.serverContract,
            )
            .having((error) => error.code, 'code', 'pull_cursor_mismatch'),
      );
    },
  );

  test('sync worker schedules retry on its exact target lane', () async {
    const target = SyncTargetId(
      typeIdentity: 'package:nodus/testing.dart#TestSyncTarget',
      wireName: 'secondary',
    );
    final retryAt = DateTime.utc(2026, 7, 11, 12);
    final persistence = _PullPersistence(target: target, retryAt: retryAt);
    SyncTargetId? scheduledTarget;
    DateTime? scheduledAt;
    final worker = SyncWorker(
      target: target,
      persistence: persistence,
      backend: _MismatchedPullBackend(),
      scheduleWake: (target, retryAt) {
        scheduledTarget = target;
        scheduledAt = retryAt;
      },
    );

    await worker.drain();

    expect(scheduledTarget, target);
    expect(scheduledAt, retryAt);
  });

  test(
    'Given durable work, When represented in memory, Then push and pull expose only valid capabilities',
    () {
      final createdAt = DateTime.utc(2026, 7, 11);
      final descriptor = TestDescriptor<_Item>();
      final push = PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 1,
        operation: PatchPushOperation(
          operationId: SyncOperationId('a0000000-0000-7000-8000-000000000002'),
          identity: descriptor.parseIdentity(
            'a0000000-0000-7000-8000-000000000001',
          ),
          baseServerVersion: ServerVersion(2),
          localRevision: 4,
          protocolVersion: 3,
          patch: EntityPatch.fromWire(const {}),
        ),
        pushKind: PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: createdAt,
        nextAttemptAt: null,
      );
      final pull = PullSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 2,
        operationId: SyncOperationId('a0000000-0000-7000-8000-000000000003'),
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: createdAt,
        nextAttemptAt: null,
      );

      expect(push.direction, SyncDirection.push);
      expect(push.kind, SyncWorkKind.statePatch);
      expect(push.operation.protocolVersion, 3);
      expect(pull.direction, SyncDirection.pull);
      expect(pull.kind, SyncWorkKind.pullChanges);
    },
  );

  test('typed entity patches pair field values with their generated codec', () {
    final field = NullableComparableEntityField<_NullableItem, DateTime>(
      name: 'updatedAt',
      read: (_) => null,
      encode: (value) => value?.toUtc().toIso8601String(),
    );
    final patch = field.patch(DateTime.parse('2026-07-11T12:00:00+02:00'));
    final wire = patch.toWire();

    expect(wire, {'updatedAt': '2026-07-11T10:00:00.000Z'});

    wire['updatedAt'] = 'changed outside';
    expect(patch['updatedAt'], '2026-07-11T10:00:00.000Z');

    final title = EqualityEntityField<_NullableItem, String>(
      name: 'title',
      read: (_) => '',
      encode: (value) => value,
    );
    final merged = patch.merge(title.patch('Focus'));
    expect(merged.toWire(), {
      'updatedAt': '2026-07-11T10:00:00.000Z',
      'title': 'Focus',
    });
    expect(patch.toWire(), {'updatedAt': '2026-07-11T10:00:00.000Z'});
  });

  test('persisted typed fields own their single storage descriptor', () {
    const persistence = EntityFieldDescriptor(
      name: 'isActive',
      columnName: 'is_active',
      kind: EntityFieldKind.boolean,
      nullable: false,
      mutable: true,
      conflictPolicy: FieldConflictPolicy.localWins,
    );
    final persisted = PersistedEqualityEntityField<_Item, bool>(
      persistence: persistence,
      read: (item) => item.isActive,
      encode: (value) => value,
      decode: (source) => source! as bool,
    );
    final queryOnly = EqualityEntityField<_Item, bool>(
      name: 'computed',
      read: (_) => true,
      encode: (value) => value,
    );

    expect(persisted.name, persistence.name);
    expect(persisted.persistence, same(persistence));
    expect(persisted.decode(true), isTrue);
    expect(persisted.encodeEntity(_Item('item')), isTrue);
    expect(persisted, isA<PersistedEntityFieldReference<_Item>>());
    expect(queryOnly, isNot(isA<PersistedEntityFieldReference<_Item>>()));
  });

  test('server-generated behavior derives from exact field conventions', () {
    const createdAt = EntityFieldDescriptor(
      name: EntityConventions.createdAtFieldName,
      columnName: 'created_at',
      kind: EntityFieldKind.timestamp,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    );
    const mutableCreatedAt = EntityFieldDescriptor(
      name: EntityConventions.createdAtFieldName,
      columnName: 'created_at',
      kind: EntityFieldKind.timestamp,
      nullable: false,
      mutable: true,
      conflictPolicy: FieldConflictPolicy.serverWins,
    );
    const serverVersion = EntityFieldDescriptor(
      name: EntityConventions.serverVersionFieldName,
      columnName: EntityConventions.serverVersionColumnName,
      kind: EntityFieldKind.integer,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    );
    const updatedAt = EntityFieldDescriptor(
      name: EntityConventions.updatedAtFieldName,
      columnName: EntityConventions.updatedAtColumnName,
      kind: EntityFieldKind.timestamp,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    );

    expect(createdAt.serverGenerated, isTrue);
    expect(serverVersion.serverGenerated, isTrue);
    expect(mutableCreatedAt.serverGenerated, isFalse);
    expect(updatedAt.serverGenerated, isFalse);
    expect(updatedAt.autoUpdated, isTrue);
  });

  test('sync rejections expose exhaustive semantic categories', () {
    expect(
      const RejectedSyncException.authorization(message: 'denied').category,
      SyncRejectionCategory.authorization,
    );
    expect(
      const RejectedSyncException.protocol(message: 'old client').code,
      'unsupported_protocol_version',
    );
    expect(
      const RejectedSyncException.notFound(message: 'gone').kind,
      SyncFailureKind.rejected,
    );
  });

  test(
    'standard collaboration commands validate and round-trip nominal IDs',
    () {
      final command = SetCollaboratorCommand<_Item, _NullableItem>.fromWire(
        const {
          'userId': 'a0000000-0000-7000-8000-000000000006',
          'active': true,
        },
        parseId: parseLocalId<_NullableItem>,
      );

      expect(
        command.collaboratorId,
        LocalId<_NullableItem>('a0000000-0000-7000-8000-000000000006'),
      );
      expect(command.active, isTrue);
      expect(command.toWire(), {
        'userId': 'a0000000-0000-7000-8000-000000000006',
        'active': true,
      });
      expect(
        () => SetCollaboratorCommand<_Item, _NullableItem>.fromWire(const {
          'userId': 'not-an-id',
          'active': true,
        }, parseId: parseLocalId<_NullableItem>),
        throwsFormatException,
      );
      expect(
        () => SetCollaboratorCommand<_Item, _NullableItem>.fromWire(const {
          'userId': 'a0000000-0000-7000-8000-000000000006',
          'active': 'yes',
        }, parseId: parseLocalId<_NullableItem>),
        throwsFormatException,
      );
    },
  );

  test(
    'state-persisting commands keep semantic and local patches separate',
    () {
      final active = PersistedEqualityEntityField<_Item, bool>(
        persistence: const EntityFieldDescriptor(
          name: 'isActive',
          columnName: 'is_active',
          kind: EntityFieldKind.boolean,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.localWins,
        ),
        read: (entity) => entity.isActive,
        encode: (value) => value,
        decode: (source) => source! as bool,
      );
      final operation = CommandPushOperation(
        operationId: parseSyncOperationId(
          'a0000000-0000-7000-8000-000000000008',
        ),
        identity: const TestDescriptor<_Item>().parseIdentity(
          'a0000000-0000-7000-8000-000000000009',
        ),
        baseServerVersion: ServerVersion.zero,
        localRevision: 2,
        protocolVersion: 3,
        command: SetCollaboratorCommand<_Item, _NullableItem>(
          collaboratorId: LocalId<_NullableItem>(
            'a0000000-0000-7000-8000-000000000010',
          ),
          active: true,
        ),
        storesEntityState: true,
        statePatch: active.patch(false),
      );

      final wire = operation.toWire();
      expect(wire['patch'], {
        'userId': 'a0000000-0000-7000-8000-000000000010',
        'active': true,
      });
      expect(wire['statePatch'], {'isActive': false});
      expect(operation.patch.toWire(), isNot(contains('isActive')));
      expect(operation.toRemoteWire(), isNot(contains('statePatch')));
      expect(operation.toRemoteWire(), isNot(contains('persistsEntityState')));
      expect(operation.toRemoteWire()['patch'], wire['patch']);
    },
  );

  test('ordered movement round-trips one semantic anchor without a rank', () {
    final command = MoveOrderedCommand<_Item>.fromWire(const {
      'placement': 'before',
      'anchorId': 'a0000000-0000-7000-8000-000000000012',
      'scopeBaseVersion': 4,
    }, parseId: parseLocalId<_Item>);

    expect(
      command.anchorId,
      LocalId<_Item>('a0000000-0000-7000-8000-000000000012'),
    );
    expect(command.placement, OrderedPlacement.before);
    expect(command.scopeBaseVersion, OrderScopeVersion(4));
    expect(command.toWire(), {
      'placement': 'before',
      'anchorId': 'a0000000-0000-7000-8000-000000000012',
      'scopeBaseVersion': 4,
    });
    expect(command.toWire(), isNot(contains('rank')));
    expect(
      () => MoveOrderedCommand<_Item>.fromWire(const {
        'placement': 'before',
        'anchorId': null,
        'scopeBaseVersion': 0,
      }, parseId: parseLocalId<_Item>),
      throwsFormatException,
    );
  });

  test('ordered create keeps placement intent beside its optimistic patch', () {
    const entityId = 'a0000000-0000-7000-8000-000000000013';
    const descriptor = TestDescriptor<_Item>();
    final operation = CreatePushOperation(
      operationId: parseSyncOperationId('a0000000-0000-7000-8000-000000000014'),
      identity: descriptor.parseIdentity(entityId),
      baseServerVersion: ServerVersion.zero,
      localRevision: 1,
      protocolVersion: descriptor.protocolVersion,
      patch: EntityPatch.fromWire(const {
        'id': entityId,
        'orderRank':
            '057896044618658097711785492504343953926634992332820282019728792003956564819967',
      }),
      orderedCreate: OrderedCreateIntent(
        placement: OrderedPlacement.last,
        scopeBaseVersion: OrderScopeVersion(4),
      ),
    );

    expect(operation.toWire()['orderedCreate'], {
      'placement': 'last',
      'scopeBaseVersion': 4,
    });
    expect(operation.toRemoteWire()['orderedCreate'], {
      'placement': 'last',
      'scopeBaseVersion': 4,
    });
    expect(operation.toWire()['patch'], operation.patch.toWire());
    expect(
      operation.toRemoteWire()['patch'],
      isNot(contains(EntityConventions.orderRankFieldName)),
    );
  });

  test('remote field snapshots validate schema and canonicalize UUIDs', () {
    final descriptor = TestDescriptor<_Item>();
    final fields = RemoteEntityFields.decode(descriptor, const {
      'id': '  A0000000-0000-7000-8000-000000000007  ',
      'isActive': true,
      'serverVersion': 1,
    }, complete: true);

    expect(fields['id'], 'a0000000-0000-7000-8000-000000000007');
    expect(fields.identity.rawId, 'a0000000-0000-7000-8000-000000000007');
    expect(fields['isActive'], isTrue);
    expect(fields['serverVersion'], 1);
    for (final invalid in <JsonMap>[
      const {'id': 'a0000000-0000-7000-8000-000000000007', 'serverVersion': 1},
      const {
        'id': 'a0000000-0000-7000-8000-000000000007',
        'isActive': 1,
        'serverVersion': 1,
      },
      const {
        'id': 'a0000000-0000-7000-8000-000000000007',
        'isActive': true,
        'serverVersion': 1,
        'unknown': 'value',
      },
    ]) {
      expect(
        () => RemoteEntityFields.decode(descriptor, invalid, complete: true),
        throwsFormatException,
      );
    }
    expect(
      () => RemoteEntityChange(
        identity: descriptor.parseIdentity(
          'a0000000-0000-7000-8000-000000000007',
        ),
        serverVersion: ServerVersion(2),
        fields: fields,
        serverSequence: ServerSequence(1),
      ),
      throwsFormatException,
      reason: 'Every backend must honor record/envelope version agreement.',
    );
    expect(
      () => RemoteEntityChange(
        identity: descriptor.parseIdentity(
          'a0000000-0000-7000-8000-000000000008',
        ),
        serverVersion: ServerVersion(1),
        fields: fields,
        serverSequence: ServerSequence(1),
      ),
      throwsFormatException,
      reason: 'Every backend must honor record/envelope identity agreement.',
    );
    expect(
      () => RemoteEntityFields.decode(descriptor, const {
        'serverVersion': 1,
      }, complete: false),
      throwsFormatException,
    );
  });

  test('push results require an exact, non-revoking operation receipt', () {
    const entityId = 'a0000000-0000-7000-8000-000000000009';
    final descriptor = TestDescriptor<_Item>();
    final operationId = SyncOperationId('a0000000-0000-7000-8000-000000000010');
    final item = PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 1,
      operation: CreatePushOperation(
        operationId: operationId,
        identity: descriptor.parseIdentity(entityId),
        baseServerVersion: ServerVersion.zero,
        localRevision: 1,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire(const {'id': entityId, 'isActive': true}),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12),
      nextAttemptAt: null,
    );

    PushResult result({
      String id = entityId,
      required SyncOperationId? receipt,
      bool isRevocation = false,
      Iterable<RemoteEntityChange> relatedChanges = const [],
    }) {
      final fields = RemoteEntityFields.decode(descriptor, {
        'id': id,
        if (!isRevocation) 'isActive': true,
        if (!isRevocation) 'serverVersion': 1,
      }, complete: !isRevocation);
      return PushResult(
        canonicalChange: RemoteEntityChange(
          identity: descriptor.parseIdentity(id),
          serverVersion: ServerVersion(1),
          fields: fields,
          serverSequence: ServerSequence(1),
          sourceOperationId: receipt,
          isRevocation: isRevocation,
        ),
        relatedChanges: relatedChanges,
      );
    }

    Matcher rejectsWith(String code) => throwsA(
      isA<RejectedSyncException>()
          .having(
            (error) => error.category,
            'category',
            SyncRejectionCategory.serverContract,
          )
          .having((error) => error.code, 'code', code),
    );

    expect(
      () => result(receipt: operationId).validateFor(item),
      returnsNormally,
    );
    expect(
      () => result(
        id: 'a0000000-0000-7000-8000-000000000011',
        receipt: operationId,
      ).validateFor(item),
      rejectsWith('push_identity_mismatch'),
    );
    expect(
      () => result(
        receipt: SyncOperationId('a0000000-0000-7000-8000-000000000012'),
      ).validateFor(item),
      rejectsWith('push_receipt_mismatch'),
    );
    expect(
      () => result(receipt: operationId, isRevocation: true).validateFor(item),
      rejectsWith('push_revocation_result'),
    );
    final duplicate = result(receipt: operationId).canonicalChange;
    expect(
      () => result(
        receipt: operationId,
        relatedChanges: [duplicate],
      ).validateFor(item),
      rejectsWith('duplicate_push_result_identity'),
    );
  });

  test(
    'in-memory transport rejects a create that would replace state',
    () async {
      const entityId = 'a0000000-0000-7000-8000-000000000009';
      final descriptor = TestDescriptor<_Item>();
      final backend = InMemorySyncBackend(descriptor: descriptor);
      addTearDown(backend.disposeRemoteChangeSignals);

      PushSyncWorkItem create(String operationId) => PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 1,
        operation: CreatePushOperation(
          operationId: parseSyncOperationId(operationId),
          identity: descriptor.parseIdentity(entityId),
          baseServerVersion: ServerVersion.zero,
          localRevision: 1,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire(const {'id': entityId, 'isActive': true}),
        ),
        pushKind: PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 12),
        nextAttemptAt: null,
      );

      await backend.push(create('a0000000-0000-7000-8000-000000000010'));

      await expectLater(
        backend.push(create('a0000000-0000-7000-8000-000000000011')),
        throwsA(
          isA<RejectedSyncException>()
              .having(
                (error) => error.category,
                'category',
                SyncRejectionCategory.validation,
              )
              .having((error) => error.code, 'code', 'unique_violation'),
        ),
      );
      expect(backend.record(entityId)?['isActive'], isTrue);
    },
  );

  test(
    'ordered creates resolve stale first and last intent on the server',
    () async {
      const descriptor = _OrderedLinkDescriptor();
      final backend = InMemorySyncBackend(descriptor: descriptor);
      addTearDown(backend.disposeRemoteChangeSignals);
      const ownerId = 'a0000000-0000-7000-8000-000000000001';
      const sourceId = 'a0000000-0000-7000-8000-000000000002';
      const firstCreated = 'a0000000-0000-7000-8000-000000000019';
      const staleLast = 'a0000000-0000-7000-8000-000000000011';
      const staleFirst = 'a0000000-0000-7000-8000-000000000099';
      final provisional = GeneratedOrderRanks.between()!;
      var queueId = 0;

      Future<PushResult> create(
        String entityId,
        OrderedPlacement placement,
      ) => backend.push(
        PushSyncWorkItem(
          target: SyncTargetId.testOnly,
          id: ++queueId,
          operation: CreatePushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(500 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(entityId),
            baseServerVersion: ServerVersion.zero,
            localRevision: 1,
            protocolVersion: descriptor.protocolVersion,
            patch: EntityPatch.fromWire({
              'id': entityId,
              'ownerId': ownerId,
              'sourceId': sourceId,
              'orderRank': provisional.value,
              'deletedAt': null,
            }),
            orderedCreate: OrderedCreateIntent(
              placement: placement,
              scopeBaseVersion: OrderScopeVersion.zero,
            ),
          ),
          pushKind: PushSyncWorkKind.statePatch,
          status: SyncWorkStatus.pending,
          attemptCount: 0,
          createdAt: DateTime.utc(2026, 7, 17),
          nextAttemptAt: null,
        ),
      );

      expect(
        (await create(
          firstCreated,
          OrderedPlacement.last,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(1),
      );
      expect(
        (await create(
          staleLast,
          OrderedPlacement.last,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(2),
      );
      expect(
        (await create(
          staleFirst,
          OrderedPlacement.first,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(3),
      );

      final canonical = [staleFirst, firstCreated, staleLast]
        ..sort((left, right) {
          final byRank = (backend.record(left)!['orderRank']! as String)
              .compareTo(backend.record(right)!['orderRank']! as String);
          return byRank != 0 ? byRank : left.compareTo(right);
        });
      expect(canonical, [staleFirst, firstCreated, staleLast]);
      expect({
        for (final id in canonical) backend.record(id)!['orderRank'],
      }, hasLength(3));
    },
  );

  test(
    'ordered transport isolates relationship-source scopes sharing one owner',
    () async {
      const descriptor = _OrderedLinkDescriptor();
      final backend = InMemorySyncBackend(descriptor: descriptor);
      addTearDown(backend.disposeRemoteChangeSignals);
      final ranks = GeneratedOrderRanks.allocate(count: 4)!;
      const ownerId = 'a0000000-0000-7000-8000-000000000001';
      const sourceA = 'a0000000-0000-7000-8000-000000000002';
      const sourceB = 'a0000000-0000-7000-8000-000000000003';
      const a1 = 'a0000000-0000-7000-8000-000000000011';
      const a2 = 'a0000000-0000-7000-8000-000000000012';
      const b1 = 'a0000000-0000-7000-8000-000000000021';
      const b2 = 'a0000000-0000-7000-8000-000000000022';
      var queueId = 0;

      PushSyncWorkItem work(PushOperation operation) => PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: ++queueId,
        operation: operation,
        pushKind:
            operation is CommandPushOperation ||
                operation is DeletePushOperation
            ? PushSyncWorkKind.semanticCommand
            : PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 17),
        nextAttemptAt: null,
      );

      Future<PushResult> create(
        String id,
        String sourceId,
        OrderRank rank,
      ) => backend.push(
        work(
          CreatePushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(100 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(id),
            baseServerVersion: ServerVersion.zero,
            localRevision: 1,
            protocolVersion: descriptor.protocolVersion,
            patch: EntityPatch.fromWire({
              'id': id,
              'ownerId': ownerId,
              'sourceId': sourceId,
              'orderRank': rank.value,
              'deletedAt': null,
            }),
          ),
        ),
      );

      Future<PushResult> move(
        String id,
        OrderedPlacement placement,
        String? anchorId,
      ) => backend.push(
        work(
          CommandPushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(200 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(id),
            baseServerVersion: ServerVersion(1),
            localRevision: 2,
            protocolVersion: descriptor.protocolVersion,
            command: MoveOrderedCommand<_OrderedLink>(
              placement: placement,
              anchorId: anchorId == null
                  ? null
                  : parseLocalId<_OrderedLink>(anchorId),
              scopeBaseVersion: OrderScopeVersion.zero,
            ),
          ),
        ),
      );

      Future<PushResult> reorder(List<String> ids) => backend.push(
        work(
          CommandPushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(300 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(ids.first),
            baseServerVersion: ServerVersion(2),
            localRevision: 3,
            protocolVersion: descriptor.protocolVersion,
            command: ReorderOrderedCommand<_OrderedLink>(
              orderedIds: ids.map(parseLocalId<_OrderedLink>),
              scopeBaseVersion: OrderScopeVersion(1),
            ),
          ),
        ),
      );

      Future<PushResult> transfer(
        String id,
        String targetSourceId,
      ) => backend.push(
        work(
          CommandPushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(350 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(id),
            baseServerVersion: ServerVersion(3),
            localRevision: 4,
            protocolVersion: descriptor.protocolVersion,
            command: TransferOrderedCommand<_OrderedLink>(
              targetScope: EntityPatch.fromWire({'sourceId': targetSourceId}),
              placement: OrderedPlacement.last,
              sourceScopeBaseVersion: OrderScopeVersion(4),
              targetScopeBaseVersion: OrderScopeVersion(3),
            ),
          ),
        ),
      );

      Future<PushResult> setDeleted(
        String id, {
        required ServerVersion baseVersion,
        required Object? deletedAt,
      }) => backend.push(
        work(
          DeletePushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-${(400 + queueId).toString().padLeft(12, '0')}',
            ),
            identity: descriptor.parseIdentity(id),
            baseServerVersion: baseVersion,
            localRevision: baseVersion.value + 1,
            protocolVersion: descriptor.protocolVersion,
            patch: EntityPatch.fromWire({'deletedAt': deletedAt}),
          ),
        ),
      );

      expect(
        (await create(a1, sourceA, ranks[0])).orderScopeVersions.single.version,
        OrderScopeVersion(1),
      );
      expect(
        (await create(a2, sourceA, ranks[1])).orderScopeVersions.single.version,
        OrderScopeVersion(2),
      );
      expect(
        (await create(b1, sourceB, ranks[2])).orderScopeVersions.single.version,
        OrderScopeVersion(1),
      );
      expect(
        (await create(b2, sourceB, ranks[3])).orderScopeVersions.single.version,
        OrderScopeVersion(2),
      );

      expect(
        (await move(
          a2,
          OrderedPlacement.before,
          a1,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(3),
      );
      expect(
        (await move(
          b2,
          OrderedPlacement.before,
          b1,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(3),
      );
      final exact = await reorder([a1, a2]);
      expect(exact.orderScopeVersions.single.version, OrderScopeVersion(4));
      expect(exact.relatedChanges, hasLength(1));
      expect(
        [
          exact.canonicalChange,
          ...exact.relatedChanges,
        ].map((change) => change.identity.rawId).toSet(),
        {a1, a2},
      );
      final exactRanks = GeneratedOrderRanks.allocate(count: 2)!;
      expect(backend.record(a1)?['orderRank'], exactRanks[0].value);
      expect(backend.record(a2)?['orderRank'], exactRanks[1].value);
      final transferred = await transfer(a2, sourceB);
      expect(
        transferred.orderScopeVersions
            .map((receipt) => (receipt.scope['sourceId'], receipt.version))
            .toSet(),
        {(sourceA, OrderScopeVersion(5)), (sourceB, OrderScopeVersion(4))},
      );
      expect(backend.record(a2)?['sourceId'], sourceB);
      final targetIds = [b1, b2, a2]
        ..sort((left, right) {
          final leftRecord = backend.record(left)!;
          final rightRecord = backend.record(right)!;
          final byRank = (leftRecord['orderRank']! as String).compareTo(
            rightRecord['orderRank']! as String,
          );
          return byRank != 0 ? byRank : left.compareTo(right);
        });
      expect(targetIds, [b2, b1, a2]);
      await expectLater(
        move(a1, OrderedPlacement.before, b1),
        throwsA(
          isA<RejectedSyncException>().having(
            (error) => error.code,
            'code',
            'invalid_order_anchor',
          ),
        ),
      );
      await expectLater(
        reorder([a1, b1]),
        throwsA(isA<VersionConflictException>()),
      );
      expect(
        (await setDeleted(
          a1,
          baseVersion: ServerVersion(2),
          deletedAt: DateTime.utc(2026, 7, 17).toIso8601String(),
        )).orderScopeVersions.single.version,
        OrderScopeVersion(6),
      );
      expect(
        (await setDeleted(
          a1,
          baseVersion: ServerVersion(3),
          deletedAt: null,
        )).orderScopeVersions.single.version,
        OrderScopeVersion(7),
      );
    },
  );

  test('ordered transport excludes inactive relationship membership', () async {
    const descriptor = _OrderedLinkDescriptor();
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    const entityId = 'a0000000-0000-7000-8000-000000000031';
    const ownerId = 'a0000000-0000-7000-8000-000000000001';
    const sourceId = 'a0000000-0000-7000-8000-000000000002';
    final rank = GeneratedOrderRanks.between()!;

    PushSyncWorkItem work(int id, PushOperation operation) => PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: id,
      operation: operation,
      pushKind: operation is CommandPushOperation
          ? PushSyncWorkKind.semanticCommand
          : PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 17),
      nextAttemptAt: null,
    );

    final created = await backend.push(
      work(
        1,
        CreatePushOperation(
          operationId: parseSyncOperationId(
            'a0000000-0000-7000-8000-000000000601',
          ),
          identity: descriptor.parseIdentity(entityId),
          baseServerVersion: ServerVersion.zero,
          localRevision: 1,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire({
            'id': entityId,
            'ownerId': ownerId,
            'sourceId': sourceId,
            'orderRank': rank.value,
            'deletedAt': null,
          }),
          orderedCreate: OrderedCreateIntent(
            placement: OrderedPlacement.last,
            scopeBaseVersion: OrderScopeVersion.zero,
          ),
        ),
      ),
    );
    expect(created.orderScopeVersions.single.version, OrderScopeVersion(1));

    final deactivated = await backend.push(
      work(
        2,
        PatchPushOperation(
          operationId: parseSyncOperationId(
            'a0000000-0000-7000-8000-000000000602',
          ),
          identity: descriptor.parseIdentity(entityId),
          baseServerVersion: ServerVersion(1),
          localRevision: 2,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire(const {'active': false}),
        ),
      ),
    );
    expect(deactivated.orderScopeVersions.single.version, OrderScopeVersion(2));
    expect(backend.record(entityId)?['active'], isFalse);

    await expectLater(
      backend.push(
        work(
          3,
          CommandPushOperation(
            operationId: parseSyncOperationId(
              'a0000000-0000-7000-8000-000000000603',
            ),
            identity: descriptor.parseIdentity(entityId),
            baseServerVersion: ServerVersion(2),
            localRevision: 3,
            protocolVersion: descriptor.protocolVersion,
            command: MoveOrderedCommand<_OrderedLink>(
              placement: OrderedPlacement.last,
              anchorId: null,
              scopeBaseVersion: OrderScopeVersion(2),
            ),
          ),
        ),
      ),
      throwsA(isA<RejectedSyncException>()),
    );
  });

  test('in-memory transport enforces generated scalar constraints', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000019';
    final descriptor = TestDescriptor<_Item>(
      fields: const [
        EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'title',
          columnName: 'title',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.localWins,
          constraints: EntityFieldConstraints(minLength: 1, maxLength: 5),
        ),
        EntityFieldDescriptor(
          name: 'serverVersion',
          columnName: 'server_version',
          kind: EntityFieldKind.integer,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
      ],
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    final item = PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 1,
      operation: CreatePushOperation(
        operationId: parseSyncOperationId(
          'a0000000-0000-7000-8000-000000000020',
        ),
        identity: descriptor.parseIdentity(entityId),
        baseServerVersion: ServerVersion.zero,
        localRevision: 1,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire(const {
          'id': entityId,
          'title': 'Too long',
        }),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12),
      nextAttemptAt: null,
    );

    await expectLater(
      backend.push(item),
      throwsA(
        isA<RejectedSyncException>()
            .having(
              (error) => error.category,
              'category',
              SyncRejectionCategory.validation,
            )
            .having((error) => error.code, 'code', 'constraint_violation'),
      ),
    );
    expect(backend.record(entityId), isNull);
  });

  test('in-memory transport synthesizes server-owned timestamps', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000031';
    final descriptor = TestDescriptor<_Item>(
      fields: const [
        EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'isActive',
          columnName: 'is_active',
          kind: EntityFieldKind.boolean,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.localWins,
        ),
        EntityFieldDescriptor(
          name: 'createdAt',
          columnName: 'created_at',
          kind: EntityFieldKind.timestamp,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'updatedAt',
          columnName: 'updated_at',
          kind: EntityFieldKind.timestamp,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'serverVersion',
          columnName: 'server_version',
          kind: EntityFieldKind.integer,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
      ],
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    final createdAt = DateTime.utc(2026, 7, 12, 9);
    final updatedAt = DateTime.utc(2026, 7, 12, 10);

    final create = await backend.push(
      PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 1,
        operation: CreatePushOperation(
          operationId: parseSyncOperationId(
            'a0000000-0000-7000-8000-000000000032',
          ),
          identity: descriptor.parseIdentity(entityId),
          baseServerVersion: ServerVersion.zero,
          localRevision: 1,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire(const {'id': entityId, 'isActive': true}),
        ),
        pushKind: PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: createdAt,
        nextAttemptAt: null,
      ),
    );
    expect(
      create.canonicalChange.fields['createdAt'],
      createdAt.toIso8601String(),
    );
    expect(
      create.canonicalChange.fields['updatedAt'],
      createdAt.toIso8601String(),
    );

    final update = await backend.push(
      PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 2,
        operation: PatchPushOperation(
          operationId: parseSyncOperationId(
            'a0000000-0000-7000-8000-000000000033',
          ),
          identity: descriptor.parseIdentity(entityId),
          baseServerVersion: ServerVersion(1),
          localRevision: 2,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire(const {'isActive': false}),
        ),
        pushKind: PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: updatedAt,
        nextAttemptAt: null,
      ),
    );
    expect(
      update.canonicalChange.fields['createdAt'],
      createdAt.toIso8601String(),
    );
    expect(
      update.canonicalChange.fields['updatedAt'],
      updatedAt.toIso8601String(),
    );
  });

  test('in-memory transport enforces generated unique constraints', () async {
    final descriptor = TestDescriptor<_Item>(
      uniqueConstraints: const [
        EntityUniqueConstraint(
          name: 'notes_is_active_idx',
          fieldNames: ['isActive'],
        ),
      ],
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);

    PushSyncWorkItem create({
      required String id,
      required String operationId,
    }) => PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 1,
      operation: CreatePushOperation(
        operationId: parseSyncOperationId(operationId),
        identity: descriptor.parseIdentity(id),
        baseServerVersion: ServerVersion.zero,
        localRevision: 1,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire({'id': id, 'isActive': true}),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12),
      nextAttemptAt: null,
    );

    await backend.push(
      create(
        id: 'a0000000-0000-7000-8000-000000000013',
        operationId: 'a0000000-0000-7000-8000-000000000014',
      ),
    );
    await expectLater(
      backend.push(
        create(
          id: 'a0000000-0000-7000-8000-000000000015',
          operationId: 'a0000000-0000-7000-8000-000000000016',
        ),
      ),
      throwsA(
        isA<RejectedSyncException>()
            .having((error) => error.code, 'code', 'unique_violation')
            .having(
              (error) => error.message,
              'message',
              contains('notes_is_active_idx'),
            ),
      ),
    );
  });

  test(
    'in-memory transport treats unordered owner pairs as reciprocal',
    () async {
      const descriptor = TestDescriptor<_Item>(
        fields: [
          EntityFieldDescriptor(
            name: 'id',
            columnName: 'id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
          EntityFieldDescriptor(
            name: 'ownerId',
            columnName: 'owner_id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
          EntityFieldDescriptor(
            name: 'friendId',
            columnName: 'friend_id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
          EntityFieldDescriptor(
            name: 'deletedAt',
            columnName: 'deleted_at',
            kind: EntityFieldKind.timestamp,
            nullable: true,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
          EntityFieldDescriptor(
            name: 'serverVersion',
            columnName: 'server_version',
            kind: EntityFieldKind.integer,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
        ],
        uniqueConstraints: [
          EntityUniqueConstraint(
            name: 'friendships_unordered_owner_id_friend_id_active_idx',
            fieldNames: ['ownerId', 'friendId'],
            condition: EntityUniqueConstraintCondition(
              fieldName: 'deletedAt',
              values: [null],
            ),
            unordered: true,
          ),
        ],
      );
      final backend = InMemorySyncBackend(descriptor: descriptor);
      addTearDown(backend.disposeRemoteChangeSignals);
      const firstUser = 'a0000000-0000-7000-8000-000000000021';
      const secondUser = 'a0000000-0000-7000-8000-000000000022';

      PushSyncWorkItem create({
        required String id,
        required String operationId,
        required String ownerId,
        required String friendId,
        String? deletedAt,
      }) => PushSyncWorkItem(
        target: SyncTargetId.testOnly,
        id: 1,
        operation: CreatePushOperation(
          operationId: parseSyncOperationId(operationId),
          identity: descriptor.parseIdentity(id),
          baseServerVersion: ServerVersion.zero,
          localRevision: 1,
          protocolVersion: descriptor.protocolVersion,
          patch: EntityPatch.fromWire({
            'id': id,
            'ownerId': ownerId,
            'friendId': friendId,
            'deletedAt': ?deletedAt,
          }),
        ),
        pushKind: PushSyncWorkKind.statePatch,
        status: SyncWorkStatus.pending,
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 12),
        nextAttemptAt: null,
      );

      await backend.push(
        create(
          id: 'a0000000-0000-7000-8000-000000000023',
          operationId: 'a0000000-0000-7000-8000-000000000024',
          ownerId: firstUser,
          friendId: secondUser,
        ),
      );
      await expectLater(
        backend.push(
          create(
            id: 'a0000000-0000-7000-8000-000000000025',
            operationId: 'a0000000-0000-7000-8000-000000000026',
            ownerId: secondUser,
            friendId: firstUser,
          ),
        ),
        throwsA(
          isA<RejectedSyncException>().having(
            (error) => error.code,
            'code',
            'unique_violation',
          ),
        ),
      );
      await expectLater(
        backend.push(
          create(
            id: 'a0000000-0000-7000-8000-000000000027',
            operationId: 'a0000000-0000-7000-8000-000000000028',
            ownerId: firstUser,
            friendId: firstUser,
          ),
        ),
        throwsA(
          isA<RejectedSyncException>().having(
            (error) => error.code,
            'code',
            'check_violation',
          ),
        ),
      );

      final tombstoneBackend = InMemorySyncBackend(descriptor: descriptor);
      addTearDown(tombstoneBackend.disposeRemoteChangeSignals);
      await tombstoneBackend.push(
        create(
          id: 'a0000000-0000-7000-8000-000000000029',
          operationId: 'a0000000-0000-7000-8000-000000000030',
          ownerId: firstUser,
          friendId: secondUser,
          deletedAt: '2026-07-12T00:00:00.000Z',
        ),
      );
      await tombstoneBackend.push(
        create(
          id: 'a0000000-0000-7000-8000-000000000031',
          operationId: 'a0000000-0000-7000-8000-000000000032',
          ownerId: secondUser,
          friendId: firstUser,
        ),
      );
      expect(
        tombstoneBackend.record('a0000000-0000-7000-8000-000000000031'),
        isNotNull,
      );
    },
  );

  test('in-memory transport scopes conditional unique constraints', () async {
    final descriptor = TestDescriptor<_Item>(
      fields: const [
        EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'taskKey',
          columnName: 'task_key',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'status',
          columnName: 'status',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'serverVersion',
          columnName: 'server_version',
          kind: EntityFieldKind.integer,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
      ],
      uniqueConstraints: const [
        EntityUniqueConstraint(
          name: 'assignments_task_key_active_idx',
          fieldNames: ['taskKey'],
          condition: EntityUniqueConstraintCondition(
            fieldName: 'status',
            values: ['pending', 'accepted'],
          ),
        ),
      ],
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);

    PushSyncWorkItem create({
      required String id,
      required String operationId,
      required String status,
    }) => PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 1,
      operation: CreatePushOperation(
        operationId: parseSyncOperationId(operationId),
        identity: descriptor.parseIdentity(id),
        baseServerVersion: ServerVersion.zero,
        localRevision: 1,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire({
          'id': id,
          'taskKey': 'task-1',
          'status': status,
        }),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12),
      nextAttemptAt: null,
    );

    await backend.push(
      create(
        id: 'a0000000-0000-7000-8000-000000000017',
        operationId: 'a0000000-0000-7000-8000-000000000018',
        status: 'declined',
      ),
    );
    await backend.push(
      create(
        id: 'a0000000-0000-7000-8000-000000000019',
        operationId: 'a0000000-0000-7000-8000-000000000020',
        status: 'pending',
      ),
    );
    await expectLater(
      backend.push(
        create(
          id: 'a0000000-0000-7000-8000-000000000021',
          operationId: 'a0000000-0000-7000-8000-000000000022',
          status: 'accepted',
        ),
      ),
      throwsA(
        isA<RejectedSyncException>().having(
          (error) => error.code,
          'code',
          'unique_violation',
        ),
      ),
    );
  });

  test('in-memory transport enforces generated state transitions', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000030';
    final descriptor = TestDescriptor<_Item>(
      fields: const [
        EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'status',
          columnName: 'status',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.serverWins,
          hasProtocolDefault: true,
          protocolDefault: 'pending',
          allowedTransitions: [EntityValueTransition('pending', 'accepted')],
        ),
        EntityFieldDescriptor(
          name: 'serverVersion',
          columnName: 'server_version',
          kind: EntityFieldKind.integer,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
      ],
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    final identity = descriptor.parseIdentity(entityId);

    PushSyncWorkItem item({
      required String operationId,
      required ServerVersion baseVersion,
      required EntityPatch patch,
      required bool create,
    }) => PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: baseVersion.value + 1,
      operation: create
          ? CreatePushOperation(
              operationId: parseSyncOperationId(operationId),
              identity: identity,
              baseServerVersion: baseVersion,
              localRevision: baseVersion.value + 1,
              protocolVersion: descriptor.protocolVersion,
              patch: patch,
            )
          : PatchPushOperation(
              operationId: parseSyncOperationId(operationId),
              identity: identity,
              baseServerVersion: baseVersion,
              localRevision: baseVersion.value + 1,
              protocolVersion: descriptor.protocolVersion,
              patch: patch,
            ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 13),
      nextAttemptAt: null,
    );

    await expectLater(
      backend.push(
        item(
          operationId: 'a0000000-0000-7000-8000-000000000034',
          baseVersion: ServerVersion.zero,
          patch: EntityPatch.fromWire(const {
            'id': entityId,
            'status': 'accepted',
          }),
          create: true,
        ),
      ),
      throwsA(
        isA<RejectedSyncException>().having(
          (error) => error.code,
          'code',
          'invalid_initial_state',
        ),
      ),
    );

    await backend.push(
      item(
        operationId: 'a0000000-0000-7000-8000-000000000031',
        baseVersion: ServerVersion.zero,
        patch: EntityPatch.fromWire(const {
          'id': entityId,
          'status': 'pending',
        }),
        create: true,
      ),
    );
    await backend.push(
      item(
        operationId: 'a0000000-0000-7000-8000-000000000032',
        baseVersion: ServerVersion(1),
        patch: EntityPatch.fromWire(const {'status': 'accepted'}),
        create: false,
      ),
    );

    await expectLater(
      backend.push(
        item(
          operationId: 'a0000000-0000-7000-8000-000000000033',
          baseVersion: ServerVersion(2),
          patch: EntityPatch.fromWire(const {'status': 'pending'}),
          create: false,
        ),
      ),
      throwsA(
        isA<RejectedSyncException>()
            .having((error) => error.code, 'code', 'invalid_transition')
            .having(
              (error) => error.category,
              'category',
              SyncRejectionCategory.validation,
            ),
      ),
    );
    expect(backend.record(entityId)?['status'], 'accepted');
  });

  test('action policies guard only action-exclusive targets', () {
    const policy = ActionPolicy(
      actions: [
        ActionDefinition(
          fieldNames: ['title', 'reviewedAt'],
          guardedFieldNames: ['reviewedAt'],
          assignments: [
            ActionAssignment.clockNow('reviewedAt', firstWriteOnly: true),
          ],
        ),
      ],
    );
    final reviewedAt = DateTime.utc(2026, 7, 21).toIso8601String();

    expect(policy.allowsPatch(const {'title': 'Draft'}, const {}), isTrue);
    expect(policy.allowsPatch({'reviewedAt': reviewedAt}, const {}), isFalse);
    expect(
      policy.allowsPatch({
        'title': 'Reviewed',
        'reviewedAt': reviewedAt,
      }, const {}),
      isTrue,
    );
  });

  test('in-memory transport enforces atomic entity action shapes', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000040';
    final descriptor = TestDescriptor<_Item>(
      fields: const [
        EntityFieldDescriptor(
          name: 'id',
          columnName: 'id',
          kind: EntityFieldKind.uuid,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'status',
          columnName: 'status',
          kind: EntityFieldKind.text,
          nullable: false,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.serverWins,
          hasProtocolDefault: true,
          protocolDefault: 'active',
          allowedTransitions: [
            EntityValueTransition('active', 'completed'),
            EntityValueTransition('completed', 'active'),
          ],
        ),
        EntityFieldDescriptor(
          name: 'completedAt',
          columnName: 'completed_at',
          kind: EntityFieldKind.timestamp,
          nullable: true,
          mutable: true,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
        EntityFieldDescriptor(
          name: 'serverVersion',
          columnName: 'server_version',
          kind: EntityFieldKind.integer,
          nullable: false,
          mutable: false,
          conflictPolicy: FieldConflictPolicy.serverWins,
        ),
      ],
      actionPolicy: const ActionPolicy(
        fixedInitialValues: {'completedAt': null},
        actions: [
          ActionDefinition(
            fieldNames: ['status', 'completedAt'],
            assignments: [
              ActionAssignment.literal('status', 'completed'),
              ActionAssignment.clockNow('completedAt', firstWriteOnly: true),
            ],
          ),
          ActionDefinition(
            fieldNames: ['status', 'completedAt'],
            assignments: [
              ActionAssignment.literal('status', 'active'),
              ActionAssignment.clear('completedAt'),
            ],
          ),
        ],
      ),
    );
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    final identity = descriptor.parseIdentity(entityId);

    PushSyncWorkItem item({
      required String operationId,
      required ServerVersion baseVersion,
      required EntityPatch patch,
      required bool create,
    }) => PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: baseVersion.value + 1,
      operation: create
          ? CreatePushOperation(
              operationId: parseSyncOperationId(operationId),
              identity: identity,
              baseServerVersion: baseVersion,
              localRevision: baseVersion.value + 1,
              protocolVersion: descriptor.protocolVersion,
              patch: patch,
            )
          : PatchPushOperation(
              operationId: parseSyncOperationId(operationId),
              identity: identity,
              baseServerVersion: baseVersion,
              localRevision: baseVersion.value + 1,
              protocolVersion: descriptor.protocolVersion,
              patch: patch,
            ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 13),
      nextAttemptAt: null,
    );

    await expectLater(
      backend.push(
        item(
          operationId: 'a0000000-0000-7000-8000-000000000041',
          baseVersion: ServerVersion.zero,
          patch: EntityPatch.fromWire(const {
            'id': entityId,
            'status': 'active',
            'completedAt': '2026-07-13T10:00:00.000Z',
          }),
          create: true,
        ),
      ),
      throwsA(
        isA<RejectedSyncException>().having(
          (error) => error.code,
          'code',
          'invalid_initial_action_state',
        ),
      ),
    );

    await backend.push(
      item(
        operationId: 'a0000000-0000-7000-8000-000000000042',
        baseVersion: ServerVersion.zero,
        patch: EntityPatch.fromWire(const {
          'id': entityId,
          'status': 'active',
          'completedAt': null,
        }),
        create: true,
      ),
    );

    Future<void> expectInvalidAction(
      String operationId,
      ServerVersion baseVersion,
      JsonMap patch,
    ) => expectLater(
      backend.push(
        item(
          operationId: operationId,
          baseVersion: baseVersion,
          patch: EntityPatch.fromWire(patch),
          create: false,
        ),
      ),
      throwsA(
        isA<RejectedSyncException>().having(
          (error) => error.code,
          'code',
          'invalid_entity_action',
        ),
      ),
    );

    await expectInvalidAction(
      'a0000000-0000-7000-8000-000000000043',
      ServerVersion(1),
      const {'status': 'completed'},
    );
    await expectInvalidAction(
      'a0000000-0000-7000-8000-000000000044',
      ServerVersion(1),
      const {'status': 'completed', 'completedAt': null},
    );
    await backend.push(
      item(
        operationId: 'a0000000-0000-7000-8000-000000000045',
        baseVersion: ServerVersion(1),
        patch: EntityPatch.fromWire(const {
          'status': 'completed',
          'completedAt': '2026-07-13T10:00:00.000Z',
        }),
        create: false,
      ),
    );
    await expectInvalidAction(
      'a0000000-0000-7000-8000-000000000046',
      ServerVersion(2),
      const {'status': 'completed', 'completedAt': '2026-07-13T11:00:00.000Z'},
    );
    await backend.push(
      item(
        operationId: 'a0000000-0000-7000-8000-000000000047',
        baseVersion: ServerVersion(2),
        patch: EntityPatch.fromWire(const {
          'status': 'active',
          'completedAt': null,
        }),
        create: false,
      ),
    );

    expect(backend.record(entityId)?['status'], 'active');
    expect(backend.record(entityId)?['completedAt'], isNull);
  });

  test('in-memory change history retains one latest entity snapshot', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000019';
    final descriptor = TestDescriptor<_Item>();
    final backend = InMemorySyncBackend(descriptor: descriptor);
    addTearDown(backend.disposeRemoteChangeSignals);
    final identity = descriptor.parseIdentity(entityId);
    final create = PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 1,
      operation: CreatePushOperation(
        operationId: SyncOperationId('a0000000-0000-7000-8000-000000000020'),
        identity: identity,
        baseServerVersion: ServerVersion.zero,
        localRevision: 1,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire(const {'id': entityId, 'isActive': true}),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12),
      nextAttemptAt: null,
    );
    final patch = PushSyncWorkItem(
      target: SyncTargetId.testOnly,
      id: 2,
      operation: PatchPushOperation(
        operationId: SyncOperationId('a0000000-0000-7000-8000-000000000021'),
        identity: identity,
        baseServerVersion: ServerVersion(1),
        localRevision: 2,
        protocolVersion: descriptor.protocolVersion,
        patch: EntityPatch.fromWire(const {'isActive': false}),
      ),
      pushKind: PushSyncWorkKind.statePatch,
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 12, 0, 1),
      nextAttemptAt: null,
    );

    final created = await backend.push(create);
    final updated = await backend.push(patch);
    final initial = await backend.pull(afterSequence: ServerSequence.zero);
    final incremental = await backend.pull(
      afterSequence: created.canonicalChange.serverSequence,
    );

    expect(initial.changes, [same(updated.canonicalChange)]);
    expect(incremental.changes, [same(updated.canonicalChange)]);
    expect(initial.nextSequence, updated.canonicalChange.serverSequence);
    expect(
      (await backend.push(create)).canonicalChange,
      same(created.canonicalChange),
      reason: 'Compaction must not remove idempotency receipts.',
    );
  });

  test(
    'Given local persistence fails, When rollback completes, Then structured diagnostics contain identity but no patch payload',
    () async {
      final descriptor = TestDescriptor<_Item>();
      final diagnostics = _CollectingDiagnostics();
      final occurredAt = DateTime.utc(2026, 7, 11, 10);
      final mutation = LocalEntityMutation(
        operationId: SyncOperationId('a0000000-0000-7000-8000-000000000004'),
        identity: descriptor.parseIdentity(
          'a0000000-0000-7000-8000-000000000005',
        ),
        baseServerVersion: ServerVersion(2),
        localRevision: 3,
        patch: EntityPatch.fromWire(const {'private': 'not diagnosed'}),
        createdAt: occurredAt,
      );
      var rolledBack = false;
      final coordinator = MutationCoordinator.batches(
        persist: (_) async => throw StateError('disk unavailable'),
        clock: _FixedClock(occurredAt),
        diagnostics: diagnostics,
      );

      final commit = coordinator.schedule(
        mutation,
        rollbackIfCurrent: () => rolledBack = true,
      );

      final result = await commit;
      expect(result.succeeded, isFalse);
      expect(result.error, isA<StateError>());
      expect(() => result.throwIfFailed(), throwsStateError);
      await expectLater(coordinator.flush(), throwsStateError);
      final diagnostic =
          diagnostics.events.single as LocalPersistenceFailureDiagnostic;
      expect(rolledBack, isTrue);
      expect(diagnostic.occurredAt, occurredAt);
      expect(diagnostic.operationId, mutation.operationId);
      expect(diagnostic.identity, mutation.identity);
      expect(diagnostic.localRevision, 3);
      expect(diagnostic.error, isA<StateError>());
      expect(diagnostic.toString(), isNot(contains('not diagnosed')));
    },
  );

  test(
    'local mutation completion reports failure only when its action is observed',
    () async {
      final failure = LocalMutationCommitResult.failure(
        StateError('disk unavailable'),
        StackTrace.current,
      );
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        final ignored = LocalMutationCompletion(Future.value(failure));
        expect(ignored, isA<Future<void>>());
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => unhandled.add(error));

      expect(unhandled, isEmpty);
      await expectLater(
        LocalMutationCompletion(Future.value(failure)),
        throwsStateError,
      );
      await expectLater(
        LocalMutationCompletion(
          Future.value(const LocalMutationCommitResult.success()),
        ),
        completes,
      );
    },
  );

  test(
    'read-only observable list reacts without exposing its mutable source',
    () {
      final source = ObservableList<int>();
      final view = ReadOnlyObservableList(source);
      final lengths = <int>[];
      final dispose = autorun((_) => lengths.add(view.length));
      addTearDown(dispose.call);

      runInAction(() => source.addAll([1, 2]));

      expect(view.toList(), [1, 2]);
      expect(view[1], 2);
      expect(lengths, [0, 2]);
    },
  );

  test(
    'typed query reacts only to observable membership and ordering inputs',
    () {
      final source = ObservableList<_Item>();
      final readOnlySource = ReadOnlyObservableList(source);
      final name = ComparableEntityField<_Item, String>(
        name: 'name',
        read: (item) => item.name,
        encode: (value) => value,
      );
      final active = EqualityEntityField<_Item, bool>(
        name: 'isActive',
        read: (item) => item.isActive,
        encode: (value) => value,
      );
      final query = LocalEntityQuery<_Item>(
        source: readOnlySource,
        where: active.equals(true),
        orderBy: name.ascending(),
      );
      final snapshots = <List<String>>[];
      final dispose = autorun(
        (_) => snapshots.add(query.items.map((item) => item.name).toList()),
      );
      addTearDown(dispose.call);

      final later = _Item('Later');
      final first = _Item('First');
      runInAction(() => source.addAll([later, first]));
      runInAction(() => later.isActive = false);

      expect(snapshots, [
        <String>[],
        ['First', 'Later'],
        ['First'],
      ]);
    },
  );

  test('typed membership queries normalize values and match empty input', () {
    final source = ObservableList<_Item>.of([
      _Item('A'),
      _Item('B'),
      _Item('C'),
    ]);
    final name = ComparableEntityField<_Item, String>(
      name: 'name',
      read: (item) => item.name,
      encode: (value) => value,
    );
    final query = LocalEntityQuery<_Item>(
      source: ReadOnlyObservableList(source),
      where: name.isIn(['C', 'A', 'A']),
      orderBy: name.ascending(),
    );
    final equivalent = name.isIn(['A', 'C']);
    final scheduledFor = ComparableEntityField<_Item, LocalDate>(
      name: 'scheduledFor',
      read: (_) => LocalDate.parse('2026-07-14'),
      encode: (value) => value.value,
    );
    final firstDate = LocalDate.parse('2026-07-14');
    final secondDate = LocalDate.parse('2026-07-15');

    expect(query.items.map((item) => item.name), ['A', 'C']);
    expect(name.isIn(['C', 'A']), equivalent);
    expect(name.isIn(const []), name.isIn(const []));
    expect(
      LocalEntityQuery<_Item>(
        source: ReadOnlyObservableList(source),
        where: name.isIn(const []),
      ).items,
      isEmpty,
    );
    expect(
      scheduledFor.isIn([secondDate, firstDate, firstDate]),
      scheduledFor.isIn([firstDate, secondDate]),
    );
  });

  test('LocalDate is canonical, comparable, and rejects invalid days', () {
    final leapDay = LocalDate.parse('2028-02-29');

    expect(leapDay.value, '2028-02-29');
    expect(leapDay.toDateTime(), DateTime(2028, 2, 29));
    expect(
      LocalDate.fromDateTime(DateTime(2028, 3, 1)).compareTo(leapDay),
      greaterThan(0),
    );
    expect(() => LocalDate.parse('2027-02-29'), throwsFormatException);
    expect(() => LocalDate.parse('2028-2-09'), throwsFormatException);
  });

  test('typed query exposes observable state as an owned stream', () async {
    final source = ObservableList<_Item>();
    final active = PersistedEqualityEntityField<_Item, bool>(
      persistence: const EntityFieldDescriptor(
        name: 'isActive',
        columnName: 'is_active',
        kind: EntityFieldKind.boolean,
        nullable: false,
        mutable: true,
        conflictPolicy: FieldConflictPolicy.localWins,
      ),
      read: (item) => item.isActive,
      encode: (value) => value,
      decode: (source) => source! as bool,
    );
    final query = LocalEntityQuery<_Item>(
      source: ReadOnlyObservableList(source),
    );
    final states = <EntityQueryState<_Item>>[];
    final subscription = query
        .watchStates(observeFields: [active])
        .listen(states.add);
    await Future<void>.delayed(Duration.zero);

    final item = _Item('One');
    runInAction(() => source.add(item));
    await Future<void>.delayed(Duration.zero);
    runInAction(() => item.isActive = false);
    await Future<void>.delayed(Duration.zero);
    query.dispose();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(states, [
      isA<EntityQueryEmpty<_Item>>(),
      isA<EntityQueryData<_Item>>(),
      isA<EntityQueryData<_Item>>(),
      isA<EntityQueryDisposed<_Item>>(),
    ]);
  });

  test('equivalent predicates and orders have stable value identity', () {
    final name = ComparableEntityField<_Item, String>(
      name: 'name',
      read: (item) => item.name,
      encode: (value) => value,
    );
    final active = EqualityEntityField<_Item, bool>(
      name: 'isActive',
      read: (item) => item.isActive,
      encode: (value) => value,
    );
    final first = active.equals(true) & name.equals('First');
    final sameReordered = name.equals('First') & active.equals(true);

    expect(first, sameReordered);
    expect(first.hashCode, sameReordered.hashCode);
    expect(active.equals(true) & active.equals(true), active.equals(true));
    expect(
      EntityPredicate<_Item>.all() & active.equals(true),
      active.equals(true),
    );
    expect(
      EntityPredicate<_Item>.all() | active.equals(true),
      EntityPredicate<_Item>.all(),
    );
    expect(name.ascending(), name.ascending());
    expect(name.ascending(), isNot(name.descending()));
  });

  test('comparable fields expose structurally typed range predicates', () {
    final name = ComparableEntityField<_Item, String>(
      name: 'name',
      read: (item) => item.name,
      encode: (value) => value,
    );
    final item = _Item('Middle');

    expect(name.isAtLeast('Middle').test(item), isTrue);
    expect(name.isGreaterThan('Middle').test(item), isFalse);
    expect(name.isLessThan('Z').test(item), isTrue);
    expect(name.isAtMost('A').test(item), isFalse);
    expect(name.isBetween('A', 'Z').test(item), isTrue);
    expect(name.isBetween('A', 'Z'), name.isAtLeast('A') & name.isAtMost('Z'));
  });

  test(
    'nullable comparable fields make null placement explicit and deterministic',
    () {
      final source = ObservableList<_NullableItem>.of([
        _NullableItem(null),
        _NullableItem('B'),
        _NullableItem('A'),
      ]);
      final value = NullableComparableEntityField<_NullableItem, String>(
        name: 'value',
        read: (item) => item.value,
        encode: (value) => value,
      );
      final query = LocalEntityQuery<_NullableItem>(
        source: ReadOnlyObservableList(source),
        where: value.isNotNull,
        orderBy: value.ascending(nulls: NullPlacement.first),
      );

      expect(query.items.map((item) => item.value), ['A', 'B']);

      final descending = LocalEntityQuery<_NullableItem>(
        source: ReadOnlyObservableList(source),
        orderBy: value.descending(),
      );
      expect(descending.items.map((item) => item.value), ['B', 'A', null]);
    },
  );

  test(
    'query pages deterministically and exposes exhaustive observable states',
    () async {
      final source = ObservableList<_Item>.of([
        _Item('C'),
        _Item('A'),
        _Item('B'),
      ]);
      final name = ComparableEntityField<_Item, String>(
        name: 'name',
        read: (item) => item.name,
        encode: (value) => value,
      );
      final query = LocalEntityQuery<_Item>(
        source: ReadOnlyObservableList(source),
        orderBy: name.ascending(),
        pageSize: 2,
      );

      expect(query.state.value, isA<EntityQueryData<_Item>>());
      expect(query.items.map((item) => item.name), ['A', 'B']);
      expect(query.hasMore, isTrue);

      await query.loadNextPage();

      expect(query.items.map((item) => item.name), ['A', 'B', 'C']);
      expect(query.hasMore, isFalse);

      query.dispose();

      expect(query.state.value, isA<EntityQueryDisposed<_Item>>());
      expect(query.items, isEmpty);
    },
  );

  test('query can resolve only its first page', () async {
    final source = ObservableList<_Item>.of([
      _Item('C'),
      _Item('A'),
      _Item('B'),
    ]);
    final name = ComparableEntityField<_Item, String>(
      name: 'name',
      read: (item) => item.name,
      encode: (value) => value,
    );
    final query = LocalEntityQuery<_Item>(
      source: ReadOnlyObservableList(source),
      orderBy: name.ascending(),
      pageSize: 2,
    );
    addTearDown(query.dispose);

    final firstPage = await query.loadFirstPage();

    expect(firstPage.map((item) => item.name), ['A', 'B']);
    expect(query.hasMore, isTrue);
    expect(() => firstPage.add(_Item('D')), throwsUnsupportedError);
  });

  test('query specifications reject invalid page sizes', () {
    expect(
      () => EntityQuerySpec<_Item>(pageSize: 0),
      throwsA(isA<RangeError>()),
    );
  });

  test('query cache shares computation while leases dispose independently', () {
    final source = ObservableList<_Item>.of([_Item('One')]);
    final active = EqualityEntityField<_Item, bool>(
      name: 'isActive',
      read: (item) => item.isActive,
      encode: (value) => value,
    );
    final cache = LocalEntityQueryCache<_Item>(
      source: ReadOnlyObservableList(source),
    );
    addTearDown(cache.dispose);
    final first = cache.acquire(EntityQuerySpec(where: active.equals(true)));
    final second = cache.acquire(EntityQuerySpec(where: active.equals(true)));

    first.dispose();

    expect(first.state.value, isA<EntityQueryDisposed<_Item>>());
    expect(second.items, hasLength(1));

    second.dispose();
    final replacement = cache.acquire(
      EntityQuerySpec(where: active.equals(true)),
    );

    expect(replacement.items, hasLength(1));
  });

  test('watched query state owns and releases one cache lease', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    var loadCount = 0;
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        loadCount++;
        return EntityQueryPage(
          items: [_Item('A')],
          hasMore: false,
          nextCursor: null,
        );
      },
    );
    addTearDown(cache.dispose);
    final spec = EntityQuerySpec<_Item>();

    final first = cache.watch(spec).listen((_) {});
    final second = cache.watch(spec).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(loadCount, 1);

    await first.cancel();
    await second.cancel();
    final replacement = cache.watch(spec).listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(loadCount, 2);
    await replacement.cancel();
  });

  test(
    'database query cache exposes loading, paging, and stale refresh states',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      var records = [_Item('A'), _Item('B'), _Item('C')];
      final firstLoad = Completer<void>();
      var loadCount = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          if (loadCount == 1) await firstLoad.future;
          final offset = (after as _TestQueryCursor?)?.offset ?? 0;
          final end = (offset + limit).clamp(0, records.length);
          return EntityQueryPage(
            items: records.sublist(offset.clamp(0, end), end),
            hasMore: end < records.length,
            nextCursor: _TestQueryCursor(end),
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 2));

      expect(query.state.value, isA<EntityQueryInitialLoading<_Item>>());

      firstLoad.complete();
      await Future<void>.delayed(Duration.zero);

      expect(query.items.map((item) => item.name), ['A', 'B']);
      expect(query.hasMore, isTrue);

      await query.loadNextPage();

      expect(query.items.map((item) => item.name), ['A', 'B', 'C']);
      expect(query.hasMore, isFalse);

      records = [_Item('Updated')];
      invalidations.add(const EntityProjectionChange<_Item>.unknown());
      expect(query.state.value, isA<EntityQueryStaleData<_Item>>());
      await Future<void>.delayed(Duration.zero);

      expect(query.items.single.name, 'Updated');
      expect(query.state.value, isA<EntityQueryData<_Item>>());
    },
  );

  test(
    'loadFirstPage waits for database initialization without exhausting pages',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final firstLoad = Completer<void>();
      var loadCount = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          await firstLoad.future;
          return EntityQueryPage(
            items: [_Item('A'), _Item('B')],
            hasMore: true,
            nextCursor: const _TestQueryCursor(2),
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 2));
      addTearDown(query.dispose);

      final result = query.loadFirstPage();
      expect(loadCount, 1);
      firstLoad.complete();

      expect(await result, hasLength(2));
      expect(query.hasMore, isTrue);
      expect(loadCount, 1);
    },
  );

  test(
    'loadAll waits for initialization and exhausts database pages',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final records = [_Item('A'), _Item('B'), _Item('C')];
      final firstLoad = Completer<void>();
      var loadCount = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          if (loadCount == 1) await firstLoad.future;
          final offset = (after as _TestQueryCursor?)?.offset ?? 0;
          final end = (offset + limit).clamp(0, records.length);
          return EntityQueryPage(
            items: records.sublist(offset, end),
            hasMore: end < records.length,
            nextCursor: _TestQueryCursor(end),
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 2));
      addTearDown(query.dispose);

      final result = query.loadAll();
      firstLoad.complete();

      final loaded = await result;
      expect(loaded, records);
      expect(loadCount, 2);
      expect(() => loaded.add(_Item('D')), throwsUnsupportedError);
    },
  );

  test(
    'generated bulk actions transact and release one canonical page at a time',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final records = [
        _Item('A'),
        _Item('B'),
        _Item('C'),
        _Item('D'),
        _Item('E'),
      ];
      var releases = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (_, {required after, required limit}) async {
          final offset = (after as _TestQueryCursor?)?.offset ?? 0;
          final end = (offset + limit).clamp(0, records.length);
          return EntityQueryPage(
            items: records.sublist(offset.clamp(0, end), end),
            hasMore: end < records.length,
            nextCursor: _TestQueryCursor(end),
            release: () => releases++,
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 2));
      await Future<void>.delayed(Duration.zero);
      var transactions = 0;

      final result = await query.runGeneratedBulkAction(
        (item) async {
          if (item.name == 'C') return false;
          item.isActive = false;
          return true;
        },
        runTransaction: (body) async {
          transactions++;
          await body();
        },
      );

      expect(result.matched, 5);
      expect(result.changed, 4);
      expect(result.skipped, 1);
      expect(transactions, 3);
      expect(releases, 4); // Three detached pages plus the cached first page.
      expect(query.state.value, isA<EntityQueryDisposed<_Item>>());
    },
  );

  test(
    'generated processes stream retained pages without a transaction',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final records = [
        _Item('A'),
        _Item('B'),
        _Item('C'),
        _Item('D'),
        _Item('E'),
      ];
      var releases = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (_, {required after, required limit}) async {
          final offset = (after as _TestQueryCursor?)?.offset ?? 0;
          final end = (offset + limit).clamp(0, records.length);
          return EntityQueryPage(
            items: records.sublist(offset.clamp(0, end), end),
            hasMore: end < records.length,
            nextCursor: _TestQueryCursor(end),
            release: () => releases++,
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 2));
      await Future<void>.delayed(Duration.zero);
      final processed = <String>[];

      await query.runGeneratedProcess((item) async {
        processed.add(item.name);
      });

      expect(processed, ['A', 'B', 'C', 'D', 'E']);
      expect(releases, 4); // Three detached pages plus the cached first page.
      expect(query.state.value, isA<EntityQueryDisposed<_Item>>());
    },
  );

  test(
    'lease callbacks release identities and queries on every exit',
    () async {
      var identityReleases = 0;
      final identity = EntityLookupLease(
        _Item('retained'),
        () => identityReleases++,
      );

      await expectLater(
        identity.use<void>((_) => throw StateError('identity failure')),
        throwsStateError,
      );
      expect(identityReleases, 1);
      await expectLater(identity.use((item) => item), throwsStateError);

      var futureReleases = 0;
      final futureValue = await Future.value(
        EntityLookupLease(_Item('future'), () => futureReleases++),
      ).use((item) => item.name, ifAbsent: () => 'missing');
      expect(futureValue, 'future');
      expect(futureReleases, 1);
      final absent = await Future<EntityLookupLease<_Item>?>.value().use(
        (item) => item.name,
        ifAbsent: () => 'missing',
      );
      expect(absent, 'missing');

      final source = ObservableList.of([_Item('A')]);
      final query = LocalEntityQuery<_Item>(
        source: ReadOnlyObservableList(source),
      );
      await expectLater(
        query.useAll<void>((_) => throw StateError('query failure')),
        throwsStateError,
      );
      expect(query.state.value, isA<EntityQueryDisposed<_Item>>());
      await expectLater(query.useAll((items) => items), throwsStateError);
    },
  );

  test(
    'first-page lease callbacks expose one page and always dispose',
    () async {
      final source = ReadOnlyObservableList(
        ObservableList.of([_Item('A'), _Item('B'), _Item('C')]),
      );
      final successful = LocalEntityQuery<_Item>(source: source, pageSize: 2);

      final names = await successful.useFirstPage(
        (items) => items.map((item) => item.name).toList(growable: false),
      );

      expect(names, ['A', 'B']);
      expect(successful.state.value, isA<EntityQueryDisposed<_Item>>());
      await expectLater(
        successful.useFirstPage((items) => items),
        throwsStateError,
      );

      final failing = LocalEntityQuery<_Item>(source: source, pageSize: 2);
      await expectLater(
        failing.useFirstPage<void>((_) => throw StateError('action failure')),
        throwsStateError,
      );
      expect(failing.state.value, isA<EntityQueryDisposed<_Item>>());
    },
  );

  test(
    'exact lookups enforce singularity and release imperative leases',
    () async {
      final one = EntityLookup<_Item>(
        LocalEntityQuery<_Item>(
          source: ReadOnlyObservableList(ObservableList.of([_Item('A')])),
          pageSize: 1,
        ),
      );
      final name = await one.use((item) => item?.name);
      expect(name, 'A');
      expect(one.state.value, isA<EntityQueryDisposed<_Item>>());

      final missing = EntityLookup<_Item>(
        LocalEntityQuery<_Item>(
          source: ReadOnlyObservableList(ObservableList<_Item>()),
          pageSize: 1,
        ),
      );
      expect(await missing.use((item) => item?.name), isNull);

      final duplicate = EntityLookup<_Item>(
        LocalEntityQuery<_Item>(
          source: ReadOnlyObservableList(
            ObservableList.of([_Item('A'), _Item('B')]),
          ),
          pageSize: 1,
        ),
      );
      addTearDown(duplicate.dispose);
      await expectLater(duplicate.load(), throwsStateError);

      expect(
        () => EntityLookup<_Item>(
          LocalEntityQuery<_Item>(
            source: ReadOnlyObservableList(ObservableList.of([_Item('A')])),
            pageSize: 2,
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'existence selections permit many rows and release their lease',
    () async {
      final existence = EntityExistence<_Item>(
        LocalEntityQuery<_Item>(
          source: ReadOnlyObservableList(
            ObservableList.of([_Item('A'), _Item('B')]),
          ),
          pageSize: 1,
        ),
      );

      expect(await existence.use((value) => value), isTrue);
      expect(existence.state.value, isA<EntityQueryDisposed<_Item>>());

      expect(
        () => EntityExistence<_Item>(
          LocalEntityQuery<_Item>(
            source: ReadOnlyObservableList(ObservableList<_Item>()),
            pageSize: 2,
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('query record leases preserve types and release every query', () async {
    LocalEntityQuery<_Item> query(String name) => LocalEntityQuery(
      source: ReadOnlyObservableList(ObservableList.of([_Item(name)])),
    );

    final first = query('A');
    final second = query('B');
    final third = query('C');
    final fourth = query('D');
    final fifthQuery = query('E');
    final fifth = EntityList(fifthQuery);
    final sixth = query('F');

    final names = await (first, second, third, fourth, fifth, sixth).useAll(
      (a, b, c, d, e, f) => [
        a.single.name,
        b.single.name,
        c.single.name,
        d.single.name,
        e.single.name,
        f.single.name,
      ],
    );

    expect(names, ['A', 'B', 'C', 'D', 'E', 'F']);
    for (final query in [first, second, third, fourth, fifthQuery, sixth]) {
      expect(query.state.value, isA<EntityQueryDisposed<_Item>>());
    }
  });

  test('typed future records preserve heterogeneous values', () async {
    final values = await (
      Future<int>.value(1),
      Future<String>.value('two'),
      Future<bool>.value(true),
      Future<double>.value(4.0),
      Future<List<int>>.value(const [5]),
      Future<Set<String>>.value(const {'six'}),
      Future<Duration>.value(const Duration(seconds: 7)),
    ).waitAll;

    expect(values.$1, 1);
    expect(values.$2, 'two');
    expect(values.$3, isTrue);
    expect(values.$4, 4.0);
    expect(values.$5, const [5]);
    expect(values.$6, const {'six'});
    expect(values.$7, const Duration(seconds: 7));

    final fourteen = await (
      Future<int>.value(1),
      Future<int>.value(2),
      Future<int>.value(3),
      Future<int>.value(4),
      Future<int>.value(5),
      Future<int>.value(6),
      Future<int>.value(7),
      Future<int>.value(8),
      Future<int>.value(9),
      Future<int>.value(10),
      Future<int>.value(11),
      Future<int>.value(12),
      Future<int>.value(13),
      Future<String>.value('fourteen'),
    ).waitAll;
    expect(fourteen.$13, 13);
    expect(fourteen.$14, 'fourteen');
  });

  test('query record leases release every query when one load fails', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (_, {required after, required limit}) async {
        throw StateError('load failure');
      },
    );
    addTearDown(cache.dispose);
    final first = cache.acquire(EntityQuerySpec<_Item>());
    final second = LocalEntityQuery<_Item>(
      source: ReadOnlyObservableList(ObservableList.of([_Item('B')])),
    );

    await expectLater(
      (first, second).useAll<void>((_, _) {}),
      throwsStateError,
    );
    expect(first.state.value, isA<EntityQueryDisposed<_Item>>());
    expect(second.state.value, isA<EntityQueryDisposed<_Item>>());
  });

  test('loadAll rejects partial and disposed query snapshots', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    var page = 0;
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        page++;
        if (page == 1) {
          return EntityQueryPage(
            items: [_Item('A')],
            hasMore: true,
            nextCursor: const _TestQueryCursor(1),
          );
        }
        throw StateError('second page failed');
      },
    );
    addTearDown(cache.dispose);
    final query = cache.acquire(EntityQuerySpec(pageSize: 1));

    await expectLater(query.loadAll(), throwsA(isA<StateError>()));
    query.dispose();
    await expectLater(query.loadAll(), throwsA(isA<StateError>()));
  });

  test(
    'loadAll publishes a terminal failure when paging makes no progress',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      var page = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          page++;
          return EntityQueryPage(
            items: page == 1 ? [_Item('A')] : const [],
            hasMore: true,
            nextCursor: _TestQueryCursor(page),
          );
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec(pageSize: 1));
      addTearDown(query.dispose);

      await expectLater(
        query.loadAll(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Entity query paging made no progress.',
          ),
        ),
      );

      expect(
        query.state.value,
        isA<EntityQueryFailure<_Item>>().having(
          (state) => state.hasMore,
          'hasMore',
          isFalse,
        ),
      );
    },
  );

  test('complete query streams suppress partial database pages', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    final records = [_Item('A'), _Item('B'), _Item('C')];
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        final offset = (after as _TestQueryCursor?)?.offset ?? 0;
        final end = (offset + limit).clamp(0, records.length);
        return EntityQueryPage(
          items: records.sublist(offset, end),
          hasMore: end < records.length,
          nextCursor: _TestQueryCursor(end),
        );
      },
    );
    addTearDown(cache.dispose);
    final emittedDataLengths = <int>[];
    final complete = Completer<List<_Item>>();
    final subscription = cache
        .watchComplete(EntityQuerySpec(pageSize: 1))
        .listen((state) {
          if (state case EntityQueryData<_Item>(:final items)) {
            emittedDataLengths.add(items.length);
            if (!complete.isCompleted) complete.complete(items);
          }
        });
    addTearDown(subscription.cancel);

    expect(await complete.future, records);
    expect(emittedDataLengths, [3]);
  });

  test('domain entity lists own exhaustive observable leases', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    final records = [_Item('A'), _Item('B'), _Item('C')];
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        final offset = (after as _TestQueryCursor?)?.offset ?? 0;
        final end = (offset + limit).clamp(0, records.length);
        return EntityQueryPage(
          items: records.sublist(offset, end),
          hasMore: end < records.length,
          nextCursor: _TestQueryCursor(end),
        );
      },
    );
    addTearDown(cache.dispose);
    final list = EntityList<_Item>(
      cache.acquire(EntityQuerySpec<_Item>(pageSize: 1)),
    );
    final complete = Completer<List<_Item>>();
    final emittedDataLengths = <int>[];
    final stream = list.watchCompleteStates();
    final subscription = stream.listen((state) {
      if (state case EntityQueryData<_Item>(:final items)) {
        emittedDataLengths.add(items.length);
        if (!complete.isCompleted) complete.complete(items);
      }
    });

    expect(await complete.future, records);
    expect(emittedDataLengths, [3]);
    expect(() => stream.listen((_) {}), throwsStateError);
    await subscription.cancel();
    expect(list.state.value, isA<EntityQueryDisposed<_Item>>());
  });

  test(
    'complete query streams surface later-page failures without partial data',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      var loadCount = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          if (after == null) {
            return EntityQueryPage(
              items: [_Item('partial')],
              hasMore: true,
              nextCursor: const _TestQueryCursor(1),
            );
          }
          throw StateError('second page failed');
        },
      );
      addTearDown(cache.dispose);
      final emittedData = <List<_Item>>[];
      final failure = Completer<EntityQueryFailure<_Item>>();
      final subscription = cache
          .watchComplete(EntityQuerySpec(pageSize: 1))
          .listen((state) {
            if (state case EntityQueryData<_Item>(:final items)) {
              emittedData.add(items);
            }
            if (state case EntityQueryFailure<_Item>()
                when !failure.isCompleted) {
              failure.complete(state);
            }
          });
      addTearDown(subscription.cancel);

      final failed = await failure.future;
      expect(failed.error, isA<StateError>());
      expect(failed.items, isEmpty);
      expect(failed.hasMore, isFalse);
      expect(emittedData, isEmpty);
      expect(loadCount, 2);
    },
  );

  test(
    'complete query streams surface paging progress violations without partial data',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      var page = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          page++;
          return EntityQueryPage(
            items: page == 1 ? [_Item('partial')] : const [],
            hasMore: true,
            nextCursor: _TestQueryCursor(page),
          );
        },
      );
      addTearDown(cache.dispose);
      final failure = Completer<EntityQueryFailure<_Item>>();
      final subscription = cache
          .watchComplete(EntityQuerySpec(pageSize: 1))
          .listen((state) {
            if (state case EntityQueryFailure<_Item>()
                when !failure.isCompleted) {
              failure.complete(state);
            }
          });
      addTearDown(subscription.cancel);

      final failed = await failure.future;
      expect(failed.error, isA<StateError>());
      expect(failed.items, isEmpty);
      expect(failed.hasMore, isFalse);
      expect(page, 2);
    },
  );

  test(
    'complete query streams retain the last complete snapshot on refresh failure',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final original = [_Item('A'), _Item('B')];
      var refresh = false;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          final offset = (after as _TestQueryCursor?)?.offset ?? 0;
          if (refresh && offset > 0) {
            throw StateError('refresh second page failed');
          }
          final records = refresh
              ? [_Item('partial replacement'), _Item('C'), _Item('D')]
              : original;
          final end = (offset + limit).clamp(0, records.length);
          return EntityQueryPage(
            items: records.sublist(offset, end),
            hasMore: end < records.length,
            nextCursor: _TestQueryCursor(end),
          );
        },
      );
      addTearDown(cache.dispose);
      final initial = Completer<List<_Item>>();
      final failure = Completer<EntityQueryFailure<_Item>>();
      final emittedData = <List<_Item>>[];
      final subscription = cache
          .watchComplete(EntityQuerySpec(pageSize: 1))
          .listen((state) {
            if (state case EntityQueryData<_Item>(:final items)) {
              emittedData.add(items);
              if (!initial.isCompleted) initial.complete(items);
            }
            if (state case EntityQueryFailure<_Item>()
                when !failure.isCompleted) {
              failure.complete(state);
            }
          });
      addTearDown(subscription.cancel);

      expect(await initial.future, original);
      refresh = true;
      invalidations.add(const EntityProjectionChange<_Item>.unknown());

      final failed = await failure.future;
      expect(failed.error, isA<StateError>());
      expect(failed.items, original);
      expect(failed.hasMore, isFalse);
      expect(emittedData, [original]);
    },
  );

  test('database query cache retains typed failure state', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast();
    addTearDown(invalidations.close);
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        throw StateError('database unavailable');
      },
    );
    addTearDown(cache.dispose);
    final query = cache.acquire(EntityQuerySpec());

    await Future<void>.delayed(Duration.zero);

    expect(
      query.state.value,
      isA<EntityQueryFailure<_Item>>().having(
        (state) => state.error,
        'error',
        isA<StateError>(),
      ),
    );
  });

  test(
    'Given a Drift-backed query, When a page is projected, Then SQL results are not filtered or sorted again in memory',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final item = _Item('Database ordered');
      var predicateReads = 0;
      var orderingReads = 0;
      final active = EqualityEntityField<_Item, bool>(
        name: 'isActive',
        read: (entity) {
          predicateReads++;
          return entity.isActive;
        },
        encode: (value) => value,
      );
      final name = ComparableEntityField<_Item, String>(
        name: 'name',
        read: (entity) {
          orderingReads++;
          return entity.name;
        },
        encode: (value) => value,
      );
      var loads = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          loads++;
          return EntityQueryPage(items: [item], hasMore: false);
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(
        EntityQuerySpec(where: active.equals(true), orderBy: name.ascending()),
      );

      await Future<void>.delayed(Duration.zero);

      expect(query.items, [item]);
      expect(predicateReads, 0);
      expect(orderingReads, 0);

      invalidations.add(const EntityProjectionChange<_Item>.unknown());
      await Future<void>.delayed(Duration.zero);

      expect(loads, 2);
      expect(predicateReads, 0);
      expect(orderingReads, 0);
    },
  );

  test(
    'Given invalidation bursts during a load, When the load settles, Then one latest reload runs without overlap',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final firstLoad = Completer<void>();
      var activeLoads = 0;
      var maximumActiveLoads = 0;
      var loadCount = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          final load = ++loadCount;
          activeLoads++;
          maximumActiveLoads = math.max(maximumActiveLoads, activeLoads);
          if (load == 1) await firstLoad.future;
          activeLoads--;
          return EntityQueryPage(items: [_Item('load-$load')], hasMore: false);
        },
      );
      addTearDown(cache.dispose);
      final query = cache.acquire(EntityQuerySpec<_Item>());

      invalidations
        ..add(const EntityProjectionChange<_Item>.unknown())
        ..add(const EntityProjectionChange<_Item>.unknown())
        ..add(const EntityProjectionChange<_Item>.unknown());
      await Future<void>.delayed(Duration.zero);

      expect(loadCount, 1);

      firstLoad.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(loadCount, 2);
      expect(maximumActiveLoads, 1);
      expect(query.items.single.name, 'load-2');
    },
  );

  test('Given retained database pages, When the final query lease is disposed, '
      'Then every page is released exactly once', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    var retainedPages = 0;
    var releasedPages = 0;
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        retainedPages++;
        return EntityQueryPage(
          items: [_Item('item-$retainedPages')],
          hasMore: false,
          release: () => releasedPages++,
        );
      },
    );
    addTearDown(cache.dispose);
    final first = cache.acquire(EntityQuerySpec());
    final second = cache.acquire(EntityQuerySpec());
    await Future<void>.delayed(Duration.zero);

    expect(retainedPages, 1);

    invalidations.add(const EntityProjectionChange<_Item>.unknown());
    await Future<void>.delayed(Duration.zero);

    expect(retainedPages, 2);
    expect(releasedPages, 1);

    first.dispose();
    expect(releasedPages, 1);

    second.dispose();
    expect(releasedPages, 2);
  });

  test('Given an obsolete asynchronous page, When a newer refresh wins, '
      'Then the stale page releases its retention', () async {
    final invalidations =
        StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    final firstLoad = Completer<void>();
    var loadCount = 0;
    var releasedPages = 0;
    final cache = LocalEntityQueryCache<_Item>.database(
      invalidations: invalidations.stream,
      loader: (spec, {required after, required limit}) async {
        final load = ++loadCount;
        if (load == 1) await firstLoad.future;
        return EntityQueryPage(
          items: [_Item('item-$load')],
          hasMore: false,
          release: () => releasedPages++,
        );
      },
    );
    addTearDown(cache.dispose);
    final query = cache.acquire(EntityQuerySpec());

    invalidations.add(const EntityProjectionChange<_Item>.unknown());
    await Future<void>.delayed(Duration.zero);
    firstLoad.complete();
    await Future<void>.delayed(Duration.zero);

    expect(query.items.single.name, 'item-2');
    expect(releasedPages, 1);

    query.dispose();
    expect(releasedPages, 2);
  });

  test(
    'database query cache reloads only queries affected by projection fields',
    () async {
      final invalidations =
          StreamController<EntityProjectionChange<_Item>>.broadcast(sync: true);
      addTearDown(invalidations.close);
      final active = EqualityEntityField<_Item, bool>(
        name: 'isActive',
        read: (item) => item.isActive,
        encode: (value) => value,
      );
      final name = ComparableEntityField<_Item, String>(
        name: 'name',
        read: (item) => item.name,
        encode: (value) => value,
      );
      final activeSpec = EntityQuerySpec<_Item>(where: active.equals(true));
      final orderedSpec = EntityQuerySpec<_Item>(orderBy: name.ascending());
      var activeLoads = 0;
      var orderedLoads = 0;
      final cache = LocalEntityQueryCache<_Item>.database(
        invalidations: invalidations.stream,
        loader: (spec, {required after, required limit}) async {
          if (spec == activeSpec) {
            activeLoads++;
          } else if (spec == orderedSpec) {
            orderedLoads++;
          } else {
            fail('Unexpected query specification.');
          }
          return EntityQueryPage(items: [_Item('item')], hasMore: false);
        },
      );
      addTearDown(cache.dispose);
      cache
        ..acquire(activeSpec)
        ..acquire(orderedSpec);
      await Future<void>.delayed(Duration.zero);

      expect((activeLoads, orderedLoads), (1, 1));

      invalidations.add(EntityProjectionChange<_Item>.fields([active]));
      await Future<void>.delayed(Duration.zero);
      expect((activeLoads, orderedLoads), (2, 1));

      final unrelated = EqualityEntityField<_Item, bool>(
        name: 'unrelated',
        read: (_) => false,
        encode: (value) => value,
      );
      invalidations.add(EntityProjectionChange<_Item>.fields([unrelated]));
      await Future<void>.delayed(Duration.zero);
      expect((activeLoads, orderedLoads), (2, 1));

      invalidations.add(EntityProjectionChange<_Item>.fields([name]));
      await Future<void>.delayed(Duration.zero);
      expect((activeLoads, orderedLoads), (2, 2));

      invalidations.add(const EntityProjectionChange<_Item>.membership());
      await Future<void>.delayed(Duration.zero);
      expect((activeLoads, orderedLoads), (3, 3));

      invalidations.add(const EntityProjectionChange<_Item>.unknown());
      await Future<void>.delayed(Duration.zero);
      expect((activeLoads, orderedLoads), (4, 4));
    },
  );

  test(
    'sync queue delegates commands while exposing one observable list',
    () async {
      final host = _SyncQueueHost();
      final queue = SyncQueue(host);

      await queue.synchronize();

      expect(queue.items, same(host.syncWork));
      expect(queue.state, same(host.syncState));
      expect(host.pullRequests, 1);
      expect(host.retries, 1);
    },
  );
}

final class _Item {
  _Item(String name) : _name = Observable(name), _isActive = Observable(true);

  final Observable<String> _name;
  final Observable<bool> _isActive;

  String get name => _name.value;

  bool get isActive => _isActive.value;

  set isActive(bool value) => _isActive.value = value;
}

final class _MismatchedPullBackend implements PullSyncAdapter {
  @override
  EntityGraphDefinition get definition =>
      EntityGraphDefinition.single(const TestDescriptor<_Item>());

  @override
  Future<PullResult> pull({required ServerSequence afterSequence}) async =>
      PullResult(
        requestedAfter: ServerSequence(4),
        changes: const [],
        nextSequence: ServerSequence(4),
        hasMore: false,
      );
}

final class _PullPersistence implements SyncPersistence {
  _PullPersistence({this.target = SyncTargetId.testOnly, this.retryAt});

  final SyncTargetId target;
  final DateTime? retryAt;
  bool _claimed = false;
  bool completed = false;
  Object? failure;

  @override
  Future<SyncWorkItem?> claimNext(SyncTargetId target) async {
    expect(target, this.target);
    if (_claimed) return null;
    _claimed = true;
    return PullSyncWorkItem(
      target: this.target,
      id: 1,
      operationId: SyncOperationId('a0000000-0000-7000-8000-000000000009'),
      status: SyncWorkStatus.pending,
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 11),
      nextAttemptAt: null,
    );
  }

  @override
  Future<void> completePull(PullSyncWorkItem item, PullResult result) async {
    completed = true;
  }

  @override
  Future<void> completePush(PushSyncWorkItem item, PushResult result) =>
      throw UnsupportedError('The worker test only claims pull work.');

  @override
  Future<SyncFailureOutcome> handleFailure(
    SyncWorkItem item,
    Object error,
    StackTrace stackTrace,
  ) async {
    failure = error;
    return SyncFailureOutcome(continueDraining: false, retryAt: retryAt);
  }

  @override
  Future<ServerSequence> readPullCursor(SyncTargetId target) async {
    expect(target, this.target);
    return ServerSequence(5);
  }
}

final class _TestQueryCursor implements EntityQueryCursor {
  const _TestQueryCursor(this.offset);

  final int offset;
}

final class _OrderedLink {}

final class _OrderedLinkDescriptor
    implements
        EntityDescriptorBase,
        EntityIdentityDescriptor<_OrderedLink>,
        OrderedDescriptor {
  const _OrderedLinkDescriptor();

  @override
  String get entityType => 'OrderedLink';

  @override
  Cardinality get cardinality => Cardinality.bounded;

  @override
  String get tableName => 'ordered_links';

  @override
  String? get collaborationTableName => null;

  @override
  int get protocolVersion => 1;

  static const _sourceIdField = EntityFieldDescriptor(
    name: 'sourceId',
    columnName: 'source_id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
  );

  @override
  List<EntityFieldDescriptor> get fields => const [
    EntityFieldDescriptor(
      name: 'id',
      columnName: 'id',
      kind: EntityFieldKind.uuid,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    ),
    EntityFieldDescriptor(
      name: 'ownerId',
      columnName: 'owner_id',
      kind: EntityFieldKind.uuid,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    ),
    _sourceIdField,
    EntityFieldDescriptor(
      name: 'orderRank',
      columnName: 'order_rank',
      kind: EntityFieldKind.text,
      nullable: false,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    ),
    EntityFieldDescriptor(
      name: 'deletedAt',
      columnName: 'deleted_at',
      kind: EntityFieldKind.timestamp,
      nullable: true,
      mutable: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    ),
    EntityFieldDescriptor(
      name: 'active',
      columnName: 'active',
      kind: EntityFieldKind.boolean,
      nullable: false,
      mutable: true,
      hasProtocolDefault: true,
      protocolDefault: true,
      conflictPolicy: FieldConflictPolicy.localWins,
    ),
    EntityFieldDescriptor(
      name: 'serverVersion',
      columnName: 'server_version',
      kind: EntityFieldKind.integer,
      nullable: false,
      mutable: false,
      inCreatePayload: false,
      conflictPolicy: FieldConflictPolicy.serverWins,
    ),
  ];

  @override
  List<EntityFieldDescriptor> get orderScopeFields => const [_sourceIdField];

  @override
  List<EntityFieldValueCondition> get orderMembershipConditions => [
    EntityFieldValueCondition(
      field: fields.singleWhere(
        (field) => field.name == EntityConventions.deletedAtFieldName,
      ),
      value: null,
    ),
    EntityFieldValueCondition(
      field: fields.singleWhere((field) => field.name == 'active'),
      value: true,
    ),
  ];

  @override
  bool isOrderMember(JsonMap fields) =>
      orderMembershipConditions.every((condition) => condition.matches(fields));

  @override
  String orderScopeKey(JsonMap fields) => fields['sourceId']! as String;

  @override
  EntityIdentity<_OrderedLink> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId<_OrderedLink>(source));

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => switch (name) {
    'moveInOrder' => MoveOrderedCommand<_OrderedLink>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    'reorder' => ReorderOrderedCommand<_OrderedLink>.fromWire(
      payload,
      parseId: parseLocalId,
    ),
    'transferInOrder' => TransferOrderedCommand<_OrderedLink>.fromWire(
      payload,
      entityType: 'OrderedLink',
      targetScopeFields: const [_sourceIdField],
    ),
    _ => throw const RejectedSyncException.validation(
      code: 'unsupported_command',
      message: 'Unsupported ordered-link command.',
    ),
  };

  @override
  GeneratedEntityRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) => throw UnsupportedError('Not needed by this transport test.');
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

final class _CollectingDiagnostics implements LocalEntityDiagnostics {
  final List<LocalEntityDiagnostic> events = [];

  @override
  void record(LocalEntityDiagnostic diagnostic) => events.add(diagnostic);
}

final class _NullableItem {
  const _NullableItem(this.value);

  final String? value;
}

final class _TextItem {
  const _TextItem({required this.title, required this.summary});

  final String title;
  final String? summary;
}

final class _ScalarValue implements PersistedScalarValue<int> {
  const _ScalarValue(this.value);

  factory _ScalarValue.fromScalar(int value) => _ScalarValue(value);

  final int value;

  @override
  int toScalar() => value;
}

final class _SyncQueueHost implements SyncQueueHost {
  final ObservableList<SyncWorkItem> _syncWork = ObservableList();

  @override
  late final ReadOnlyObservableList<SyncWorkItem> syncWork =
      ReadOnlyObservableList(_syncWork);

  @override
  final Observable<SyncState> syncState = Observable(const SyncState.idle());

  int pullRequests = 0;
  int retries = 0;

  @override
  Future<void> refreshSyncWork() async {}

  @override
  Future<void> retryNow() async => retries++;

  @override
  Future<void> schedulePull() async => pullRequests++;
}
