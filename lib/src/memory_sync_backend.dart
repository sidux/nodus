part of '../nodus.dart';

/// Deterministic in-memory transport for tests and offline demonstrations.
///
/// It follows the same idempotency, optimistic concurrency, change-log, and
/// Realtime signal contracts as the generated Supabase protocol.
final class InMemorySyncBackend
    implements
        PushPullSyncAdapter,
        SnapshotSyncAdapter,
        RemoteChangeSignalSource {
  InMemorySyncBackend({required EntityDescriptorBase descriptor})
    : this._definition(EntityGraphDefinition.single(descriptor));

  InMemorySyncBackend.graph({required EntityGraphDefinition definition})
    : this._definition(definition);

  InMemorySyncBackend._definition(this.definition)
    : _descriptors = {
        for (final descriptor in definition.descriptors)
          descriptor.entityType: descriptor,
      };

  @override
  final EntityGraphDefinition definition;
  final Map<String, EntityDescriptorBase> _descriptors;
  final Map<String, Map<String, JsonMap>> _records = {};
  final Map<String, RemoteEntityChange> _changes =
      <String, RemoteEntityChange>{};
  final Map<SyncOperationId, RemoteEntityChange> _receipts =
      <SyncOperationId, RemoteEntityChange>{};
  final Map<SyncOperationId, List<RemoteEntityChange>> _receiptRelatedChanges =
      {};
  final Map<SyncOperationId, List<OrderScopeVersionReceipt>>
  _receiptOrderScopeVersions = {};
  final Map<String, OrderScopeVersion> _orderScopeVersions = {};
  final Map<String, Map<String, Map<String, bool>>> _collaborators = {};
  final Set<String> _revokedIdentities = <String>{};
  final StreamController<void> _remoteChanges = StreamController.broadcast();
  int _sequence = 0;
  bool _disposed = false;

  @override
  Stream<void> get remoteChangeSignals => _remoteChanges.stream;

  @override
  Future<PushResult> push(PushSyncWorkItem item) async {
    final descriptor = _descriptorFor(item.operation.identity.entityType);
    item = item.upcast(descriptor);
    final operation = item.operation;
    final entityType = operation.identity.entityType;
    final records = _recordsFor(entityType);
    final entityId = operation.identity.rawId;
    final operationId = operation.operationId;
    final accepted = _receipts[operationId];
    if (accepted != null) {
      return _pushResult(
        item,
        accepted,
        relatedChanges: _receiptRelatedChanges[operationId] ?? const [],
        orderScopeVersions: _receiptOrderScopeVersions[operationId] ?? const [],
      );
    }
    final existing = records[entityId] ?? <String, Object?>{};
    final baseVersion = operation.baseServerVersion;
    final versionField = EntityConventions.serverVersionFieldName;
    final serverVersion = parseServerVersion(existing[versionField] ?? 0);
    if (operation case CommandPushOperation(:final command)) {
      if (command is ReorderOrderedCommand<dynamic>) {
        final orderedRecord = records[entityId];
        final orderedDescriptor = switch (descriptor) {
          final OrderedDescriptor value => value,
          _ => throw StateError(
            '$entityType accepts ordered commands without generated Ordered '
            'metadata.',
          ),
        };
        if (orderedRecord == null ||
            !orderedDescriptor.isOrderMember(orderedRecord)) {
          throw const RejectedSyncException.notFound(
            code: 'entity_not_found',
            message: 'Cannot reorder an entity outside canonical membership.',
          );
        }
        final scopeOwner = orderedDescriptor.orderScopeKey(orderedRecord);
        final members = records.entries
            .where(
              (entry) =>
                  orderedDescriptor.isOrderMember(entry.value) &&
                  orderedDescriptor.orderScopeKey(entry.value) == scopeOwner,
            )
            .toList(growable: false);
        final requestedIds = command.orderedIds
            .map((id) => id.value)
            .toList(growable: false);
        final currentIds = members.map((entry) => entry.key).toSet();
        if (requestedIds.length != members.length ||
            !currentIds.containsAll(requestedIds)) {
          throw const VersionConflictException(
            'Exact ordered membership changed on the server.',
          );
        }
        final scopeKey = '$entityType\u0000$scopeOwner';
        final currentScopeVersion =
            _orderScopeVersions[scopeKey] ?? OrderScopeVersion.zero;
        if (command.scopeBaseVersion.value > currentScopeVersion.value) {
          throw const RejectedSyncException.validation(
            code: 'invalid_order_scope_version',
            message: 'Ordered scope base version is ahead of the server.',
          );
        }
        final ranks = GeneratedOrderRanks.allocate(count: requestedIds.length)!;
        final changes = <RemoteEntityChange>[];
        for (final (index, requestedId) in requestedIds.indexed) {
          final current = records[requestedId]!;
          final nextVersion = ServerVersion(
            parseServerVersion(current[versionField]).value + 1,
          );
          final canonical = <String, Object?>{
            ...current,
            EntityConventions.orderRankFieldName: ranks[index].value,
            versionField: nextVersion.value,
          };
          records[requestedId] = canonical;
          changes.add(
            _appendChange(
              descriptor: descriptor,
              entityId: requestedId,
              serverVersion: nextVersion,
              fields: canonical,
              operationId: operationId,
            ),
          );
        }
        final canonicalChange = changes.singleWhere(
          (change) => change.identity.rawId == entityId,
        );
        final relatedChanges = changes
            .where((change) => !identical(change, canonicalChange))
            .toList(growable: false);
        final nextScopeVersion = OrderScopeVersion(
          currentScopeVersion.value + 1,
        );
        _orderScopeVersions[scopeKey] = nextScopeVersion;
        _receipts[operationId] = canonicalChange;
        _receiptRelatedChanges[operationId] = relatedChanges;
        final scopeVersions = [
          _scopeVersionReceipt(
            orderedDescriptor,
            records[entityId]!,
            nextScopeVersion,
          ),
        ];
        _receiptOrderScopeVersions[operationId] = scopeVersions;
        if (!_disposed) _remoteChanges.add(null);
        return _pushResult(
          item,
          canonicalChange,
          relatedChanges: relatedChanges,
          orderScopeVersions: scopeVersions,
        );
      }
      if (command is MoveOrderedCommand<dynamic>) {
        var orderedRecord = records[entityId];
        if (command.anchorId?.value == entityId) {
          throw const RejectedSyncException.validation(
            code: 'invalid_order_neighbor',
            message: 'An ordered entity cannot be its own anchor.',
          );
        }

        final orderedDescriptor = switch (descriptor) {
          final OrderedDescriptor value => value,
          _ => throw StateError(
            '$entityType accepts ordered commands without generated Ordered '
            'metadata.',
          ),
        };
        if (orderedRecord == null ||
            !orderedDescriptor.isOrderMember(orderedRecord)) {
          throw const RejectedSyncException.notFound(
            code: 'entity_not_found',
            message: 'Cannot order an entity outside canonical membership.',
          );
        }
        final scopeOwner = orderedDescriptor.orderScopeKey(orderedRecord);
        bool isActiveScopeMember(MapEntry<String, JsonMap> entry) =>
            orderedDescriptor.isOrderMember(entry.value) &&
            orderedDescriptor.orderScopeKey(entry.value) == scopeOwner;
        int compareMembers(
          MapEntry<String, JsonMap> left,
          MapEntry<String, JsonMap> right,
        ) {
          final rankComparison =
              OrderRank.parse(
                left.value[EntityConventions.orderRankFieldName]! as String,
              ).compareTo(
                OrderRank.parse(
                  right.value[EntityConventions.orderRankFieldName]! as String,
                ),
              );
          return rankComparison == 0
              ? left.key.compareTo(right.key)
              : rankComparison;
        }

        List<MapEntry<String, JsonMap>> movableMembers() {
          final members = records.entries
              .where(isActiveScopeMember)
              .where((entry) => entry.key != entityId)
              .toList(growable: false);
          members.sort(compareMembers);
          return members;
        }

        (JsonMap?, JsonMap?) resolveBounds() {
          final members = movableMembers();
          switch (command.placement) {
            case OrderedPlacement.first:
              return (null, members.firstOrNull?.value);
            case OrderedPlacement.last:
              return (members.lastOrNull?.value, null);
            case OrderedPlacement.before:
            case OrderedPlacement.after:
              final anchorId = command.anchorId!.value;
              final anchorIndex = members.indexWhere(
                (entry) => entry.key == anchorId,
              );
              if (anchorIndex < 0) {
                throw const RejectedSyncException.validation(
                  code: 'invalid_order_anchor',
                  message: 'Ordered anchor is outside the canonical scope.',
                );
              }
              if (command.placement == OrderedPlacement.before) {
                return (
                  anchorIndex == 0 ? null : members[anchorIndex - 1].value,
                  members[anchorIndex].value,
                );
              }
              return (
                members[anchorIndex].value,
                anchorIndex == members.length - 1
                    ? null
                    : members[anchorIndex + 1].value,
              );
          }
        }

        OrderRank? rankOf(JsonMap? record) => record == null
            ? null
            : OrderRank.parse(
                record[EntityConventions.orderRankFieldName]! as String,
              );
        OrderRank? allocateMoveRank() {
          final (after, before) = resolveBounds();
          return GeneratedOrderRanks.between(
            after: rankOf(after),
            before: rankOf(before),
          );
        }

        final rebalancedChanges = <RemoteEntityChange>[];
        void rebalanceScope() {
          final members = records.entries
              .where(isActiveScopeMember)
              .toList(growable: false);
          members.sort(compareMembers);
          final ranks = GeneratedOrderRanks.allocate(count: members.length)!;
          for (final (index, member) in members.indexed) {
            final current = member.value;
            final nextVersion = ServerVersion(
              parseServerVersion(current[versionField]).value + 1,
            );
            final rebalanced = <String, Object?>{
              ...current,
              EntityConventions.orderRankFieldName: ranks[index].value,
              versionField: nextVersion.value,
            };
            records[member.key] = rebalanced;
            final change = _appendChange(
              descriptor: descriptor,
              entityId: member.key,
              serverVersion: nextVersion,
              fields: rebalanced,
              operationId: operationId,
            );
            if (member.key != entityId) rebalancedChanges.add(change);
          }
          orderedRecord = records[entityId]!;
        }

        final scopeKey = '$entityType\u0000$scopeOwner';
        final currentScopeVersion =
            _orderScopeVersions[scopeKey] ?? OrderScopeVersion.zero;
        if (command.scopeBaseVersion.value > currentScopeVersion.value) {
          throw const RejectedSyncException.validation(
            code: 'invalid_order_scope_version',
            message: 'Ordered scope base version is ahead of the server.',
          );
        }
        var rank = allocateMoveRank();
        if (rank == null) {
          rebalanceScope();
          rank = allocateMoveRank();
        }
        if (rank == null) throw const OrderRankSpaceExhaustedException();
        final nextVersion = ServerVersion(
          parseServerVersion(orderedRecord![versionField]).value + 1,
        );
        final canonical = <String, Object?>{
          ...orderedRecord!,
          EntityConventions.orderRankFieldName: rank.value,
          versionField: nextVersion.value,
        };
        records[entityId] = canonical;
        final nextScopeVersion = OrderScopeVersion(
          currentScopeVersion.value + 1,
        );
        _orderScopeVersions[scopeKey] = nextScopeVersion;
        final change = _appendChange(
          descriptor: descriptor,
          entityId: entityId,
          serverVersion: nextVersion,
          fields: canonical,
          operationId: operationId,
        );
        _receipts[operationId] = change;
        if (rebalancedChanges.isNotEmpty) {
          _receiptRelatedChanges[operationId] = rebalancedChanges;
        }
        final scopeVersions = [
          _scopeVersionReceipt(orderedDescriptor, canonical, nextScopeVersion),
        ];
        _receiptOrderScopeVersions[operationId] = scopeVersions;
        if (!_disposed) _remoteChanges.add(null);
        return _pushResult(
          item,
          change,
          relatedChanges: rebalancedChanges,
          orderScopeVersions: scopeVersions,
        );
      }
      if (command is TransferOrderedCommand<dynamic>) {
        final orderedRecord = records[entityId];
        final orderedDescriptor = switch (descriptor) {
          final OrderedDescriptor value => value,
          _ => throw StateError(
            '$entityType accepts an ordered transfer without generated '
            'Ordered metadata.',
          ),
        };
        if (orderedRecord == null ||
            !orderedDescriptor.isOrderMember(orderedRecord)) {
          throw const RejectedSyncException.notFound(
            code: 'entity_not_found',
            message: 'Cannot transfer an entity outside canonical membership.',
          );
        }
        final sourceScopeOwner = orderedDescriptor.orderScopeKey(orderedRecord);
        final targetRecord = <String, Object?>{
          ...orderedRecord,
          ...command.targetScope.toWire(),
        };
        final targetScopeOwner = orderedDescriptor.orderScopeKey(targetRecord);
        if (sourceScopeOwner == targetScopeOwner) {
          throw const RejectedSyncException.validation(
            code: 'unchanged_order_scope',
            message: 'An ordered transfer must change its canonical scope.',
          );
        }
        _validateInMemoryTransferReferences(
          descriptor: descriptor,
          entityId: entityId,
          targetScope: command.targetScope,
        );
        _validateUniqueConstraints(
          descriptor: descriptor,
          records: records,
          entityId: entityId,
          candidate: targetRecord,
        );
        final sourceScopeKey = '$entityType\u0000$sourceScopeOwner';
        final targetScopeKey = '$entityType\u0000$targetScopeOwner';
        final sourceVersion =
            _orderScopeVersions[sourceScopeKey] ?? OrderScopeVersion.zero;
        final targetVersion =
            _orderScopeVersions[targetScopeKey] ?? OrderScopeVersion.zero;
        if (command.sourceScopeBaseVersion.value > sourceVersion.value ||
            command.targetScopeBaseVersion.value > targetVersion.value) {
          throw const RejectedSyncException.validation(
            code: 'invalid_order_scope_version',
            message: 'Ordered scope base version is ahead of the server.',
          );
        }
        bool isTargetMember(MapEntry<String, JsonMap> entry) =>
            entry.key != entityId &&
            orderedDescriptor.isOrderMember(entry.value) &&
            orderedDescriptor.orderScopeKey(entry.value) == targetScopeOwner;
        int compareMembers(
          MapEntry<String, JsonMap> left,
          MapEntry<String, JsonMap> right,
        ) {
          final byRank =
              OrderRank.parse(
                left.value[EntityConventions.orderRankFieldName]! as String,
              ).compareTo(
                OrderRank.parse(
                  right.value[EntityConventions.orderRankFieldName]! as String,
                ),
              );
          return byRank != 0 ? byRank : left.key.compareTo(right.key);
        }

        List<MapEntry<String, JsonMap>> targetMembers() =>
            records.entries.where(isTargetMember).toList(growable: false)
              ..sort(compareMembers);
        OrderRank? allocateTargetRank() {
          final members = targetMembers();
          return command.placement == OrderedPlacement.first
              ? GeneratedOrderRanks.between(
                  before: members.firstOrNull == null
                      ? null
                      : OrderRank.parse(
                          members.first.value[EntityConventions
                                  .orderRankFieldName]
                              as String,
                        ),
                )
              : GeneratedOrderRanks.between(
                  after: members.lastOrNull == null
                      ? null
                      : OrderRank.parse(
                          members.last.value[EntityConventions
                                  .orderRankFieldName]
                              as String,
                        ),
                );
        }

        final relatedChanges = <RemoteEntityChange>[];
        var rank = allocateTargetRank();
        if (rank == null) {
          final members = targetMembers();
          final ranks = GeneratedOrderRanks.allocate(count: members.length);
          if (ranks == null) throw const OrderRankSpaceExhaustedException();
          for (final (index, member) in members.indexed) {
            final memberVersion = ServerVersion(
              parseServerVersion(member.value[versionField]).value + 1,
            );
            final rebalanced = <String, Object?>{
              ...member.value,
              EntityConventions.orderRankFieldName: ranks[index].value,
              versionField: memberVersion.value,
            };
            records[member.key] = rebalanced;
            relatedChanges.add(
              _appendChange(
                descriptor: descriptor,
                entityId: member.key,
                serverVersion: memberVersion,
                fields: rebalanced,
                operationId: operationId,
              ),
            );
          }
          rank = allocateTargetRank();
        }
        if (rank == null) throw const OrderRankSpaceExhaustedException();
        final nextVersion = ServerVersion(serverVersion.value + 1);
        final canonical = <String, Object?>{
          ...targetRecord,
          EntityConventions.orderRankFieldName: rank.value,
          versionField: nextVersion.value,
        };
        records[entityId] = canonical;
        final nextSourceVersion = OrderScopeVersion(sourceVersion.value + 1);
        final nextTargetVersion = OrderScopeVersion(targetVersion.value + 1);
        _orderScopeVersions[sourceScopeKey] = nextSourceVersion;
        _orderScopeVersions[targetScopeKey] = nextTargetVersion;
        final change = _appendChange(
          descriptor: descriptor,
          entityId: entityId,
          serverVersion: nextVersion,
          fields: canonical,
          operationId: operationId,
        );
        final scopeVersions = [
          _scopeVersionReceipt(
            orderedDescriptor,
            orderedRecord,
            nextSourceVersion,
          ),
          _scopeVersionReceipt(orderedDescriptor, canonical, nextTargetVersion),
        ];
        _receipts[operationId] = change;
        _receiptRelatedChanges[operationId] = relatedChanges;
        _receiptOrderScopeVersions[operationId] = scopeVersions;
        if (!_disposed) _remoteChanges.add(null);
        return _pushResult(
          item,
          change,
          relatedChanges: relatedChanges,
          orderScopeVersions: scopeVersions,
        );
      }
      if (command is! SetCollaboratorCommand<dynamic, dynamic>) {
        throw const RejectedSyncException.validation(
          code: 'unsupported_command',
          message: 'Unsupported in-memory command.',
        );
      }
      final existingRecord = records[entityId];
      if (existingRecord == null) {
        throw const RejectedSyncException.notFound(
          code: 'entity_not_found',
          message: 'Cannot collaborate on an unknown entity.',
        );
      }
      final userId = command.collaboratorId.value;
      final active = command.active;
      ((_collaborators[entityType] ??= {})[entityId] ??= {})[userId] = active;
      final change = _appendChange(
        descriptor: descriptor,
        entityId: entityId,
        serverVersion: serverVersion,
        fields: existingRecord,
        operationId: operationId,
      );
      _receipts[operationId] = change;
      if (!_disposed) _remoteChanges.add(null);
      return _pushResult(item, change);
    }
    if (operation is CreatePushOperation && records.containsKey(entityId)) {
      throw const RejectedSyncException.validation(
        code: 'unique_violation',
        message: 'A create cannot replace an existing entity.',
      );
    }
    final patch = operation.patch.toWire();
    final actionPolicy = switch (descriptor) {
      ActionPolicyProvider provider => provider.actionPolicy,
      _ => null,
    };
    if (operation is CreatePushOperation) {
      if (actionPolicy != null && !actionPolicy.allowsCreate(patch)) {
        throw const RejectedSyncException.validation(
          code: 'invalid_initial_action_state',
          message: 'Action-managed fields must use their generated defaults.',
        );
      }
      for (final field in descriptor.fields) {
        if (field.allowedTransitions.isEmpty ||
            patch[field.name] == field.protocolDefault) {
          continue;
        }
        throw RejectedSyncException.validation(
          code: 'invalid_initial_state',
          message:
              '${descriptor.entityType}.${field.name} must start from its declared default.',
        );
      }
    }
    if (operation is! CreatePushOperation && baseVersion != serverVersion) {
      throw const VersionConflictException();
    }
    if (operation is PatchPushOperation &&
        actionPolicy != null &&
        !actionPolicy.allowsPatch(patch, existing)) {
      throw const RejectedSyncException.validation(
        code: 'invalid_entity_action',
        message: 'Patch does not match a declared entity action.',
      );
    }
    if (operation is! CreatePushOperation) {
      for (final field in descriptor.fields) {
        if (!patch.containsKey(field.name) ||
            field.allowsTransition(existing[field.name], patch[field.name])) {
          continue;
        }
        throw RejectedSyncException.validation(
          code: 'invalid_transition',
          message:
              '${descriptor.entityType}.${field.name} transition is not allowed.',
        );
      }
    }
    final nextVersion = ServerVersion(serverVersion.value + 1);
    final canonical = <String, Object?>{
      ...existing,
      ...patch,
      EntityConventions.idFieldName: entityId,
      for (final field in descriptor.fields)
        if (field.kind == EntityFieldKind.timestamp &&
            ((field.serverGenerated && !existing.containsKey(field.name)) ||
                field.autoUpdated))
          field.name: item.createdAt.toUtc().toIso8601String(),
      versionField: nextVersion.value,
    };
    for (final field in descriptor.fields) {
      if (canonical.containsKey(field.name)) continue;
      if (field.nullable) {
        canonical[field.name] = null;
      } else if (field.hasProtocolDefault) {
        canonical[field.name] = field.protocolDefault;
      }
    }
    try {
      for (final field in descriptor.fields) {
        if (!canonical.containsKey(field.name)) {
          throw FormatException(
            '${descriptor.entityType}.${field.name} is required.',
          );
        }
        canonical[field.name] = field.decodeWireValue(
          canonical[field.name],
          entityType: descriptor.entityType,
        );
      }
    } on FormatException catch (error) {
      throw RejectedSyncException.validation(
        code: 'constraint_violation',
        message: error.message.toString(),
      );
    }
    _validateUniqueConstraints(
      descriptor: descriptor,
      records: records,
      entityId: entityId,
      candidate: canonical,
    );
    final orderedCreateRelatedChanges = <RemoteEntityChange>[];
    if (operation is CreatePushOperation && operation.orderedCreate != null) {
      final orderedDescriptor = switch (descriptor) {
        final OrderedDescriptor value => value,
        _ => throw StateError(
          '$entityType carries ordered create intent without generated '
          'Ordered metadata.',
        ),
      };
      orderedCreateRelatedChanges.addAll(
        _resolveOrderedCreate(
          descriptor: descriptor,
          orderedDescriptor: orderedDescriptor,
          operation: operation,
          records: records,
          canonical: canonical,
        ),
      );
    }
    OrderScopeVersion? nextOrderScopeVersion;
    if (descriptor case final OrderedDescriptor orderedDescriptor) {
      final wasActive =
          existing.isNotEmpty && orderedDescriptor.isOrderMember(existing);
      final isActive = orderedDescriptor.isOrderMember(canonical);
      if (wasActive != isActive) {
        final scopeSource = isActive ? canonical : existing;
        final scopeOwner = orderedDescriptor.orderScopeKey(scopeSource);
        final scopeKey = '$entityType\u0000$scopeOwner';
        final currentOrderScopeVersion =
            _orderScopeVersions[scopeKey] ?? OrderScopeVersion.zero;
        nextOrderScopeVersion = OrderScopeVersion(
          currentOrderScopeVersion.value + 1,
        );
        _orderScopeVersions[scopeKey] = nextOrderScopeVersion;
      }
    }
    records[entityId] = canonical;
    final change = _appendChange(
      descriptor: descriptor,
      entityId: entityId,
      serverVersion: nextVersion,
      fields: canonical,
      operationId: operationId,
    );
    _receipts[operationId] = change;
    if (orderedCreateRelatedChanges.isNotEmpty) {
      _receiptRelatedChanges[operationId] = orderedCreateRelatedChanges;
    }
    if (nextOrderScopeVersion != null) {
      _receiptOrderScopeVersions[operationId] = [
        _scopeVersionReceipt(
          descriptor as OrderedDescriptor,
          canonical,
          nextOrderScopeVersion,
        ),
      ];
    }
    return _pushResult(
      item,
      change,
      relatedChanges: orderedCreateRelatedChanges,
      orderScopeVersions: _receiptOrderScopeVersions[operationId] ?? const [],
    );
  }

  void _validateInMemoryTransferReferences({
    required EntityDescriptorBase descriptor,
    required String entityId,
    required EntityPatch targetScope,
  }) {
    for (final field in descriptor.fields) {
      final reference = field.reference;
      if (reference == null || !targetScope.containsKey(field.name)) continue;
      final targetId = targetScope[field.name] as String?;
      if (targetId == null) continue;
      final target = _recordsFor(reference.targetEntityType)[targetId];
      if (target == null ||
          target[EntityConventions.deletedAtFieldName] != null) {
        throw const RejectedSyncException.validation(
          code: 'invalid_transfer_reference',
          message: 'An ordered transfer target reference does not exist.',
        );
      }
      if (reference.targetEntityType != descriptor.entityType) continue;
      final visited = <String>{};
      var cursor = targetId;
      while (visited.add(cursor)) {
        if (cursor == entityId) {
          throw const RejectedSyncException.validation(
            code: 'hierarchy_cycle',
            message: 'An ordered hierarchy transfer cannot create a cycle.',
          );
        }
        final parent = _recordsFor(descriptor.entityType)[cursor]?[field.name];
        if (parent is! String) break;
        cursor = parent;
      }
    }
  }

  List<RemoteEntityChange> _resolveOrderedCreate({
    required EntityDescriptorBase descriptor,
    required OrderedDescriptor orderedDescriptor,
    required CreatePushOperation operation,
    required Map<String, JsonMap> records,
    required JsonMap canonical,
  }) {
    final intent = operation.orderedCreate!;
    final entityType = descriptor.entityType;
    final scopeOwner = orderedDescriptor.orderScopeKey(canonical);
    final scopeKey = '$entityType\u0000$scopeOwner';
    final currentScopeVersion =
        _orderScopeVersions[scopeKey] ?? OrderScopeVersion.zero;
    if (intent.scopeBaseVersion.value > currentScopeVersion.value) {
      throw const RejectedSyncException.validation(
        code: 'invalid_order_scope_version',
        message: 'Ordered scope base version is ahead of the server.',
      );
    }
    final versionField = EntityConventions.serverVersionFieldName;
    bool isScopeMember(MapEntry<String, JsonMap> entry) =>
        orderedDescriptor.isOrderMember(entry.value) &&
        orderedDescriptor.orderScopeKey(entry.value) == scopeOwner;
    int compareMembers(
      MapEntry<String, JsonMap> left,
      MapEntry<String, JsonMap> right,
    ) {
      final byRank =
          OrderRank.parse(
            left.value[EntityConventions.orderRankFieldName]! as String,
          ).compareTo(
            OrderRank.parse(
              right.value[EntityConventions.orderRankFieldName]! as String,
            ),
          );
      return byRank != 0 ? byRank : left.key.compareTo(right.key);
    }

    List<MapEntry<String, JsonMap>> members() {
      final result = records.entries.where(isScopeMember).toList();
      result.sort(compareMembers);
      return result;
    }

    OrderRank? allocate() {
      final current = members();
      return intent.placement == OrderedPlacement.first
          ? GeneratedOrderRanks.between(
              before: current.firstOrNull == null
                  ? null
                  : OrderRank.parse(
                      current.first.value[EntityConventions.orderRankFieldName]
                          as String,
                    ),
            )
          : GeneratedOrderRanks.between(
              after: current.lastOrNull == null
                  ? null
                  : OrderRank.parse(
                      current.last.value[EntityConventions.orderRankFieldName]
                          as String,
                    ),
            );
    }

    final relatedChanges = <RemoteEntityChange>[];
    var rank = allocate();
    if (rank == null) {
      final current = members();
      final ranks = GeneratedOrderRanks.allocate(count: current.length)!;
      for (final (index, member) in current.indexed) {
        final nextVersion = ServerVersion(
          parseServerVersion(member.value[versionField]).value + 1,
        );
        final rebalanced = <String, Object?>{
          ...member.value,
          EntityConventions.orderRankFieldName: ranks[index].value,
          versionField: nextVersion.value,
        };
        records[member.key] = rebalanced;
        relatedChanges.add(
          _appendChange(
            descriptor: descriptor,
            entityId: member.key,
            serverVersion: nextVersion,
            fields: rebalanced,
            operationId: operation.operationId,
          ),
        );
      }
      rank = allocate();
    }
    if (rank == null) throw const OrderRankSpaceExhaustedException();
    canonical[EntityConventions.orderRankFieldName] = rank.value;
    return relatedChanges;
  }

  void _validateUniqueConstraints({
    required EntityDescriptorBase descriptor,
    required Map<String, JsonMap> records,
    required String entityId,
    required JsonMap candidate,
  }) {
    if (descriptor is! EntityUniqueConstraintDescriptor) return;
    final uniqueDescriptor = descriptor as EntityUniqueConstraintDescriptor;
    for (final constraint in uniqueDescriptor.uniqueConstraints) {
      if (constraint.unordered && constraint.fieldNames.length != 2) {
        throw StateError(
          'Unordered unique constraints require exactly two fields.',
        );
      }
      if (!(constraint.condition?.matches(candidate) ?? true)) continue;
      final values = [
        for (final fieldName in constraint.fieldNames) candidate[fieldName],
      ];
      // Match PostgreSQL unique-index semantics: null values are distinct.
      if (values.any((value) => value == null)) continue;
      if (constraint.unordered && entityValuesEqual(values[0], values[1])) {
        throw RejectedSyncException.validation(
          code: 'check_violation',
          message: 'Unordered relationship endpoints must differ.',
        );
      }
      var conflicts = false;
      for (final entry in records.entries) {
        if (entry.key == entityId) continue;
        if (!(constraint.condition?.matches(entry.value) ?? true)) continue;
        final matches = constraint.unordered
            ? (entityValuesEqual(
                        entry.value[constraint.fieldNames[0]],
                        values[0],
                      ) &&
                      entityValuesEqual(
                        entry.value[constraint.fieldNames[1]],
                        values[1],
                      )) ||
                  (entityValuesEqual(
                        entry.value[constraint.fieldNames[0]],
                        values[1],
                      ) &&
                      entityValuesEqual(
                        entry.value[constraint.fieldNames[1]],
                        values[0],
                      ))
            : constraint.fieldNames.indexed.every(
                (field) =>
                    entityValuesEqual(entry.value[field.$2], values[field.$1]),
              );
        if (matches) {
          conflicts = true;
          break;
        }
      }
      if (conflicts) {
        throw RejectedSyncException.validation(
          code: 'unique_violation',
          message: 'Unique constraint `${constraint.name}` was violated.',
        );
      }
    }
  }

  @override
  Future<PullResult> pull({required ServerSequence afterSequence}) async {
    final page = _changes.values
        .where((change) => change.serverSequence.value > afterSequence.value)
        .take(501)
        .toList(growable: false);
    final changes = page.take(500).toList(growable: false);
    return PullResult(
      requestedAfter: afterSequence,
      changes: changes,
      nextSequence: changes.isEmpty
          ? afterSequence
          : changes.last.serverSequence,
      hasMore: page.length > changes.length,
    );
  }

  @override
  Future<RemoteEntitySnapshot?> fetchSnapshot(
    EntityIdentity<dynamic> identity,
  ) async {
    if (_revokedIdentities.contains(_identityKey(identity))) return null;
    final descriptor = _descriptorFor(identity.entityType);
    final record = _recordsFor(identity.entityType)[identity.rawId];
    if (record == null) return null;
    final fields = RemoteEntityFields.decode(
      descriptor,
      record,
      complete: true,
    );
    return RemoteEntitySnapshot(
      identity: identity,
      serverVersion: parseServerVersion(
        record[EntityConventions.serverVersionFieldName],
      ),
      fields: fields,
    );
  }

  RemoteEntityChange collaboratorEdit(String entityId, JsonMap patch) {
    return collaboratorEditFor(_singleDescriptor.entityType, entityId, patch);
  }

  RemoteEntityChange collaboratorEditFor(
    String entityType,
    String entityId,
    JsonMap patch,
  ) {
    final descriptor = _descriptorFor(entityType);
    final records = _recordsFor(entityType);
    final existing = records[entityId];
    if (existing == null) {
      throw StateError('$entityType `$entityId` has not reached the server.');
    }
    final versionField = EntityConventions.serverVersionFieldName;
    final nextVersion = ServerVersion(
      parseServerVersion(existing[versionField]).value + 1,
    );
    final canonical = <String, Object?>{
      ...existing,
      ...patch,
      versionField: nextVersion.value,
    };
    records[entityId] = canonical;
    final change = _appendChange(
      descriptor: descriptor,
      entityId: entityId,
      serverVersion: nextVersion,
      fields: canonical,
    );
    if (!_disposed) _remoteChanges.add(null);
    return change;
  }

  RemoteEntityChange revokeAccess(String entityId) {
    return revokeAccessFor(_singleDescriptor.entityType, entityId);
  }

  RemoteEntityChange revokeAccessFor(String entityType, String entityId) {
    final descriptor = _descriptorFor(entityType);
    final existing = _recordsFor(entityType)[entityId];
    if (existing == null) {
      throw StateError('$entityType `$entityId` has not reached the server.');
    }
    _revokedIdentities.add(_identityKey(descriptor.parseIdentity(entityId)));
    final change = _appendChange(
      descriptor: descriptor,
      entityId: entityId,
      serverVersion: parseServerVersion(
        existing[EntityConventions.serverVersionFieldName],
      ),
      fields: {EntityConventions.idFieldName: entityId},
      isRevocation: true,
    );
    if (!_disposed) _remoteChanges.add(null);
    return change;
  }

  JsonMap? record(String id) => recordFor(_singleDescriptor.entityType, id);

  JsonMap? recordFor(String entityType, String id) {
    final record = _recordsFor(entityType)[id];
    return record == null ? null : JsonMap.of(record);
  }

  bool isCollaborator(String entityId, String userId) =>
      isCollaboratorFor(_singleDescriptor.entityType, entityId, userId);

  bool isCollaboratorFor(String entityType, String entityId, String userId) =>
      _collaborators[entityType]?[entityId]?[userId] ?? false;

  @override
  Future<void> disposeRemoteChangeSignals() async {
    if (_disposed) return;
    _disposed = true;
    await _remoteChanges.close();
  }

  RemoteEntityChange _appendChange({
    required EntityDescriptorBase descriptor,
    required String entityId,
    required ServerVersion serverVersion,
    required JsonMap fields,
    SyncOperationId? operationId,
    bool isRevocation = false,
  }) {
    final changeKey = '${descriptor.entityType}\u0000$entityId';
    final change = RemoteEntityChange(
      identity: descriptor.parseIdentity(entityId),
      serverVersion: serverVersion,
      fields: RemoteEntityFields.decode(
        descriptor,
        JsonMap.of(fields),
        complete: !isRevocation,
      ),
      serverSequence: ServerSequence(++_sequence),
      sourceOperationId: operationId,
      isRevocation: isRevocation,
    );
    _changes
      ..remove(changeKey)
      ..[changeKey] = change;
    return change;
  }

  PushResult _pushResult(
    PushSyncWorkItem item,
    RemoteEntityChange canonicalChange, {
    Iterable<RemoteEntityChange> relatedChanges = const [],
    Iterable<OrderScopeVersionReceipt> orderScopeVersions = const [],
  }) {
    final result = PushResult(
      canonicalChange: canonicalChange,
      relatedChanges: relatedChanges,
      orderScopeVersions: orderScopeVersions,
    );
    result.validateFor(item);
    return result;
  }

  OrderScopeVersionReceipt _scopeVersionReceipt(
    OrderedDescriptor descriptor,
    JsonMap record,
    OrderScopeVersion version,
  ) => OrderScopeVersionReceipt(
    scope: {
      for (final field in descriptor.orderScopeFields)
        field.name: record[field.name],
    },
    version: version,
  );

  EntityDescriptorBase _descriptorFor(String entityType) {
    final descriptor = _descriptors[entityType];
    if (descriptor == null) {
      throw RejectedSyncException.protocol(
        code: 'unknown_entity_type',
        message: 'No in-memory protocol handles `$entityType`.',
      );
    }
    return descriptor;
  }

  Map<String, JsonMap> _recordsFor(String entityType) =>
      _records.putIfAbsent(entityType, () => <String, JsonMap>{});

  String _identityKey(EntityIdentity<dynamic> identity) =>
      '${identity.entityType}\u0000${identity.rawId}';

  EntityDescriptorBase get _singleDescriptor {
    if (_descriptors.length != 1) {
      throw StateError('Specify entityType when using a graph backend.');
    }
    return _descriptors.values.single;
  }
}
