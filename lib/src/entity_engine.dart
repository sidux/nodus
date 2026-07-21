part of '../nodus.dart';

final Object _relationshipOutboundSuppressionZoneKey = Object();

enum EntityFieldKind { text, uuid, boolean, integer, real, date, timestamp }

@TableIndex.sql(
  "CREATE INDEX local_entity_push_patch_idx "
  "ON local_entity_sync_work (sync_target, entity_type, entity_id, id) WHERE direction = "
  "'push' AND kind = 'statePatch' AND status = 'pending'",
)
@TableIndex.sql(
  "CREATE INDEX local_entity_sync_ready_idx "
  "ON local_entity_sync_work "
  "(sync_target, status, next_attempt_at, direction, id)",
)
class LocalEntitySyncWorkRows extends Table {
  @override
  String get tableName => 'local_entity_sync_work';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncTarget => text().named('sync_target')();
  TextColumn get direction => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get entityType => text().named('entity_type')();
  TextColumn get entityId => text().named('entity_id')();
  TextColumn get operationId => text().named('operation_id')();
  IntColumn get baseServerVersion => integer().named('base_server_version')();
  IntColumn get localRevision => integer().named('local_revision')();
  IntColumn get protocolVersion =>
      integer().named('protocol_version').withDefault(const Constant(1))();
  TextColumn get payload => text()();
  IntColumn get attemptCount =>
      integer().named('attempt_count').withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt =>
      dateTime().named('next_attempt_at').nullable()();
  DateTimeColumn get leaseUntil => dateTime().named('lease_until').nullable()();
  TextColumn get lastErrorCode => text().named('last_error_code').nullable()();
  TextColumn get lastErrorDetail =>
      text().named('last_error_detail').nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
}

class LocalEntitySyncCursorRows extends Table {
  @override
  String get tableName => 'local_entity_sync_cursor';

  TextColumn get syncTarget => text().named('sync_target')();
  IntColumn get cursor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {syncTarget};
}

/// Scalar validation derived from one persisted domain field declaration.
///
/// Generated domain validation, Drift/PostgreSQL checks, transport decoding,
/// deterministic test backends, and UI affordances all consume these same
/// values instead of repeating limits at each boundary.
final class EntityFieldConstraints {
  const EntityFieldConstraints({
    this.minLength,
    this.maxLength,
    this.allowWhitespace = false,
    this.minValue,
    this.maxValue,
    this.allowedValues = const [],
  }) : assert(minLength == null || minLength > 0),
       assert(maxLength == null || maxLength > 0),
       assert(minLength == null || maxLength == null || maxLength >= minLength),
       assert(minValue == null || maxValue == null || maxValue >= minValue);

  final int? minLength;
  final int? maxLength;
  final bool allowWhitespace;
  final int? minValue;
  final int? maxValue;
  final List<String> allowedValues;

  bool get hasTextRules =>
      minLength != null || maxLength != null || allowedValues.isNotEmpty;

  bool get hasNumericRules => minValue != null || maxValue != null;

  void validate(
    Object value, {
    required String entityType,
    required String fieldName,
  }) {
    if (value case final String text) {
      final minimum = minLength;
      final measuredLength = allowWhitespace ? text.length : text.trim().length;
      if (minimum != null && measuredLength < minimum) {
        throw FormatException(
          '$entityType.$fieldName must contain at least $minimum '
          '${allowWhitespace ? '' : 'non-whitespace '}characters.',
        );
      }
      final maximum = maxLength;
      if (maximum != null && text.length > maximum) {
        throw FormatException(
          '$entityType.$fieldName cannot exceed $maximum characters.',
        );
      }
      if (allowedValues.isNotEmpty && !allowedValues.contains(text)) {
        throw FormatException(
          '$entityType.$fieldName is not one of its declared values.',
        );
      }
    }
    if (value case final num number) {
      final minimum = minValue;
      if (minimum != null && number < minimum) {
        throw FormatException(
          '$entityType.$fieldName cannot be less than $minimum.',
        );
      }
      final maximum = maxValue;
      if (maximum != null && number > maximum) {
        throw FormatException('$entityType.$fieldName cannot exceed $maximum.');
      }
    }
  }
}

final class EntityFieldDescriptor {
  const EntityFieldDescriptor({
    required this.name,
    required this.columnName,
    required this.kind,
    required this.nullable,
    required this.mutable,
    required this.conflictPolicy,
    this.sinceProtocolVersion = 1,
    this.renamedFrom,
    this.hasProtocolDefault = false,
    this.protocolDefault,
    this.inCreatePayload = true,
    this.reference,
    this.allowedTransitions = const [],
    this.constraints = const EntityFieldConstraints(),
    this.normalization = FieldNormalization.none,
  });

  final String name;
  final String columnName;
  final EntityFieldKind kind;
  final bool nullable;
  final bool mutable;
  final FieldConflictPolicy conflictPolicy;
  final int sinceProtocolVersion;
  final String? renamedFrom;
  final bool hasProtocolDefault;
  final Object? protocolDefault;
  final bool inCreatePayload;
  final EntityReferenceDescriptor? reference;
  final List<EntityValueTransition> allowedTransitions;
  final EntityFieldConstraints constraints;
  final FieldNormalization normalization;

  bool allowsTransition(Object? from, Object? to) =>
      from == to ||
      allowedTransitions.isEmpty ||
      allowedTransitions.any(
        (transition) => transition.from == from && transition.to == to,
      );

  bool get serverGenerated =>
      (!mutable &&
          !nullable &&
          name == EntityConventions.createdAtFieldName &&
          kind == EntityFieldKind.timestamp) ||
      (!mutable &&
          !nullable &&
          name == EntityConventions.serverVersionFieldName &&
          kind == EntityFieldKind.integer);

  bool get autoUpdated =>
      !mutable &&
      !nullable &&
      name == EntityConventions.updatedAtFieldName &&
      kind == EntityFieldKind.timestamp;

  String get sqliteType => switch (kind) {
    EntityFieldKind.boolean || EntityFieldKind.integer => 'INTEGER',
    EntityFieldKind.real => 'REAL',
    EntityFieldKind.text ||
    EntityFieldKind.uuid ||
    EntityFieldKind.date ||
    EntityFieldKind.timestamp => 'TEXT',
  };

  Object? toDatabase(Object? value) {
    final normalized = normalizeValue(value);
    if (normalized == null) return null;
    return switch (kind) {
      EntityFieldKind.boolean => (normalized as bool) ? 1 : 0,
      EntityFieldKind.real => switch (normalized) {
        final num number when number.isFinite => number.toDouble(),
        _ => throw FormatException(
          'Invalid finite real for $name.',
          normalized,
        ),
      },
      EntityFieldKind.timestamp =>
        normalized is DateTime
            ? normalized.toUtc().toIso8601String()
            : normalized,
      _ => normalized,
    };
  }

  Object? fromDatabase(Object? value) {
    if (value == null) return null;
    final decoded = switch (kind) {
      EntityFieldKind.boolean => switch (value) {
        0 || false => false,
        1 || true => true,
        _ => throw FormatException('Invalid SQLite boolean for $name.', value),
      },
      EntityFieldKind.real => switch (value) {
        final num number when number.isFinite => number.toDouble(),
        _ => throw FormatException('Invalid SQLite real for $name.', value),
      },
      EntityFieldKind.timestamp =>
        value is DateTime ? value.toUtc().toIso8601String() : value.toString(),
      _ => value,
    };
    return normalizeValue(decoded);
  }

  /// Applies the field's deterministic canonical representation.
  ///
  /// Generated entity APIs call the same normalizers before constructing
  /// domain values. Keeping the descriptor authoritative as well covers raw
  /// transport, database, and synchronization paths that operate without a
  /// generated field object.
  Object? normalizeValue(Object? value) {
    if (value == null) return null;
    return switch (normalization) {
      FieldNormalization.none => value,
      FieldNormalization.trim => normalizeTrimmedString(value as String),
      FieldNormalization.trimToNull => normalizeTrimmedStringToNull(
        value as String,
      ),
    };
  }

  Object? decodeWireValue(Object? value, {required String entityType}) {
    if ((constraints.hasTextRules && kind != EntityFieldKind.text) ||
        (constraints.hasNumericRules &&
            kind != EntityFieldKind.integer &&
            kind != EntityFieldKind.real)) {
      throw StateError('$entityType.$name has constraints for another type.');
    }
    if (value == null) {
      if (nullable) return null;
      throw FormatException('Non-null $entityType.$name cannot be null.');
    }
    final decoded = _decodeWireValue(
      kind,
      value,
      entityType: entityType,
      fieldName: name,
    );
    final normalized = normalizeValue(decoded);
    if (normalized == null) {
      if (nullable) return null;
      throw FormatException('Non-null $entityType.$name cannot be null.');
    }
    constraints.validate(normalized, entityType: entityType, fieldName: name);
    return normalized;
  }
}

Object _decodeWireValue(
  EntityFieldKind kind,
  Object value, {
  required String entityType,
  required String fieldName,
}) {
  return switch (kind) {
    EntityFieldKind.text when value is String => value,
    EntityFieldKind.uuid when value is String => parseLocalId<dynamic>(
      value,
    ).value,
    EntityFieldKind.boolean when value is bool => value,
    EntityFieldKind.integer
        when value is num && value.isFinite && value == value.truncate() =>
      value.toInt(),
    EntityFieldKind.real when value is num && value.isFinite =>
      value.toDouble(),
    EntityFieldKind.date when value is String => LocalDate.parse(value).value,
    EntityFieldKind.timestamp when value is String => DateTime.parse(
      value,
    ).toUtc().toIso8601String(),
    _ => throw FormatException('Invalid $entityType.$fieldName wire value.'),
  };
}

final class EntityValueTransition {
  const EntityValueTransition(this.from, this.to);

  final Object from;
  final Object to;
}

final class EntityReferenceDescriptor {
  const EntityReferenceDescriptor({
    required this.targetEntityType,
    required this.onDelete,
    this.composition = false,
    this.inverseCardinality,
  });

  final String targetEntityType;
  final ReferenceDeleteAction onDelete;
  final bool composition;
  final Cardinality? inverseCardinality;
}

abstract interface class GeneratedEntityRecord {
  String get generatedEntityType;

  String get generatedEntityId;

  String get generatedOwnerId;

  bool generatedHasParticipant(String principalId);

  ServerVersion get generatedServerVersion;

  int get generatedLocalRevision;

  JsonMap generatedCreateSnapshot();

  JsonMap generatedSnapshot();

  void generatedApplyRemote({
    required JsonMap fields,
    required ServerVersion serverVersion,
    required int localRevision,
  });
}

abstract interface class TypedGeneratedEntityRecord<E>
    implements GeneratedEntityRecord, GeneratedEntityAccess<E> {
  /// The domain view implemented by this generated persistence record.
  ///
  /// Dart cannot express an intersection bound such as `Record extends E &
  /// GeneratedEntityRecord`. This generated projection encodes that relation
  /// once and lets generic infrastructure remain cast-free.
  E get generatedDomain;
}

/// Record-only services exposed to generated extensions through the domain
/// entity's inherited [OwnedBy.generatedAccess] capability.
abstract interface class GeneratedEntityAccess<E> {
  int get generatedLocalRevision;

  GeneratedOrderedEntityAccess<E>? get generatedOrderAccess;

  D? resolveGeneratedReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> descriptor,
    String? entityId,
  );

  Future<void> recordGeneratedCommand(EntitySemanticCommand<E> command);

  Future<R> runGeneratedTransaction<R>(Future<R> Function() body);

  void validateGeneratedDraft();

  Future<void> applyGeneratedDraft({
    required TypedEntityPatch<E> base,
    required TypedEntityPatch<E> candidate,
  });

  Future<void> awaitGeneratedLocalCommit(int expectedRevision);
}

/// Record-only ordering services generated exclusively for [Ordered] entities.
abstract interface class GeneratedOrderedEntityAccess<E> {
  OrderRank get generatedOrderRank;

  /// Whether this record currently belongs to its canonical ordered scope.
  bool get generatedIsOrderMember;

  /// Stable identity of the canonical ordered scope containing this record.
  ///
  /// Generated records derive this from the active relationship source, the
  /// owner, or the bounded entity root. Infrastructure must never guess the
  /// scope from conventional field names because relationship-scoped ordering
  /// may use a different reference.
  String get generatedOrderScopeKey;

  /// Applies one optimistic generated rank and returns its durable bookkeeping.
  /// The caller must either record the returned change or invoke its rollback.
  GeneratedOrderStateChange<E>? prepareGeneratedOrderRank(OrderRank rank);

  Future<void> recordGeneratedOrderMove({
    required OrderRank rank,
    required MoveOrderedCommand<E> command,
  });

  Future<void> recordGeneratedExactOrder({
    required List<GeneratedOrderStateChange<E>> changes,
    required ReorderOrderedCommand<E> command,
  });
}

/// One prepared optimistic rank update owned by generated ordering code.
final class GeneratedOrderStateChange<E> {
  const GeneratedOrderStateChange({
    required this.entity,
    required this.scopeKey,
    required this.patch,
    required this.rollbackIfCurrent,
    required this.bindLocalCommit,
  });

  final TypedGeneratedEntityRecord<E> entity;
  final String scopeKey;
  final TypedEntityPatch<E> patch;
  final void Function() rollbackIfCurrent;
  final void Function(Future<LocalMutationCommitResult> commit) bindLocalCommit;
}

/// Prepared local state for one generated cross-scope ordered transfer.
final class GeneratedOrderTransferPlan<E> {
  GeneratedOrderTransferPlan({
    required this.rank,
    required this.sourceScopeKey,
    required this.targetScopeKey,
    required this.sourceScopeBaseVersion,
    required this.targetScopeBaseVersion,
    required Iterable<GeneratedOrderStateChange<E>> targetRebalanceChanges,
    required void Function() releasePreparedScopes,
  }) : targetRebalanceChanges = List.unmodifiable(targetRebalanceChanges),
       _releasePreparedScopes = releasePreparedScopes;

  final OrderRank rank;
  final String sourceScopeKey;
  final String targetScopeKey;
  final OrderScopeVersion sourceScopeBaseVersion;
  final OrderScopeVersion targetScopeBaseVersion;
  final List<GeneratedOrderStateChange<E>> targetRebalanceChanges;
  final void Function() _releasePreparedScopes;
  bool _released = false;

  void releasePreparedScopes() {
    if (_released) return;
    _released = true;
    _releasePreparedScopes();
  }

  void rollbackPreparedChanges() {
    for (final change in targetRebalanceChanges.reversed) {
      change.rollbackIfCurrent();
    }
    releasePreparedScopes();
  }
}

final class _GeneratedOrderMovePlan<E> {
  const _GeneratedOrderMovePlan({required this.target, required this.changes});

  final TypedGeneratedEntityRecord<E> target;
  final List<GeneratedOrderStateChange<E>> changes;

  void rollback() {
    for (final change in changes.reversed) {
      change.rollbackIfCurrent();
    }
  }
}

final class _GeneratedOrderCreatePlan<E> {
  const _GeneratedOrderCreatePlan({
    required this.rank,
    required this.scopeKey,
    required this.changes,
  });

  final OrderRank rank;
  final String scopeKey;
  final List<GeneratedOrderStateChange<E>> changes;

  void rollback() {
    for (final change in changes.reversed) {
      change.rollbackIfCurrent();
    }
  }
}

Map<String, List<CompositionDefinition>> _indexCompositions(
  Iterable<CompositionDefinition> compositions,
  String Function(CompositionDefinition composition) keyOf,
) {
  final mutable = <String, List<CompositionDefinition>>{};
  for (final composition in compositions) {
    (mutable[keyOf(composition)] ??= []).add(composition);
  }
  return Map.unmodifiable({
    for (final entry in mutable.entries)
      entry.key: List<CompositionDefinition>.unmodifiable(entry.value),
  });
}

final class _OrderedProjection<T extends TypedGeneratedEntityRecord<dynamic>> {
  const _OrderedProjection({
    required this.id,
    required this.fields,
    this.row,
    this.record,
  }) : assert(row != null || record != null);

  final String id;
  final JsonMap fields;
  final QueryRow? row;
  final T? record;
}

abstract interface class EntityMutationSink {
  String? get authenticatedPrincipalId;

  /// Whether writes are currently buffered by one graph transaction.
  /// Generated actions still bind their real durable commit, but must not
  /// await it from inside the transaction body that will schedule that batch.
  bool get isInMutationTransaction;

  Future<R> runEntityTransaction<R>(Future<R> Function() body);

  Future<LocalMutationCommitResult> recordEntityMutation<E>({
    required TypedGeneratedEntityRecord<E> entity,
    required TypedEntityPatch<E> patch,
    TypedEntityPatch<E>? syncPatch,
    SyncMutationOperation operation = SyncMutationOperation.patch,
    PushSyncWorkKind kind = PushSyncWorkKind.statePatch,
    ActivityOperation? activityOperation,
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  });

  Future<LocalMutationCommitResult> recordEntityCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    TypedEntityPatch<D>? localPatch,
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  });

  Future<LocalMutationCommitResult> recordEntityScopeCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    required List<GeneratedOrderStateChange<D>> stateChanges,
    required String scopeKey,
    DateTime? occurredAt,
  });

  E? resolveReference<E, R extends TypedGeneratedEntityRecord<E>>(
    EntityDescriptor<E, R> descriptor,
    String? entityId,
  );

  void validateDraftTarget(GeneratedEntityRecord entity);

  void validateMutationAuthorization({
    required GeneratedEntityRecord entity,
    required RlsOperation operation,
    required List<RlsPrincipal> principals,
  });
}

/// Optional mutation capability used only by entities whose canonical order
/// scope can change.
///
/// Keeping transfers separate from [EntityMutationSink] means ordinary entity
/// records, fixtures, and adapters do not implement APIs they can never use.
abstract interface class OrderedTransferMutationSink {
  Future<GeneratedOrderTransferPlan<D>> prepareEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntityPatch targetScope,
    required OrderedPlacement placement,
  });

  Future<LocalMutationCommitResult> recordEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required TransferOrderedCommand<D> command,
    required GeneratedOrderStateChange<D> transferChange,
    required List<GeneratedOrderStateChange<D>> targetRebalanceChanges,
    DateTime? occurredAt,
  });
}

abstract interface class EntityDescriptorBase {
  String get entityType;

  Cardinality get cardinality;

  String get tableName;

  String? get collaborationTableName;

  int get protocolVersion;

  List<EntityFieldDescriptor> get fields;

  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  );

  EntityIdentity<dynamic> parseIdentity(String source);

  GeneratedEntityRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  });
}

/// Generated capability metadata for an [ActivityTracked] source.
abstract interface class ActivityTrackedEntityDescriptor {
  String activityLabel(GeneratedEntityRecord entity);
}

/// Generated marker for an immutable [ActivityOf] entry descriptor.
abstract interface class ActivityEntryEntityDescriptor {}

/// Storage-independent metadata for a generated unique index.
final class EntityUniqueConstraint {
  const EntityUniqueConstraint({
    required this.name,
    required this.fieldNames,
    this.condition,
    this.unordered = false,
  });

  final String name;
  final List<String> fieldNames;
  final EntityUniqueConstraintCondition? condition;
  final bool unordered;
}

final class EntityUniqueConstraintCondition {
  const EntityUniqueConstraintCondition({
    required this.fieldName,
    required this.values,
  });

  final String fieldName;
  final List<Object?> values;

  bool matches(JsonMap record) =>
      values.any((value) => entityValuesEqual(record[fieldName], value));
}

/// Optional descriptor capability used by schema-less local transports.
abstract interface class EntityUniqueConstraintDescriptor {
  List<EntityUniqueConstraint> get uniqueConstraints;
}

/// Optional generated metadata for an entity carrying the [Ordered]
/// capability.
///
/// Backends use this contract to derive exactly the same canonical scope as
/// generated local collections. It deliberately consumes wire fields so the
/// metadata remains independent of a particular database adapter.
abstract interface class OrderedDescriptor {
  /// Persisted fields that form the canonical ordering-scope tuple, in tuple
  /// order. An empty list identifies the one complete root scope.
  List<EntityFieldDescriptor> get orderScopeFields;

  /// Generated equality constraints that define membership in a canonical
  /// ordered scope. Every ordered entity excludes tombstones; inferred active
  /// relationship entities additionally exclude inactive links.
  List<EntityFieldValueCondition> get orderMembershipConditions;

  String orderScopeKey(JsonMap fields);

  bool isOrderMember(JsonMap fields);
}

/// One generated, storage-independent equality condition.
///
/// Keeping the field descriptor beside its wire value lets local SQL adapters
/// bind the correct database representation without naming conventions while
/// schema-less adapters evaluate the same contract directly.
final class EntityFieldValueCondition {
  const EntityFieldValueCondition({required this.field, required this.value});

  final EntityFieldDescriptor field;
  final Object? value;

  bool matches(JsonMap fields) => entityValuesEqual(fields[field.name], value);
}

/// Storage-independent protocol contract for generated atomic entity actions.
final class ActionPolicy {
  const ActionPolicy({
    required this.actions,
    this.fixedInitialValues = const {},
  });

  final List<ActionDefinition> actions;
  final JsonMap fixedInitialValues;

  bool allowsCreate(JsonMap patch) => fixedInitialValues.entries.every(
    (entry) =>
        patch.containsKey(entry.key) &&
        entityValuesEqual(patch[entry.key], entry.value),
  );

  bool allowsPatch(JsonMap patch, JsonMap existing) {
    for (final fieldName in patch.keys) {
      var managed = false;
      var valid = false;
      for (final action in actions) {
        if (!action.guards(fieldName)) continue;
        managed = true;
        if (action.matches(patch, existing)) {
          valid = true;
          break;
        }
      }
      if (managed && !valid) {
        return false;
      }
    }
    return true;
  }
}

final class ActionDefinition {
  const ActionDefinition({
    required this.fieldNames,
    this.assignments = const [],
    this.guardedFieldNames,
  });

  final List<String> fieldNames;
  final List<ActionAssignment> assignments;

  /// Fields that activate this action's full-shape validation.
  ///
  /// `null` preserves the all-fields behavior for manually authored
  /// descriptors. Generated descriptors identify only action-exclusive fields
  /// so ordinary draft fields can also participate in a compound action.
  final List<String>? guardedFieldNames;

  bool guards(String fieldName) =>
      (guardedFieldNames ?? fieldNames).contains(fieldName);

  bool matches(JsonMap patch, JsonMap existing) =>
      fieldNames.every(patch.containsKey) &&
      assignments.every((assignment) => assignment.matches(patch, existing));
}

final class ActionAssignment {
  const ActionAssignment.literal(this.fieldName, this.value)
    : kind = ActionValueKind.literal,
      firstWriteOnly = false;

  const ActionAssignment.clockNow(this.fieldName, {this.firstWriteOnly = false})
    : value = null,
      kind = ActionValueKind.clockNow;

  const ActionAssignment.clear(this.fieldName)
    : value = null,
      kind = ActionValueKind.clear,
      firstWriteOnly = false;

  final String fieldName;
  final Object? value;
  final ActionValueKind kind;
  final bool firstWriteOnly;

  bool matches(JsonMap patch, JsonMap existing) => switch (kind) {
    ActionValueKind.literal => entityValuesEqual(patch[fieldName], value),
    ActionValueKind.clockNow =>
      patch[fieldName] != null &&
          (!firstWriteOnly ||
              existing[fieldName] == null ||
              entityValuesEqual(patch[fieldName], existing[fieldName])),
    ActionValueKind.clear => patch[fieldName] == null,
  };
}

abstract interface class ActionPolicyProvider {
  ActionPolicy get actionPolicy;
}

JsonMap upcastSyncOperation(
  EntityDescriptorBase descriptor,
  JsonMap operation,
) {
  final rawVersion = operation['protocolVersion'];
  final sourceVersion = switch (rawVersion) {
    final int value => value,
    final num value when value.isFinite && value == value.truncate() =>
      value.toInt(),
    _ => throw const RejectedSyncException.protocol(
      code: 'unsupported_protocol_version',
      message: 'A sync operation must contain an integer protocolVersion.',
    ),
  };
  if (sourceVersion < 1 || sourceVersion > descriptor.protocolVersion) {
    throw RejectedSyncException.protocol(
      code: 'unsupported_protocol_version',
      message:
          'Protocol $sourceVersion is not supported for '
          '${descriptor.entityType} (current ${descriptor.protocolVersion}).',
    );
  }
  if (sourceVersion == descriptor.protocolVersion) return operation;

  final upgraded = <String, Object?>{...operation};
  final patch = switch (operation['patch']) {
    final Map value => Map<String, Object?>.from(value),
    _ => throw const RejectedSyncException.validation(
      code: 'invalid_operation',
      message: 'A sync operation patch must be an object.',
    ),
  };
  upgraded['patch'] = patch;
  final isCreate = operation['operation'] == SyncMutationOperation.create.name;

  for (
    var version = sourceVersion + 1;
    version <= descriptor.protocolVersion;
    version++
  ) {
    for (final field in descriptor.fields) {
      if (field.sinceProtocolVersion != version) continue;
      final oldName = field.renamedFrom;
      if (oldName != null && patch.containsKey(oldName)) {
        patch.putIfAbsent(field.name, () => patch[oldName]);
        patch.remove(oldName);
      }
      if (isCreate && field.inCreatePayload && !patch.containsKey(field.name)) {
        if (field.hasProtocolDefault) {
          patch[field.name] = field.protocolDefault;
        } else if (field.nullable) {
          patch[field.name] = null;
        } else {
          throw RejectedSyncException.protocol(
            code: 'protocol_upcast_failed',
            message:
                'Protocol $version cannot synthesize required '
                '${descriptor.entityType}.${field.name}.',
          );
        }
      }
    }
    upgraded['protocolVersion'] = version;
  }
  return upgraded;
}

abstract interface class EntityDescriptor<
  E,
  T extends TypedGeneratedEntityRecord<E>
>
    implements EntityDescriptorBase {
  /// Requests an identity with the descriptor's domain entity as its nominal type.
  EntityIdentity<E> nextIdentity(EntityIdGenerator generator);

  @override
  T instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  });
}

final class LocalEntityEngine<E, T extends TypedGeneratedEntityRecord<E>>
    implements EntityMutationSink, OrderedTransferMutationSink {
  LocalEntityEngine._({
    required this.descriptor,
    required this.database,
    required SyncAdapter? backend,
    required this.clock,
    required this.idGenerator,
    required this.graphCoordinator,
  }) : _backend = backend;

  @override
  Future<R> runEntityTransaction<R>(Future<R> Function() body) =>
      graphCoordinator.transaction(body);

  @override
  Future<LocalMutationCommitResult> recordEntityCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    TypedEntityPatch<D>? localPatch,
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  }) => _recordEntityMutation(
    entity: entity,
    patch: localPatch ?? EntityPatch.fromWire(command.toWire()),
    operation: SyncMutationOperation.command,
    kind: PushSyncWorkKind.semanticCommand,
    semanticCommand: command,
    persistsEntityState: persistsEntityState,
    occurredAt: occurredAt,
    rollbackIfCurrent: rollbackIfCurrent,
  );

  @override
  Future<LocalMutationCommitResult> recordEntityScopeCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    required List<GeneratedOrderStateChange<D>> stateChanges,
    required String scopeKey,
    DateTime? occurredAt,
  }) {
    if (stateChanges.isEmpty) {
      throw ArgumentError.value(
        stateChanges,
        'stateChanges',
        'A semantic scope command must change local state.',
      );
    }
    if (scopeKey.isEmpty) {
      throw StateError(
        '${descriptor.entityType} recorded an ordered scope command without '
        'the Ordered capability.',
      );
    }
    for (final change in stateChanges) {
      final changedEntity = change.entity;
      if (!identical(
            _identityMap[changedEntity.generatedEntityId],
            changedEntity,
          ) ||
          change.scopeKey != scopeKey) {
        throw StateError(
          'Every ordered scope state change must belong to the same attached '
          '${descriptor.entityType} scope.',
        );
      }
    }
    final mutation = LocalEntityMutation(
      operationId: idGenerator.nextOperationId(),
      identity: descriptor.parseIdentity(entity.generatedEntityId),
      baseServerVersion: entity.generatedServerVersion,
      localRevision: entity.generatedLocalRevision,
      patch: EntityPatch.fromWire(const {}),
      createdAt: (occurredAt ?? clock.nowUtc()).toUtc(),
      operation: SyncMutationOperation.command,
      kind: PushSyncWorkKind.semanticCommand,
      semanticCommand: command,
      activityOperation: ActivityOperation.reordered,
      scopeStatePatches: [
        for (final change in stateChanges)
          LocalEntityStatePatch(
            identity: descriptor.parseIdentity(change.entity.generatedEntityId),
            localRevision: change.entity.generatedLocalRevision,
            patch: change.patch,
          ),
      ],
    );
    return _scheduleMutation(
      mutation,
      rollbackIfCurrent: () {
        for (final change in stateChanges.reversed) {
          change.rollbackIfCurrent();
        }
      },
    );
  }

  @override
  Future<GeneratedOrderTransferPlan<D>> prepareEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntityPatch targetScope,
    required OrderedPlacement placement,
  }) async {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw ArgumentError.value(
        placement,
        'placement',
        'Ordered transfer supports only first or last placement.',
      );
    }
    if (!identical(_identityMap[entity.generatedEntityId], entity)) {
      throw StateError(
        'Ordered transfer target does not belong to the '
        '${descriptor.entityType} engine.',
      );
    }
    final orderedDescriptor = switch (descriptor) {
      final OrderedDescriptor value => value,
      _ => throw StateError(
        '${descriptor.entityType} requested a scope transfer without the '
        'Ordered capability.',
      ),
    };
    final sourceSnapshot = entity.generatedSnapshot();
    final targetSnapshot = <String, Object?>{
      ...sourceSnapshot,
      ...targetScope.toWire(),
    };
    final sourceScopeKey = orderedDescriptor.orderScopeKey(sourceSnapshot);
    final targetScopeKey = orderedDescriptor.orderScopeKey(targetSnapshot);
    if (sourceScopeKey == targetScopeKey) {
      throw StateError('An ordered transfer must change its canonical scope.');
    }
    final release = await _acquireOrderScopes({sourceScopeKey, targetScopeKey});
    try {
      final currentSourceScopeKey = orderedDescriptor.orderScopeKey(
        entity.generatedSnapshot(),
      );
      if (currentSourceScopeKey != sourceScopeKey) {
        throw StateError(
          '${descriptor.entityType} changed ordered scope while its transfer '
          'was waiting for local scope lanes.',
        );
      }
      await _validateOrderTransferCycle(
        entity: entity,
        targetScope: targetScope,
        orderedDescriptor: orderedDescriptor,
      );

      final targetPlan = await _prepareIndexedOrderCreate(
        targetSnapshot,
        placement: placement,
      );
      final rebalanced = <GeneratedOrderStateChange<D>>[
        for (final change in targetPlan.changes)
          change as GeneratedOrderStateChange<D>,
      ];
      return GeneratedOrderTransferPlan(
        rank: targetPlan.rank,
        sourceScopeKey: sourceScopeKey,
        targetScopeKey: targetScopeKey,
        sourceScopeBaseVersion: orderScopeVersionFor(sourceScopeKey),
        targetScopeBaseVersion: orderScopeVersionFor(targetScopeKey),
        targetRebalanceChanges: rebalanced,
        releasePreparedScopes: release,
      );
    } catch (_) {
      release();
      rethrow;
    }
  }

  Future<void> _validateOrderTransferCycle<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntityPatch targetScope,
    required OrderedDescriptor orderedDescriptor,
  }) async {
    final recursive = orderedDescriptor.orderScopeFields
        .where(
          (field) =>
              targetScope.containsKey(field.name) &&
              field.reference?.targetEntityType == descriptor.entityType,
        )
        .toList(growable: false);
    if (recursive.isEmpty) return;
    if (recursive.length != 1) {
      throw StateError(
        '${descriptor.entityType} has more than one recursive transfer '
        'discriminator.',
      );
    }
    final field = recursive.single;
    var cursor = targetScope[field.name] as String?;
    final visited = <String>{};
    while (cursor != null && visited.add(cursor)) {
      if (cursor == entity.generatedEntityId) {
        throw EntityValidationException(
          entityType: descriptor.entityType,
          field: field.name,
          message: 'An ordered hierarchy transfer cannot create a cycle.',
        );
      }
      final loaded = _identityMap[cursor];
      if (loaded != null) {
        cursor = loaded.generatedSnapshot()[field.name] as String?;
        continue;
      }
      final row = await database
          .customSelect(
            'select ${field.columnName} from ${descriptor.tableName} where '
            '${EntityConventions.idColumnName} = ? and '
            '${EntityConventions.deletedAtColumnName} is null',
            variables: [Variable.withString(cursor)],
          )
          .getSingleOrNull();
      if (row == null) {
        throw EntityValidationException(
          entityType: descriptor.entityType,
          field: field.name,
          message: 'The ordered hierarchy target does not exist locally.',
        );
      }
      cursor = row.readNullable<String>(field.columnName);
    }
  }

  @override
  Future<LocalMutationCommitResult> recordEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required TransferOrderedCommand<D> command,
    required GeneratedOrderStateChange<D> transferChange,
    required List<GeneratedOrderStateChange<D>> targetRebalanceChanges,
    DateTime? occurredAt,
  }) {
    final targetScopeKey = transferChange.scopeKey;
    for (final change in targetRebalanceChanges) {
      if (change.scopeKey != targetScopeKey) {
        throw StateError(
          'Every destination rebalance must remain in the transfer target '
          'scope.',
        );
      }
    }
    final changes = [...targetRebalanceChanges, transferChange];
    final mutation = LocalEntityMutation(
      operationId: idGenerator.nextOperationId(),
      identity: descriptor.parseIdentity(entity.generatedEntityId),
      baseServerVersion: entity.generatedServerVersion,
      localRevision: entity.generatedLocalRevision,
      patch: EntityPatch.fromWire(const {}),
      createdAt: (occurredAt ?? clock.nowUtc()).toUtc(),
      operation: SyncMutationOperation.command,
      kind: PushSyncWorkKind.semanticCommand,
      semanticCommand: command,
      activityOperation: ActivityOperation.moved,
      scopeStatePatches: [
        for (final change in changes)
          LocalEntityStatePatch(
            identity: descriptor.parseIdentity(change.entity.generatedEntityId),
            localRevision: change.entity.generatedLocalRevision,
            patch: change.patch,
          ),
      ],
    );
    return _scheduleMutation(
      mutation,
      rollbackIfCurrent: () {
        for (final change in changes.reversed) {
          change.rollbackIfCurrent();
        }
      },
    );
  }

  @override
  D? resolveReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> targetDescriptor,
    String? entityId,
  ) {
    if (entityId == null) return null;
    return graphCoordinator._resolveReference(targetDescriptor, entityId);
  }

  @override
  void validateDraftTarget(GeneratedEntityRecord entity) {
    if (_closing || graphCoordinator._closed) {
      throw EntityDraftStateException(
        entityType: entity.generatedEntityType,
        entityId: entity.generatedEntityId,
        reason: EntityDraftFailureReason.entityGraphDisposed,
        message: 'The entity graph that created this draft is disposed.',
      );
    }
    if (!identical(_identityMap[entity.generatedEntityId], entity)) {
      throw EntityDraftStateException(
        entityType: entity.generatedEntityType,
        entityId: entity.generatedEntityId,
        reason: EntityDraftFailureReason.detached,
        message: 'The entity is no longer attached to its identity map.',
      );
    }
  }

  @override
  String get authenticatedPrincipalId =>
      graphCoordinator.authenticatedPrincipalId;

  @override
  bool get isInMutationTransaction => graphCoordinator._ownsCurrentTransaction;

  @override
  void validateMutationAuthorization({
    required GeneratedEntityRecord entity,
    required RlsOperation operation,
    required List<RlsPrincipal> principals,
  }) {
    final accountId = authenticatedPrincipalId;
    for (final principal in principals) {
      switch (principal) {
        case RlsPrincipal.owner:
          if (entity.generatedOwnerId == accountId) return;
          break;
        case RlsPrincipal.participant:
          if (entity.generatedHasParticipant(accountId)) return;
          break;
        case RlsPrincipal.authenticated:
          return;
        case RlsPrincipal.collaborator:
        case RlsPrincipal.reference:
        case RlsPrincipal.relationship:
          // These grants are revocable graph projections. Their canonical
          // authorization remains the generated remote policy, so local
          // validation must not reject an offline mutation from stale data.
          return;
      }
    }
    throw EntityAuthorizationException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      operation: operation,
    );
  }

  final EntityDescriptor<E, T> descriptor;
  final GeneratedDatabase database;
  final Clock clock;
  final EntityIdGenerator idGenerator;
  final LocalEntityGraphCoordinator graphCoordinator;
  final Map<String, OrderScopeVersion> _orderScopeVersions = {};
  final Map<String, Future<void>> _orderScopeOperationTails = {};

  OrderScopeVersion orderScopeVersionFor(String scopeKey) =>
      _orderScopeVersions[scopeKey] ?? OrderScopeVersion.zero;

  /// Applies one semantic ordered move using only indexed boundary/window
  /// reads. Unbounded scopes never need to be loaded into the identity map.
  Future<void> moveInGeneratedOrder({
    required String entityId,
    required OrderedPlacement placement,
    String? anchorId,
  }) async {
    if ((placement == OrderedPlacement.before ||
            placement == OrderedPlacement.after) !=
        (anchorId != null)) {
      throw ArgumentError.value(
        (placement, anchorId),
        'placement',
        'Before/after require one anchor; first/last forbid one.',
      );
    }
    if (entityId == anchorId) {
      throw EntityValidationException(
        entityType: descriptor.entityType,
        field: 'order',
        message: 'An entity cannot be its own ordering anchor.',
      );
    }
    final initial = await _activeOrderedProjection(entityId);
    final orderedDescriptor = _orderedDescriptor;
    final initialScopeKey = orderedDescriptor.orderScopeKey(initial.fields);
    await _withOrderScopeOperation(initialScopeKey, () async {
      final target = await _activeOrderedProjection(entityId);
      final scopeKey = orderedDescriptor.orderScopeKey(target.fields);
      if (scopeKey != initialScopeKey) {
        throw StateError(
          '${descriptor.entityType} changed ordered scope while a move was '
          'waiting for its local scope lane.',
        );
      }
      final anchor = anchorId == null
          ? null
          : await _activeOrderedProjection(anchorId);
      if (anchor != null &&
          orderedDescriptor.orderScopeKey(anchor.fields) != scopeKey) {
        throw EntityValidationException(
          entityType: descriptor.entityType,
          field: 'order',
          message: 'The ordering anchor is outside the canonical scope.',
        );
      }
      if (await _orderedMoveAlreadySatisfied(
        target: target,
        anchor: anchor,
        placement: placement,
      )) {
        return;
      }
      final plan = await _prepareIndexedOrderMove(
        target: target,
        anchor: anchor,
        placement: placement,
      );
      if (plan.changes.isEmpty) return;
      Future<LocalMutationCommitResult> commit;
      try {
        commit = recordEntityScopeCommand<E>(
          entity: plan.target,
          command: MoveOrderedCommand<E>(
            placement: placement,
            anchorId: anchorId == null ? null : parseLocalId<E>(anchorId),
            scopeBaseVersion: orderScopeVersionFor(scopeKey),
          ),
          stateChanges: plan.changes,
          scopeKey: scopeKey,
          occurredAt: clock.nowUtc(),
        );
        for (final change in plan.changes) {
          change.bindLocalCommit(commit);
        }
      } catch (_) {
        plan.rollback();
        rethrow;
      }
      if (!graphCoordinator._ownsCurrentTransaction) {
        (await commit).throwIfFailed();
      }
    });
  }

  /// Creates at one canonical boundary without loading an unbounded scope.
  /// Any rare rank repair and the create share one local durability boundary.
  Future<E> createInGeneratedOrder(
    JsonMap initialFields, {
    required List<RlsPrincipal> principals,
    LocalId<E>? id,
    required OrderedPlacement placement,
  }) async {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw ArgumentError.value(
        placement,
        'placement',
        'Ordered creation supports only first or last placement.',
      );
    }
    final scopeKey = _orderedDescriptor.orderScopeKey(initialFields);
    late E result;
    await _withOrderScopeOperation(scopeKey, () async {
      final plan = await _prepareIndexedOrderCreate(
        initialFields,
        placement: placement,
      );
      try {
        final created = _createRecord(
          {
            ...initialFields,
            EntityConventions.orderRankFieldName: plan.rank.value,
          },
          principals: principals,
          id: id,
          orderedPlacement: placement,
          relatedOrderChanges: plan.changes,
        );
        result = created.entity;
        if (!graphCoordinator._ownsCurrentTransaction) {
          (await created.commit).throwIfFailed();
        }
      } catch (_) {
        plan.rollback();
        rethrow;
      }
    });
    return result;
  }

  Future<_GeneratedOrderCreatePlan<E>> _prepareIndexedOrderCreate(
    JsonMap initialFields, {
    required OrderedPlacement placement,
  }) async {
    final first = placement == OrderedPlacement.first;
    final boundary = await _orderedBoundaryProjections(
      initialFields,
      first: first,
      limit: 1,
    );
    final boundaryRank = boundary.firstOrNull == null
        ? null
        : _orderRankFromProjection(boundary.first);
    OrderRank? directRank;
    try {
      directRank = first
          ? GeneratedOrderRanks.between(before: boundaryRank)
          : GeneratedOrderRanks.between(after: boundaryRank);
    } on ArgumentError {
      directRank = null;
    }
    final scopeKey = _orderedDescriptor.orderScopeKey(initialFields);
    if (directRank != null) {
      return _GeneratedOrderCreatePlan(
        rank: directRank,
        scopeKey: scopeKey,
        changes: const [],
      );
    }

    var windowSize = 8;
    while (true) {
      final rows = await _orderedBoundaryProjections(
        initialFields,
        first: first,
        limit: windowSize + 1,
      );
      final outside = rows.length > windowSize
          ? _orderRankFromProjection(rows[windowSize])
          : null;
      final selected = rows.take(windowSize).toList(growable: false);
      final orderedRows = first
          ? selected
          : selected.reversed.toList(growable: false);
      List<OrderRank>? ranks;
      try {
        ranks = GeneratedOrderRanks.allocate(
          count: orderedRows.length + 1,
          after: first ? null : outside,
          before: first ? outside : null,
        );
      } on ArgumentError {
        ranks = null;
      }
      if (ranks != null) {
        final changes = <GeneratedOrderStateChange<E>>[];
        try {
          for (final (index, projection) in orderedRows.indexed) {
            final rankIndex = first ? index + 1 : index;
            final record = _recordFromOrderedProjection(projection);
            final change = record.generatedOrderAccess!
                .prepareGeneratedOrderRank(ranks[rankIndex]);
            if (change != null) changes.add(change);
          }
        } catch (_) {
          for (final change in changes.reversed) {
            change.rollbackIfCurrent();
          }
          rethrow;
        }
        return _GeneratedOrderCreatePlan(
          rank: first ? ranks.first : ranks.last,
          scopeKey: scopeKey,
          changes: changes,
        );
      }
      if (rows.length <= windowSize || windowSize > 1 << 20) {
        throw const OrderRankSpaceExhaustedException();
      }
      windowSize *= 2;
    }
  }

  Future<List<_OrderedProjection<T>>> _orderedBoundaryProjections(
    JsonMap fields, {
    required bool first,
    required int limit,
  }) async {
    final rankField = descriptor.fields.singleWhere(
      (field) => field.name == EntityConventions.orderRankFieldName,
    );
    final conditions = <String>[];
    final variables = <Variable>[];
    _addOrderMembershipSql(conditions, variables);
    for (final field in _orderedDescriptor.orderScopeFields) {
      final value = field.toDatabase(fields[field.name]);
      if (value == null) {
        conditions.add('${field.columnName} is null');
      } else {
        conditions.add('${field.columnName} = ?');
        variables.add(_databaseVariable(field, value));
      }
    }
    final overlay = _transactionOrderedOverlay();
    variables.add(Variable.withInt(limit + overlay.length));
    final direction = first ? 'asc' : 'desc';
    final rows = await database
        .customSelect(
          'select * from ${descriptor.tableName} where '
          '${conditions.join(' and ')} order by ${rankField.columnName} '
          '$direction, ${EntityConventions.idColumnName} $direction limit ?',
          variables: variables,
        )
        .get();
    final projections =
        <String, _OrderedProjection<T>>{
              for (final row in rows)
                row.read<String>(EntityConventions.idColumnName):
                    _orderedProjectionFromRow(row),
              for (final projection in overlay) projection.id: projection,
            }.values
            .where((projection) {
              return _orderedDescriptor.isOrderMember(projection.fields) &&
                  _orderedDescriptor.orderScopeKey(projection.fields) ==
                      _orderedDescriptor.orderScopeKey(fields);
            })
            .toList(growable: false);
    projections.sort((left, right) {
      final compared = _compareOrderedProjections(left, right);
      return first ? compared : -compared;
    });
    return projections.take(limit).toList(growable: false);
  }

  OrderedDescriptor get _orderedDescriptor => switch (descriptor) {
    final OrderedDescriptor value => value,
    _ => throw StateError(
      '${descriptor.entityType} requested ordered infrastructure without the '
      'Ordered capability.',
    ),
  };

  void _addOrderMembershipSql(
    List<String> conditions,
    List<Variable<Object>> variables,
  ) {
    for (final condition in _orderedDescriptor.orderMembershipConditions) {
      final value = condition.field.toDatabase(condition.value);
      if (value == null) {
        conditions.add('${condition.field.columnName} is null');
      } else {
        conditions.add('${condition.field.columnName} = ?');
        variables.add(_databaseVariable(condition.field, value));
      }
    }
  }

  Future<void> _withOrderScopeOperation(
    String scopeKey,
    Future<void> Function() body,
  ) async {
    final release = await _acquireOrderScopes({scopeKey});
    try {
      await body();
    } finally {
      release();
    }
  }

  Future<void Function()> _acquireOrderScopes(Set<String> scopeKeys) async {
    final orderedKeys = scopeKeys.toList(growable: false)..sort();
    final predecessors = <Future<void>>[];
    final turn = Completer<void>();
    for (final scopeKey in orderedKeys) {
      final predecessor = _orderScopeOperationTails[scopeKey];
      if (predecessor != null) predecessors.add(predecessor);
      _orderScopeOperationTails[scopeKey] = turn.future;
    }
    await Future.wait(predecessors);
    var released = false;
    return () {
      if (released) return;
      released = true;
      turn.complete();
      for (final scopeKey in orderedKeys) {
        if (identical(_orderScopeOperationTails[scopeKey], turn.future)) {
          _orderScopeOperationTails.remove(scopeKey);
        }
      }
    };
  }

  Future<_OrderedProjection<T>> _activeOrderedProjection(String id) async {
    final overlay = _transactionOrderedOverlay()
        .where((projection) => projection.id == id)
        .firstOrNull;
    if (overlay != null) {
      if (_orderedDescriptor.isOrderMember(overlay.fields)) {
        return overlay;
      }
      throw EntityValidationException(
        entityType: descriptor.entityType,
        field: 'order',
        message: 'Ordered movement requires an active entity.',
      );
    }
    final conditions = <String>['${EntityConventions.idColumnName} = ?'];
    final variables = <Variable<Object>>[Variable.withString(id)];
    _addOrderMembershipSql(conditions, variables);
    final row = await database
        .customSelect(
          'select * from ${descriptor.tableName} where '
          '${conditions.join(' and ')}',
          variables: variables,
        )
        .getSingleOrNull();
    if (row == null) {
      throw EntityValidationException(
        entityType: descriptor.entityType,
        field: 'order',
        message: 'Ordered movement requires an active persisted entity.',
      );
    }
    return _orderedProjectionFromRow(row);
  }

  Future<bool> _orderedMoveAlreadySatisfied({
    required _OrderedProjection<T> target,
    required _OrderedProjection<T>? anchor,
    required OrderedPlacement placement,
  }) async {
    final rows = await _orderedSideProjections(
      target: target,
      anchor: anchor,
      placement: placement,
      left:
          placement == OrderedPlacement.last ||
          placement == OrderedPlacement.before,
      excludeTarget: false,
      limit: 1,
    );
    return rows.firstOrNull?.id == target.id;
  }

  Future<_GeneratedOrderMovePlan<E>> _prepareIndexedOrderMove({
    required _OrderedProjection<T> target,
    required _OrderedProjection<T>? anchor,
    required OrderedPlacement placement,
  }) async {
    final immediateLeft = await _orderedSideProjections(
      target: target,
      anchor: anchor,
      placement: placement,
      left: true,
      excludeTarget: true,
      limit: 1,
    );
    final immediateRight = await _orderedSideProjections(
      target: target,
      anchor: anchor,
      placement: placement,
      left: false,
      excludeTarget: true,
      limit: 1,
    );
    OrderRank? directRank;
    try {
      directRank = GeneratedOrderRanks.between(
        after: immediateLeft.firstOrNull == null
            ? null
            : _orderRankFromProjection(immediateLeft.first),
        before: immediateRight.firstOrNull == null
            ? null
            : _orderRankFromProjection(immediateRight.first),
      );
    } on ArgumentError {
      directRank = null;
    }
    if (directRank != null) {
      final targetRecord = _recordFromOrderedProjection(target);
      final change = targetRecord.generatedOrderAccess!
          .prepareGeneratedOrderRank(directRank);
      return _GeneratedOrderMovePlan(
        target: targetRecord,
        changes: change == null ? const [] : [change],
      );
    }
    var windowSize = 8;
    while (true) {
      final leftRows = await _orderedSideProjections(
        target: target,
        anchor: anchor,
        placement: placement,
        left: true,
        excludeTarget: true,
        limit: windowSize + 1,
      );
      final rightRows = await _orderedSideProjections(
        target: target,
        anchor: anchor,
        placement: placement,
        left: false,
        excludeTarget: true,
        limit: windowSize + 1,
      );
      final lowerOutside = leftRows.length > windowSize
          ? _orderRankFromProjection(leftRows[windowSize])
          : null;
      final upperOutside = rightRows.length > windowSize
          ? _orderRankFromProjection(rightRows[windowSize])
          : null;
      final leftWindow = leftRows.take(windowSize).toList(growable: false);
      final rightWindow = rightRows.take(windowSize).toList(growable: false);
      final orderedRows = <_OrderedProjection<T>>[
        ...leftWindow.reversed,
        target,
        ...rightWindow,
      ];
      List<OrderRank>? ranks;
      try {
        ranks = GeneratedOrderRanks.allocate(
          count: orderedRows.length,
          after: lowerOutside,
          before: upperOutside,
        );
      } on ArgumentError {
        ranks = null;
      }
      if (ranks != null) {
        final changes = <GeneratedOrderStateChange<E>>[];
        late TypedGeneratedEntityRecord<E> targetRecord;
        try {
          for (final (index, projection) in orderedRows.indexed) {
            final record = _recordFromOrderedProjection(projection);
            if (record.generatedEntityId == target.id) targetRecord = record;
            final change = record.generatedOrderAccess!
                .prepareGeneratedOrderRank(ranks[index]);
            if (change != null) changes.add(change);
          }
        } catch (_) {
          for (final change in changes.reversed) {
            change.rollbackIfCurrent();
          }
          rethrow;
        }
        return _GeneratedOrderMovePlan(target: targetRecord, changes: changes);
      }
      if (leftRows.length <= windowSize && rightRows.length <= windowSize) {
        throw const OrderRankSpaceExhaustedException();
      }
      if (windowSize > 1 << 20) {
        throw const OrderRankSpaceExhaustedException();
      }
      windowSize *= 2;
    }
  }

  Future<List<_OrderedProjection<T>>> _orderedSideProjections({
    required _OrderedProjection<T> target,
    required _OrderedProjection<T>? anchor,
    required OrderedPlacement placement,
    required bool left,
    required bool excludeTarget,
    required int limit,
  }) async {
    if ((placement == OrderedPlacement.first && left) ||
        (placement == OrderedPlacement.last && !left)) {
      return <_OrderedProjection<T>>[];
    }
    final rankField = descriptor.fields.singleWhere(
      (field) => field.name == EntityConventions.orderRankFieldName,
    );
    final conditions = <String>[];
    final variables = <Variable>[];
    _addOrderMembershipSql(conditions, variables);
    for (final field in _orderedDescriptor.orderScopeFields) {
      final value = field.toDatabase(target.fields[field.name]);
      if (value == null) {
        conditions.add('${field.columnName} is null');
      } else {
        conditions.add('${field.columnName} = ?');
        variables.add(_databaseVariable(field, value));
      }
    }
    if (excludeTarget) {
      conditions.add('${EntityConventions.idColumnName} <> ?');
      variables.add(Variable.withString(target.id));
    }
    if (anchor != null) {
      final operator = switch ((placement, left)) {
        (OrderedPlacement.before, true) => '<',
        (OrderedPlacement.before, false) => '>=',
        (OrderedPlacement.after, true) => '<=',
        (OrderedPlacement.after, false) => '>',
        _ => throw StateError('Boundary placement cannot have an anchor.'),
      };
      conditions.add(
        '(${rankField.columnName}, ${EntityConventions.idColumnName}) '
        '$operator (?, ?)',
      );
      variables
        ..add(Variable.withString(_orderRankFromProjection(anchor).value))
        ..add(Variable.withString(anchor.id));
    }
    final overlay = _transactionOrderedOverlay();
    variables.add(Variable.withInt(limit + overlay.length));
    final direction = left ? 'desc' : 'asc';
    final rows = await database
        .customSelect(
          'select * from ${descriptor.tableName} where '
          '${conditions.join(' and ')} order by ${rankField.columnName} '
          '$direction, ${EntityConventions.idColumnName} $direction limit ?',
          variables: variables,
        )
        .get();
    final scopeKey = _orderedDescriptor.orderScopeKey(target.fields);
    final projections =
        <String, _OrderedProjection<T>>{
              for (final row in rows)
                row.read<String>(EntityConventions.idColumnName):
                    _orderedProjectionFromRow(row),
              for (final projection in overlay) projection.id: projection,
            }.values
            .where((projection) {
              if (!_orderedDescriptor.isOrderMember(projection.fields) ||
                  _orderedDescriptor.orderScopeKey(projection.fields) !=
                      scopeKey ||
                  (excludeTarget && projection.id == target.id)) {
                return false;
              }
              if (anchor == null) return true;
              final compared = _compareOrderedProjections(projection, anchor);
              return switch ((placement, left)) {
                (OrderedPlacement.before, true) => compared < 0,
                (OrderedPlacement.before, false) => compared >= 0,
                (OrderedPlacement.after, true) => compared <= 0,
                (OrderedPlacement.after, false) => compared > 0,
                _ => throw StateError(
                  'Boundary placement cannot have an anchor.',
                ),
              };
            })
            .toList(growable: false);
    projections.sort((first, second) {
      final compared = _compareOrderedProjections(first, second);
      return left ? -compared : compared;
    });
    return projections.take(limit).toList(growable: false);
  }

  _OrderedProjection<T> _orderedProjectionFromRow(QueryRow row) =>
      _OrderedProjection<T>(
        id: row.read<String>(EntityConventions.idColumnName),
        fields: _fieldsFromRow(row.data),
        row: row,
      );

  _OrderedProjection<T> _orderedProjectionFromRecord(T record) =>
      _OrderedProjection<T>(
        id: record.generatedEntityId,
        fields: record.generatedSnapshot(),
        record: record,
      );

  List<_OrderedProjection<T>> _transactionOrderedOverlay() {
    if (!graphCoordinator._ownsCurrentTransaction) return const [];
    final pending = graphCoordinator._transactionBuffer;
    if (pending == null || pending.isEmpty) return const [];
    final ids = <String>{};
    for (final entry in pending) {
      final mutation = entry.mutation;
      if (mutation.entityType != descriptor.entityType) continue;
      ids.add(mutation.entityId);
      for (final patch in mutation.scopeStatePatches) {
        if (patch.identity.entityType == descriptor.entityType) {
          ids.add(patch.identity.rawId);
        }
      }
    }
    return <_OrderedProjection<T>>[
      for (final id in ids)
        if (_identityMap[id] case final record?)
          _orderedProjectionFromRecord(record),
    ];
  }

  int _compareOrderedProjections(
    _OrderedProjection<T> left,
    _OrderedProjection<T> right,
  ) {
    final byRank = _orderRankFromProjection(
      left,
    ).compareTo(_orderRankFromProjection(right));
    return byRank != 0 ? byRank : left.id.compareTo(right.id);
  }

  OrderRank _orderRankFromProjection(_OrderedProjection<T> projection) {
    final value = projection.fields[EntityConventions.orderRankFieldName];
    return switch (value) {
      final OrderRank rank => rank,
      final String raw => OrderRank.parse(raw),
      _ => throw StateError(
        '${descriptor.entityType} ordered projection has no generated rank.',
      ),
    };
  }

  T _recordFromOrderedProjection(_OrderedProjection<T> projection) =>
      projection.record ?? _materializeRow(projection.row!);

  LocalId<A> authenticatedOwnerId<A>() =>
      parseLocalId<A>(graphCoordinator.authenticatedPrincipalId);
  final ObservableList<E> _all = ObservableList<E>();
  late final ReadOnlyObservableList<E> all = ReadOnlyObservableList(_all);
  final ObservableMap<String, T> _identityMap = ObservableMap<String, T>();
  final Map<String, int> _identityRetainCounts = <String, int>{};
  final Set<String> _pendingWorkIdentityPins = <String>{};
  final Set<String> _persistedIds = <String>{};
  final StreamController<EntityProjectionChange<E>> _projectionChanges =
      StreamController<EntityProjectionChange<E>>.broadcast(sync: true);
  final SyncAdapter? _backend;
  SyncBindingDefinition get _syncBinding =>
      graphCoordinator.definition.syncBindingFor(descriptor.entityType);
  StreamSubscription<Set<TableUpdate>>? _databaseUpdateSubscription;
  int _projectionRefreshRequest = 0;
  bool _closing = false;

  static Future<LocalEntityEngine<E, T>>
  openInGraph<E, T extends TypedGeneratedEntityRecord<E>>({
    required EntityDescriptor<E, T> descriptor,
    required GeneratedDatabase database,
    required SyncAdapter? backend,
    required LocalEntityGraphCoordinator graphCoordinator,
    Clock clock = const SystemClock(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) => _open(
    descriptor: descriptor,
    database: database,
    backend: backend,
    clock: clock,
    idGenerator: idGenerator,
    graphCoordinator: graphCoordinator,
  );

  static Future<LocalEntityEngine<E, T>>
  _open<E, T extends TypedGeneratedEntityRecord<E>>({
    required EntityDescriptor<E, T> descriptor,
    required GeneratedDatabase database,
    required SyncAdapter? backend,
    required Clock clock,
    required EntityIdGenerator idGenerator,
    required LocalEntityGraphCoordinator graphCoordinator,
  }) async {
    final engine = LocalEntityEngine<E, T>._(
      descriptor: descriptor,
      database: database,
      backend: backend,
      clock: clock,
      idGenerator: idGenerator,
      graphCoordinator: graphCoordinator,
    );
    graphCoordinator._register(engine);
    try {
      await engine._initialize();
    } catch (_) {
      graphCoordinator._unregister(engine);
      rethrow;
    }
    return engine;
  }

  Stream<EntityProjectionChange<E>> get projectionChanges =>
      _projectionChanges.stream;

  Future<EntityLookupLease<E>?> loadRawId(
    String id, {
    bool refresh = false,
  }) async {
    if (_closing) throw StateError('The entity engine is closed.');
    if (!refresh) {
      final cached = _identityMap[id];
      if (cached != null) {
        _retainIdentity(id);
        return EntityLookupLease(
          cached.generatedDomain,
          () => _releaseIdentity(id),
        );
      }
    }
    var row = await _projectionRow(id);
    if (row == null || refresh) {
      final readsRemoteSnapshots =
          _syncBinding.mode == SyncMode.replicated ||
          _syncBinding.mode == SyncMode.imported;
      if (!readsRemoteSnapshots) {
        if (row == null) return null;
      } else {
        final loader = switch (_backend) {
          final SnapshotSyncAdapter value => value,
          _ => throw UnsupportedError(
            'The configured sync backend does not support entity lookup.',
          ),
        };
        final snapshot = await loader.fetchSnapshot(
          descriptor.parseIdentity(id),
        );
        if (snapshot == null) {
          if (row == null) return null;
          final purged = await database.transaction(
            () => _purgeMissingSnapshotIfSafe(id),
          );
          if (!purged) {
            row = await _projectionRow(id);
          } else {
            _persistedIds.remove(id);
            runInAction(() {
              final removed = _identityMap.remove(id);
              if (removed != null) _all.remove(removed.generatedDomain);
            });
            _notifyProjectionChanged(EntityProjectionChange<E>.membership());
            return null;
          }
        } else {
          final resolved = await database.transaction(
            () => _mergeRemoteIntoDatabase(
              identity: snapshot.identity,
              serverVersion: snapshot.serverVersion,
              fields: snapshot.fields,
            ),
          );
          row = await _projectionRow(id);
          if (resolved.inserted) {
            _notifyProjectionChanged(EntityProjectionChange<E>.membership());
          } else if (resolved.changedFieldNames.isNotEmpty) {
            _notifyProjectionChanged(
              EntityProjectionChange<E>._fromFieldNames(
                resolved.changedFieldNames,
              ),
            );
          }
        }
      }
    }
    if (row == null) return null;

    _retainIdentity(id);
    try {
      final entity = _materializeRow(row).generatedDomain;
      return EntityLookupLease(entity, () => _releaseIdentity(id));
    } catch (_) {
      _releaseIdentity(id);
      rethrow;
    }
  }

  Future<QueryRow?> _projectionRow(String id) => database
      .customSelect(
        'select * from ${descriptor.tableName} where '
        '${EntityConventions.idColumnName} = ?',
        variables: [Variable.withString(id)],
      )
      .getSingleOrNull();

  Future<bool> _purgeMissingSnapshotIfSafe(String id) async {
    final pending = await database
        .customSelect(
          "select 1 from local_entity_sync_work where direction = 'push' "
          "and entity_type = ? and entity_id = ? and status in "
          "('pending', 'processing', 'retryableFailure', 'conflict') limit 1",
          variables: [
            Variable.withString(descriptor.entityType),
            Variable.withString(id),
          ],
        )
        .getSingleOrNull();
    if (pending != null) return false;
    await database.customStatement(
      'delete from ${descriptor.tableName} where '
      '${EntityConventions.idColumnName} = ?',
      [id],
    );
    return true;
  }

  Future<EntityQueryPage<E>> loadQueryPage(
    EntityQuerySpec<E> spec, {
    required EntityQueryCursor? after,
    required int limit,
  }) async {
    if (limit <= 0) {
      throw RangeError.value(limit, 'limit', 'Must be greater than zero.');
    }
    final variables = <Variable>[];
    final predicate = _predicateSql(spec.where, variables);
    final continuation = _continuationSql(spec.orderBy, after, variables);
    final ordering = _orderSql(spec.orderBy);
    variables.add(Variable.withInt(limit + 1));
    final rows = await database
        .customSelect(
          'select * from ${descriptor.tableName} where ($predicate) '
          'and ($continuation) order by $ordering limit ?',
          variables: variables,
        )
        .get();
    if (_closing) {
      return EntityQueryPage<E>(items: const <Never>[], hasMore: false);
    }
    final items = <E>[];
    final retainedIds = <String>[];
    final visibleRows = rows.take(limit).toList(growable: false);
    for (final row in visibleRows) {
      final entity = _materializeRow(row);
      items.add(entity.generatedDomain);
      if (descriptor.cardinality == Cardinality.unbounded) {
        _retainIdentity(entity.generatedEntityId);
        retainedIds.add(entity.generatedEntityId);
      }
    }
    return EntityQueryPage(
      items: List<E>.unmodifiable(items),
      hasMore: rows.length > limit,
      nextCursor: visibleRows.isEmpty
          ? null
          : _queryCursor(spec.orderBy, visibleRows.last),
      release: retainedIds.isEmpty
          ? null
          : () {
              for (final id in retainedIds) {
                _releaseIdentity(id);
              }
            },
    );
  }

  String _predicateSql(
    EntityPredicate<E> predicate,
    List<Variable> variables,
  ) => predicate._accept(_EntityPredicateSqlWriter(this, variables));

  String _comparisonSql(
    String fieldName,
    EntityComparison comparison,
    Object? expected,
    List<Variable> variables,
  ) {
    final field = _field(fieldName);
    if (expected == null) {
      return '${field.columnName} is '
          '${comparison == EntityComparison.equal ? '' : 'not '}null';
    }
    variables.add(_queryVariable(field, expected));
    final operator = switch (comparison) {
      EntityComparison.equal => '=',
      EntityComparison.notEqual => '<>',
      EntityComparison.lessThan => '<',
      EntityComparison.lessThanOrEqual => '<=',
      EntityComparison.greaterThan => '>',
      EntityComparison.greaterThanOrEqual => '>=',
    };
    return '${field.columnName} $operator ?';
  }

  String _membershipSql(
    String fieldName,
    List<Object?> expected,
    List<Variable> variables,
  ) {
    if (expected.isEmpty) return '0';
    final field = _field(fieldName);
    final includesNull = expected.contains(null);
    final nonNull = expected.whereType<Object>().toList(growable: false);
    for (final value in nonNull) {
      variables.add(_queryVariable(field, value));
    }
    final membership = nonNull.isEmpty
        ? null
        : '${field.columnName} in '
              '(${List.filled(nonNull.length, '?').join(', ')})';
    if (!includesNull) return membership!;
    if (membership == null) return '${field.columnName} is null';
    return '($membership or ${field.columnName} is null)';
  }

  String _orderSql(EntityOrder<E>? order) {
    if (order == null) return '${EntityConventions.idColumnName} asc';
    final field = _field(order.fieldName);
    final direction = order.direction == EntitySortDirection.ascending
        ? 'asc'
        : 'desc';
    final parts = <String>[];
    if (field.nullable) {
      parts.add(
        '(${field.columnName} is null) '
        '${order.nulls == NullPlacement.first ? 'desc' : 'asc'}',
      );
    }
    parts.add('${field.columnName} $direction');
    if (field.columnName != EntityConventions.idColumnName) {
      parts.add('${EntityConventions.idColumnName} $direction');
    }
    return parts.join(', ');
  }

  String _continuationSql(
    EntityOrder<E>? order,
    EntityQueryCursor? after,
    List<Variable> variables,
  ) {
    if (after == null) return '1 = 1';
    if (after is! _DriftEntityQueryCursor ||
        after.entityType != descriptor.entityType ||
        after.fieldName != order?.fieldName ||
        after.direction != order?.direction ||
        after.nulls != order?.nulls) {
      throw ArgumentError('Query cursor does not belong to this query.');
    }
    final idColumn = EntityConventions.idColumnName;
    if (order == null) {
      variables.add(Variable.withString(after.entityId));
      return '$idColumn > ?';
    }
    final field = _field(order.fieldName);
    final column = field.columnName;
    final comparison = order.direction == EntitySortDirection.ascending
        ? '>'
        : '<';
    if (column == idColumn) {
      variables.add(Variable.withString(after.entityId));
      return '$column $comparison ?';
    }
    if (after.fieldValue == null) {
      variables.add(Variable.withString(after.entityId));
      final sameNullGroup = '$column is null and $idColumn $comparison ?';
      return order.nulls == NullPlacement.first
          ? '(($sameNullGroup) or $column is not null)'
          : '($sameNullGroup)';
    }
    variables
      ..add(_databaseVariable(field, after.fieldValue!))
      ..add(_databaseVariable(field, after.fieldValue!))
      ..add(Variable.withString(after.entityId));
    final withinGroup =
        '$column $comparison ? or ($column = ? and $idColumn $comparison ?)';
    if (!field.nullable) return '($withinGroup)';
    return order.nulls == NullPlacement.last
        ? '(($column is not null and ($withinGroup)) or $column is null)'
        : '($column is not null and ($withinGroup))';
  }

  _DriftEntityQueryCursor _queryCursor(EntityOrder<E>? order, QueryRow row) {
    final field = order == null ? null : _field(order.fieldName);
    return _DriftEntityQueryCursor(
      entityType: descriptor.entityType,
      fieldName: order?.fieldName,
      direction: order?.direction,
      nulls: order?.nulls,
      fieldValue: field == null ? null : row.data[field.columnName],
      entityId: row.read<String>(EntityConventions.idColumnName),
    );
  }

  EntityFieldDescriptor _field(String name) => descriptor.fields.singleWhere(
    (candidate) => candidate.name == name,
    orElse: () => throw StateError(
      'Query references unknown ${descriptor.entityType} field `$name`.',
    ),
  );

  Variable _queryVariable(EntityFieldDescriptor field, Object value) {
    final encoded = field.toDatabase(value);
    return _databaseVariable(field, encoded!);
  }

  Variable _databaseVariable(EntityFieldDescriptor field, Object encoded) {
    return switch (field.kind) {
      EntityFieldKind.boolean ||
      EntityFieldKind.integer => Variable.withInt(encoded as int),
      EntityFieldKind.real => Variable.withReal(encoded as double),
      EntityFieldKind.text ||
      EntityFieldKind.uuid ||
      EntityFieldKind.date ||
      EntityFieldKind.timestamp => Variable.withString(encoded as String),
    };
  }

  E? byRawId(String id) => _identityMap[id]?.generatedDomain;

  /// Bridges a stable MobX identity into stream-based composition boundaries.
  ///
  /// The generated snapshot read tracks every observable persisted field, so
  /// subscribers receive the same entity instance when it materializes,
  /// changes locally, merges remotely, or disappears.
  Stream<E?> watchRawId(String id) => Stream.multi((controller) {
    _retainIdentity(id);
    ReactionDisposer? disposeReaction;
    var cancelled = false;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _releaseIdentity(id);
    }

    controller.onCancel = () {
      cancelled = true;
      disposeReaction?.call();
      release();
    };
    try {
      disposeReaction = autorun((_) {
        final record = _identityMap[id];
        record?.generatedSnapshot();
        controller.addSync(record?.generatedDomain);
      });
      if (cancelled) disposeReaction.call();
    } catch (_) {
      release();
      rethrow;
    }
  });

  /// Materializes an on-demand identity and retains it for one subscription.
  ///
  /// The reactive retain is acquired before loading starts, so releasing the
  /// temporary lookup lease can never evict the identity between load and the
  /// first observer notification. Cancellation suppresses late load errors.
  Stream<E?> watchLoadedRawId(String id) => Stream.multi((controller) {
    var active = true;
    final subscription = watchRawId(
      id,
    ).listen(controller.addSync, onError: controller.addErrorSync);
    unawaited(() async {
      EntityLookupLease<E>? lease;
      try {
        lease = await loadRawId(id);
      } catch (error, stackTrace) {
        if (active) controller.addErrorSync(error, stackTrace);
      } finally {
        lease?.release();
      }
    }());
    controller.onCancel = () async {
      active = false;
      await subscription.cancel();
    };
  });

  E requireRawId(String id) {
    final entity = byRawId(id);
    if (entity == null) {
      throw EntityNotFoundException(
        entityType: descriptor.entityType,
        entityId: id,
      );
    }
    return entity;
  }

  LocalId<E> allocateId() => descriptor.nextIdentity(idGenerator).id;

  /// Optimistically creates one stable identity and resolves it only after its
  /// exact local projection/queue commit succeeds.
  ///
  /// Inside an entity-graph transaction the returned future resolves
  /// immediately after registration because the outer transaction is the sole
  /// durability boundary and cannot schedule its batch until the body returns.
  Future<E> create(
    JsonMap initialFields, {
    required List<RlsPrincipal> principals,
    LocalId<E>? id,
    OrderedPlacement? orderedPlacement,
  }) async {
    final created = _createRecord(
      initialFields,
      principals: principals,
      id: id,
      orderedPlacement: orderedPlacement,
    );
    if (!graphCoordinator._ownsCurrentTransaction) {
      (await created.commit).throwIfFailed();
    }
    return created.entity;
  }

  ({E entity, Future<LocalMutationCommitResult> commit}) _createRecord(
    JsonMap initialFields, {
    required List<RlsPrincipal> principals,
    LocalId<E>? id,
    OrderedPlacement? orderedPlacement,
    List<GeneratedOrderStateChange<E>> relatedOrderChanges = const [],
  }) {
    final rawId = id?.value ?? descriptor.nextIdentity(idGenerator).rawId;
    final mutationTime = clock.nowUtc();
    final fields = <String, Object?>{
      ...initialFields,
      EntityConventions.idFieldName: rawId,
      EntityConventions.serverVersionFieldName: 0,
      for (final field in descriptor.fields)
        if (field.name == EntityConventions.createdAtFieldName &&
            field.serverGenerated &&
            field.kind == EntityFieldKind.timestamp)
          field.name: mutationTime.toIso8601String(),
      for (final field in descriptor.fields)
        if (field.autoUpdated) field.name: mutationTime.toIso8601String(),
      for (final field in descriptor.fields)
        if (!field.inCreatePayload &&
            field.hasProtocolDefault &&
            !initialFields.containsKey(field.name))
          field.name: field.protocolDefault,
    };
    final entity = descriptor.instantiate(
      mutationSink: this,
      clock: clock,
      fields: fields,
      localRevision: 1,
    );
    validateMutationAuthorization(
      entity: entity,
      operation: RlsOperation.insert,
      principals: principals,
    );
    final orderedCreate = orderedPlacement == null
        ? null
        : _orderedCreateIntent(fields, orderedPlacement);
    runInAction(() {
      _identityMap[rawId] = entity;
      _all.add(entity.generatedDomain);
    });

    late final Future<LocalMutationCommitResult> commit;
    try {
      commit = _recordEntityMutation(
        entity: entity,
        patch: EntityPatch.fromWire(entity.generatedSnapshot()),
        syncPatch: EntityPatch.fromWire(entity.generatedCreateSnapshot()),
        operation: SyncMutationOperation.create,
        orderedCreate: orderedCreate,
        scopeStatePatches: [
          for (final change in relatedOrderChanges)
            LocalEntityStatePatch(
              identity: descriptor.parseIdentity(
                change.entity.generatedEntityId,
              ),
              localRevision: change.entity.generatedLocalRevision,
              patch: change.patch,
            ),
        ],
        rollbackIfCurrent: () {
          if (entity.generatedLocalRevision == 1) {
            _identityMap.remove(rawId);
            _all.remove(entity.generatedDomain);
          }
          for (final change in relatedOrderChanges.reversed) {
            change.rollbackIfCurrent();
          }
        },
      );
      for (final change in relatedOrderChanges) {
        change.bindLocalCommit(commit);
      }
    } catch (_) {
      _identityMap.remove(rawId);
      _all.remove(entity.generatedDomain);
      for (final change in relatedOrderChanges.reversed) {
        change.rollbackIfCurrent();
      }
      rethrow;
    }
    return (entity: entity.generatedDomain, commit: commit);
  }

  OrderedCreateIntent _orderedCreateIntent(
    JsonMap fields,
    OrderedPlacement placement,
  ) {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw ArgumentError.value(
        placement,
        'orderedPlacement',
        'Ordered creation supports only first or last placement.',
      );
    }
    final orderedDescriptor = switch (descriptor) {
      final OrderedDescriptor value => value,
      _ => throw StateError(
        '${descriptor.entityType} requested ordered creation without the '
        'Ordered capability.',
      ),
    };
    final scopeKey = orderedDescriptor.orderScopeKey(fields);
    return OrderedCreateIntent(
      placement: placement,
      scopeBaseVersion: orderScopeVersionFor(scopeKey),
    );
  }

  @override
  Future<LocalMutationCommitResult> recordEntityMutation<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required TypedEntityPatch<D> patch,
    TypedEntityPatch<D>? syncPatch,
    SyncMutationOperation operation = SyncMutationOperation.patch,
    PushSyncWorkKind kind = PushSyncWorkKind.statePatch,
    ActivityOperation? activityOperation,
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  }) => _recordEntityMutation(
    entity: entity,
    patch: patch,
    syncPatch: syncPatch,
    operation: operation,
    kind: kind,
    activityOperation: activityOperation,
    persistsEntityState: persistsEntityState,
    occurredAt: occurredAt,
    rollbackIfCurrent: rollbackIfCurrent,
  );

  Future<LocalMutationCommitResult> _recordEntityMutation({
    required GeneratedEntityRecord entity,
    required EntityPatch patch,
    EntityPatch? syncPatch,
    SyncMutationOperation operation = SyncMutationOperation.patch,
    PushSyncWorkKind kind = PushSyncWorkKind.statePatch,
    EntitySemanticCommand<dynamic>? semanticCommand,
    ActivityOperation? activityOperation,
    OrderedCreateIntent? orderedCreate,
    List<LocalEntityStatePatch> scopeStatePatches = const [],
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  }) {
    final entityId = entity.generatedEntityId;
    if (!identical(_identityMap[entityId], entity)) {
      throw StateError(
        'Mutation target does not belong to the ${descriptor.entityType} engine.',
      );
    }
    final mutation = LocalEntityMutation(
      operationId: idGenerator.nextOperationId(),
      identity: descriptor.parseIdentity(entityId),
      baseServerVersion: entity.generatedServerVersion,
      localRevision: entity.generatedLocalRevision,
      patch: patch,
      syncPatch: syncPatch,
      createdAt: (occurredAt ?? clock.nowUtc()).toUtc(),
      operation: operation,
      kind: kind,
      semanticCommand: semanticCommand,
      activityOperation: activityOperation,
      orderedCreate: orderedCreate,
      persistsEntityState: persistsEntityState,
      suppressOutboundIntent:
          Zone.current[_relationshipOutboundSuppressionZoneKey] ==
          graphCoordinator,
      scopeStatePatches: scopeStatePatches,
    );
    return _scheduleMutation(mutation, rollbackIfCurrent: rollbackIfCurrent);
  }

  Future<LocalMutationCommitResult> _scheduleMutation(
    LocalEntityMutation mutation, {
    required void Function() rollbackIfCurrent,
  }) {
    if (descriptor.cardinality == Cardinality.unbounded) {
      _pendingWorkIdentityPins.add(mutation.entityId);
      _persistedIds.add(mutation.entityId);
    }
    _retainIdentity(mutation.entityId);
    void settled() {
      _releaseIdentity(mutation.entityId);
      unawaited(_refreshPendingIdentityPins());
    }

    return graphCoordinator._recordMutation(
      mutation,
      rollbackIfCurrent: rollbackIfCurrent,
      onSettled: settled,
    );
  }

  void _retainIdentity(String id) {
    if (descriptor.cardinality == Cardinality.bounded) return;
    _identityRetainCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
    _persistedIds.add(id);
  }

  void _releaseIdentity(String id) {
    if (descriptor.cardinality == Cardinality.bounded) return;
    final count = _identityRetainCounts[id];
    if (count == null) return;
    if (count > 1) {
      _identityRetainCounts[id] = count - 1;
      return;
    }
    _identityRetainCounts.remove(id);
    _evictIdentityIfUnused(id);
  }

  void _evictIdentityIfUnused(String id) {
    if (descriptor.cardinality == Cardinality.bounded ||
        _identityRetainCounts.containsKey(id) ||
        _pendingWorkIdentityPins.contains(id)) {
      return;
    }
    _persistedIds.remove(id);
    runInAction(() {
      final removed = _identityMap.remove(id);
      if (removed != null) _all.remove(removed.generatedDomain);
    });
  }

  Future<void> _refreshPendingIdentityPins() async {
    if (descriptor.cardinality == Cardinality.bounded || _closing) return;
    final rows = await database
        .customSelect(
          "select distinct entity_id from local_entity_sync_work "
          "where direction = 'push' and entity_type = ? and status in "
          "('pending', 'processing', 'retryableFailure', 'conflict')",
          variables: [Variable.withString(descriptor.entityType)],
        )
        .get();
    if (_closing) return;
    final next = rows.map((row) => row.read<String>('entity_id')).toSet();
    final released = _pendingWorkIdentityPins.difference(next);
    _pendingWorkIdentityPins
      ..clear()
      ..addAll(next);
    _persistedIds.addAll(next);
    for (final id in released) {
      _evictIdentityIfUnused(id);
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _projectionChanges.close();
    await _databaseUpdateSubscription?.cancel();
  }

  Future<void> _initialize() async {
    await database.customSelect('select 1').get();
    await _refreshPendingIdentityPins();
    if (descriptor.cardinality == Cardinality.bounded) {
      final rows = await database
          .customSelect(
            'select * from ${descriptor.tableName} '
            'order by ${EntityConventions.idColumnName}',
          )
          .get();
      runInAction(() {
        for (final row in rows) {
          final fields = _fieldsFromRow(row.data);
          final entity = descriptor.instantiate(
            mutationSink: this,
            clock: clock,
            fields: fields,
            localRevision: row.read<int>('local_revision'),
          );
          _identityMap[entity.generatedEntityId] = entity;
          _persistedIds.add(entity.generatedEntityId);
          _all.add(entity.generatedDomain);
        }
      });
    } else {
      final rows = await _readRetainedProjectionRows();
      for (final row in rows) {
        _materializeRow(row);
      }
    }
    _databaseUpdateSubscription = database
        .tableUpdates(TableUpdateQuery.onTableName(descriptor.tableName))
        .listen(_handleDatabaseUpdates);
  }

  void _handleDatabaseUpdates(Set<TableUpdate> updates) {
    if (_closing || graphCoordinator._closed) return;
    if (updates.any((update) => update.table == descriptor.tableName)) {
      _runInBackground(_refreshProjectionFromDatabase());
    }
  }

  Future<void> _refreshProjectionFromDatabase() async {
    final request = ++_projectionRefreshRequest;
    final rows = await _readRetainedProjectionRows();
    if (request != _projectionRefreshRequest || _closing) return;
    final databaseIds = <String>{};
    runInAction(() {
      for (final row in rows) {
        final id = row.read<String>(EntityConventions.idColumnName);
        final localRevision = row.read<int>('local_revision');
        databaseIds.add(id);
        final existing = _identityMap[id];
        if (existing == null) {
          final entity = descriptor.instantiate(
            mutationSink: this,
            clock: clock,
            fields: _fieldsFromRow(row.data),
            localRevision: localRevision,
          );
          _identityMap[id] = entity;
          _all.add(entity.generatedDomain);
          continue;
        }
        if (localRevision < existing.generatedLocalRevision) continue;
        existing.generatedApplyRemote(
          fields: _fieldsFromRow(row.data),
          serverVersion: parseServerVersion(
            row.read<int>(EntityConventions.serverVersionColumnName),
          ),
          localRevision: localRevision,
        );
      }
      for (final removedId in _persistedIds.difference(databaseIds)) {
        final removed = _identityMap.remove(removedId);
        if (removed != null) _all.remove(removed.generatedDomain);
      }
      _persistedIds
        ..clear()
        ..addAll(databaseIds);
    });
    _notifyProjectionChanged(EntityProjectionChange<E>.unknown());
  }

  Future<List<QueryRow>> _readRetainedProjectionRows() async {
    if (descriptor.cardinality == Cardinality.bounded) {
      return database
          .customSelect(
            'select * from ${descriptor.tableName} '
            'order by ${EntityConventions.idColumnName}',
          )
          .get();
    }
    final retainedIds = _persistedIds.toList(growable: false);
    if (retainedIds.isEmpty) return const [];
    final rows = <QueryRow>[];
    const chunkSize = 400;
    for (var start = 0; start < retainedIds.length; start += chunkSize) {
      final end = math.min(start + chunkSize, retainedIds.length);
      final chunk = retainedIds.sublist(start, end);
      rows.addAll(
        await database
            .customSelect(
              'select * from ${descriptor.tableName} where '
              '${EntityConventions.idColumnName} in '
              '(${List.filled(chunk.length, '?').join(', ')})',
              variables: chunk.map(Variable.withString).toList(),
            )
            .get(),
      );
    }
    return rows;
  }

  T _materializeRow(QueryRow row) {
    final id = row.read<String>(EntityConventions.idColumnName);
    final localRevision = row.read<int>('local_revision');
    late T result;
    runInAction(() {
      final existing = _identityMap[id];
      if (existing == null) {
        result = descriptor.instantiate(
          mutationSink: this,
          clock: clock,
          fields: _fieldsFromRow(row.data),
          localRevision: localRevision,
        );
        _identityMap[id] = result;
        _all.add(result.generatedDomain);
      } else {
        result = existing;
        if (localRevision >= existing.generatedLocalRevision) {
          existing.generatedApplyRemote(
            fields: _fieldsFromRow(row.data),
            serverVersion: parseServerVersion(
              row.read<int>(EntityConventions.serverVersionColumnName),
            ),
            localRevision: localRevision,
          );
        }
      }
      if (descriptor.cardinality == Cardinality.bounded) {
        _persistedIds.add(id);
      }
    });
    return result;
  }

  Future<void> _persistMutationInCurrentTransaction(
    LocalEntityMutation mutation,
  ) async {
    if (mutation.scopeStatePatches.isNotEmpty &&
        mutation.operation == SyncMutationOperation.command) {
      await _updateLocalStatePatches(mutation.scopeStatePatches);
      if (!mutation.suppressOutboundIntent) {
        await _coalescePushWork(mutation);
      }
      return;
    }
    final persistsEntityState =
        mutation.kind != PushSyncWorkKind.semanticCommand ||
        mutation.persistsEntityState;
    final existing = !persistsEntityState
        ? null
        : await database
              .customSelect(
                'select ${EntityConventions.idColumnName} from ${descriptor.tableName} '
                'where ${EntityConventions.idColumnName} = ?',
                variables: [Variable.withString(mutation.entityId)],
              )
              .getSingleOrNull();

    if (persistsEntityState) {
      if (existing == null) {
        await _insertEntity(mutation);
      } else {
        await _updateEntity(mutation);
      }
    }
    if (mutation.scopeStatePatches.isNotEmpty) {
      await _updateLocalStatePatches(mutation.scopeStatePatches);
    }
    if (!mutation.suppressOutboundIntent) {
      await _coalescePushWork(mutation);
    }
  }

  Future<void> _updateLocalStatePatches(
    List<LocalEntityStatePatch> statePatches,
  ) async {
    final identities = <String>{};
    final touchedFieldNames = <String>{};
    for (final statePatch in statePatches) {
      if (statePatch.identity.entityType != descriptor.entityType) {
        throw StateError(
          'A local scope command cannot persist another entity type.',
        );
      }
      if (!identities.add(statePatch.identity.rawId)) {
        throw StateError('A local scope command repeated one identity.');
      }
      touchedFieldNames.addAll(
        statePatch.patch.entries.map((entry) => entry.key),
      );
    }
    // Reserve headroom under SQLite's conventional 999-variable limit. Each
    // member needs two variables per touched field, two for its revision, and
    // one for the final membership predicate.
    final variablesPerMember = touchedFieldNames.length * 2 + 3;
    final chunkSize = math.min(150, math.max(1, 900 ~/ variablesPerMember));
    for (var start = 0; start < statePatches.length; start += chunkSize) {
      final end = math.min(start + chunkSize, statePatches.length);
      final chunk = statePatches.sublist(start, end);
      final assignments = <String>[];
      final values = <Object?>[];
      for (final field in descriptor.fields) {
        final changes = [
          for (final statePatch in chunk)
            if (statePatch.patch.containsKey(field.name)) statePatch,
        ];
        if (changes.isEmpty) continue;
        final cases = StringBuffer('case ${EntityConventions.idColumnName} ');
        for (final statePatch in changes) {
          cases.write('when ? then ? ');
          values
            ..add(statePatch.identity.rawId)
            ..add(field.toDatabase(statePatch.patch[field.name]));
        }
        cases.write('else ${field.columnName} end');
        assignments.add('${field.columnName} = $cases');
      }
      final revisionCases = StringBuffer(
        'case ${EntityConventions.idColumnName} ',
      );
      for (final statePatch in chunk) {
        revisionCases.write('when ? then ? ');
        values
          ..add(statePatch.identity.rawId)
          ..add(statePatch.localRevision);
      }
      revisionCases.write('else local_revision end');
      assignments.add('local_revision = $revisionCases');
      values.addAll(chunk.map((patch) => patch.identity.rawId));
      final updated = await database.customUpdate(
        'update ${descriptor.tableName} set ${assignments.join(', ')} '
        'where ${EntityConventions.idColumnName} in '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: values.map(Variable.new).toList(),
      );
      if (updated != chunk.length) {
        throw StateError(
          'An ordered scope command referenced an unpersisted member.',
        );
      }
    }
  }

  EntityProjectionChange<E>? _projectionChangeFor(
    LocalEntityMutation mutation,
  ) {
    if (mutation.operation == SyncMutationOperation.create ||
        mutation.operation == SyncMutationOperation.delete) {
      return EntityProjectionChange<E>.membership();
    }
    if (mutation.scopeStatePatches.isNotEmpty) {
      return EntityProjectionChange<E>._fromFieldNames({
        for (final statePatch in mutation.scopeStatePatches)
          for (final entry in statePatch.patch.entries) entry.key,
      });
    }
    final persistsEntityState =
        mutation.kind != PushSyncWorkKind.semanticCommand ||
        mutation.persistsEntityState;
    if (!persistsEntityState) return null;
    if (mutation.patch.isEmpty) return null;
    return EntityProjectionChange<E>._fromFieldNames(
      mutation.patch.entries.map((entry) => entry.key),
    );
  }

  Future<void> _insertEntity(LocalEntityMutation mutation) async {
    final columnNames = <String>[];
    final values = <Object?>[];
    for (final field in descriptor.fields) {
      if (!mutation.patch.containsKey(field.name) && !field.nullable) {
        throw StateError('Creation is missing required field `${field.name}`.');
      }
      columnNames.add(field.columnName);
      values.add(field.toDatabase(mutation.patch[field.name]));
    }
    columnNames.add('local_revision');
    values.add(mutation.localRevision);
    await database.customStatement(
      'insert into ${descriptor.tableName} (${columnNames.join(', ')}) '
      'values (${List.filled(values.length, '?').join(', ')})',
      values,
    );
  }

  Future<void> _updateEntity(LocalEntityMutation mutation) async {
    final assignments = <String>[];
    final values = <Object?>[];
    for (final entry in mutation.patch.entries) {
      final field = descriptor.fields.singleWhere(
        (candidate) => candidate.name == entry.key,
        orElse: () => throw StateError('Unknown field `${entry.key}`.'),
      );
      assignments.add('${field.columnName} = ?');
      values.add(field.toDatabase(entry.value));
    }
    assignments.add('local_revision = ?');
    values
      ..add(mutation.localRevision)
      ..add(mutation.entityId);
    await database.customStatement(
      'update ${descriptor.tableName} set ${assignments.join(', ')} '
      'where ${EntityConventions.idColumnName} = ?',
      values,
    );
  }

  Future<void> _coalescePushWork(LocalEntityMutation mutation) async {
    final target = switch (_syncBinding) {
      SyncBindingDefinition(mode: SyncMode.localOnly) => null,
      SyncBindingDefinition(mode: SyncMode.imported) => throw StateError(
        '${descriptor.entityType} is an imported read projection and cannot '
        'produce local mutations.',
      ),
      SyncBindingDefinition(:final target?) => target,
      _ => throw StateError(
        '${descriptor.entityType} has no resolved push sync target.',
      ),
    };
    if (target == null) return;
    final existing =
        mutation.kind == PushSyncWorkKind.statePatch &&
            descriptor is! ActivityTrackedEntityDescriptor
        ? await database
              .customSelect(
                "select * from local_entity_sync_work where direction = 'push' "
                "and sync_target = ? and kind = 'statePatch' "
                "and entity_type = ? and entity_id = ? "
                "and status = 'pending' order by id desc limit 1",
                variables: [
                  Variable.withString(target.wireName),
                  Variable.withString(descriptor.entityType),
                  Variable.withString(mutation.entityId),
                ],
              )
              .getSingleOrNull()
        : null;
    final currentProtocolVersion = descriptor.protocolVersion;
    final operation = _operationForMutation(
      mutation,
      protocolVersion: currentProtocolVersion,
    );

    if (existing == null) {
      await _insertPushWork(target, mutation, operation);
      return;
    }

    final existingOperation = _decodePushOperation(
      descriptor,
      upcastSyncOperation(
        descriptor,
        _decodeMap(existing.read<String>('payload')),
      ),
      definition: graphCoordinator.definition,
    );
    final mergedPatch = <String, Object?>{
      ...existingOperation.patch.toWire(),
      ...(mutation.syncPatch ?? mutation.patch).toWire(),
    };
    if (_mustPreserveCreateBoundary(
      existingOperation,
      mutation.syncPatch ?? mutation.patch,
      mergedPatch,
    )) {
      await _insertPushWork(target, mutation, operation);
      return;
    }
    final mergedOperation = _copyPushOperation(
      existingOperation,
      localRevision: mutation.localRevision,
      patch: EntityPatch.fromWire(mergedPatch),
    );
    await database.customStatement(
      'update local_entity_sync_work set local_revision = ?, '
      'protocol_version = ?, payload = ? '
      'where id = ?',
      [
        mutation.localRevision,
        currentProtocolVersion,
        jsonEncode(mergedOperation.toWire()),
        existing.read<int>('id'),
      ],
    );
  }

  bool _mustPreserveCreateBoundary(
    PushOperation existing,
    EntityPatch nextPatch,
    JsonMap mergedPatch,
  ) {
    if (existing is! CreatePushOperation) return false;
    final next = nextPatch.toWire();
    for (final field in descriptor.fields) {
      if (field.allowedTransitions.isEmpty || !next.containsKey(field.name)) {
        continue;
      }
      if (!entityValuesEqual(existing.patch[field.name], next[field.name])) {
        return true;
      }
    }
    final actionPolicy = switch (descriptor) {
      ActionPolicyProvider provider => provider.actionPolicy,
      _ => null,
    };
    return actionPolicy != null && !actionPolicy.allowsCreate(mergedPatch);
  }

  Future<void> _insertPushWork(
    SyncTargetId target,
    LocalEntityMutation mutation,
    PushOperation operation,
  ) => database.customStatement(
    'insert into local_entity_sync_work '
    '(sync_target, direction, kind, status, entity_type, entity_id, operation_id, '
    'base_server_version, local_revision, protocol_version, payload, '
    'attempt_count, created_at) '
    "values (?, 'push', ?, 'pending', ?, ?, ?, ?, ?, ?, ?, 0, ?)",
    [
      target.wireName,
      mutation.kind.name,
      mutation.entityType,
      mutation.entityId,
      mutation.operationId.value,
      mutation.baseServerVersion.value,
      mutation.localRevision,
      operation.protocolVersion,
      jsonEncode(operation.toWire()),
      mutation.createdAt.millisecondsSinceEpoch,
    ],
  );

  void _rememberOrderScopeVersion(PushResult result) {
    if (result.orderScopeVersions.isEmpty) return;
    final orderedDescriptor = switch (descriptor) {
      final OrderedDescriptor value => value,
      _ => throw StateError(
        '${descriptor.entityType} returned an ordered-scope version without '
        'generated Ordered metadata.',
      ),
    };
    for (final receipt in result.orderScopeVersions) {
      final scopeKey = orderedDescriptor.orderScopeKey(receipt.scope);
      final current = _orderScopeVersions[scopeKey];
      if (current == null || receipt.version.value > current.value) {
        _orderScopeVersions[scopeKey] = receipt.version;
      }
    }
  }

  Future<void> _purgeRevokedEntity(String entityId) async {
    await database.customStatement(
      'delete from local_entity_sync_work where entity_type = ? and entity_id = ?',
      [descriptor.entityType, entityId],
    );
    await database.customStatement(
      'delete from ${descriptor.tableName} where ${EntityConventions.idColumnName} = ?',
      [entityId],
    );
  }

  Future<SyncFailureOutcome> _handleFailureForThisEntity(
    PushSyncWorkItem item,
    Object error, {
    bool refreshQueue = true,
  }) async {
    List<_RejectedProjection> rejectedProjections = const [];
    final outcome = await database.transaction(() async {
      final typed = error is SyncBackendException
          ? error
          : RetryableSyncException(
              code: 'unexpected_error',
              message: error.toString(),
            );
      final nextAttemptCount = item.attemptCount + 1;
      if (typed.kind == SyncFailureKind.rejected) {
        await _storeTerminalFailure(
          item,
          status: SyncWorkStatus.rejected,
          failure: typed,
        );
        rejectedProjections = await _reconstructAfterRejection(item);
        return const SyncFailureOutcome(continueDraining: true);
      }
      if (typed.kind == SyncFailureKind.conflict) {
        if (nextAttemptCount >= 3) {
          await _storeTerminalFailure(
            item,
            status: SyncWorkStatus.conflict,
            failure: typed,
          );
          return const SyncFailureOutcome(continueDraining: true);
        }
        await database.customStatement(
          "update local_entity_sync_work set status = 'retryableFailure', "
          "attempt_count = ?, lease_until = null, next_attempt_at = null, "
          "last_error_code = ?, last_error_detail = ? where id = ?",
          [nextAttemptCount, typed.code, typed.message, item.id],
        );
        if (item.direction == SyncDirection.push) {
          await graphCoordinator._schedulePullInCurrentTransaction(item.target);
        }
        return const SyncFailureOutcome(continueDraining: true);
      }
      final retryAt = clock.nowUtc().add(
        _syncRetryDelay(item.id, nextAttemptCount),
      );
      await database.customStatement(
        "update local_entity_sync_work set status = 'retryableFailure', "
        "attempt_count = ?, lease_until = null, next_attempt_at = ?, "
        "last_error_code = ?, last_error_detail = ? where id = ?",
        [
          nextAttemptCount,
          retryAt.millisecondsSinceEpoch,
          typed.code,
          typed.message,
          item.id,
        ],
      );
      return SyncFailureOutcome(continueDraining: false, retryAt: retryAt);
    });
    EntityProjectionChange<E>? projectionChange;
    for (final projection in rejectedProjections) {
      final change =
          projection.fields == null ||
              !_identityMap.containsKey(projection.entityId)
          ? EntityProjectionChange<E>.membership()
          : projection.changedFieldNames.isEmpty
          ? null
          : EntityProjectionChange<E>._fromFieldNames(
              projection.changedFieldNames,
            );
      _applyRejectedProjection(projection);
      if (change != null) {
        projectionChange = projectionChange?._merge(change) ?? change;
      }
    }
    if (projectionChange != null) _notifyProjectionChanged(projectionChange);
    if (refreshQueue) await graphCoordinator.refreshSyncWork();
    return outcome;
  }

  Future<List<_RejectedProjection>> _reconstructAfterRejection(
    PushSyncWorkItem rejected,
  ) async {
    final operation = rejected.operation;
    if (!operation.persistsEntityState && operation is CommandPushOperation) {
      return const [];
    }
    final entityIds =
        operation is CommandPushOperation &&
            operation.scopeStatePatches.isNotEmpty
        ? operation.scopeStatePatches
              .map((statePatch) => statePatch.identity.rawId)
              .toList(growable: false)
        : [operation.identity.rawId];
    final projections = <_RejectedProjection>[];
    for (final entityId in entityIds) {
      final projection = await _reconstructIdentityAfterRejection(
        rejected,
        entityId,
      );
      if (projection != null) projections.add(projection);
    }
    return projections;
  }

  Future<_RejectedProjection?> _reconstructIdentityAfterRejection(
    PushSyncWorkItem rejected,
    String entityId,
  ) async {
    final operation = rejected.operation;
    final row = await database
        .customSelect(
          'select * from ${descriptor.tableName} '
          'where ${EntityConventions.idColumnName} = ?',
          variables: [Variable.withString(entityId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final acceptedJson = row.readNullable<String>('accepted_snapshot');
    if (acceptedJson == null) {
      final relationshipCreate = operation is CommandPushOperation
          ? operation.scopeStatePatches
                .where(
                  (statePatch) =>
                      statePatch.identity.rawId == entityId &&
                      statePatch.operation == LocalEntityStateOperation.create,
                )
                .firstOrNull
          : null;
      if (operation is! CreatePushOperation && relationshipCreate == null) {
        return null;
      }
      await database.customStatement(
        "update local_entity_sync_work set status = 'rejected', "
        "attempt_count = attempt_count + 1, lease_until = null, "
        "next_attempt_at = null, last_error_code = 'dependency_rejected', "
        "last_error_detail = 'The entity create operation was rejected.' "
        "where id <> ? and direction = 'push' and entity_type = ? "
        "and entity_id = ? and status <> 'rejected'",
        [rejected.id, descriptor.entityType, entityId],
      );
      await database.customStatement(
        'delete from ${descriptor.tableName} '
        'where ${EntityConventions.idColumnName} = ?',
        [entityId],
      );
      return _RejectedProjection.removed(entityId);
    }

    final accepted = _decodeMap(acceptedJson);
    final persistedFieldNames = descriptor.fields
        .map((field) => field.name)
        .toSet();
    final pendingRows = await database
        .customSelect(
          "select kind, entity_id, payload from local_entity_sync_work "
          "where id <> ? and direction = 'push' and entity_type = ? "
          "and (entity_id = ? or kind = 'semanticCommand') and status in "
          "('pending', 'processing', 'retryableFailure', 'conflict') "
          "order by id",
          variables: [
            Variable.withInt(rejected.id),
            Variable.withString(descriptor.entityType),
            Variable.withString(entityId),
          ],
        )
        .get();
    final rebuilt = JsonMap.of(accepted);
    for (final pendingRow in pendingRows) {
      final kind = SyncWorkKind.values.byName(pendingRow.read<String>('kind'));
      final pendingPayload = _decodeMap(pendingRow.read<String>('payload'));
      final patch = _pendingLocalStatePatch(
        kind: kind,
        primaryEntityId: pendingRow.read<String>('entity_id'),
        payload: pendingPayload,
        entityId: entityId,
      );
      if (patch == null) continue;
      for (final entry in patch.entries) {
        if (persistedFieldNames.contains(entry.key)) {
          rebuilt[entry.key] = entry.value;
        }
      }
    }
    final localRevision = row.read<int>('local_revision');
    final current = _fieldsFromRow(row.data);
    final changedFieldNames = {
      for (final field in descriptor.fields)
        if (rebuilt.containsKey(field.name) &&
            current[field.name] != rebuilt[field.name])
          field.name,
    };
    await _updateResolved(entityId, rebuilt, acceptedFields: accepted);
    return _RejectedProjection.updated(
      entityId,
      rebuilt,
      localRevision: localRevision,
      changedFieldNames: changedFieldNames,
    );
  }

  void _applyRejectedProjection(_RejectedProjection projection) {
    runInAction(() {
      final fields = projection.fields;
      if (fields == null) {
        final removed = _identityMap.remove(projection.entityId);
        if (removed != null) _all.remove(removed.generatedDomain);
        return;
      }
      final serverVersion = fields[EntityConventions.serverVersionFieldName];
      final acceptedServerVersion = parseServerVersion(serverVersion);
      final existing = _identityMap[projection.entityId];
      if (existing != null) {
        existing.generatedApplyRemote(
          fields: fields,
          serverVersion: acceptedServerVersion,
          localRevision: projection.localRevision,
        );
        return;
      }
      if (descriptor.cardinality == Cardinality.unbounded) return;
      final entity = descriptor.instantiate(
        mutationSink: this,
        clock: clock,
        fields: fields,
        localRevision: projection.localRevision,
      );
      _identityMap[projection.entityId] = entity;
      _all.add(entity.generatedDomain);
    });
  }

  Future<void> _storeTerminalFailure(
    SyncWorkItem item, {
    required SyncWorkStatus status,
    required SyncBackendException failure,
  }) {
    return database.customStatement(
      'update local_entity_sync_work set status = ?, attempt_count = ?, '
      'lease_until = null, next_attempt_at = null, last_error_code = ?, '
      'last_error_detail = ? where id = ?',
      [
        status.name,
        item.attemptCount + 1,
        failure.code,
        failure.message,
        item.id,
      ],
    );
  }

  Future<_MergedRemoteProjection> _mergeRemoteIntoDatabase({
    required EntityIdentity<dynamic> identity,
    required ServerVersion serverVersion,
    required RemoteEntityFields fields,
  }) async {
    final row = await database
        .customSelect(
          'select * from ${descriptor.tableName} where ${EntityConventions.idColumnName} = ?',
          variables: [Variable.withString(identity.rawId)],
        )
        .getSingleOrNull();
    final pendingRows = await database
        .customSelect(
          "select * from local_entity_sync_work where direction = 'push' "
          "and entity_type = ? "
          "and (entity_id = ? or kind = 'semanticCommand') and status in "
          "('pending', 'processing', 'retryableFailure') order by id",
          variables: [
            Variable.withString(descriptor.entityType),
            Variable.withString(identity.rawId),
          ],
        )
        .get();
    if (row != null &&
        serverVersion.value <
            row.read<int>(EntityConventions.serverVersionColumnName)) {
      return _MergedRemoteProjection(
        fields: _fieldsFromRow(row.data),
        inserted: false,
        changedFieldNames: const {},
        ignored: true,
      );
    }
    final accepted = <String, Object?>{
      ...fields.toWire(),
      EntityConventions.idFieldName: identity.rawId,
      EntityConventions.serverVersionFieldName: serverVersion.value,
    };
    final resolved = JsonMap.of(accepted);
    final persistedFieldNames = descriptor.fields
        .map((field) => field.name)
        .toSet();
    final policies = {
      for (final field in descriptor.fields) field.name: field.conflictPolicy,
    };
    for (final pendingRow in pendingRows) {
      final kind = SyncWorkKind.values.byName(pendingRow.read<String>('kind'));
      final pendingPayload = _decodeMap(pendingRow.read<String>('payload'));
      if (kind == SyncWorkKind.statePatch) {
        if (pendingRow.read<String>('entity_id') != identity.rawId) continue;
        final patch = _decodeMap(pendingPayload['patch']);
        final resolution = mergeRemoteFields(
          visibleFields: resolved,
          pendingPatch: patch,
          remoteFields: fields.toWire(),
          policies: policies,
          remoteVersion: serverVersion,
          pendingBaseVersion: ServerVersion(
            pendingRow.read<int>('base_server_version'),
          ),
        );
        final rebasedPatch = resolution.rebasedPendingPatch;
        resolved
          ..clear()
          ..addAll(resolution.visibleFields);
        resolved.removeWhere(
          (field, _) => !persistedFieldNames.contains(field),
        );
        if (rebasedPatch.isEmpty) {
          await database.customStatement(
            'delete from local_entity_sync_work where id = ?',
            [pendingRow.read<int>('id')],
          );
        } else if (rebasedPatch.length != patch.length) {
          await database.customStatement(
            'update local_entity_sync_work set payload = ? where id = ?',
            [
              jsonEncode({...pendingPayload, 'patch': rebasedPatch}),
              pendingRow.read<int>('id'),
            ],
          );
        }
        continue;
      }
      final commandStatePatch = _pendingLocalStatePatch(
        kind: kind,
        primaryEntityId: pendingRow.read<String>('entity_id'),
        payload: pendingPayload,
        entityId: identity.rawId,
      );
      if (commandStatePatch == null) continue;
      for (final entry in commandStatePatch.entries) {
        if (persistedFieldNames.contains(entry.key)) {
          resolved[entry.key] = entry.value;
        }
      }
    }

    if (row == null) {
      await _insertResolved(resolved, acceptedFields: accepted);
    } else {
      await _updateResolved(identity.rawId, resolved, acceptedFields: accepted);
    }
    await _rebaseFirstPendingPush(identity.rawId, serverVersion);
    final previousFields = row == null ? null : _fieldsFromRow(row.data);
    return _MergedRemoteProjection(
      fields: resolved,
      inserted: row == null,
      changedFieldNames: previousFields == null
          ? const {}
          : {
              for (final field in descriptor.fields)
                if (resolved.containsKey(field.name) &&
                    previousFields[field.name] != resolved[field.name])
                  field.name,
            },
    );
  }

  JsonMap? _pendingLocalStatePatch({
    required SyncWorkKind kind,
    required String primaryEntityId,
    required JsonMap payload,
    required String entityId,
  }) {
    if (kind != SyncWorkKind.semanticCommand) return null;
    final operation = payload['operation'];
    if (operation == SyncMutationOperation.command.name) {
      final rawScopePatches = payload['localStatePatches'];
      if (rawScopePatches is List) {
        for (final rawPatch in rawScopePatches) {
          final statePatch = _decodeMap(rawPatch);
          if (statePatch['entityId'] == entityId) {
            return _decodeMap(statePatch['patch']);
          }
        }
      }
      if (primaryEntityId == entityId &&
          payload['persistsEntityState'] == true &&
          payload['statePatch'] != null) {
        return _decodeMap(payload['statePatch']);
      }
      return null;
    }
    if (primaryEntityId == entityId && payload['persistsEntityState'] == true) {
      return _decodeMap(payload['patch']);
    }
    return null;
  }

  Future<void> _rebaseFirstPendingPush(
    String entityId,
    ServerVersion serverVersion,
  ) async {
    final row = await database
        .customSelect(
          "select id, base_server_version, payload from local_entity_sync_work "
          "where direction = 'push' "
          "and entity_type = ? and entity_id = ? and status in "
          "('pending', 'processing', 'retryableFailure') order by id limit 1",
          variables: [
            Variable.withString(descriptor.entityType),
            Variable.withString(entityId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return;
    if (serverVersion.value <= row.read<int>('base_server_version')) return;
    final payload = <String, Object?>{
      ..._decodeMap(row.read<String>('payload')),
      'baseServerVersion': serverVersion.value,
    };
    await database.customStatement(
      'update local_entity_sync_work set base_server_version = ?, payload = ? '
      'where id = ?',
      [serverVersion.value, jsonEncode(payload), row.read<int>('id')],
    );
  }

  Future<void> _insertResolved(
    JsonMap fields, {
    required JsonMap acceptedFields,
  }) async {
    final columns = [
      ...descriptor.fields.map((field) => field.columnName),
      'local_revision',
      'accepted_snapshot',
    ];
    final values = <Object?>[
      for (final field in descriptor.fields)
        field.toDatabase(fields[field.name]),
      0,
      jsonEncode(acceptedFields),
    ];
    await database.customStatement(
      'insert into ${descriptor.tableName} (${columns.join(', ')}) '
      'values (${List.filled(values.length, '?').join(', ')})',
      values,
    );
  }

  Future<void> _updateResolved(
    String id,
    JsonMap fields, {
    required JsonMap acceptedFields,
  }) async {
    final assignments = <String>[];
    final values = <Object?>[];
    for (final field in descriptor.fields) {
      if (!fields.containsKey(field.name)) continue;
      assignments.add('${field.columnName} = ?');
      values.add(field.toDatabase(fields[field.name]));
    }
    assignments.add('accepted_snapshot = ?');
    values.add(jsonEncode(acceptedFields));
    values.add(id);
    await database.customStatement(
      'update ${descriptor.tableName} set ${assignments.join(', ')} '
      'where ${EntityConventions.idColumnName} = ?',
      values,
    );
  }

  void _applyResolved(RemoteEntityChange change, JsonMap fields) {
    runInAction(() {
      final existing = _identityMap[change.identity.rawId];
      if (existing != null) {
        existing.generatedApplyRemote(
          fields: fields,
          serverVersion: change.serverVersion,
          localRevision: existing.generatedLocalRevision,
        );
        return;
      }
      if (descriptor.cardinality == Cardinality.unbounded) return;
      final entity = descriptor.instantiate(
        mutationSink: this,
        clock: clock,
        fields: fields,
        localRevision: 0,
      );
      _identityMap[change.identity.rawId] = entity;
      _all.add(entity.generatedDomain);
    });
  }

  JsonMap _fieldsFromRow(Map<String, Object?> row) {
    return {
      for (final field in descriptor.fields)
        field.name: field.fromDatabase(row[field.columnName]),
    };
  }

  void _runInBackground(Future<void> work) {
    graphCoordinator._runInBackground(
      work,
      task: LocalEntityBackgroundTask.projectionRefresh,
      entityType: descriptor.entityType,
    );
  }

  void _notifyProjectionChanged(EntityProjectionChange<E> change) {
    if (!_closing && !_projectionChanges.isClosed) {
      _projectionChanges.add(change);
    }
  }

  void _notifyErasedProjectionChanged(EntityProjectionChange<dynamic> change) {
    _notifyProjectionChanged(
      change.isUnknown
          ? EntityProjectionChange<E>.unknown()
          : change.affectsMembership
          ? EntityProjectionChange<E>.membership()
          : EntityProjectionChange<E>._fromFieldNames(change._fieldNames),
    );
  }
}

/// Owns the one queue plus independent target workers, cursors, signal
/// subscriptions, and database lifecycle for one account graph.
final class LocalEntityGraphCoordinator
    implements SyncQueueHost, SyncPersistence {
  LocalEntityGraphCoordinator({
    required this.database,
    required this.adapters,
    required this.definition,
    required this.authenticatedPrincipalId,
    required this.autoSync,
    this.clock = const SystemClock(),
    this.idGenerator = const UuidV7EntityIdGenerator(),
    this.diagnostics = const NoopLocalEntityDiagnostics(),
  }) : _expectedEntityTypes = Set.unmodifiable(
         definition.descriptors.map((descriptor) => descriptor.entityType),
       ) {
    if (!definition.isTransportCompatibleWith(adapters.definition)) {
      throw ArgumentError.value(
        adapters.definition,
        'adapters',
        'The adapter registry belongs to a different entity graph.',
      );
    }
    _mutationCoordinator = MutationCoordinator.batches(
      persist: _persistMutationBatch,
      clock: clock,
      diagnostics: diagnostics,
    );
    persistenceFailures = _mutationCoordinator.failures;
    _workers = {
      for (final target in definition.syncTargets)
        target: SyncWorker(
          target: target,
          persistence: this,
          backend: adapters.backendFor(target),
          scheduleWake: _scheduleSyncWake,
        ),
    };
  }

  final GeneratedDatabase database;
  final SyncAdapterRegistry adapters;
  final EntityGraphDefinition definition;
  final String authenticatedPrincipalId;
  final Clock clock;
  final EntityIdGenerator idGenerator;
  final LocalEntityDiagnostics diagnostics;
  final bool autoSync;
  final Set<String> _expectedEntityTypes;
  late final Map<String, List<CompositionDefinition>> _compositionsByAggregate =
      _indexCompositions(
        definition.compositions,
        (composition) => composition.aggregateEntityType,
      );
  late final Map<String, List<CompositionDefinition>> _compositionsByComponent =
      _indexCompositions(
        definition.compositions,
        (composition) => composition.componentEntityType,
      );
  late final Map<String, ActivityTrackingDefinition> _activityTrackingBySource =
      Map.unmodifiable({
        for (final tracking in definition.activityTrackings)
          tracking.sourceEntityType: tracking,
      });
  late final Map<SyncTargetId, SyncWorker> _workers;
  late final MutationCoordinator _mutationCoordinator;
  final Map<String, _ErasedLocalEntityEngine> _engines = {};
  final ObservableList<SyncWorkItem> _syncWork = ObservableList();
  late final ReadOnlyObservableList<SyncWorkItem> _syncWorkView =
      ReadOnlyObservableList(_syncWork);
  final Observable<SyncState> _syncState = Observable(const SyncState.idle());
  late final ReadOnlyObservableList<LocalPersistenceFailure>
  persistenceFailures;
  List<_PendingMutation>? _transactionBuffer;
  Object? _transactionOwnerToken;
  final Map<SyncTargetId, StreamSubscription<void>> _remoteSignalSubscriptions =
      {};
  StreamSubscription<Set<TableUpdate>>? _queueUpdateSubscription;
  final Set<Future<void>> _backgroundTasks = {};
  final Map<SyncTargetId, Future<void>> _remoteSignalWork = {};
  final Set<SyncTargetId> _remoteSignalRerunRequested = {};
  final Map<SyncTargetId, Timer> _retryTimers = {};
  final Map<SyncTargetId, DateTime> _scheduledRetryAt = {};
  bool _started = false;
  bool _closed = false;
  Future<void>? _closeFuture;
  int _syncWorkRefreshRequest = 0;

  void _register<E, T extends TypedGeneratedEntityRecord<E>>(
    LocalEntityEngine<E, T> engine,
  ) {
    if (_started || _closed) {
      throw StateError('Entity engines must register before graph start.');
    }
    final expectedBackend = adapters.backendForEntity(
      engine.descriptor.entityType,
    );
    if (!identical(database, engine.database) ||
        !identical(expectedBackend, engine._backend)) {
      throw ArgumentError(
        'Every entity engine must use the graph database and its generated '
        'sync-target binding.',
      );
    }
    final entityType = engine.descriptor.entityType;
    if (!_expectedEntityTypes.contains(entityType)) {
      throw ArgumentError('Unexpected entity type `$entityType`.');
    }
    if (_engines.containsKey(entityType)) {
      throw StateError('Entity type `$entityType` is registered twice.');
    }
    _engines[entityType] = engine;
  }

  void _unregister<E, T extends TypedGeneratedEntityRecord<E>>(
    LocalEntityEngine<E, T> engine,
  ) {
    final entityType = engine.descriptor.entityType;
    _engines.remove(entityType);
  }

  D? _resolveReference<D, R extends TypedGeneratedEntityRecord<D>>(
    EntityDescriptor<D, R> descriptor,
    String entityId,
  ) {
    final engine = _engineFor(descriptor.entityType);
    final domain = engine.byRawId(entityId);
    if (domain == null) return null;
    if (domain is! D) {
      throw StateError(
        'Generated descriptor `${descriptor.entityType}` is registered with '
        'an incompatible domain engine.',
      );
    }
    return domain;
  }

  Future<void> start() async {
    if (_closed) throw StateError('The entity graph is closed.');
    if (_started) return;
    final registered = _engines.keys.toSet();
    if (!_setEquals(registered, _expectedEntityTypes)) {
      final missing = _expectedEntityTypes.difference(registered).join(', ');
      throw StateError('Entity graph is missing engines: $missing.');
    }
    _started = true;
    final now = clock.nowUtc().millisecondsSinceEpoch;
    await database.customStatement(
      "update local_entity_sync_work set status = 'retryableFailure', "
      "lease_until = null, next_attempt_at = null where status = 'processing' "
      "and (lease_until is null or lease_until <= ?)",
      [now],
    );
    await _refreshSyncState();
    await refreshSyncWork();
    _queueUpdateSubscription = database
        .tableUpdates(
          const TableUpdateQuery.onTableName('local_entity_sync_work'),
        )
        .listen(
          (_) => _runInBackground(
            _refreshWorkAndState(),
            task: LocalEntityBackgroundTask.queueRefresh,
          ),
        );
    if (!autoSync) return;
    for (final target in definition.pullSyncTargets) {
      final backend = adapters.backendFor(target);
      if (backend case RemoteChangeSignalSource source) {
        _remoteSignalSubscriptions[target] = source.remoteChangeSignals.listen(
          (_) => _handleRemoteSignal(target),
        );
      }
    }
    await schedulePull();
    _requestSync();
  }

  @override
  ReadOnlyObservableList<SyncWorkItem> get syncWork => _syncWorkView;

  @override
  Observable<SyncState> get syncState => _syncState;

  SyncQueue get syncQueue => SyncQueue(this);

  Future<void> sync() => _performSync();

  Future<LocalMutationCommitResult> _recordMutation(
    LocalEntityMutation mutation, {
    required void Function() rollbackIfCurrent,
    required void Function() onSettled,
  }) {
    final pending = _PendingMutation(
      mutation,
      rollbackIfCurrent,
      onSettled: onSettled,
    );
    final transaction = _transactionBuffer;
    if (transaction != null) {
      if (!_ownsCurrentTransaction) {
        throw StateError(
          'A mutation cannot join an entity graph transaction owned by '
          'another asynchronous flow.',
        );
      }
      transaction.add(pending);
      _appendActivityForMutation(mutation);
      return pending.committed;
    }

    final batch = <_PendingMutation>[pending];
    final ownerToken = Object();
    _transactionBuffer = batch;
    _transactionOwnerToken = ownerToken;
    try {
      runZoned(
        () => _appendActivityForMutation(mutation),
        zoneValues: {this: ownerToken},
      );
    } catch (error, stackTrace) {
      runInAction(() {
        for (final mutation in batch.reversed) {
          mutation.rollbackIfCurrent();
        }
      });
      final failure = LocalMutationCommitResult.failure(error, stackTrace);
      for (final mutation in batch) {
        mutation.onSettled?.call();
        mutation.complete(failure);
      }
      rethrow;
    } finally {
      _transactionBuffer = null;
      _transactionOwnerToken = null;
    }
    _mutationCoordinator._scheduleBatch(batch);
    return pending.committed;
  }

  void _appendActivityForMutation(LocalEntityMutation mutation) {
    final tracking = _activityTrackingBySource[mutation.entityType];
    if (tracking == null) return;
    final sourceEngine = _engineFor(mutation.entityType);
    final source = sourceEngine._identityMap[mutation.entityId];
    final descriptor = sourceEngine.descriptor;
    if (source == null || descriptor is! ActivityTrackedEntityDescriptor) {
      throw StateError(
        'Tracked activity source `${mutation.entityType}` is not attached.',
      );
    }
    final activityDescriptor = descriptor as ActivityTrackedEntityDescriptor;
    final activityEngine = _engineFor(tracking.activityEntityType);
    activityEngine._createRecord(
      {
        EntityConventions.ownerFieldName: source.generatedOwnerId,
        'subjectId': mutation.entityId,
        'actorId': authenticatedPrincipalId,
        'operation': _activityOperationFor(mutation).toScalar(),
        'label': activityDescriptor.activityLabel(source),
        'sourceOperationId': mutation.operationId.value,
        'occurredAt': mutation.createdAt.toIso8601String(),
      },
      principals: const [RlsPrincipal.owner, RlsPrincipal.collaborator],
    );
  }

  ActivityOperation _activityOperationFor(LocalEntityMutation mutation) {
    final explicit = mutation.activityOperation;
    if (explicit != null) return explicit;
    if (mutation.operation == SyncMutationOperation.create) {
      return ActivityOperation.created;
    }
    final commandName = mutation.semanticCommand?.name;
    if (commandName == 'setCollaborator') {
      return ActivityOperation.collaborationChanged;
    }
    if (commandName == 'moveInOrder' || commandName == 'reorder') {
      return ActivityOperation.reordered;
    }
    if (commandName == 'transferInOrder') {
      return ActivityOperation.moved;
    }
    if (commandName != null) return ActivityOperation.action(commandName);
    if (mutation.operation == SyncMutationOperation.delete) {
      return mutation.patch[EntityConventions.deletedAtFieldName] == null
          ? ActivityOperation.restored
          : ActivityOperation.removed;
    }
    return ActivityOperation.edited;
  }

  Future<R> transaction<R>(FutureOr<R> Function() body) async {
    if (_closed) throw StateError('The entity graph is closed.');
    if (_ownsCurrentTransaction) {
      return _runJoinedTransaction(body);
    }
    if (_transactionBuffer != null) {
      throw StateError(
        'The entity graph already has a transaction owned by another '
        'asynchronous flow.',
      );
    }
    await _mutationCoordinator.flush();
    if (_transactionBuffer != null) {
      throw StateError(
        'The entity graph acquired another transaction while waiting to '
        'flush pending mutations.',
      );
    }
    final pending = <_PendingMutation>[];
    final ownerToken = Object();
    _transactionBuffer = pending;
    _transactionOwnerToken = ownerToken;
    late R result;
    try {
      result = await runZoned(
        () => Future<R>.value(runInAction(body)),
        zoneValues: {this: ownerToken},
      );
      _validateComponentCreates(pending);
    } catch (error, stackTrace) {
      runInAction(() {
        for (final mutation in pending.reversed) {
          mutation.rollbackIfCurrent();
        }
      });
      final failure = LocalMutationCommitResult.failure(error, stackTrace);
      for (final mutation in pending) {
        mutation.onSettled?.call();
        mutation.complete(failure);
      }
      rethrow;
    } finally {
      _transactionBuffer = null;
      _transactionOwnerToken = null;
    }
    _mutationCoordinator._scheduleBatch(pending);
    await _mutationCoordinator.flush();
    return result;
  }

  /// Commits the local mechanics of one exact relationship replacement while
  /// exposing only its final graph-scope command to writable sync targets.
  ///
  /// Generated link creation, activation, deactivation, and rank updates still
  /// use their ordinary validated mutation paths. Their individual outbound
  /// intents are suppressed only inside [applyLocalProjection];
  /// [recordSemanticCommand] then records the one durable remote operation in
  /// the same graph transaction.
  Future<void> replaceActiveRelationship({
    required Future<void> Function() applyLocalProjection,
    required Future<void> Function() recordSemanticCommand,
  }) => transaction(() async {
    final pending = _transactionBuffer!;
    final savepoint = pending.length;
    await runZoned(
      applyLocalProjection,
      zoneValues: {_relationshipOutboundSuppressionZoneKey: this},
    );
    final localMechanics = pending.sublist(savepoint);
    if (localMechanics.isEmpty ||
        localMechanics.any(
          (candidate) => !candidate.mutation.suppressOutboundIntent,
        )) {
      throw StateError(
        'A relationship replacement must produce only generated local '
        'mechanics before its semantic command.',
      );
    }
    await recordSemanticCommand();
    if (pending.length != savepoint + localMechanics.length + 1) {
      throw StateError(
        'A relationship replacement must record exactly one semantic command.',
      );
    }
    final commandPending = pending.last;
    final commandMutation = commandPending.mutation;
    if (commandMutation.suppressOutboundIntent ||
        commandMutation.operation != SyncMutationOperation.command ||
        commandMutation.semanticCommand
            is! ReplaceActiveRelationshipCommand<dynamic, dynamic, dynamic>) {
      throw StateError(
        'A relationship replacement ended without its exact graph command.',
      );
    }

    final identities = <String, EntityIdentity<dynamic>>{};
    final revisions = <String, int>{};
    final operations = <String, LocalEntityStateOperation>{};
    final patches = <String, JsonMap>{};
    void mergeState(LocalEntityStatePatch state) {
      final id = state.identity.rawId;
      identities[id] = state.identity;
      revisions[id] = state.localRevision;
      if (state.operation == LocalEntityStateOperation.create) {
        operations[id] = LocalEntityStateOperation.create;
      } else {
        operations.putIfAbsent(id, () => LocalEntityStateOperation.patch);
      }
      (patches[id] ??= <String, Object?>{}).addAll(state.patch.toWire());
    }

    for (final candidate in localMechanics) {
      final mutation = candidate.mutation;
      final persistsDirectState =
          mutation.kind != PushSyncWorkKind.semanticCommand ||
          mutation.persistsEntityState;
      if (persistsDirectState) {
        mergeState(
          LocalEntityStatePatch(
            identity: mutation.identity,
            localRevision: mutation.localRevision,
            patch: mutation.patch,
            operation: mutation.operation == SyncMutationOperation.create
                ? LocalEntityStateOperation.create
                : LocalEntityStateOperation.patch,
          ),
        );
      }
      for (final state in mutation.scopeStatePatches) {
        mergeState(state);
      }
    }
    final statePatches = [
      for (final id in patches.keys)
        LocalEntityStatePatch(
          identity: identities[id]!,
          localRevision: revisions[id]!,
          patch: EntityPatch.fromWire(patches[id]!),
          operation: operations[id]!,
        ),
    ];
    commandPending.mutation = LocalEntityMutation(
      operationId: commandMutation.operationId,
      identity: commandMutation.identity,
      baseServerVersion: commandMutation.baseServerVersion,
      localRevision: commandMutation.localRevision,
      patch: commandMutation.patch,
      syncPatch: commandMutation.syncPatch,
      createdAt: commandMutation.createdAt,
      operation: commandMutation.operation,
      kind: commandMutation.kind,
      semanticCommand: commandMutation.semanticCommand,
      activityOperation: commandMutation.activityOperation,
      orderedCreate: commandMutation.orderedCreate,
      persistsEntityState: commandMutation.persistsEntityState,
      scopeStatePatches: statePatches,
    );
  });

  bool get _ownsCurrentTransaction =>
      _transactionBuffer != null &&
      identical(Zone.current[this], _transactionOwnerToken);

  Future<R> _runJoinedTransaction<R>(FutureOr<R> Function() body) async {
    final pending = _transactionBuffer!;
    final savepoint = pending.length;
    try {
      return await Future<R>.value(runInAction(body));
    } catch (error, stackTrace) {
      final joined = pending.sublist(savepoint);
      runInAction(() {
        for (final mutation in joined.reversed) {
          mutation.rollbackIfCurrent();
        }
      });
      pending.removeRange(savepoint, pending.length);
      final failure = LocalMutationCommitResult.failure(error, stackTrace);
      for (final mutation in joined) {
        mutation.onSettled?.call();
        mutation.complete(failure);
      }
      rethrow;
    }
  }

  void _validateComponentCreates(List<_PendingMutation> pending) {
    if (definition.compositions.isEmpty) return;
    final attachments = <(String, String), List<int>>{};
    for (
      var aggregateIndex = 0;
      aggregateIndex < pending.length;
      aggregateIndex++
    ) {
      final aggregate = pending[aggregateIndex].mutation;
      if (aggregate.operation != SyncMutationOperation.create) continue;
      final compositions = _compositionsByAggregate[aggregate.entityType];
      if (compositions == null) continue;
      for (final composition in compositions) {
        final componentId = aggregate.patch[composition.fieldName];
        if (componentId is! String) continue;
        (attachments[(composition.componentEntityType, componentId)] ??= [])
            .add(aggregateIndex);
      }
    }

    for (
      var componentIndex = 0;
      componentIndex < pending.length;
      componentIndex++
    ) {
      final component = pending[componentIndex].mutation;
      if (component.operation != SyncMutationOperation.create) continue;
      if (!_compositionsByComponent.containsKey(component.entityType)) continue;
      final matches =
          attachments[(component.entityType, component.entityId)] ??
          const <int>[];
      if (matches.length != 1) {
        throw EntityValidationException(
          entityType: component.entityType,
          field: 'composition',
          message: matches.isEmpty
              ? 'A Component create must be attached to exactly one aggregate '
                    'create in the same entity-graph transaction.'
              : 'A Component identity cannot be attached to more than one '
                    'aggregate create.',
        );
      }
      if (matches.single <= componentIndex) {
        throw EntityValidationException(
          entityType: component.entityType,
          field: 'composition',
          message:
              'A Component must be created before its composing '
              'aggregate in the transaction causal order.',
        );
      }
    }
  }

  @override
  Future<SyncWorkItem?> claimNext(SyncTargetId target) async {
    final item = await database.transaction(() async {
      final now = clock.nowUtc();
      final row = await database
          .customSelect(
            "select * from local_entity_sync_work where "
            "sync_target = ? and "
            "((status in ('pending', 'retryableFailure') "
            "and (next_attempt_at is null or next_attempt_at <= ?)) "
            "or (status = 'processing' "
            "and (lease_until is null or lease_until <= ?))) "
            "order by case when direction = 'pull' then 0 else 1 end, id limit 1",
            variables: [
              Variable.withString(target.wireName),
              Variable.withInt(now.millisecondsSinceEpoch),
              Variable.withInt(now.millisecondsSinceEpoch),
            ],
          )
          .getSingleOrNull();
      if (row == null) return null;
      var item = _syncWorkItemFromRow(
        row,
        _descriptorFor,
        _targetForWire,
        definition,
        status: SyncWorkStatus.processing,
      );
      if (item case PushSyncWorkItem pushItem) {
        pushItem = pushItem.upcast(
          _engineFor(pushItem.operation.identity.entityType).descriptor,
        );
        item = pushItem;
        if (pushItem.operation.protocolVersion !=
            row.read<int>('protocol_version')) {
          await database.customStatement(
            'update local_entity_sync_work set protocol_version = ?, payload = ? '
            'where id = ?',
            [
              pushItem.operation.protocolVersion,
              jsonEncode(pushItem.operation.toWire()),
              pushItem.id,
            ],
          );
        }
      }
      await database.customStatement(
        "update local_entity_sync_work set status = 'processing', "
        "lease_until = ?, next_attempt_at = null where id = ?",
        [
          now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
          row.read<int>('id'),
        ],
      );
      return item;
    });
    await refreshSyncWork();
    return item;
  }

  @override
  Future<ServerSequence> readPullCursor(SyncTargetId target) async {
    final row = await database
        .customSelect(
          'select cursor from local_entity_sync_cursor where sync_target = ?',
          variables: [Variable.withString(target.wireName)],
        )
        .getSingle();
    return ServerSequence(row.read<int>('cursor'));
  }

  @override
  Future<void> completePush(PushSyncWorkItem item, PushResult result) =>
      _completePush(item, result);

  @override
  Future<void> completePull(PullSyncWorkItem item, PullResult result) =>
      _completePull(item, result);

  @override
  Future<SyncFailureOutcome> handleFailure(
    SyncWorkItem item,
    Object error,
    StackTrace stackTrace,
  ) => _handleFailure(item, error, stackTrace);

  Future<void> flushLocal() => _mutationCoordinator.flush();

  Future<void> _persistMutationBatch(
    List<LocalEntityMutation> mutations,
  ) async {
    final ordered = _orderMutationsByDependencies(mutations);
    final changes =
        <_ErasedLocalEntityEngine, EntityProjectionChange<dynamic>>{};
    await database.transaction(() async {
      for (final mutation in ordered) {
        final engine = _engineFor(mutation.entityType);
        await _validateMutationReferences(engine, mutation);
        final change = engine._projectionChangeFor(mutation);
        if (change != null) {
          changes.update(
            engine,
            (current) => current._merge(change),
            ifAbsent: () => change,
          );
        }
        await engine._persistMutationInCurrentTransaction(mutation);
      }
    });
    for (final entry in changes.entries) {
      entry.key._notifyErasedProjectionChanged(entry.value);
    }
    await _workChanged();
  }

  Future<void> _validateMutationReferences(
    _ErasedLocalEntityEngine engine,
    LocalEntityMutation mutation,
  ) async {
    for (final field in engine.descriptor.fields) {
      final reference = field.reference;
      if (reference == null || !mutation.patch.containsKey(field.name)) {
        continue;
      }
      final targetId = mutation.patch[field.name];
      if (targetId == null) continue;
      if (targetId is! String) {
        throw EntityValidationException(
          entityType: mutation.entityType,
          field: field.name,
          message: 'Reference IDs must use canonical UUID strings.',
        );
      }
      final target = _engineFor(reference.targetEntityType);
      final exists = await database
          .customSelect(
            'select 1 from ${target.descriptor.tableName} '
            'where ${EntityConventions.idColumnName} = ? limit 1',
            variables: [Variable.withString(targetId)],
          )
          .getSingleOrNull();
      if (exists == null) {
        throw EntityValidationException(
          entityType: mutation.entityType,
          field: field.name,
          message:
              'Referenced ${reference.targetEntityType} `$targetId` is not '
              'available in the local projection.',
        );
      }
    }
  }

  List<LocalEntityMutation> _orderMutationsByDependencies(
    List<LocalEntityMutation> mutations,
  ) {
    String key(String entityType, String entityId) =>
        '$entityType\u0000$entityId';
    final creates = <String, LocalEntityMutation>{
      for (final mutation in mutations)
        if (mutation.operation == SyncMutationOperation.create)
          key(mutation.entityType, mutation.entityId): mutation,
    };
    final visiting = <LocalEntityMutation>{};
    final visited = <LocalEntityMutation>{};
    final ordered = <LocalEntityMutation>[];

    void visit(LocalEntityMutation mutation) {
      if (visited.contains(mutation)) return;
      if (!visiting.add(mutation)) {
        throw StateError(
          'A cycle between newly-created entity references cannot be pushed '
          'as independent server operations.',
        );
      }
      if (mutation.operation == SyncMutationOperation.create) {
        final engine = _engineFor(mutation.entityType);
        for (final field in engine.descriptor.fields) {
          final reference = field.reference;
          if (reference == null) continue;
          final referencedId = mutation.patch[field.name];
          if (referencedId is! String) continue;
          final dependency =
              creates[key(reference.targetEntityType, referencedId)];
          if (dependency != null) visit(dependency);
        }
      }
      visiting.remove(mutation);
      visited.add(mutation);
      ordered.add(mutation);
    }

    for (final mutation in mutations) {
      visit(mutation);
    }
    return ordered;
  }

  @override
  Future<void> refreshSyncWork() async {
    final request = ++_syncWorkRefreshRequest;
    final rows = await database
        .customSelect('select * from local_entity_sync_work order by id')
        .get();
    if (request != _syncWorkRefreshRequest || _closed) return;
    final items = rows
        .map(
          (row) => _syncWorkItemFromRow(
            row,
            _descriptorFor,
            _targetForWire,
            definition,
          ),
        )
        .toList(growable: false);
    runInAction(() {
      _syncWork
        ..clear()
        ..addAll(items);
    });
    await _refreshPendingIdentityPins();
  }

  @override
  Future<void> schedulePull() async {
    await database.transaction(() async {
      for (final target in definition.pullSyncTargets) {
        await _schedulePullInCurrentTransaction(target);
      }
    });
    await refreshSyncWork();
  }

  Future<void> _schedulePullTarget(SyncTargetId target) async {
    if (!definition.pullSyncTargets.contains(target)) return;
    await database.transaction(() => _schedulePullInCurrentTransaction(target));
    await refreshSyncWork();
  }

  Future<void> _schedulePullInCurrentTransaction(SyncTargetId target) async {
    final existing = await database
        .customSelect(
          "select id from local_entity_sync_work where direction = 'pull' "
          "and sync_target = ? "
          "and status in ('pending', 'processing', 'retryableFailure') limit 1",
          variables: [Variable.withString(target.wireName)],
        )
        .getSingleOrNull();
    if (existing != null) return;
    await database.customStatement(
      'insert into local_entity_sync_work '
      '(sync_target, direction, kind, status, entity_type, entity_id, operation_id, '
      'base_server_version, local_revision, protocol_version, payload, '
      'attempt_count, created_at) '
      "values (?, 'pull', 'pullChanges', 'pending', '__graph__', '', ?, "
      "0, 0, 1, '{}', 0, ?)",
      [
        target.wireName,
        idGenerator.nextOperationId().value,
        clock.nowUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> retryNow() async {
    await database.customStatement(
      "update local_entity_sync_work set next_attempt_at = null "
      "where status = 'retryableFailure'",
    );
    await _performSync();
  }

  Future<void> _workChanged() async {
    if (_closed) return;
    await refreshSyncWork();
    await _refreshSyncState();
    if (autoSync) _requestSync();
  }

  Future<void> _refreshWorkAndState() async {
    await refreshSyncWork();
    await _refreshSyncState();
  }

  Future<void> _refreshSyncState() async {
    final terminal = await database
        .customSelect(
          "select status, last_error_detail from local_entity_sync_work "
          "where status in ('rejected', 'conflict') order by id limit 1",
        )
        .getSingleOrNull();
    if (terminal != null) {
      runInAction(
        () => _syncState.value = SyncState(
          SyncPhase.needsAttention,
          message: terminal.readNullable<String>('last_error_detail'),
        ),
      );
      return;
    }
    final retry = await database
        .customSelect(
          "select last_error_detail from local_entity_sync_work "
          "where status = 'retryableFailure' order by id limit 1",
        )
        .getSingleOrNull();
    runInAction(
      () => _syncState.value = retry == null
          ? const SyncState.idle()
          : SyncState(
              SyncPhase.waitingToRetry,
              message: retry.readNullable<String>('last_error_detail'),
            ),
    );
  }

  Future<void> _refreshPendingIdentityPins() async {
    await Future.wait([
      for (final engine in _engines.values)
        engine._refreshPendingIdentityPins(),
    ]);
  }

  Future<void> _completePush(PushSyncWorkItem item, PushResult result) async {
    result.validateFor(item);
    final canonicalChanges = result.canonicalChanges.toList(growable: false)
      ..sort(
        (left, right) =>
            left.serverSequence.value.compareTo(right.serverSequence.value),
      );
    final resolved =
        <
          (
            _ErasedLocalEntityEngine,
            RemoteEntityChange,
            _MergedRemoteProjection,
          )
        >[];
    var supersededReceipt = false;
    await database.transaction(() async {
      final cursorRow = await database
          .customSelect(
            'select cursor from local_entity_sync_cursor where sync_target = ?',
            variables: [Variable.withString(item.target.wireName)],
          )
          .getSingle();
      final lastSequence = canonicalChanges.last.serverSequence.value;
      supersededReceipt = lastSequence <= cursorRow.read<int>('cursor');
      if (supersededReceipt) {
        final workRow = await database
            .customSelect(
              'select payload from local_entity_sync_work where id = ?',
              variables: [Variable.withInt(item.id)],
            )
            .getSingle();
        final replacementId = idGenerator.nextOperationId();
        final payload = <String, Object?>{
          ..._decodeMap(workRow.read<String>('payload')),
          'operationId': replacementId.value,
        };
        await database.customStatement(
          "update local_entity_sync_work set operation_id = ?, payload = ?, "
          "status = 'pending', attempt_count = 0, lease_until = null, "
          'next_attempt_at = null, last_error_code = null, '
          'last_error_detail = null where id = ?',
          [replacementId.value, jsonEncode(payload), item.id],
        );
        return;
      }
      await database.customStatement(
        'delete from local_entity_sync_work where id = ?',
        [item.id],
      );
      for (final change in canonicalChanges) {
        final engine = _engineForRemoteChange(
          change,
          target: item.target,
          fromPull: false,
        );
        // Remaining operations for this identity happened after the scope
        // operation just acknowledged. Rebase before conflict resolution so
        // the server receipt is not mistaken for a concurrent remote edit.
        await engine._rebaseFirstPendingPush(
          change.identity.rawId,
          change.serverVersion,
        );
        resolved.add((
          engine,
          change,
          await engine._mergeRemoteIntoDatabase(
            identity: change.identity,
            serverVersion: change.serverVersion,
            fields: change.fields,
          ),
        ));
      }
    });
    if (!supersededReceipt) {
      final notifications =
          <_ErasedLocalEntityEngine, EntityProjectionChange<dynamic>>{};
      runInAction(() {
        for (final entry in resolved) {
          final engine = entry.$1;
          final change = entry.$2;
          final projection = entry.$3;
          if (!projection.ignored) {
            engine._applyResolved(change, projection.fields);
          }
          final notification = projection.ignored
              ? null
              : projection.inserted
              ? const EntityProjectionChange<dynamic>.membership()
              : projection.changedFieldNames.isEmpty
              ? null
              : EntityProjectionChange<dynamic>._fromFieldNames(
                  projection.changedFieldNames,
                );
          if (notification != null) {
            notifications.update(
              engine,
              (current) => current._merge(notification),
              ifAbsent: () => notification,
            );
          }
        }
      });
      _engineFor(
        result.canonicalChange.identity.entityType,
      )._rememberOrderScopeVersion(result);
      for (final entry in notifications.entries) {
        entry.key._notifyErasedProjectionChanged(entry.value);
      }
    }
    await _workChanged();
  }

  Future<void> _completePull(PullSyncWorkItem item, PullResult result) async {
    final resolved =
        <
          (
            _ErasedLocalEntityEngine,
            RemoteEntityChange,
            _MergedRemoteProjection,
          )
        >[];
    await database.transaction(() async {
      for (final change in result.changes) {
        final engine = _engineForRemoteChange(
          change,
          target: item.target,
          fromPull: true,
        );
        if (change.isRevocation) {
          await engine._purgeRevokedEntity(change.identity.rawId);
          resolved.add((
            engine,
            change,
            const _MergedRemoteProjection(
              fields: <String, Object?>{},
              inserted: false,
              changedFieldNames: <String>{},
            ),
          ));
          continue;
        }
        if (change.sourceOperationId != null) {
          await database.customStatement(
            'delete from local_entity_sync_work '
            'where sync_target = ? and operation_id = ?',
            [item.target.wireName, change.sourceOperationId!.value],
          );
        }
        resolved.add((
          engine,
          change,
          await engine._mergeRemoteIntoDatabase(
            identity: change.identity,
            serverVersion: change.serverVersion,
            fields: change.fields,
          ),
        ));
      }
      await database.customStatement(
        'update local_entity_sync_cursor set cursor = ? where sync_target = ?',
        [result.nextSequence.value, item.target.wireName],
      );
      if (result.hasMore) {
        await database.customStatement(
          "update local_entity_sync_work set status = 'pending' where id = ?",
          [item.id],
        );
      } else {
        await database.customStatement(
          'delete from local_entity_sync_work where id = ?',
          [item.id],
        );
      }
    });
    final changes =
        <_ErasedLocalEntityEngine, EntityProjectionChange<dynamic>>{};
    runInAction(() {
      for (final entry in resolved) {
        final engine = entry.$1;
        final change = entry.$2;
        final projectionChange = entry.$3.ignored
            ? null
            : change.isRevocation || entry.$3.inserted
            ? const EntityProjectionChange<dynamic>.membership()
            : entry.$3.changedFieldNames.isEmpty
            ? null
            : EntityProjectionChange<dynamic>._fromFieldNames(
                entry.$3.changedFieldNames,
              );
        if (projectionChange != null) {
          changes.update(
            engine,
            (current) => current._merge(projectionChange),
            ifAbsent: () => projectionChange,
          );
        }
        if (change.isRevocation) {
          final revoked = engine._identityMap.remove(change.identity.rawId);
          engine._persistedIds.remove(change.identity.rawId);
          if (revoked != null) engine._all.remove(revoked.generatedDomain);
        } else if (!entry.$3.ignored) {
          engine._applyResolved(change, entry.$3.fields);
        }
      }
    });
    for (final entry in changes.entries) {
      entry.key._notifyErasedProjectionChanged(entry.value);
    }
    await _workChanged();
  }

  Future<SyncFailureOutcome> _handleFailure(
    SyncWorkItem item,
    Object error,
    StackTrace stackTrace,
  ) async {
    final failure = error is SyncBackendException
        ? error
        : RetryableSyncException(
            code: 'unexpected_error',
            message: error.toString(),
          );
    final outcome = switch (item) {
      PushSyncWorkItem() => await _engineFor(
        item.operation.identity.entityType,
      )._handleFailureForThisEntity(item, failure, refreshQueue: false),
      PullSyncWorkItem() => await _handlePullFailure(item, failure),
    };
    final attemptCount = item.attemptCount + 1;
    final resultingStatus = switch (failure.kind) {
      SyncFailureKind.rejected => SyncWorkStatus.rejected,
      SyncFailureKind.conflict when attemptCount >= 3 =>
        SyncWorkStatus.conflict,
      SyncFailureKind.retryable ||
      SyncFailureKind.conflict => SyncWorkStatus.retryableFailure,
    };
    _recordDiagnosticSafely(
      diagnostics,
      SyncFailureDiagnostic(
        occurredAt: clock.nowUtc(),
        workId: item.id,
        target: item.target,
        operationId: item.operationId,
        direction: item.direction,
        identity: switch (item) {
          PushSyncWorkItem(:final operation) => operation.identity,
          PullSyncWorkItem() => null,
        },
        attemptCount: attemptCount,
        failure: failure,
        stackTrace: stackTrace,
        resultingStatus: resultingStatus,
        retryAt: outcome.retryAt,
      ),
    );
    await _workChanged();
    return outcome;
  }

  Future<SyncFailureOutcome> _handlePullFailure(
    PullSyncWorkItem item,
    Object error,
  ) async {
    final failure = error is SyncBackendException
        ? error
        : RetryableSyncException(
            code: 'unexpected_error',
            message: error.toString(),
          );
    final attemptCount = item.attemptCount + 1;
    if (failure.kind == SyncFailureKind.rejected ||
        (failure.kind == SyncFailureKind.conflict && attemptCount >= 3)) {
      final status = failure.kind == SyncFailureKind.conflict
          ? SyncWorkStatus.conflict
          : SyncWorkStatus.rejected;
      await database.customStatement(
        'update local_entity_sync_work set status = ?, attempt_count = ?, '
        'lease_until = null, next_attempt_at = null, last_error_code = ?, '
        'last_error_detail = ? where id = ?',
        [status.name, attemptCount, failure.code, failure.message, item.id],
      );
      return const SyncFailureOutcome(continueDraining: true);
    }
    if (failure.kind == SyncFailureKind.conflict) {
      await database.customStatement(
        "update local_entity_sync_work set status = 'retryableFailure', "
        "attempt_count = ?, lease_until = null, next_attempt_at = null, "
        'last_error_code = ?, last_error_detail = ? where id = ?',
        [attemptCount, failure.code, failure.message, item.id],
      );
      return const SyncFailureOutcome(continueDraining: true);
    }
    final retryAt = clock.nowUtc().add(_syncRetryDelay(item.id, attemptCount));
    await database.customStatement(
      "update local_entity_sync_work set status = 'retryableFailure', "
      'attempt_count = ?, lease_until = null, next_attempt_at = ?, '
      'last_error_code = ?, last_error_detail = ? where id = ?',
      [
        attemptCount,
        retryAt.millisecondsSinceEpoch,
        failure.code,
        failure.message,
        item.id,
      ],
    );
    return SyncFailureOutcome(continueDraining: false, retryAt: retryAt);
  }

  void _handleRemoteSignal(SyncTargetId target) {
    if (_closed) return;
    if (_remoteSignalWork.containsKey(target)) {
      _remoteSignalRerunRequested.add(target);
      return;
    }
    late final Future<void> work;
    work = _drainRemoteSignals(target).whenComplete(() {
      if (!identical(_remoteSignalWork[target], work)) return;
      _remoteSignalWork.remove(target);
      if (_remoteSignalRerunRequested.remove(target) && !_closed) {
        _handleRemoteSignal(target);
      }
    });
    _remoteSignalWork[target] = work;
    _runInBackground(
      work,
      task: LocalEntityBackgroundTask.remoteSignal,
      target: target,
    );
  }

  Future<void> _drainRemoteSignals(SyncTargetId target) async {
    do {
      _remoteSignalRerunRequested.remove(target);
      if (_closed) return;
      await _schedulePullTarget(target);
      await _workers[target]!.drain();
    } while (_remoteSignalRerunRequested.contains(target));
  }

  void _scheduleSyncWake(SyncTargetId target, DateTime retryAt) {
    if (_closed || !autoSync) return;
    final existing = _scheduledRetryAt[target];
    if (existing != null && !retryAt.isBefore(existing)) return;
    _retryTimers.remove(target)?.cancel();
    _scheduledRetryAt[target] = retryAt;
    final delay = retryAt.difference(clock.nowUtc());
    late final Timer timer;
    timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!identical(_retryTimers[target], timer)) return;
      _retryTimers.remove(target);
      _scheduledRetryAt.remove(target);
      _requestTargetSync(target);
    });
    _retryTimers[target] = timer;
  }

  void _requestSync() {
    if (_closed) return;
    _runInBackground(
      _performSync(),
      task: LocalEntityBackgroundTask.synchronization,
    );
  }

  void _requestTargetSync(SyncTargetId target) {
    if (_closed) return;
    _runInBackground(
      _performWorkers([_workers[target]!]),
      task: LocalEntityBackgroundTask.synchronization,
      target: target,
    );
  }

  Future<void> _performSync() => _performWorkers(_workers.values);

  Future<void> _performWorkers(Iterable<SyncWorker> workers) async {
    runInAction(() => _syncState.value = const SyncState(SyncPhase.syncing));
    try {
      await Future.wait([for (final worker in workers) worker.drain()]);
      await _refreshSyncState();
      await refreshSyncWork();
    } catch (error) {
      await refreshSyncWork();
      runInAction(
        () => _syncState.value = SyncState(
          SyncPhase.failed,
          message: error.toString(),
        ),
      );
      rethrow;
    }
  }

  void _runInBackground(
    Future<void> work, {
    required LocalEntityBackgroundTask task,
    SyncTargetId? target,
    String? entityType,
  }) {
    late final Future<void> tracked;
    tracked = work
        .catchError((Object error, StackTrace stackTrace) {
          _recordDiagnosticSafely(
            diagnostics,
            BackgroundTaskFailureDiagnostic(
              occurredAt: clock.nowUtc(),
              task: task,
              target: target,
              entityType: entityType,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          runInAction(
            () => _syncState.value = SyncState(
              SyncPhase.failed,
              message: error.toString(),
            ),
          );
        })
        .whenComplete(() => _backgroundTasks.remove(tracked));
    _backgroundTasks.add(tracked);
    unawaited(tracked);
  }

  Future<void> _waitForBackgroundTasks() async {
    while (_backgroundTasks.isNotEmpty) {
      await Future.wait(_backgroundTasks.toList(growable: false));
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _scheduledRetryAt.clear();
    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> release(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
        _recordDiagnosticSafely(
          diagnostics,
          BackgroundTaskFailureDiagnostic(
            occurredAt: clock.nowUtc(),
            task: LocalEntityBackgroundTask.shutdown,
            target: null,
            entityType: null,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    for (final subscription in _remoteSignalSubscriptions.values) {
      await release(subscription.cancel);
    }
    await release(() async => _queueUpdateSubscription?.cancel());
    await release(flushLocal);
    for (final worker in _workers.values) {
      await release(worker.waitForIdle);
    }
    await release(_waitForBackgroundTasks);
    for (final engine in _engines.values) {
      await release(engine.close);
    }
    for (final backend in adapters.targets.map(adapters.backendFor).toSet()) {
      if (backend case RemoteChangeSignalSource source) {
        await release(source.disposeRemoteChangeSignals);
      }
    }
    await release(database.close);
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  _ErasedLocalEntityEngine _engineFor(String entityType) {
    final engine = _engines[entityType];
    if (engine == null) {
      throw RejectedSyncException.protocol(
        code: 'unknown_entity_type',
        message: 'No generated entity handles `$entityType`.',
      );
    }
    return engine;
  }

  _ErasedLocalEntityEngine _engineForRemoteChange(
    RemoteEntityChange change, {
    required SyncTargetId target,
    required bool fromPull,
  }) {
    final engine = _engineFor(change.identity.entityType);
    final binding = definition.syncBindingFor(change.identity.entityType);
    final acceptsRemoteChange = fromPull
        ? binding.mode == SyncMode.replicated ||
              binding.mode == SyncMode.imported
        : binding.mode != SyncMode.localOnly;
    if (binding.target != target || !acceptsRemoteChange) {
      throw RejectedSyncException.serverContract(
        code: 'sync_target_mismatch',
        message:
            'Target `${target.wireName}` returned '
            '`${change.identity.entityType}`, which is bound to '
            '`${binding.target?.wireName ?? 'localOnly'}` in '
            '`${binding.mode.name}` mode.',
      );
    }
    return engine;
  }

  EntityDescriptorBase _descriptorFor(String entityType) =>
      _engineFor(entityType).descriptor;

  SyncTargetId _targetForWire(String wireName) {
    for (final target in definition.syncTargets) {
      if (target.wireName == wireName) return target;
    }
    throw FormatException('Unknown generated sync target `$wireName`.');
  }
}

SyncWorkItem _syncWorkItemFromRow(
  QueryRow row,
  EntityDescriptorBase Function(String entityType) descriptorFor,
  SyncTargetId Function(String wireName) targetForWire,
  EntityGraphDefinition definition, {
  SyncWorkStatus? status,
}) {
  final direction = SyncDirection.values.byName(row.read<String>('direction'));
  final kind = SyncWorkKind.values.byName(row.read<String>('kind'));
  final id = row.read<int>('id');
  final target = targetForWire(_requiredWorkText(row, 'sync_target'));
  final operationId = parseSyncOperationId(row.read<String>('operation_id'));
  final resolvedStatus =
      status ?? SyncWorkStatus.values.byName(row.read<String>('status'));
  final attemptCount = row.read<int>('attempt_count');
  final createdAt = DateTime.fromMillisecondsSinceEpoch(
    row.read<int>('created_at'),
    isUtc: true,
  );
  final nextAttemptAt = switch (row.readNullable<int>('next_attempt_at')) {
    final value? => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    null => null,
  };
  final lastFailure = _syncWorkFailureFromRow(row, resolvedStatus);
  return switch (direction) {
    SyncDirection.push => _decodePushWorkItem(
      row: row,
      descriptor: descriptorFor(_requiredWorkText(row, 'entity_type')),
      definition: definition,
      id: id,
      target: target,
      operationId: operationId,
      kind: switch (kind) {
        SyncWorkKind.statePatch => PushSyncWorkKind.statePatch,
        SyncWorkKind.semanticCommand => PushSyncWorkKind.semanticCommand,
        SyncWorkKind.pullChanges => throw const FormatException(
          'Push work cannot have pullChanges kind.',
        ),
      },
      status: resolvedStatus,
      attemptCount: attemptCount,
      createdAt: createdAt,
      nextAttemptAt: nextAttemptAt,
      lastFailure: lastFailure,
    ),
    SyncDirection.pull => switch (kind) {
      SyncWorkKind.pullChanges => PullSyncWorkItem(
        id: id,
        target: target,
        operationId: operationId,
        status: resolvedStatus,
        attemptCount: attemptCount,
        createdAt: createdAt,
        nextAttemptAt: nextAttemptAt,
        lastFailure: lastFailure,
      ),
      SyncWorkKind.statePatch || SyncWorkKind.semanticCommand =>
        throw const FormatException('Pull work must have pullChanges kind.'),
    },
  };
}

PushSyncWorkItem _decodePushWorkItem({
  required QueryRow row,
  required EntityDescriptorBase descriptor,
  required EntityGraphDefinition definition,
  required int id,
  required SyncTargetId target,
  required SyncOperationId operationId,
  required PushSyncWorkKind kind,
  required SyncWorkStatus status,
  required int attemptCount,
  required DateTime createdAt,
  required DateTime? nextAttemptAt,
  required SyncWorkFailure? lastFailure,
}) {
  final operation = _decodePushOperation(
    descriptor,
    _decodeMap(row.read<String>('payload')),
    definition: definition,
  );
  if (operation.operationId != operationId) {
    throw const FormatException(
      'Push work operation ID column and payload do not match.',
    );
  }
  if (operation.identity.rawId != _requiredWorkText(row, 'entity_id')) {
    throw const FormatException(
      'Push work entity ID column and payload do not match.',
    );
  }
  if (operation.protocolVersion != row.read<int>('protocol_version')) {
    throw const FormatException(
      'Push work protocol version column and payload do not match.',
    );
  }
  return PushSyncWorkItem(
    id: id,
    target: target,
    operation: operation,
    pushKind: kind,
    status: status,
    attemptCount: attemptCount,
    createdAt: createdAt,
    nextAttemptAt: nextAttemptAt,
    lastFailure: lastFailure,
  );
}

SyncWorkFailure? _syncWorkFailureFromRow(QueryRow row, SyncWorkStatus status) {
  final code = row.readNullable<String>('last_error_code');
  if (code == null || code.isEmpty) return null;
  final detail = row.readNullable<String>('last_error_detail');
  if (code == 'version_conflict') {
    return ConflictSyncWorkFailure(code: code, detail: detail);
  }
  if (status == SyncWorkStatus.rejected) {
    return RejectedSyncWorkFailure(
      code: code,
      detail: detail,
      category: syncRejectionCategoryForCode(code),
    );
  }
  return RetryableSyncWorkFailure(code: code, detail: detail);
}

PushOperation _decodePushOperation(
  EntityDescriptorBase descriptor,
  JsonMap payload, {
  EntityGraphDefinition? definition,
}) {
  String requiredText(String key) {
    final value = payload[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Push operation requires non-empty `$key`.');
    }
    return value;
  }

  int requiredInt(String key) {
    final value = payload[key];
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    throw FormatException('Push operation requires integer `$key`.');
  }

  final entityType = requiredText('entityType');
  if (entityType != descriptor.entityType) {
    throw FormatException(
      'Push operation entity type `$entityType` does not match '
      '`${descriptor.entityType}`.',
    );
  }
  final protocolVersion = requiredInt('protocolVersion');
  if (protocolVersion < 1 || protocolVersion > descriptor.protocolVersion) {
    throw FormatException(
      'Unsupported ${descriptor.entityType} protocol version '
      '$protocolVersion.',
    );
  }
  final operationId = parseSyncOperationId(requiredText('operationId'));
  final identity = descriptor.parseIdentity(requiredText('entityId'));
  final baseServerVersion = parseServerVersion(
    requiredInt('baseServerVersion'),
  );
  final localRevision = requiredInt('localRevision');
  final rawPatch = _decodeMap(payload['patch']);
  final operationName = requiredText('operation');
  final operation = SyncMutationOperation.values
      .where((candidate) => candidate.name == operationName)
      .firstOrNull;
  if (operation == null) {
    throw FormatException('Unknown push operation `$operationName`.');
  }
  final patch = operation == SyncMutationOperation.command
      ? EntityPatch.fromWire(rawPatch)
      : _decodeEntityPatch(descriptor, rawPatch);
  final rawOrderedCreate = payload['orderedCreate'];
  if (rawOrderedCreate != null && operation != SyncMutationOperation.create) {
    throw const FormatException(
      'orderedCreate is valid only for create operations.',
    );
  }
  final persistedStatePatch = payload['statePatch'] == null
      ? null
      : _decodeEntityPatch(descriptor, _decodeMap(payload['statePatch']));
  return switch (operation) {
    SyncMutationOperation.create => CreatePushOperation(
      operationId: operationId,
      identity: identity,
      baseServerVersion: baseServerVersion,
      localRevision: localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
      orderedCreate: rawOrderedCreate == null
          ? null
          : OrderedCreateIntent.fromWire(_decodeMap(rawOrderedCreate)),
      localStatePatches: _decodeLocalStatePatches(descriptor, payload),
    ),
    SyncMutationOperation.patch => PatchPushOperation(
      operationId: operationId,
      identity: identity,
      baseServerVersion: baseServerVersion,
      localRevision: localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
    ),
    SyncMutationOperation.delete => DeletePushOperation(
      operationId: operationId,
      identity: identity,
      baseServerVersion: baseServerVersion,
      localRevision: localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
    ),
    SyncMutationOperation.command => CommandPushOperation(
      operationId: operationId,
      identity: identity,
      baseServerVersion: baseServerVersion,
      localRevision: localRevision,
      protocolVersion: protocolVersion,
      command: definition == null
          ? descriptor.decodeSemanticCommand(
              requiredText('commandName'),
              patch.toWire(),
            )
          : definition.decodeSemanticCommand(
              descriptor: descriptor,
              name: requiredText('commandName'),
              payload: patch.toWire(),
            ),
      storesEntityState: payload['persistsEntityState'] == true,
      statePatch: persistedStatePatch,
      scopeStatePatches: _decodeLocalStatePatches(descriptor, payload),
    ),
  };
}

PushOperation _operationForMutation(
  LocalEntityMutation mutation, {
  required int protocolVersion,
}) {
  final patch = mutation.syncPatch ?? mutation.patch;
  return switch (mutation.operation) {
    SyncMutationOperation.create => CreatePushOperation(
      operationId: mutation.operationId,
      identity: mutation.identity,
      baseServerVersion: mutation.baseServerVersion,
      localRevision: mutation.localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
      orderedCreate: mutation.orderedCreate,
      localStatePatches: mutation.scopeStatePatches,
    ),
    SyncMutationOperation.patch => PatchPushOperation(
      operationId: mutation.operationId,
      identity: mutation.identity,
      baseServerVersion: mutation.baseServerVersion,
      localRevision: mutation.localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
    ),
    SyncMutationOperation.delete => DeletePushOperation(
      operationId: mutation.operationId,
      identity: mutation.identity,
      baseServerVersion: mutation.baseServerVersion,
      localRevision: mutation.localRevision,
      protocolVersion: protocolVersion,
      patch: patch,
    ),
    SyncMutationOperation.command => CommandPushOperation(
      operationId: mutation.operationId,
      identity: mutation.identity,
      baseServerVersion: mutation.baseServerVersion,
      localRevision: mutation.localRevision,
      protocolVersion: protocolVersion,
      command:
          mutation.semanticCommand ??
          (throw StateError('Semantic command has no typed payload.')),
      storesEntityState:
          mutation.persistsEntityState || mutation.scopeStatePatches.isNotEmpty,
      statePatch: mutation.persistsEntityState ? mutation.patch : null,
      scopeStatePatches: mutation.scopeStatePatches,
    ),
  };
}

PushOperation _copyPushOperation(
  PushOperation operation, {
  required int localRevision,
  required EntityPatch patch,
}) => switch (operation) {
  CreatePushOperation(:final orderedCreate, :final localStatePatches) =>
    CreatePushOperation(
      operationId: operation.operationId,
      identity: operation.identity,
      baseServerVersion: operation.baseServerVersion,
      localRevision: localRevision,
      protocolVersion: operation.protocolVersion,
      patch: patch,
      orderedCreate: orderedCreate,
      localStatePatches: localStatePatches,
    ),
  PatchPushOperation() => PatchPushOperation(
    operationId: operation.operationId,
    identity: operation.identity,
    baseServerVersion: operation.baseServerVersion,
    localRevision: localRevision,
    protocolVersion: operation.protocolVersion,
    patch: patch,
  ),
  DeletePushOperation() => DeletePushOperation(
    operationId: operation.operationId,
    identity: operation.identity,
    baseServerVersion: operation.baseServerVersion,
    localRevision: localRevision,
    protocolVersion: operation.protocolVersion,
    patch: patch,
  ),
  CommandPushOperation(
    :final command,
    :final storesEntityState,
    :final statePatch,
    :final scopeStatePatches,
  ) =>
    CommandPushOperation(
      operationId: operation.operationId,
      identity: operation.identity,
      baseServerVersion: operation.baseServerVersion,
      localRevision: localRevision,
      protocolVersion: operation.protocolVersion,
      command: command,
      storesEntityState: storesEntityState,
      statePatch: statePatch,
      scopeStatePatches: scopeStatePatches,
    ),
};

List<LocalEntityStatePatch> _decodeLocalStatePatches(
  EntityDescriptorBase descriptor,
  JsonMap payload,
) {
  final raw = payload['localStatePatches'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('localStatePatches must be an array.');
  }
  final result = <LocalEntityStatePatch>[];
  final identities = <String>{};
  for (final value in raw) {
    final item = _decodeMap(value);
    final entityType = item['entityType'];
    final entityId = item['entityId'];
    final localRevision = item['localRevision'];
    final rawOperation = item['operation'] ?? 'patch';
    final operation = rawOperation is String
        ? LocalEntityStateOperation.values
              .where((candidate) => candidate.name == rawOperation)
              .firstOrNull
        : null;
    if (entityType != descriptor.entityType ||
        entityId is! String ||
        entityId.isEmpty ||
        localRevision is! int ||
        localRevision < 0 ||
        operation == null) {
      throw const FormatException('Invalid local ordered state patch.');
    }
    if (!identities.add(entityId)) {
      throw const FormatException(
        'localStatePatches cannot repeat an identity.',
      );
    }
    result.add(
      LocalEntityStatePatch(
        identity: descriptor.parseIdentity(entityId),
        localRevision: localRevision,
        operation: operation,
        patch: _decodeEntityPatch(descriptor, _decodeMap(item['patch'])),
      ),
    );
  }
  return List<LocalEntityStatePatch>.unmodifiable(result);
}

EntityPatch _decodeEntityPatch(EntityDescriptorBase descriptor, JsonMap wire) {
  final fields = {for (final field in descriptor.fields) field.name: field};
  final canonical = <String, Object?>{};
  for (final entry in wire.entries) {
    final field = fields[entry.key];
    if (field == null) {
      throw FormatException(
        'Unknown ${descriptor.entityType} patch field `${entry.key}`.',
      );
    }
    canonical[entry.key] = field.decodeWireValue(
      entry.value,
      entityType: descriptor.entityType,
    );
  }
  return EntityPatch.fromWire(canonical);
}

String _requiredWorkText(QueryRow row, String column) {
  final value = row.read<String>(column);
  if (value.isEmpty) {
    throw FormatException('Push work requires non-empty $column.');
  }
  return value;
}

Duration _syncRetryDelay(int workId, int attemptCount) {
  final exponent = math.min(attemptCount - 1, 8);
  final baseMilliseconds = math.min(300000, 1000 * (1 << exponent));
  final jitterBasis = ((workId * 1103515245) + (attemptCount * 12345)) & 1023;
  final jitterFactor = 0.8 + (jitterBasis / 1023) * 0.4;
  return Duration(milliseconds: (baseMilliseconds * jitterFactor).round());
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

typedef _ErasedGeneratedEntityRecord = TypedGeneratedEntityRecord<dynamic>;
typedef _ErasedLocalEntityEngine =
    LocalEntityEngine<dynamic, _ErasedGeneratedEntityRecord>;

final class _EntityPredicateSqlWriter<
  E,
  T extends TypedGeneratedEntityRecord<E>
>
    implements _EntityPredicateVisitor<E, String> {
  const _EntityPredicateSqlWriter(this.engine, this.variables);

  final LocalEntityEngine<E, T> engine;
  final List<Variable> variables;

  @override
  String visitAll() => '1';

  @override
  String visitComparison<V>(
    EntityField<E, V> field,
    EntityComparison comparison,
    V expected,
  ) => engine._comparisonSql(
    field.name,
    comparison,
    field.encode(expected),
    variables,
  );

  @override
  String visitNull<V>(EntityField<E, V?> field, {required bool expectsNull}) =>
      '${engine._field(field.name).columnName} '
      'is ${expectsNull ? '' : 'not '}null';

  @override
  String visitMembership<V>(EntityField<E, V> field, List<V> expected) =>
      engine._membershipSql(
        field.name,
        expected.map(field.encode).toList(growable: false),
        variables,
      );

  @override
  String visitLogical(
    EntityLogicalOperator operator,
    List<EntityPredicate<E>> operands,
  ) {
    final separator = operator == EntityLogicalOperator.and ? ' and ' : ' or ';
    return '(${operands.map((part) => part._accept(this)).join(separator)})';
  }
}

final class _DriftEntityQueryCursor implements EntityQueryCursor {
  const _DriftEntityQueryCursor({
    required this.entityType,
    required this.fieldName,
    required this.direction,
    required this.nulls,
    required this.fieldValue,
    required this.entityId,
  });

  final String entityType;
  final String? fieldName;
  final EntitySortDirection? direction;
  final NullPlacement? nulls;
  final Object? fieldValue;
  final String entityId;
}

final class _RejectedProjection {
  const _RejectedProjection.updated(
    this.entityId,
    this.fields, {
    required this.localRevision,
    required this.changedFieldNames,
  }) : assert(fields != null);

  const _RejectedProjection.removed(this.entityId)
    : fields = null,
      localRevision = 0,
      changedFieldNames = const {};

  final String entityId;
  final JsonMap? fields;
  final int localRevision;
  final Set<String> changedFieldNames;
}

final class _MergedRemoteProjection {
  const _MergedRemoteProjection({
    required this.fields,
    required this.inserted,
    required this.changedFieldNames,
    this.ignored = false,
  });

  final JsonMap fields;
  final bool inserted;
  final Set<String> changedFieldNames;
  final bool ignored;
}

JsonMap _decodeMap(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  }
  throw FormatException('Expected a JSON object, got $value.');
}
