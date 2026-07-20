/// Descriptor-driven Supabase synchronization for generated Nodus graphs.
library;

export 'nodus.dart';

import 'dart:async';

import 'package:nodus/nodus.dart';
import 'package:supabase/supabase.dart';

/// Generic Supabase transport for a generated entity graph.
///
/// Entity-specific RPC names, Realtime subscriptions, and row decoding are
/// derived from descriptors, so features do not need handwritten backends.
final class SupabaseSyncBackend
    implements
        PushPullSyncAdapter,
        SnapshotSyncAdapter,
        RemoteChangeSignalSource {
  SupabaseSyncBackend({
    required SupabaseClient client,
    required EntityDescriptorBase descriptor,
  }) : this._definition(
         client: client,
         definition: EntityGraphDefinition.single(descriptor),
       );

  SupabaseSyncBackend.graph({
    required SupabaseClient client,
    required EntityGraphDefinition definition,
  }) : this._definition(client: client, definition: definition);

  SupabaseSyncBackend._definition({
    required SupabaseClient client,
    required this.definition,
  }) : _client = client,
       _descriptors = Map.unmodifiable({
         for (final descriptor in definition.descriptors)
           descriptor.entityType: descriptor,
       }),
       _pullRpcName = definition.pullRpcName {
    final tables = <String>{
      for (final descriptor in definition.descriptors) descriptor.tableName,
      for (final descriptor in definition.descriptors)
        ?descriptor.collaborationTableName,
    }.toList(growable: false)..sort();
    _channel = _subscribeGraph(tables);
  }

  final SupabaseClient _client;
  @override
  final EntityGraphDefinition definition;
  final Map<String, EntityDescriptorBase> _descriptors;
  final String _pullRpcName;
  final StreamController<void> _remoteChanges = StreamController.broadcast();
  late final RealtimeChannel _channel;
  bool _disposed = false;

  @override
  Stream<void> get remoteChangeSignals => _remoteChanges.stream;

  @override
  Future<PushResult> push(PushSyncWorkItem item) async {
    try {
      final descriptor = _descriptorFor(item.operation.identity.entityType);
      item = item.upcast(descriptor);
      final payload = item.operation.toRemoteWire();
      _validateEntityType(payload['entityType'], descriptor);
      final response = await _client.rpc(
        'push_${descriptor.tableName}_operations',
        params: {
          'p_operations': [payload],
        },
      );
      final results = _list(response);
      if (results.length != 1) {
        throw FormatException(
          'Expected one push result, received ${results.length}.',
        );
      }
      final result = _map(results.single);
      final fields = _decodeRecord(result['record'], descriptor);
      final remoteFields = RemoteEntityFields.decode(
        descriptor,
        fields,
        complete: true,
      );
      final sourceOperationId = result['operationId'] == null
          ? throw const FormatException(
              'Push response is missing its operation receipt.',
            )
          : parseSyncOperationId(result['operationId'].toString());
      final serverVersion = parseServerVersion(result['serverVersion']);
      final relatedChanges = <RemoteEntityChange>[];
      for (final value in switch (result['relatedChanges']) {
        null => const <Object?>[],
        final value => _list(value),
      }) {
        final related = _map(value);
        final relatedType = related['entityType'];
        if (relatedType is! String || relatedType.isEmpty) {
          throw const FormatException(
            'Related push response is missing its entity type.',
          );
        }
        final relatedDescriptor = _descriptorFor(relatedType);
        final relatedFields = RemoteEntityFields.decode(
          relatedDescriptor,
          _decodeRecord(related['record'], relatedDescriptor),
          complete: true,
        );
        relatedChanges.add(
          RemoteEntityChange(
            identity: relatedFields.identity,
            serverVersion: parseServerVersion(related['serverVersion']),
            fields: relatedFields,
            serverSequence: parseServerSequence(related['sequence']),
            sourceOperationId: related['operationId'] == null
                ? throw const FormatException(
                    'Related push response is missing its operation receipt.',
                  )
                : parseSyncOperationId(related['operationId'].toString()),
          ),
        );
      }
      final pushResult = PushResult(
        orderScopeVersions: switch (result['scopeVersions']) {
          null => const [],
          final source => _list(source).map(OrderScopeVersionReceipt.fromWire),
        },
        canonicalChange: RemoteEntityChange(
          identity: remoteFields.identity,
          serverVersion: serverVersion,
          fields: remoteFields,
          serverSequence: parseServerSequence(result['sequence']),
          sourceOperationId: sourceOperationId,
        ),
        relatedChanges: relatedChanges,
      );
      pushResult.validateFor(item);
      return pushResult;
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on FormatException catch (error) {
      throw RejectedSyncException.serverContract(
        code: 'invalid_server_response',
        message: error.message,
      );
    } on ArgumentError catch (error) {
      throw RejectedSyncException.validation(
        code: 'invalid_local_operation',
        message: error.message?.toString() ?? error.toString(),
      );
    }
  }

  @override
  Future<PullResult> pull({required ServerSequence afterSequence}) async {
    try {
      final response = await _client.rpc(
        _pullRpcName,
        params: {'p_after_sequence': afterSequence.value},
      );
      final envelope = _map(response);
      final rows = _list(envelope['changes']);
      final changes = rows
          .map((value) {
            final row = _map(value);
            final descriptor = _descriptorFor(
              row['entity_type']?.toString() ?? _singleDescriptor.entityType,
            );
            final isRevocation = row['is_revocation'] == null
                ? false
                : _bool(row['is_revocation'], 'is_revocation');
            final fields = isRevocation
                ? <String, Object?>{
                    EntityConventions.idFieldName: _map(
                      row['record'],
                    )[EntityConventions.idColumnName],
                  }
                : _decodeRecord(row['record'], descriptor);
            final remoteFields = RemoteEntityFields.decode(
              descriptor,
              fields,
              complete: !isRevocation,
            );
            final serverVersion = parseServerVersion(row['server_version']);
            return RemoteEntityChange(
              identity: remoteFields.identity,
              serverVersion: serverVersion,
              fields: remoteFields,
              serverSequence: parseServerSequence(row['sequence']),
              sourceOperationId: row['operation_id'] == null
                  ? null
                  : parseSyncOperationId(row['operation_id'].toString()),
              isRevocation: isRevocation,
            );
          })
          .toList(growable: false);

      return PullResult(
        requestedAfter: afterSequence,
        changes: changes,
        nextSequence: parseServerSequence(envelope['nextSequence']),
        hasMore: _bool(envelope['hasMore'], 'hasMore'),
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on FormatException catch (error) {
      throw RejectedSyncException.serverContract(
        code: 'invalid_server_response',
        message: error.message,
      );
    } on ArgumentError catch (error) {
      throw RejectedSyncException.serverContract(
        code: 'invalid_server_response',
        message: error.message?.toString() ?? error.toString(),
      );
    }
  }

  @override
  Future<RemoteEntitySnapshot?> fetchSnapshot(
    EntityIdentity<dynamic> identity,
  ) async {
    try {
      final descriptor = _descriptorFor(identity.entityType);
      final response = await _client
          .from(descriptor.tableName)
          .select()
          .eq(EntityConventions.idColumnName, identity.rawId)
          .maybeSingle();
      if (response == null) return null;
      final fields = RemoteEntityFields.decode(
        descriptor,
        _decodeRecord(response, descriptor),
        complete: true,
      );
      return RemoteEntitySnapshot(
        identity: identity,
        serverVersion: parseServerVersion(
          fields[EntityConventions.serverVersionFieldName],
        ),
        fields: fields,
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on FormatException catch (error) {
      throw RejectedSyncException.serverContract(
        code: 'invalid_server_response',
        message: error.message,
      );
    } on ArgumentError catch (error) {
      throw RejectedSyncException.validation(
        code: 'invalid_lookup_identity',
        message: error.message?.toString() ?? error.toString(),
      );
    }
  }

  @override
  Future<void> disposeRemoteChangeSignals() async {
    if (_disposed) return;
    _disposed = true;
    await _client.removeChannel(_channel);
    await _remoteChanges.close();
  }

  JsonMap _decodeRecord(Object? value, EntityDescriptorBase descriptor) {
    final record = _map(value);
    for (final field in descriptor.fields) {
      if (!record.containsKey(field.columnName)) {
        throw FormatException(
          'Supabase ${descriptor.entityType} record is missing '
          '`${field.columnName}`.',
        );
      }
    }
    return {
      for (final field in descriptor.fields)
        field.name: record[field.columnName],
    };
  }

  void _validateEntityType(
    Object? entityType,
    EntityDescriptorBase descriptor,
  ) {
    if (entityType != descriptor.entityType) {
      throw ArgumentError.value(
        entityType,
        'entityType',
        'Expected ${descriptor.entityType}.',
      );
    }
  }

  EntityDescriptorBase _descriptorFor(String entityType) {
    final descriptor = _descriptors[entityType];
    if (descriptor == null) {
      throw FormatException('Unknown entity type `$entityType`.');
    }
    return descriptor;
  }

  EntityDescriptorBase get _singleDescriptor {
    if (_descriptors.length != 1) {
      throw const FormatException(
        'Graph pull rows must include `entity_type`.',
      );
    }
    return _descriptors.values.single;
  }

  void _signalRemoteChange() {
    if (!_disposed) _remoteChanges.add(null);
  }

  RealtimeChannel _subscribeGraph(List<String> tables) {
    var channel = _client.channel('entity-sync:$_pullRpcName');
    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _signalRemoteChange(),
      );
    }
    return channel.subscribe();
  }

  static List<Object?> _list(Object? value) {
    if (value is List) return List<Object?>.from(value);
    throw FormatException('Expected a Supabase array response, got $value.');
  }

  static JsonMap _map(Object? value) {
    if (value is! Map) {
      throw FormatException('Expected a Supabase object response, got $value.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw FormatException('Expected a string object key, got $key.');
      }
      result[key] = entry.value;
    }
    return result;
  }

  static bool _bool(Object? value, String field) {
    if (value is bool) return value;
    throw FormatException('Expected boolean `$field`.', value);
  }

  static SyncBackendException _mapPostgrestError(PostgrestException error) {
    return switch (error.code) {
      '40001' => VersionConflictException(error.message),
      '42501' => RejectedSyncException.authorization(
        code: 'authorization_denied',
        message: error.message,
      ),
      'P0001' => RejectedSyncException.serverContract(
        code: 'server_contract_violation',
        message: error.message,
      ),
      'P0002' => RejectedSyncException.notFound(
        code: 'entity_not_found',
        message: error.message,
      ),
      '23503' => RejectedSyncException.relationship(
        code: 'foreign_key_violation',
        message: error.message,
      ),
      '23505' => RejectedSyncException.validation(
        code: 'unique_violation',
        message: error.message,
      ),
      '22023' ||
      '23502' ||
      '23514' ||
      '22P02' => RejectedSyncException.validation(
        code: 'invalid_operation',
        message: error.message,
      ),
      _ => RetryableSyncException(
        code: error.code ?? 'supabase_unavailable',
        message: error.message,
      ),
    };
  }
}
