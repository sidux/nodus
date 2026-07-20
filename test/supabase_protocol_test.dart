import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodus/nodus_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'support/test_descriptor.dart';

void main() {
  test('one graph Realtime channel is shared as entity count grows', () async {
    final client = SupabaseClient('https://example.invalid', 'test-anon-key');
    final backend = SupabaseSyncBackend.graph(
      client: client,
      definition: _testGraphDefinition(
        descriptors: [
          const TestDescriptor<_TestEntity>(),
          const TestDescriptor<_OtherEntity>(
            entityType: 'Task',
            tableName: 'tasks',
            collaborationTableName: 'task_members',
          ),
        ],
        pullRpcName: 'pull_test_graph_changes',
      ),
    );
    addTearDown(() async {
      await backend.disposeRemoteChangeSignals();
      await client.dispose();
    });

    expect(client.getChannels(), hasLength(1));
  });

  test('snapshot lookup uses an RLS table read instead of an RPC', () async {
    const entityId = 'a0000000-0000-7000-8000-000000000010';
    late Uri requestUri;
    final httpClient = MockClient((request) async {
      requestUri = request.url;
      return http.Response(
        jsonEncode({'id': entityId, 'is_active': true, 'server_version': 4}),
        200,
        headers: const {'content-type': 'application/json'},
        request: request,
      );
    });
    final client = SupabaseClient(
      'https://example.invalid',
      'test-anon-key',
      httpClient: httpClient,
    );
    final backend = SupabaseSyncBackend.graph(
      client: client,
      definition: _testGraphDefinition(),
    );
    addTearDown(() async {
      await backend.disposeRemoteChangeSignals();
      await client.dispose();
    });

    final snapshot = await backend.fetchSnapshot(
      const TestDescriptor<_TestEntity>().parseIdentity(entityId),
    );

    expect(requestUri.path, '/rest/v1/notes');
    expect(requestUri.path, isNot(contains('/rpc/')));
    expect(requestUri.queryParameters['id'], 'eq.$entityId');
    expect(snapshot, isNotNull);
    expect(snapshot!.identity.rawId, entityId);
    expect(snapshot.serverVersion, ServerVersion(4));
    expect(snapshot.fields['isActive'], isTrue);
  });

  test('PostgreSQL constraint codes retain typed sync meaning', () async {
    for (final expectation in [
      ('23503', SyncRejectionCategory.relationship, 'foreign_key_violation'),
      ('23505', SyncRejectionCategory.validation, 'unique_violation'),
    ]) {
      final fixture = _errorFixture(expectation.$1);
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.backend.push(_createWork()),
        throwsA(
          isA<RejectedSyncException>()
              .having((error) => error.category, 'category', expectation.$2)
              .having((error) => error.code, 'code', expectation.$3),
        ),
      );
    }
  });

  test(
    'malformed pull booleans become typed server-contract rejections',
    () async {
      final fixture = _fixture({
        'changes': <Object?>[],
        'nextSequence': 0,
        'hasMore': 'false',
      });
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.backend.pull(afterSequence: ServerSequence.zero),
        throwsA(_serverContractRejection),
      );
    },
  );

  test(
    'fractional server versions are rejected instead of truncated',
    () async {
      final fixture = _fixture({
        'changes': [
          {
            'sequence': 1,
            'entity_type': 'Note',
            'record': {
              'id': 'a0000000-0000-7000-8000-000000000001',
              'is_active': true,
              'server_version': 1,
            },
            'server_version': 1.5,
            'operation_id': null,
            'is_revocation': false,
          },
        ],
        'nextSequence': 1,
        'hasMore': false,
      });
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.backend.pull(afterSequence: ServerSequence.zero),
        throwsA(_serverContractRejection),
      );
    },
  );

  test(
    'malformed remote IDs are validated before identity construction',
    () async {
      final fixture = _fixture({
        'changes': [
          {
            'sequence': 1,
            'entity_type': 'Note',
            'record': {'id': 42, 'is_active': true, 'server_version': 1},
            'server_version': 1,
            'operation_id': null,
            'is_revocation': false,
          },
        ],
        'nextSequence': 1,
        'hasMore': false,
      });
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.backend.pull(afterSequence: ServerSequence.zero),
        throwsA(_serverContractRejection),
      );
    },
  );

  test('record and envelope server versions must match', () async {
    final fixture = _fixture({
      'changes': [
        {
          'sequence': 1,
          'entity_type': 'Note',
          'record': {
            'id': 'a0000000-0000-7000-8000-000000000001',
            'is_active': true,
            'server_version': 1,
          },
          'server_version': 2,
          'operation_id': null,
          'is_revocation': false,
        },
      ],
      'nextSequence': 1,
      'hasMore': false,
    });
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.backend.pull(afterSequence: ServerSequence.zero),
      throwsA(_serverContractRejection),
    );
  });

  test('push response identity must match the submitted operation', () async {
    final fixture = _pushFixture(
      recordId: 'a0000000-0000-7000-8000-000000000099',
      operationId: 'a0000000-0000-7000-8000-000000000002',
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.backend.push(_createWork()),
      throwsA(_serverContractRejection),
    );
  });

  test('push receipt must match the submitted operation', () async {
    final fixture = _pushFixture(
      recordId: 'a0000000-0000-7000-8000-000000000001',
      operationId: 'a0000000-0000-7000-8000-000000000099',
    );
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.backend.push(_createWork()),
      throwsA(_serverContractRejection),
    );
  });

  test('push responses preserve typed ordered-scope versions', () async {
    final fixture = _pushFixture(
      recordId: 'a0000000-0000-7000-8000-000000000001',
      operationId: 'a0000000-0000-7000-8000-000000000002',
      scopeVersion: 3,
    );
    addTearDown(fixture.dispose);

    final result = await fixture.backend.push(_createWork());

    expect(result.orderScopeVersions.single.version, OrderScopeVersion(3));
    expect(result.orderScopeVersions.single.scope, const {'sourceId': 'lane'});
  });

  test(
    'push responses decode every related canonical acknowledgement',
    () async {
      const relatedId = 'a0000000-0000-7000-8000-000000000003';
      final fixture = _pushFixture(
        recordId: 'a0000000-0000-7000-8000-000000000001',
        operationId: 'a0000000-0000-7000-8000-000000000002',
        relatedChanges: const [
          {
            'entityType': 'Note',
            'record': {
              'id': relatedId,
              'is_active': false,
              'server_version': 4,
            },
            'serverVersion': 4,
            'sequence': 2,
            'operationId': 'a0000000-0000-7000-8000-000000000002',
          },
        ],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.backend.push(_createWork());

      expect(result.relatedChanges, hasLength(1));
      expect(result.relatedChanges.single.identity.rawId, relatedId);
      expect(result.relatedChanges.single.serverVersion, ServerVersion(4));
      expect(result.relatedChanges.single.fields['isActive'], isFalse);
    },
  );
}

final _serverContractRejection = isA<RejectedSyncException>().having(
  (error) => error.category,
  'category',
  SyncRejectionCategory.serverContract,
);

_SupabaseFixture _fixture(Object response) {
  final httpClient = MockClient(
    (request) async => http.Response(
      jsonEncode(response),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    ),
  );
  final client = SupabaseClient(
    'https://example.invalid',
    'test-anon-key',
    httpClient: httpClient,
  );
  final backend = SupabaseSyncBackend.graph(
    client: client,
    definition: _testGraphDefinition(),
  );
  return _SupabaseFixture(backend: backend, client: client);
}

_SupabaseFixture _pushFixture({
  required String recordId,
  required String operationId,
  int? scopeVersion,
  List<JsonMap> relatedChanges = const [],
}) => _fixture([
  {
    'record': {'id': recordId, 'is_active': true, 'server_version': 1},
    'serverVersion': 1,
    'sequence': 1,
    'operationId': operationId,
    'scopeVersions': scopeVersion == null
        ? const []
        : [
            {
              'scope': {'sourceId': 'lane'},
              'version': scopeVersion,
            },
          ],
    'relatedChanges': relatedChanges,
  },
]);

_SupabaseFixture _errorFixture(String code) {
  final httpClient = MockClient(
    (request) async => http.Response(
      jsonEncode({
        'code': code,
        'message': 'constraint rejected',
        'details': null,
        'hint': null,
      }),
      409,
      headers: const {'content-type': 'application/json'},
      request: request,
    ),
  );
  final client = SupabaseClient(
    'https://example.invalid',
    'test-anon-key',
    httpClient: httpClient,
  );
  final backend = SupabaseSyncBackend.graph(
    client: client,
    definition: _testGraphDefinition(),
  );
  return _SupabaseFixture(backend: backend, client: client);
}

EntityGraphDefinition _testGraphDefinition({
  List<EntityDescriptorBase> descriptors = const [
    TestDescriptor<_TestEntity>(),
  ],
  String pullRpcName = 'pull_test_changes',
}) => EntityGraphDefinition(
  schemaVersion: 1,
  descriptors: descriptors,
  relationships: const [],
  syncBindings: [
    for (final descriptor in descriptors)
      SyncBindingDefinition(
        entityType: descriptor.entityType,
        mode: SyncMode.replicated,
        target: SyncTargetId.testOnly,
      ),
  ],
  pullRpcName: pullRpcName,
);

PushSyncWorkItem _createWork() {
  const entityId = 'a0000000-0000-7000-8000-000000000001';
  const descriptor = TestDescriptor<_TestEntity>();
  return PushSyncWorkItem(
    target: SyncTargetId.testOnly,
    id: 1,
    operation: CreatePushOperation(
      operationId: SyncOperationId('a0000000-0000-7000-8000-000000000002'),
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
}

final class _SupabaseFixture {
  const _SupabaseFixture({required this.backend, required this.client});

  final SupabaseSyncBackend backend;
  final SupabaseClient client;

  Future<void> dispose() async {
    await backend.disposeRemoteChangeSignals();
    await client.dispose();
  }
}

final class _TestEntity {}

final class _OtherEntity {}
