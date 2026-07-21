/// Core Nodus declarations, generated-runtime contracts, typed queries, and
/// deterministic synchronization primitives.
library;

export 'src/annotations.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:mobx/mobx.dart' hide Action;
import 'package:uuid/uuid.dart';

import 'src/annotations.dart';

part 'src/entity_engine.dart';
part 'src/account_entity_graph_session.dart';
part 'src/memory_sync_backend.dart';
part 'src/migration.dart';

typedef JsonMap = Map<String, Object?>;

String normalizeTrimmedString(String value) => value.trim();

String? normalizeTrimmedStringToNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// Contract for an immutable domain value backed by one native scalar.
///
/// Implementations expose the storage value once and provide a named
/// `fromScalar` constructor with one required positional parameter of the same
/// [Wire] type. Generation validates the convention and preserves the domain
/// type across entities, queries, synchronization, Drift, and PostgreSQL while
/// storing the most specific native scalar instead of JSON or encoded text.
/// [Wire] is intentionally limited to String, bool, int, or double.
abstract interface class PersistedScalarValue<Wire extends Object> {
  Wire toScalar();
}

/// Declares the entity's nominal identity and authenticated owner types.
///
/// Dart cannot yet generate members into an existing class, so [Self] is the
/// compile-time bridge that keeps `id` nominal without a generated replacement
/// domain type. Persistence, local revisioning, tombstones, and sync routing
/// remain universal generated behavior; implementing this contract does not
/// opt the entity into a storage or synchronization strategy.
abstract interface class OwnedBy<Self, Owner> {
  LocalId<Self> get id;

  LocalId<Owner> get ownerId;

  DateTime? get deletedAt;

  ServerVersion get serverVersion;

  GeneratedEntityAccess<Self> get generatedAccess;
}

/// Adds caller-authored tombstone lifecycle operations to an entity.
///
/// Entities without this capability cannot expose generated delete APIs. Their
/// remote rows may still be revoked or tombstoned by an authorized server
/// workflow and will continue to merge correctly.
abstract interface class SoftDeletable {
  DateTime? get deletedAt;

  Future<void> remove();

  Future<void> restore();
}

/// Adds generated archive lifecycle and default active-list visibility.
///
/// The generator supplies [archivedAt], both lifecycle actions, the owner-scoped
/// index, local/remote persistence, synchronization, and typed archive-aware
/// query surfaces. Entity declarations must not repeat any of those members.
abstract interface class Archivable {
  DateTime? get archivedAt;

  Future<void> archive();

  Future<void> unarchive();
}

/// Marks an entity or relationship as participating in one canonical order.
///
/// The generator derives the scope, opaque rank storage, indexes, and semantic
/// collection operations. Domain code never declares a rank field or move
/// action alongside this capability.
abstract interface class Ordered {}

/// Marks an entity whose identity and lifecycle belong to one aggregate root.
///
/// A component is attached through a generated [Composition] relationship. It
/// may be reused as a target type by several aggregate types, but each concrete
/// component identity belongs to exactly one aggregate instance. Generation
/// derives relationship authorization and rejects standalone component
/// creation outside an entity-graph transaction.
abstract interface class Component {}

/// Adds generated active/inactive membership to a relationship entity.
///
/// The generator owns the persisted field, default, conflict policy, atomic
/// actions, storage mapping, synchronization validation, and list filtering.
abstract interface class Activatable {
  bool get active;

  Future<void> activate();

  Future<void> deactivate();
}

/// Adds generated direct collaborator membership to an entity.
///
/// [Principal] is normally the same nominal account type used by [OwnedBy].
/// The generator owns membership persistence, authorization, synchronization,
/// and the durable semantic operation behind [setCollaborator].
abstract interface class Collaborative<Principal> {
  Future<void> setCollaborator(
    LocalId<Principal> collaboratorId, {
    required bool active,
  });
}

/// One stable semantic operation recorded in a generated activity trail.
///
/// Conventional generated mutations use the named constants. A declared
/// entity action uses [action], preserving its compile-time-validated method
/// identity without pretending that the generator can infer business meaning
/// from the method name.
final class ActivityOperation implements PersistedScalarValue<String> {
  const ActivityOperation._(this._value);

  factory ActivityOperation.fromScalar(String source) {
    if (_conventionalActivityOperations.contains(source) ||
        _activityActionPattern.hasMatch(source)) {
      return ActivityOperation._(source);
    }
    throw FormatException('Invalid activity operation.', source);
  }

  factory ActivityOperation.action(String methodName) {
    if (!_activityMethodPattern.hasMatch(methodName)) {
      throw ArgumentError.value(
        methodName,
        'methodName',
        'An activity action must be a lowerCamelCase Dart identifier.',
      );
    }
    return ActivityOperation._('action:$methodName');
  }

  static const created = ActivityOperation._('created');
  static const edited = ActivityOperation._('edited');
  static const removed = ActivityOperation._('removed');
  static const restored = ActivityOperation._('restored');
  static const archived = ActivityOperation._('archived');
  static const unarchived = ActivityOperation._('unarchived');
  static const activated = ActivityOperation._('activated');
  static const deactivated = ActivityOperation._('deactivated');
  static const collaborationChanged = ActivityOperation._(
    'collaborationChanged',
  );
  static const reordered = ActivityOperation._('reordered');
  static const moved = ActivityOperation._('moved');

  final String _value;

  String? get actionName =>
      _value.startsWith('action:') ? _value.substring('action:'.length) : null;

  @override
  String toScalar() => _value;

  @override
  bool operator ==(Object other) =>
      other is ActivityOperation && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value;
}

const _conventionalActivityOperations = {
  'created',
  'edited',
  'removed',
  'restored',
  'archived',
  'unarchived',
  'activated',
  'deactivated',
  'collaborationChanged',
  'reordered',
  'moved',
};

final _activityMethodPattern = RegExp(r'^[a-z][a-zA-Z0-9]*$');
final _activityActionPattern = RegExp(r'^action:[a-z][a-zA-Z0-9]*$');

/// Adds a generated, immutable domain activity trail to an entity.
///
/// The concrete entity supplies a pure [activityLabel]. Generation snapshots
/// that label and appends one [ActivityOf] entry in the same mutation batch as
/// every successful durable create, edit, action, lifecycle, relationship, or
/// ordering operation.
abstract interface class ActivityTracked {
  String get activityLabel;
}

/// Declares the generated activity-entry entity for [Subject].
///
/// [Actor] must be the entity graph's authenticated owner type. The generator
/// supplies every persisted field and keeps the entry create-only outside its
/// internal mutation pipeline. [subjectId] is a historical nominal identity,
/// deliberately not a live relationship.
abstract interface class ActivityOf<Subject, Actor> {
  LocalId<Subject> get subjectId;

  LocalId<Actor> get actorId;

  ActivityOperation get operation;

  String get label;

  String get sourceOperationId;

  DateTime get occurredAt;
}

/// Controls whether generated entity-list selections expose soft-deleted rows.
///
/// Ordinary domain reads use [exclude]. Repair, audit, and recovery workflows
/// must opt into [include] or [only] explicitly; an additional query predicate
/// never weakens this lifecycle boundary by itself.
enum TombstoneVisibility { exclude, include, only }

/// Controls whether generated selections expose archived entities.
///
/// Ordinary lists use [exclude]. Archive views opt into [only], while exact
/// identity and administrative flows may use [include].
enum ArchiveVisibility { exclude, include, only }

/// A MobX-observable collection boundary without mutation capabilities.
///
/// Iteration, indexing, and [length] still report reads to the wrapped
/// [ObservableList], so reactions update normally. Mutations remain private to
/// the owning engine and therefore cannot bypass persistence or sync rules.
final class ReadOnlyObservableList<E> extends IterableBase<E> {
  ReadOnlyObservableList(ObservableList<E> source) : _source = source;

  final ObservableList<E> _source;

  @override
  Iterator<E> get iterator => _source.iterator;

  @override
  int get length => _source.length;

  E operator [](int index) => _source[index];
}

final class EntityValidationException implements Exception {
  const EntityValidationException({
    required this.entityType,
    required this.field,
    required this.message,
  });

  final String entityType;
  final String field;
  final String message;

  @override
  String toString() => '$entityType.$field: $message';
}

/// A generated identity lookup could not find the requested entity.
///
/// Keeping this failure in the runtime lets every generated unbounded set
/// expose the same lease-safe lookup API without importing an application's
/// error hierarchy or repeating a feature-specific missing-row policy.
final class EntityNotFoundException implements Exception {
  const EntityNotFoundException({
    required this.entityType,
    required this.entityId,
  });

  final String entityType;
  final String entityId;

  @override
  String toString() => '$entityType `$entityId` was not found.';
}

/// A local mutation was not permitted for the account-scoped entity graph.
///
/// This is a deterministic early rejection derived from the same grants used
/// to generate remote row security. Revocable server-only authorization still
/// remains authoritative at synchronization time.
final class EntityAuthorizationException implements Exception {
  const EntityAuthorizationException({
    required this.entityType,
    required this.entityId,
    required this.operation,
  });

  final String entityType;
  final String entityId;
  final RlsOperation operation;

  @override
  String toString() =>
      '$entityType `$entityId`: the authenticated account cannot '
      '${operation.name} this entity.';
}

enum EntityDraftFailureReason { consumed, stale, detached, entityGraphDisposed }

/// Typed lifecycle failure raised by a generated entity edit draft.
final class EntityDraftStateException implements Exception {
  const EntityDraftStateException({
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.message,
  });

  final String entityType;
  final String entityId;
  final EntityDraftFailureReason reason;
  final String message;

  @override
  String toString() => '$entityType `$entityId`: $message';
}

/// Typed conflict raised when an edit draft and a newer mutation changed the
/// same persisted fields to different values.
final class EntityDraftFieldConflictException implements Exception {
  EntityDraftFieldConflictException({
    required this.entityType,
    required this.entityId,
    required List<String> fields,
  }) : fields = List.unmodifiable(fields);

  final String entityType;
  final String entityId;
  final List<String> fields;

  @override
  String toString() =>
      '$entityType `$entityId`: the draft overlaps newer changes to '
      '${fields.map((field) => '`$field`').join(', ')}.';
}

/// Mutable, typed input owned by one generated create/edit draft.
///
/// A field can be genuinely unset, which lets creation forms distinguish a
/// missing required value from an explicitly supplied nullable value. Generated
/// drafts turn an unset required field into the same field-addressable
/// [EntityValidationException] used by entity actions.
final class EntityDraftField<T> {
  EntityDraftField.unset({bool writable = true})
    : _value = _unsetDraftValue,
      _writable = writable;

  EntityDraftField.value(T value, {bool writable = true})
    : _value = value,
      _writable = writable;

  static const Object _unsetDraftValue = Object();
  Object? _value;
  final bool _writable;

  bool get isSet => !identical(_value, _unsetDraftValue);

  T? get valueOrNull => isSet ? _value as T : null;

  T get value {
    if (!isSet) {
      throw StateError('This draft field has no value.');
    }
    return _value as T;
  }

  set value(T value) {
    _ensureWritable();
    _value = value;
  }

  void clear() {
    _ensureWritable();
    _value = _unsetDraftValue;
  }

  void _ensureWritable() {
    if (!_writable) {
      throw StateError('This field is available only while creating.');
    }
  }

  T requireValue({required String entityType, required String field}) {
    if (!isSet) {
      throw EntityValidationException(
        entityType: entityType,
        field: field,
        message: 'A value is required.',
      );
    }
    return _value as T;
  }
}

/// Common lifecycle exposed by generated create/edit drafts.
abstract interface class EntityMutationDraft<E> {
  bool get isCreating;

  E? get entity;

  LocalId<E> get id;

  bool get isConsumed;

  Future<E> save();

  void discard();
}

/// One generated, typed child-collection mutation inside an aggregate.
///
/// Collection drafts load only a domain-declared bounded inverse, preserve
/// existing child identities, and own create/edit/remove/order persistence in
/// one entity-graph transaction. They intentionally expose the generated child
/// drafts so application code can keep genuine business mapping and guards
/// without rebuilding infrastructure mechanics.
abstract interface class AggregateCollectionDraft {
  bool get isConsumed;

  Future<void> save();

  void discard();
}

/// One generated root draft spanning an entity and its declared aggregate
/// mutation parts.
abstract interface class AggregateMutationDraft<E>
    implements EntityMutationDraft<E> {
  EntityMutationDraft<E> get root;
}

/// Completion of one local entity mutation batch.
///
/// The future carrying this value never completes with an unhandled error, so
/// ignored optimistic entity actions may safely leave it unobserved. Generated
/// awaitable APIs call [throwIfFailed] to surface their exact persistence
/// failure without flushing unrelated mutations.
final class LocalMutationCommitResult {
  const LocalMutationCommitResult.success() : error = null, stackTrace = null;

  const LocalMutationCommitResult.failure(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => error == null;

  void throwIfFailed() {
    final failure = error;
    if (failure == null) return;
    Error.throwWithStackTrace(failure, stackTrace!);
  }
}

/// A lazily observed local mutation completion.
///
/// Mutation persistence reports failures as values so an intentionally ignored
/// optimistic action cannot create an unhandled asynchronous error. As soon as
/// a caller awaits or otherwise observes this future, the exact persistence
/// failure is rethrown with its original stack trace.
final class LocalMutationCompletion implements Future<void> {
  LocalMutationCompletion(this._result);

  final Future<LocalMutationCommitResult> _result;

  Future<void> _observed() async {
    final result = await _result;
    result.throwIfFailed();
  }

  @override
  Stream<void> asStream() => _observed().asStream();

  @override
  Future<void> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _observed().catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(void value) onValue, {
    Function? onError,
  }) => _observed().then(onValue, onError: onError);

  @override
  Future<void> timeout(
    Duration timeLimit, {
    FutureOr<void> Function()? onTimeout,
  }) => _observed().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<void> whenComplete(FutureOr<void> Function() action) =>
      _observed().whenComplete(action);
}

enum SyncFailureKind { retryable, rejected, conflict }

enum SyncRejectionCategory {
  authorization,
  validation,
  protocol,
  relationship,
  notFound,
  serverContract,
  other,
}

sealed class SyncBackendException implements Exception {
  const SyncBackendException({
    required this.code,
    required this.message,
    required this.kind,
  });

  final String code;
  final String message;
  final SyncFailureKind kind;

  @override
  String toString() => '$code: $message';
}

final class RetryableSyncException extends SyncBackendException {
  const RetryableSyncException({required super.code, required super.message})
    : super(kind: SyncFailureKind.retryable);
}

final class RejectedSyncException extends SyncBackendException {
  const RejectedSyncException.authorization({
    required super.message,
    super.code = 'authorization_denied',
  }) : category = SyncRejectionCategory.authorization,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.validation({
    required super.message,
    super.code = 'invalid_operation',
  }) : category = SyncRejectionCategory.validation,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.protocol({
    required super.message,
    super.code = 'unsupported_protocol_version',
  }) : category = SyncRejectionCategory.protocol,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.relationship({
    required super.message,
    super.code = 'relationship_denied',
  }) : category = SyncRejectionCategory.relationship,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.notFound({
    required super.message,
    super.code = 'entity_not_found',
  }) : category = SyncRejectionCategory.notFound,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.serverContract({
    required super.message,
    super.code = 'server_contract_violation',
  }) : category = SyncRejectionCategory.serverContract,
       super(kind: SyncFailureKind.rejected);

  const RejectedSyncException.other({
    required super.code,
    required super.message,
  }) : category = SyncRejectionCategory.other,
       super(kind: SyncFailureKind.rejected);

  final SyncRejectionCategory category;
}

final class VersionConflictException extends SyncBackendException {
  const VersionConflictException([String message = 'Server version conflict.'])
    : super(
        code: 'version_conflict',
        message: message,
        kind: SyncFailureKind.conflict,
      );
}

/// Supplies every local identity from the account-scoped composition root.
///
/// Entity and synchronization-operation IDs are separate nominal types while
/// sharing one injectable source for deterministic ordering and testing.
abstract interface class EntityIdGenerator {
  LocalId<T> next<T>();

  SyncOperationId nextOperationId();
}

final class UuidV7EntityIdGenerator implements EntityIdGenerator {
  const UuidV7EntityIdGenerator();

  @override
  LocalId<T> next<T>() => LocalId<T>(const Uuid().v7());

  @override
  SyncOperationId nextOperationId() => SyncOperationId(const Uuid().v7());
}

/// Nominal identity for one durable synchronization operation.
///
/// It remains distinct from entity IDs throughout runtime state and crosses to
/// a string only in generated persistence and transport codecs.
extension type const SyncOperationId._(String value) {
  factory SyncOperationId(String source) => parseSyncOperationId(source);
}

SyncOperationId parseSyncOperationId(String source) =>
    SyncOperationId._(parseLocalId<_SyncOperationIdentity>(source).value);

SyncOperationId? tryParseSyncOperationId(String source) {
  final parsed = tryParseLocalId<_SyncOperationIdentity>(source);
  return parsed == null ? null : SyncOperationId._(parsed.value);
}

abstract final class _SyncOperationIdentity {}

/// A non-negative position in the backend's globally ordered change log.
extension type const ServerSequence._(int value) {
  factory ServerSequence(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must be non-negative.');
    }
    return ServerSequence._(value);
  }

  static const zero = ServerSequence._(0);
}

ServerSequence parseServerSequence(Object? source) {
  final value = switch (source) {
    int value => value,
    num value when value.isFinite && value == value.truncate() => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  if (value == null || value < 0) {
    throw FormatException('Expected a non-negative server sequence.', source);
  }
  return ServerSequence._(value);
}

/// A non-negative optimistic-concurrency version assigned by the server.
///
/// Domain and synchronization APIs use this nominal type so versions cannot be
/// confused with local revisions or change-log sequences. Persistence codecs
/// unwrap it to an integer only at SQLite/PostgreSQL/JSON boundaries.
extension type const ServerVersion._(int value) implements Comparable<num> {
  factory ServerVersion(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must be non-negative.');
    }
    return ServerVersion._(value);
  }

  static const zero = ServerVersion._(0);
}

ServerVersion parseServerVersion(Object? source) {
  final value = switch (source) {
    int value => value,
    num value when value.isFinite && value == value.truncate() => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  if (value == null || value < 0) {
    throw FormatException('Expected a non-negative server version.', source);
  }
  return ServerVersion._(value);
}

/// The server-serialized revision of one canonical ordered scope.
///
/// This is deliberately distinct from an entity [ServerVersion]: moving one
/// member changes the shared order even when its neighbors are unchanged.
extension type const OrderScopeVersion._(int value) implements Comparable<num> {
  factory OrderScopeVersion(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must be non-negative.');
    }
    return OrderScopeVersion._(value);
  }

  static const zero = OrderScopeVersion._(0);
}

OrderScopeVersion parseOrderScopeVersion(Object? source) {
  final value = switch (source) {
    int value => value,
    num value when value.isFinite && value == value.truncate() => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  if (value == null || value < 0) {
    throw FormatException(
      'Expected a non-negative ordered-scope version.',
      source,
    );
  }
  return OrderScopeVersion._(value);
}

/// One authoritative version acknowledgement for a typed ordering scope.
///
/// The scope is carried as named canonical wire fields rather than an
/// adapter-specific encoded key. Generated descriptor metadata derives the
/// local identity, so composite and nullable scopes remain transport-neutral.
final class OrderScopeVersionReceipt {
  OrderScopeVersionReceipt({required JsonMap scope, required this.version})
    : scope = canonicalJsonObject(scope, field: 'orderScopeReceipt');

  factory OrderScopeVersionReceipt.fromWire(Object? source) {
    final receipt = canonicalJsonObject(source, field: 'orderScopeReceipt');
    if (receipt.length != 2 ||
        !receipt.containsKey('scope') ||
        !receipt.containsKey('version')) {
      throw const FormatException(
        'An ordered-scope receipt requires only scope and version.',
      );
    }
    return OrderScopeVersionReceipt(
      scope: canonicalJsonObject(
        receipt['scope'],
        field: 'orderScopeReceipt.scope',
      ),
      version: parseOrderScopeVersion(receipt['version']),
    );
  }

  final JsonMap scope;
  final OrderScopeVersion version;

  JsonMap toWire() => {'scope': scope, 'version': version.value};
}

/// Collision-free local identity for a composite generated ordering scope.
///
/// Components are already canonical wire values. JSON array encoding preserves
/// tuple order, scalar types, and null without field-name or sentinel guessing.
String encodeOrderScopeKey(List<Object?> components) =>
    jsonEncode(canonicalJsonArray(components, field: 'orderScope'));

abstract interface class Clock {
  DateTime nowUtc();
}

/// Mutation sink for generated records that are intentionally detached from a
/// local entity graph.
///
/// Detached records are useful for previews, pure-domain tests, and immutable
/// input fixtures. Generated actions still update their observable in-memory
/// state, but no persistence or synchronization work is recorded. Production
/// writes must use a generated set owned by an entity graph.
final class DetachedEntityMutationSink
    implements EntityMutationSink, OrderedTransferMutationSink {
  const DetachedEntityMutationSink();

  @override
  bool get isInMutationTransaction => false;

  @override
  String? get authenticatedPrincipalId => null;

  @override
  Future<R> runEntityTransaction<R>(Future<R> Function() body) => body();

  @override
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
  }) async => LocalMutationCommitResult.failure(
    EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity draft cannot be persisted.',
    ),
    StackTrace.current,
  );

  @override
  Future<LocalMutationCommitResult> recordEntityCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    TypedEntityPatch<D>? localPatch,
    bool persistsEntityState = false,
    DateTime? occurredAt,
    required void Function() rollbackIfCurrent,
  }) async => LocalMutationCommitResult.failure(
    EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity command cannot be persisted.',
    ),
    StackTrace.current,
  );

  @override
  Future<LocalMutationCommitResult> recordEntityScopeCommand<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntitySemanticCommand<D> command,
    required List<GeneratedOrderStateChange<D>> stateChanges,
    required String scopeKey,
    DateTime? occurredAt,
  }) async => LocalMutationCommitResult.failure(
    EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity scope command cannot be persisted.',
    ),
    StackTrace.current,
  );

  @override
  Future<GeneratedOrderTransferPlan<D>> prepareEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required EntityPatch targetScope,
    required OrderedPlacement placement,
  }) async {
    throw EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity cannot resolve an ordered transfer scope.',
    );
  }

  @override
  Future<LocalMutationCommitResult> recordEntityOrderTransfer<D>({
    required TypedGeneratedEntityRecord<D> entity,
    required TransferOrderedCommand<D> command,
    required GeneratedOrderStateChange<D> transferChange,
    required List<GeneratedOrderStateChange<D>> targetRebalanceChanges,
    DateTime? occurredAt,
  }) async => LocalMutationCommitResult.failure(
    EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity transfer cannot be persisted.',
    ),
    StackTrace.current,
  );

  @override
  void validateDraftTarget(GeneratedEntityRecord entity) {
    throw EntityDraftStateException(
      entityType: entity.generatedEntityType,
      entityId: entity.generatedEntityId,
      reason: EntityDraftFailureReason.detached,
      message: 'A detached entity cannot create a persistent edit draft.',
    );
  }

  @override
  void validateMutationAuthorization({
    required GeneratedEntityRecord entity,
    required RlsOperation operation,
    required List<RlsPrincipal> principals,
  }) {}

  @override
  E? resolveReference<E, R extends TypedGeneratedEntityRecord<E>>(
    EntityDescriptor<E, R> descriptor,
    String? entityId,
  ) => null;
}

sealed class LocalEntityDiagnostic {
  const LocalEntityDiagnostic({required this.occurredAt});

  final DateTime occurredAt;
}

final class LocalPersistenceFailureDiagnostic extends LocalEntityDiagnostic {
  const LocalPersistenceFailureDiagnostic({
    required super.occurredAt,
    required this.operationId,
    required this.identity,
    required this.operation,
    required this.localRevision,
    required this.error,
    required this.stackTrace,
  });

  final SyncOperationId operationId;
  final EntityIdentity<dynamic> identity;
  final SyncMutationOperation operation;
  final int localRevision;
  final Object error;
  final StackTrace stackTrace;
}

final class SyncFailureDiagnostic extends LocalEntityDiagnostic {
  const SyncFailureDiagnostic({
    required super.occurredAt,
    required this.workId,
    required this.target,
    required this.operationId,
    required this.direction,
    required this.identity,
    required this.attemptCount,
    required this.failure,
    required this.stackTrace,
    required this.resultingStatus,
    required this.retryAt,
  });

  final int workId;
  final SyncTargetId target;
  final SyncOperationId operationId;
  final SyncDirection direction;
  final EntityIdentity<dynamic>? identity;
  final int attemptCount;
  final SyncBackendException failure;
  final StackTrace stackTrace;
  final SyncWorkStatus resultingStatus;
  final DateTime? retryAt;
}

enum LocalEntityBackgroundTask {
  projectionRefresh,
  queueRefresh,
  remoteSignal,
  synchronization,
  durableProcess,
  secondaryProjection,
  shutdown,
}

enum GeneratedDurableWorkKind { process, projection }

/// Stable identity and retry metadata for one generated process/projection run.
final class GeneratedDurableWorkContext {
  const GeneratedDurableWorkContext({
    required this.operationId,
    required this.attempt,
  });

  final SyncOperationId operationId;
  final int attempt;
}

/// Internal binding emitted from an [EntityProcess] or [SecondaryProjection].
///
/// Application code receives a domain-named generated installer and supplies
/// only [run]. Direct construction is public solely because generated code is
/// emitted into the consuming package.
final class GeneratedDurableWorkBinding {
  GeneratedDurableWorkBinding({
    required this.name,
    required this.kind,
    required Iterable<Stream<Object?>> triggers,
    required this.run,
  }) : triggers = List.unmodifiable(triggers) {
    if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Expected lowerCamelCase.');
    }
    if (this.triggers.isEmpty) {
      throw ArgumentError.value(triggers, 'triggers', 'Must not be empty.');
    }
  }

  final String name;
  final GeneratedDurableWorkKind kind;
  final List<Stream<Object?>> triggers;
  final Future<void> Function(GeneratedDurableWorkContext context) run;
}

final class BackgroundTaskFailureDiagnostic extends LocalEntityDiagnostic {
  const BackgroundTaskFailureDiagnostic({
    required super.occurredAt,
    required this.task,
    required this.target,
    required this.entityType,
    required this.error,
    required this.stackTrace,
  });

  final LocalEntityBackgroundTask task;
  final SyncTargetId? target;
  final String? entityType;
  final Object error;
  final StackTrace stackTrace;
}

abstract interface class LocalEntityDiagnostics {
  void record(LocalEntityDiagnostic diagnostic);
}

final class NoopLocalEntityDiagnostics implements LocalEntityDiagnostics {
  const NoopLocalEntityDiagnostics();

  @override
  void record(LocalEntityDiagnostic diagnostic) {}
}

void _recordDiagnosticSafely(
  LocalEntityDiagnostics diagnostics,
  LocalEntityDiagnostic diagnostic,
) {
  try {
    diagnostics.record(diagnostic);
  } catch (_) {
    // Diagnostics must never change persistence or synchronization behavior.
  }
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

enum MutationOrigin { local, hydration, remote, rollback, migration }

enum SyncDirection { push, pull }

enum SyncWorkKind { statePatch, semanticCommand, pullChanges }

enum PushSyncWorkKind { statePatch, semanticCommand }

enum SyncMutationOperation { create, patch, delete, command }

enum SyncWorkStatus {
  pending,
  processing,
  retryableFailure,
  rejected,
  conflict,
}

enum SyncPhase { idle, syncing, waitingToRetry, needsAttention, failed }

final class SyncState {
  const SyncState(this.phase, {this.message});

  const SyncState.idle() : this(SyncPhase.idle);

  final SyncPhase phase;
  final String? message;
}

enum EntityComparison {
  equal,
  notEqual,
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual,
}

enum EntityLogicalOperator { and, or }

enum EntitySortDirection { ascending, descending }

enum NullPlacement { first, last }

/// A structurally comparable predicate that can be evaluated in memory or
/// translated to Drift SQL without inspecting a callback.
sealed class EntityPredicate<E> {
  const EntityPredicate();

  const factory EntityPredicate.all() = _AllEntityPredicate<E>;

  bool test(E entity);

  EntityPredicate<E> operator &(EntityPredicate<E> other) =>
      _LogicalEntityPredicate.normalized(
        EntityLogicalOperator.and,
        this,
        other,
      );

  EntityPredicate<E> operator |(EntityPredicate<E> other) =>
      _LogicalEntityPredicate.normalized(EntityLogicalOperator.or, this, other);

  String get _stableKey;

  Set<String> get _fieldNames;

  R _accept<R>(_EntityPredicateVisitor<E, R> visitor);
}

abstract interface class _EntityPredicateVisitor<E, R> {
  R visitAll();

  R visitComparison<V>(
    EntityField<E, V> field,
    EntityComparison comparison,
    V expected,
  );

  R visitNull<V>(EntityField<E, V?> field, {required bool expectsNull});

  R visitMembership<V>(EntityField<E, V> field, List<V> expected);

  R visitLogical(
    EntityLogicalOperator operator,
    List<EntityPredicate<E>> operands,
  );
}

final class _MembershipEntityPredicate<E, V> extends EntityPredicate<E> {
  _MembershipEntityPredicate(this.field, Iterable<V> expected)
    : expected = _normalizedQueryValues(expected);

  final EntityField<E, V> field;
  final List<V> expected;

  @override
  bool test(E entity) => expected.any(
    (candidate) => entityValuesEqual(candidate, field.read(entity)),
  );

  @override
  String get _stableKey =>
      '${field.name}:in(${expected.map(_stableQueryValue).join(',')})';

  @override
  Set<String> get _fieldNames => {field.name};

  @override
  R _accept<R>(_EntityPredicateVisitor<E, R> visitor) =>
      visitor.visitMembership(field, expected);

  @override
  bool operator ==(Object other) =>
      other is _MembershipEntityPredicate<E, V> &&
      field == other.field &&
      _iterableEquals(expected, other.expected);

  @override
  int get hashCode => Object.hash(field, _stableKey);
}

final class _AllEntityPredicate<E> extends EntityPredicate<E> {
  const _AllEntityPredicate();

  @override
  bool test(E entity) => true;

  @override
  String get _stableKey => 'all';

  @override
  Set<String> get _fieldNames => const {};

  @override
  R _accept<R>(_EntityPredicateVisitor<E, R> visitor) => visitor.visitAll();

  @override
  bool operator ==(Object other) => other is _AllEntityPredicate<E>;

  @override
  int get hashCode => Object.hash(E, _AllEntityPredicate);
}

final class _ComparisonEntityPredicate<E, V> extends EntityPredicate<E> {
  const _ComparisonEntityPredicate(this.field, this.comparison, this.expected);

  final EntityField<E, V> field;
  final EntityComparison comparison;
  final V expected;

  @override
  bool test(E entity) {
    final actual = field.read(entity);
    return switch (comparison) {
      EntityComparison.equal => entityValuesEqual(actual, expected),
      EntityComparison.notEqual => !entityValuesEqual(actual, expected),
      EntityComparison.lessThan =>
        actual != null &&
            expected != null &&
            (actual as Comparable<dynamic>).compareTo(expected) < 0,
      EntityComparison.lessThanOrEqual =>
        actual != null &&
            expected != null &&
            (actual as Comparable<dynamic>).compareTo(expected) <= 0,
      EntityComparison.greaterThan =>
        actual != null &&
            expected != null &&
            (actual as Comparable<dynamic>).compareTo(expected) > 0,
      EntityComparison.greaterThanOrEqual =>
        actual != null &&
            expected != null &&
            (actual as Comparable<dynamic>).compareTo(expected) >= 0,
    };
  }

  @override
  String get _stableKey =>
      '${field.name}:${comparison.name}:${_stableQueryValue(expected)}';

  @override
  Set<String> get _fieldNames => {field.name};

  @override
  R _accept<R>(_EntityPredicateVisitor<E, R> visitor) =>
      visitor.visitComparison<V>(field, comparison, expected);

  @override
  bool operator ==(Object other) =>
      other is _ComparisonEntityPredicate<E, V> &&
      field == other.field &&
      comparison == other.comparison &&
      entityValuesEqual(expected, other.expected);

  @override
  int get hashCode => Object.hash(field, comparison, _stableKey);
}

final class _NullEntityPredicate<E, V> extends EntityPredicate<E> {
  const _NullEntityPredicate(this.field, {required this.expectsNull});

  final EntityField<E, V?> field;
  final bool expectsNull;

  @override
  bool test(E entity) => (field.read(entity) == null) == expectsNull;

  @override
  String get _stableKey => '${field.name}:${expectsNull ? 'null' : 'notNull'}';

  @override
  Set<String> get _fieldNames => {field.name};

  @override
  R _accept<R>(_EntityPredicateVisitor<E, R> visitor) =>
      visitor.visitNull<V>(field, expectsNull: expectsNull);

  @override
  bool operator ==(Object other) =>
      other is _NullEntityPredicate<E, V> &&
      field == other.field &&
      expectsNull == other.expectsNull;

  @override
  int get hashCode => Object.hash(field, expectsNull);
}

final class _LogicalEntityPredicate<E> extends EntityPredicate<E> {
  _LogicalEntityPredicate._(this.operator, this.operands);

  static EntityPredicate<E> normalized<E>(
    EntityLogicalOperator operator,
    EntityPredicate<E> left,
    EntityPredicate<E> right,
  ) {
    final expanded = <EntityPredicate<E>>[
      if (left is _LogicalEntityPredicate<E> && left.operator == operator)
        ...left.operands
      else
        left,
      if (right is _LogicalEntityPredicate<E> && right.operator == operator)
        ...right.operands
      else
        right,
    ]..sort((a, b) => a._stableKey.compareTo(b._stableKey));
    if (operator == EntityLogicalOperator.or &&
        expanded.any((part) => part is _AllEntityPredicate<E>)) {
      return EntityPredicate<E>.all();
    }
    final operands = <EntityPredicate<E>>[];
    for (final part in expanded) {
      if (operator == EntityLogicalOperator.and &&
          part is _AllEntityPredicate<E>) {
        continue;
      }
      if (operands.isEmpty || operands.last != part) operands.add(part);
    }
    if (operands.isEmpty) return EntityPredicate<E>.all();
    if (operands.length == 1) return operands.single;
    return _LogicalEntityPredicate._(
      operator,
      List<EntityPredicate<E>>.unmodifiable(operands),
    );
  }

  final EntityLogicalOperator operator;
  final List<EntityPredicate<E>> operands;

  @override
  bool test(E entity) => switch (operator) {
    EntityLogicalOperator.and => operands.every((part) => part.test(entity)),
    EntityLogicalOperator.or => operands.any((part) => part.test(entity)),
  };

  @override
  String get _stableKey =>
      '${operator.name}(${operands.map((part) => part._stableKey).join(',')})';

  @override
  Set<String> get _fieldNames => {
    for (final operand in operands) ...operand._fieldNames,
  };

  @override
  R _accept<R>(_EntityPredicateVisitor<E, R> visitor) =>
      visitor.visitLogical(operator, operands);

  @override
  bool operator ==(Object other) =>
      other is _LogicalEntityPredicate<E> &&
      operator == other.operator &&
      _iterableEquals(operands, other.operands);

  @override
  int get hashCode => Object.hash(operator, Object.hashAll(operands));
}

/// Base metadata shared by generated field capabilities.
sealed class EntityFieldReference<E> {
  const EntityFieldReference();

  String get name;
}

sealed class EntityField<E, V> extends EntityFieldReference<E> {
  const EntityField({
    required this.name,
    required this.read,
    required this.encode,
    this.normalize,
  }) : super();

  @override
  final String name;
  final V Function(E entity) read;
  final Object? Function(V value) encode;
  final V Function(V value)? normalize;

  /// Returns the same canonical value used by patches, predicates, storage,
  /// synchronization, and generated mutation APIs.
  ///
  /// This is useful when domain code must key or deduplicate an in-memory
  /// collection before it reaches persistence.
  V canonicalize(V value) => normalize == null ? value : normalize!(value);

  TypedEntityPatch<E> patch(V value) =>
      TypedEntityPatch<E>._({name: encode(canonicalize(value))});

  EntityPredicate<E> equals(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.equal,
    canonicalize(expected),
  );

  EntityPredicate<E> notEquals(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.notEqual,
    canonicalize(expected),
  );

  /// Matches any of the provided typed values. Empty input matches nothing.
  EntityPredicate<E> isIn(Iterable<V> expected) =>
      _MembershipEntityPredicate(this, expected.map(canonicalize));

  @override
  bool operator ==(Object other) =>
      other is EntityField<E, V> && name == other.name;

  @override
  int get hashCode => Object.hash(E, V, name);
}

/// A generated persisted field with its storage metadata and one wire codec.
///
/// Query-only fields intentionally do not implement this interface, so generic
/// persistence code cannot request storage metadata or decoding from them.
abstract interface class PersistedEntityFieldReference<E>
    implements EntityFieldReference<E> {
  EntityFieldDescriptor get persistence;

  Object? encodeEntity(E entity);
}

extension PersistedEntityFieldConstraints<E>
    on PersistedEntityFieldReference<E> {
  EntityFieldConstraints get constraints => persistence.constraints;
}

abstract base class PersistedEntityField<E, V> extends EntityField<E, V>
    implements PersistedEntityFieldReference<E> {
  PersistedEntityField({
    required this.persistence,
    required super.read,
    required super.encode,
    super.normalize,
    required this.decode,
  }) : super(name: persistence.name);

  @override
  final EntityFieldDescriptor persistence;
  final V Function(Object? source) decode;

  @override
  Object? encodeEntity(E entity) => encode(read(entity));
}

/// Equality-only capability for IDs, booleans, and other non-ordered values.
final class EqualityEntityField<E, V> extends EntityField<E, V> {
  const EqualityEntityField({
    required super.name,
    required super.read,
    required super.encode,
    super.normalize,
  });
}

final class PersistedEqualityEntityField<E, V>
    extends PersistedEntityField<E, V> {
  PersistedEqualityEntityField({
    required super.persistence,
    required super.read,
    required super.encode,
    super.normalize,
    required super.decode,
  });
}

mixin _ComparableFieldCapabilities<E, V extends Comparable<dynamic>>
    on EntityField<E, V> {
  EntityPredicate<E> isLessThan(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.lessThan,
    canonicalize(expected),
  );

  EntityPredicate<E> isAtMost(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.lessThanOrEqual,
    canonicalize(expected),
  );

  EntityPredicate<E> isGreaterThan(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.greaterThan,
    canonicalize(expected),
  );

  EntityPredicate<E> isAtLeast(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.greaterThanOrEqual,
    canonicalize(expected),
  );

  EntityPredicate<E> isBetween(V lower, V upper) =>
      isAtLeast(lower) & isAtMost(upper);

  EntityOrder<E> ascending({String Function(E entity)? tieBreakBy}) =>
      EntityOrder._(
        fieldName: name,
        direction: EntitySortDirection.ascending,
        nulls: NullPlacement.last,
        compare: (left, right) {
          final primary = read(left).compareTo(read(right));
          return primary != 0 || tieBreakBy == null
              ? primary
              : tieBreakBy(left).compareTo(tieBreakBy(right));
        },
      );

  EntityOrder<E> descending({String Function(E entity)? tieBreakBy}) =>
      EntityOrder._(
        fieldName: name,
        direction: EntitySortDirection.descending,
        nulls: NullPlacement.last,
        compare: (left, right) {
          final primary = read(right).compareTo(read(left));
          return primary != 0 || tieBreakBy == null
              ? primary
              : tieBreakBy(right).compareTo(tieBreakBy(left));
        },
      );
}

/// Equality and ordering capability for non-null comparable values.
final class ComparableEntityField<E, V extends Comparable<dynamic>>
    extends EntityField<E, V>
    with _ComparableFieldCapabilities<E, V> {
  const ComparableEntityField({
    required super.name,
    required super.read,
    required super.encode,
    super.normalize,
  });
}

final class PersistedComparableEntityField<E, V extends Comparable<dynamic>>
    extends PersistedEntityField<E, V>
    with _ComparableFieldCapabilities<E, V> {
  PersistedComparableEntityField({
    required super.persistence,
    required super.read,
    required super.encode,
    super.normalize,
    required super.decode,
  });
}

mixin _NullableFieldCapabilities<E, V> on EntityField<E, V?> {
  EntityPredicate<E> get isNull =>
      _NullEntityPredicate<E, V>(this, expectsNull: true);

  EntityPredicate<E> get isNotNull =>
      _NullEntityPredicate<E, V>(this, expectsNull: false);
}

/// Equality and nullability capability for non-ordered nullable values.
final class NullableEntityField<E, V> extends EntityField<E, V?>
    with _NullableFieldCapabilities<E, V> {
  const NullableEntityField({
    required super.name,
    required super.read,
    required super.encode,
    super.normalize,
  });
}

final class PersistedNullableEntityField<E, V>
    extends PersistedEntityField<E, V?>
    with _NullableFieldCapabilities<E, V> {
  PersistedNullableEntityField({
    required super.persistence,
    required super.read,
    required super.encode,
    super.normalize,
    required super.decode,
  });
}

mixin _NullableComparableFieldCapabilities<E, V extends Comparable<dynamic>>
    on EntityField<E, V?> {
  EntityPredicate<E> isLessThan(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.lessThan,
    canonicalize(expected),
  );

  EntityPredicate<E> isAtMost(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.lessThanOrEqual,
    canonicalize(expected),
  );

  EntityPredicate<E> isGreaterThan(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.greaterThan,
    canonicalize(expected),
  );

  EntityPredicate<E> isAtLeast(V expected) => _ComparisonEntityPredicate(
    this,
    EntityComparison.greaterThanOrEqual,
    canonicalize(expected),
  );

  EntityPredicate<E> isBetween(V lower, V upper) =>
      isAtLeast(lower) & isAtMost(upper);

  EntityPredicate<E> get isNull =>
      _NullEntityPredicate<E, V>(this, expectsNull: true);

  EntityPredicate<E> get isNotNull =>
      _NullEntityPredicate<E, V>(this, expectsNull: false);

  EntityOrder<E> ascending({
    NullPlacement nulls = NullPlacement.last,
    String Function(E entity)? tieBreakBy,
  }) => EntityOrder._(
    fieldName: name,
    direction: EntitySortDirection.ascending,
    nulls: nulls,
    compare: (left, right) {
      final primary = _compareNullable(read(left), read(right), nulls: nulls);
      return primary != 0 || tieBreakBy == null
          ? primary
          : tieBreakBy(left).compareTo(tieBreakBy(right));
    },
  );

  EntityOrder<E> descending({
    NullPlacement nulls = NullPlacement.last,
    String Function(E entity)? tieBreakBy,
  }) => EntityOrder._(
    fieldName: name,
    direction: EntitySortDirection.descending,
    nulls: nulls,
    compare: (left, right) {
      final primary = _compareNullable(
        read(left),
        read(right),
        nulls: nulls,
        descending: true,
      );
      return primary != 0 || tieBreakBy == null
          ? primary
          : tieBreakBy(right).compareTo(tieBreakBy(left));
    },
  );
}

/// Equality, nullability, and ordering capability for nullable comparables.
final class NullableComparableEntityField<E, V extends Comparable<dynamic>>
    extends EntityField<E, V?>
    with _NullableComparableFieldCapabilities<E, V> {
  const NullableComparableEntityField({
    required super.name,
    required super.read,
    required super.encode,
    super.normalize,
  });
}

final class PersistedNullableComparableEntityField<
  E,
  V extends Comparable<dynamic>
>
    extends PersistedEntityField<E, V?>
    with _NullableComparableFieldCapabilities<E, V> {
  PersistedNullableComparableEntityField({
    required super.persistence,
    required super.read,
    required super.encode,
    super.normalize,
    required super.decode,
  });
}

final class EntityOrder<E> {
  const EntityOrder._({
    required this.fieldName,
    required this.direction,
    required this.nulls,
    required this.compare,
  });

  final String fieldName;
  final EntitySortDirection direction;
  final NullPlacement nulls;
  final Comparator<E> compare;

  @override
  bool operator ==(Object other) =>
      other is EntityOrder<E> &&
      fieldName == other.fieldName &&
      direction == other.direction &&
      nulls == other.nulls;

  @override
  int get hashCode => Object.hash(E, fieldName, direction, nulls);
}

/// The immutable identity of an entity query.
///
/// Query caches use value equality, so rebuilding a widget with an equivalent
/// predicate and order does not create duplicate subscriptions or SQL work.
final class EntityQuerySpec<E> {
  EntityQuerySpec({
    EntityPredicate<E>? where,
    this.orderBy,
    this.pageSize = defaultPageSize,
  }) : where = where ?? EntityPredicate<E>.all() {
    if (pageSize <= 0) {
      throw RangeError.value(
        pageSize,
        'pageSize',
        'Must be greater than zero.',
      );
    }
  }

  static const int defaultPageSize = 50;

  final EntityPredicate<E> where;
  final EntityOrder<E>? orderBy;
  final int pageSize;

  Set<String> get _fieldNames => {
    ...where._fieldNames,
    if (orderBy case final order?) order.fieldName,
  };

  @override
  bool operator ==(Object other) =>
      other is EntityQuerySpec<E> &&
      where == other.where &&
      orderBy == other.orderBy &&
      pageSize == other.pageSize;

  @override
  int get hashCode => Object.hash(E, where, orderBy, pageSize);
}

/// Describes the smallest persisted projection change that can affect queries.
///
/// Unknown external database writes conservatively refresh every query.
/// Creates/deletes can change every query's membership. Patches refresh only
/// queries whose predicate or order references a changed field; loaded entity
/// objects already expose other field changes reactively.
final class EntityProjectionChange<E> {
  const EntityProjectionChange.unknown()
    : isUnknown = true,
      affectsMembership = true,
      _fieldNames = const {};

  const EntityProjectionChange.membership()
    : isUnknown = false,
      affectsMembership = true,
      _fieldNames = const {};

  EntityProjectionChange.fields(Iterable<EntityFieldReference<E>> fields)
    : this._fromFieldNames(fields.map((field) => field.name));

  EntityProjectionChange._fromFieldNames(Iterable<String> fields)
    : isUnknown = false,
      affectsMembership = false,
      _fieldNames = Set.unmodifiable(fields);

  final bool isUnknown;
  final bool affectsMembership;
  final Set<String> _fieldNames;

  bool affectsFields(Iterable<String> fieldNames) {
    if (isUnknown || affectsMembership) return true;
    final selected = fieldNames.toSet();
    return selected.isEmpty || selected.any(_fieldNames.contains);
  }

  EntityProjectionChange<E> _merge(EntityProjectionChange<E> other) {
    if (isUnknown || other.isUnknown) {
      return EntityProjectionChange<E>.unknown();
    }
    if (affectsMembership || other.affectsMembership) {
      return EntityProjectionChange<E>.membership();
    }
    return EntityProjectionChange<E>._fromFieldNames({
      ..._fieldNames,
      ...other._fieldNames,
    });
  }

  bool _affects(EntityQuerySpec<E> spec) {
    if (isUnknown || affectsMembership) return true;
    return spec._fieldNames.any(_fieldNames.contains);
  }
}

sealed class EntityQueryState<E> {
  const EntityQueryState({required this.items, required this.hasMore});

  final List<E> items;
  final bool hasMore;
}

final class EntityQueryInitialLoading<E> extends EntityQueryState<E> {
  const EntityQueryInitialLoading()
    : super(items: const <Never>[], hasMore: false);
}

final class EntityQueryData<E> extends EntityQueryState<E> {
  const EntityQueryData({required super.items, required super.hasMore});
}

final class EntityQueryEmpty<E> extends EntityQueryState<E> {
  const EntityQueryEmpty() : super(items: const <Never>[], hasMore: false);
}

final class EntityQueryStaleData<E> extends EntityQueryState<E> {
  const EntityQueryStaleData({required super.items, required super.hasMore});
}

final class EntityQueryFailure<E> extends EntityQueryState<E> {
  const EntityQueryFailure({
    required this.error,
    required super.items,
    required super.hasMore,
  });

  final Object error;
}

final class EntityQueryDisposed<E> extends EntityQueryState<E> {
  const EntityQueryDisposed() : super(items: const <Never>[], hasMore: false);
}

/// Adapts typed query state to immutable item snapshots for legacy stream
/// composition boundaries without hiding query failures.
///
/// Direct MobX UI observes [LocalEntityQuery.state]. This narrow adapter exists
/// for non-UI consumers that already compose streams while migrating to the
/// generated entity graph; initial/disposed states do not invent an empty result.
extension EntityQueryStateStreamSnapshots<E> on Stream<EntityQueryState<E>> {
  Stream<List<E>> get itemSnapshots => transform(
    StreamTransformer.fromHandlers(
      handleData: (state, sink) {
        switch (state) {
          case EntityQueryData<E>(:final items) ||
              EntityQueryStaleData<E>(:final items):
            sink.add(List<E>.unmodifiable(items));
          case EntityQueryEmpty<E>():
            sink.add(List<E>.empty(growable: false));
          case EntityQueryFailure<E>(:final error):
            sink.addError(error);
          case EntityQueryInitialLoading<E>() || EntityQueryDisposed<E>():
            break;
        }
      },
    ),
  );
}

final class EntityQueryPage<E> {
  const EntityQueryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.release,
  });

  final List<E> items;
  final bool hasMore;
  final EntityQueryCursor? nextCursor;

  /// Releases resources retained while this page is visible.
  final void Function()? release;
}

/// Work performed while an on-demand identity is retained.
///
/// This public alias keeps generated libraries independent of a direct
/// `dart:async` import while preserving synchronous and asynchronous actions.
typedef LeaseAction<E, R> = FutureOr<R> Function(E entity);

/// Keeps an on-demand entity materialized for exactly as long as its consumer
/// needs the stable object identity.
final class EntityLookupLease<E> {
  EntityLookupLease(this.value, void Function() release) : _release = release;

  final E value;
  final void Function() _release;
  bool _released = false;

  /// Runs [action] while this identity is retained, then releases the lease.
  ///
  /// Prefer this callback boundary for imperative work so success, failure,
  /// and synchronous exceptions cannot leak an unbounded identity retain.
  Future<R> use<R>(LeaseAction<E, R> action) async {
    if (_released) throw StateError('Cannot use a released entity lease.');
    try {
      return await action(value);
    } finally {
      release();
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Owns an optional asynchronous lookup lease for exactly one callback.
///
/// Generated `loadById` methods return this future shape. The callback keeps a
/// present identity retained, [ifAbsent] defines the caller's missing-entity
/// policy, and every exit path releases the lease.
extension EntityLookupLeaseFuture<E> on Future<EntityLookupLease<E>?> {
  Future<R> use<R>(
    LeaseAction<E, R> action, {
    required FutureOr<R> Function() ifAbsent,
  }) async {
    final lease = await this;
    if (lease == null) return await ifAbsent();
    return lease.use(action);
  }
}

/// Opaque continuation state produced and consumed by one page loader.
abstract interface class EntityQueryCursor {}

typedef EntityQueryPageLoader<E> =
    Future<EntityQueryPage<E>> Function(
      EntityQuerySpec<E> spec, {
      required EntityQueryCursor? after,
      required int limit,
    });

final class LocalEntityQuery<E> {
  factory LocalEntityQuery({
    required ReadOnlyObservableList<E> source,
    EntityPredicate<E>? where,
    EntityOrder<E>? orderBy,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) {
    final spec = EntityQuerySpec<E>(
      where: where,
      orderBy: orderBy,
      pageSize: pageSize,
    );
    final controller = _LocalEntityQueryController<E>.inMemory(
      source: source,
      spec: spec,
    );
    return LocalEntityQuery._(controller, controller.dispose);
  }

  LocalEntityQuery._(this._controller, this._release) {
    state = Computed(() {
      if (_released.value) return EntityQueryDisposed<E>();
      return _controller.state.value;
    });
  }

  final _LocalEntityQueryController<E> _controller;
  final void Function() _release;
  final Observable<bool> _released = Observable(false);
  late final Computed<EntityQueryState<E>> state;

  EntityQuerySpec<E> get spec => _controller.spec;

  List<E> get items => state.value.items;

  bool get hasMore => state.value.hasMore;

  Future<void> loadNextPage() =>
      _released.value ? Future<void>.value() : _controller.loadNextPage();

  Future<void> refresh() =>
      _released.value ? Future<void>.value() : _controller.refresh();

  /// Resolves the first loaded page without walking an unbounded result set.
  ///
  /// Use this for existence checks, unique lookups, previews, and top-N reads.
  /// The returned list is immutable and contains at most `spec.pageSize`
  /// entities. The query lease remains owned by the caller.
  Future<List<E>> loadFirstPage() async {
    if (_released.value) {
      throw StateError('Cannot load a disposed entity query.');
    }
    await _controller.waitForIdle();
    if (_released.value) {
      throw StateError('Entity query was disposed while loading.');
    }
    final current = state.value;
    if (current case EntityQueryFailure<E>(:final error)) throw error;
    if (current is EntityQueryDisposed<E>) {
      throw StateError('Entity query was disposed while loading.');
    }
    return List<E>.unmodifiable(current.items.take(spec.pageSize));
  }

  /// Resolves a complete, immutable snapshot of this query.
  ///
  /// Database-backed queries wait for their active refresh and load every
  /// remaining page. A failed page is surfaced to the caller rather than
  /// returning a partial result. The query lease remains owned by the caller.
  Future<List<E>> loadAll() async {
    if (_released.value) {
      throw StateError('Cannot load a disposed entity query.');
    }

    while (true) {
      await _controller.waitForIdle();
      if (_released.value) {
        throw StateError('Entity query was disposed while loading.');
      }

      final current = state.value;
      if (current case EntityQueryFailure<E>(:final error)) throw error;
      if (current is EntityQueryDisposed<E>) {
        throw StateError('Entity query was disposed while loading.');
      }
      if (!current.hasMore) return List<E>.unmodifiable(current.items);

      final previousLength = current.items.length;
      await _controller.loadNextPage();
      await _controller.waitForIdle();
      final next = state.value;
      if (next case EntityQueryFailure<E>(:final error)) throw error;
      if (next is EntityQueryDisposed<E>) {
        throw StateError('Entity query was disposed while loading.');
      }
      if (next.hasMore && next.items.length <= previousLength) {
        final error = StateError('Entity query paging made no progress.');
        _controller.reportExhaustiveFailure(error);
        throw error;
      }
    }
  }

  /// Loads one immutable page, keeps its identities retained for [action],
  /// and disposes this query on every exit path.
  ///
  /// Use this for imperative single-page or bounded lookups. [useAll] remains
  /// the explicit choice when the action requires an exhaustive snapshot.
  Future<R> useFirstPage<R>(FutureOr<R> Function(List<E> items) action) async {
    if (_released.value) {
      throw StateError('Cannot use a disposed entity query.');
    }
    try {
      return await action(await loadFirstPage());
    } finally {
      dispose();
    }
  }

  /// Loads a complete snapshot, keeps its identities retained for [action],
  /// and disposes this query on every exit path.
  ///
  /// This is the imperative counterpart to a UI-owned query lease. It avoids
  /// returning unbounded entities after their retention boundary has ended.
  Future<R> useAll<R>(FutureOr<R> Function(List<E> items) action) async {
    if (_released.value) {
      throw StateError('Cannot use a disposed entity query.');
    }
    try {
      return await action(await loadAll());
    } finally {
      dispose();
    }
  }

  /// Runs a generated semantic action over this selection in retained pages.
  ///
  /// This method is public only because application-generated code lives in a
  /// separate library. Domain callers use the named operation emitted on their
  /// concrete `EntityList`; exposing arbitrary callbacks from feature code is
  /// not a supported application surface.
  Future<EntityBulkMutationResult> runGeneratedBulkAction(
    Future<bool> Function(E entity) action, {
    required Future<void> Function(FutureOr<void> Function() body)
    runTransaction,
  }) async {
    if (_released.value) {
      throw StateError('Cannot mutate through a disposed entity query.');
    }
    var matched = 0;
    var changed = 0;
    try {
      if (!_controller.databaseBacked) {
        final entities = await loadAll();
        await runTransaction(() async {
          for (final entity in entities) {
            matched++;
            if (await action(entity)) changed++;
          }
        });
        return EntityBulkMutationResult(matched: matched, changed: changed);
      }

      EntityQueryCursor? cursor;
      while (true) {
        final page = await _controller.loadDetachedPage(
          after: cursor,
          limit: spec.pageSize,
        );
        final nextCursor = page.nextCursor;
        try {
          if (page.items.isEmpty) break;
          await runTransaction(() async {
            for (final entity in page.items) {
              matched++;
              if (await action(entity)) changed++;
            }
          });
        } finally {
          page.release?.call();
        }
        if (!page.hasMore) break;
        if (nextCursor == null) {
          throw StateError('Generated bulk paging did not return a cursor.');
        }
        cursor = nextCursor;
      }
      return EntityBulkMutationResult(matched: matched, changed: changed);
    } finally {
      dispose();
    }
  }

  /// Runs one declaration-generated durable process over canonical pages.
  ///
  /// No database transaction surrounds [action], so a typed external process
  /// may perform I/O and then commit its outcome through an entity action. The
  /// generated durable lane retries the complete deterministic scan.
  Future<void> runGeneratedProcess(
    Future<void> Function(E entity) action,
  ) async {
    if (_released.value) {
      throw StateError('Cannot process through a disposed entity query.');
    }
    try {
      if (!_controller.databaseBacked) {
        for (final entity in await loadAll()) {
          await action(entity);
        }
        return;
      }
      EntityQueryCursor? cursor;
      while (true) {
        final page = await _controller.loadDetachedPage(
          after: cursor,
          limit: spec.pageSize,
        );
        final nextCursor = page.nextCursor;
        try {
          for (final entity in page.items) {
            await action(entity);
          }
        } finally {
          page.release?.call();
        }
        if (!page.hasMore) return;
        if (nextCursor == null) {
          throw StateError('Generated process paging returned no cursor.');
        }
        cursor = nextCursor;
      }
    } finally {
      dispose();
    }
  }

  /// Emits exhaustive query state after each observable projection change.
  ///
  /// Each invocation creates one single-subscription bridge. The caller owns
  /// both the stream subscription and this query lease. [observeFields]
  /// explicitly opts legacy stream consumers into selected stable-entity field
  /// changes without forcing a query reload.
  Stream<EntityQueryState<E>> watchStates({
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) {
    final observed = List<PersistedEntityFieldReference<E>>.unmodifiable(
      observeFields,
    );
    late final StreamController<EntityQueryState<E>> controller;
    ReactionDisposer? disposeReaction;
    controller = StreamController<EntityQueryState<E>>(
      sync: true,
      onListen: () {
        disposeReaction = reaction<_EntityQueryObservation<E>>(
          (_) {
            final current = state.value;
            for (final entity in current.items) {
              for (final field in observed) {
                field.encodeEntity(entity);
              }
            }
            return _EntityQueryObservation(current);
          },
          (observation) => controller.add(observation.state),
          fireImmediately: true,
        );
      },
      onCancel: () {
        disposeReaction?.call();
        disposeReaction = null;
      },
    );
    return controller.stream;
  }

  /// Watches this query as one exhaustive, lease-owning stream.
  ///
  /// Partial pages are never emitted. A refresh keeps the previous complete
  /// snapshot visible until every replacement page has loaded. Cancelling the
  /// subscription releases this query, so consumers cannot accidentally leave
  /// an unbounded identity set retained after observation ends.
  Stream<EntityQueryState<E>> watchCompleteStates({
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) {
    List<E> lastCompleteItems = const [];
    var loadingAll = false;
    var cancelled = false;
    late final StreamSubscription<EntityQueryState<E>> subscription;
    late final StreamController<EntityQueryState<E>> controller;

    void loadRemainingPages() {
      if (loadingAll || cancelled) return;
      loadingAll = true;
      loadAll()
          .then(
            (_) {},
            onError: (_) {
              // loadAll publishes the typed query failure. Disposal errors
              // after cancellation are intentionally ignored.
            },
          )
          .whenComplete(() => loadingAll = false);
    }

    controller = StreamController<EntityQueryState<E>>(
      sync: true,
      onListen: () {
        subscription = watchStates(observeFields: observeFields).listen(
          (current) {
            if (current case EntityQueryFailure<E>(:final error)) {
              controller.add(
                EntityQueryFailure<E>(
                  error: error,
                  items: lastCompleteItems,
                  hasMore: false,
                ),
              );
              return;
            }
            if (current.hasMore) {
              loadRemainingPages();
              return;
            }
            if (current is EntityQueryData<E> ||
                current is EntityQueryEmpty<E> ||
                current is EntityQueryStaleData<E>) {
              lastCompleteItems = List<E>.unmodifiable(current.items);
            }
            controller.add(current);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        cancelled = true;
        await subscription.cancel();
        dispose();
      },
    );
    return controller.stream;
  }

  void dispose() {
    if (_released.value) return;
    runInAction(() => _released.value = true);
    _release();
  }
}

/// Lease-owning zero-or-one selection backed by an exact unique-index query.
///
/// Entity-graph generation emits a concrete `<Entity>Lookup` subclass only for
/// unique indexes whose singularity is statically unambiguous. The lookup owns
/// the query lease: imperative consumers should prefer [use], while UI code
/// acquires it with `useEntityLookup` and lets the widget lifetime dispose it.
class EntityLookup<E> {
  EntityLookup(this.query) {
    if (query.spec.pageSize != 1) {
      throw ArgumentError.value(
        query.spec.pageSize,
        'query.spec.pageSize',
        'An exact entity lookup must request exactly one row.',
      );
    }
  }

  final LocalEntityQuery<E> query;

  Computed<EntityQueryState<E>> get state => query.state;
  EntityQuerySpec<E> get spec => query.spec;

  /// The retained identity, or `null` when the exact key has no row.
  ///
  /// Access this only while the lookup is alive. A second row indicates local
  /// storage corruption or a descriptor/index mismatch and fails loudly.
  E? get value => _uniqueValue(query.items, hasMore: query.hasMore);

  Future<E?> load() async {
    final items = await query.loadFirstPage();
    return _uniqueValue(items, hasMore: query.hasMore);
  }

  /// Runs [action] while the selected identity is retained, then releases the
  /// lookup on success, absence, or failure.
  Future<R> use<R>(FutureOr<R> Function(E? value) action) => query.useFirstPage(
    (items) => action(_uniqueValue(items, hasMore: query.hasMore)),
  );

  Stream<EntityQueryState<E>> watchStates({
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) => query.watchCompleteStates(observeFields: observeFields);

  void dispose() => query.dispose();

  E? _uniqueValue(List<E> items, {required bool hasMore}) {
    if (hasMore || items.length > 1) {
      throw StateError(
        'An exact entity lookup matched more than one row. '
        'The generated unique-index contract is inconsistent with storage.',
      );
    }
    return items.isEmpty ? null : items.single;
  }
}

/// Lease-owning existence selection backed by one indexed query row.
///
/// Unlike [EntityLookup], this contract intentionally permits many matching
/// rows and answers only whether at least one exists.
class EntityExistence<E> {
  EntityExistence(this.query) {
    if (query.spec.pageSize != 1) {
      throw ArgumentError.value(
        query.spec.pageSize,
        'query.spec.pageSize',
        'An entity existence query must request exactly one row.',
      );
    }
  }

  final LocalEntityQuery<E> query;

  Computed<EntityQueryState<E>> get state => query.state;
  bool get value => query.items.isNotEmpty;

  Future<bool> load() async => (await query.loadFirstPage()).isNotEmpty;

  Future<R> use<R>(FutureOr<R> Function(bool exists) action) =>
      query.useFirstPage((items) => action(items.isNotEmpty));

  void dispose() => query.dispose();
}

/// Lease-owning first row of one explicitly ordered selection.
///
/// This is not a uniqueness claim. The generated set requires a typed order so
/// choosing the first row is deterministic domain query intent.
class EntityFirst<E> {
  EntityFirst(this.query) {
    if (query.spec.pageSize != 1 || query.spec.orderBy == null) {
      throw ArgumentError.value(
        query.spec,
        'query.spec',
        'An entity-first query requires one row and an explicit order.',
      );
    }
  }

  final LocalEntityQuery<E> query;

  Computed<EntityQueryState<E>> get state => query.state;
  E? get value => query.items.firstOrNull;

  Future<E?> load() async => (await query.loadFirstPage()).firstOrNull;

  Future<R> use<R>(FutureOr<R> Function(E? value) action) =>
      query.useFirstPage((items) => action(items.firstOrNull));

  void dispose() => query.dispose();
}

/// Domain-named live selection backed by one generated query lease.
///
/// Entity-graph generation emits a concrete `<Entity>List` subclass with
/// constructors inferred from ownership and typed references. The wrapper
/// keeps selection intent in the domain vocabulary while delegating loading,
/// paging, observation, and identity retention to [LocalEntityQuery].
class EntityList<E> {
  EntityList(this.query);

  final LocalEntityQuery<E> query;

  Computed<EntityQueryState<E>> get state => query.state;
  EntityQuerySpec<E> get spec => query.spec;
  List<E> get items => query.items;
  bool get hasMore => query.hasMore;

  Future<void> loadNextPage() => query.loadNextPage();
  Future<void> refresh() => query.refresh();
  Future<List<E>> loadFirstPage() => query.loadFirstPage();
  Future<List<E>> loadAll() => query.loadAll();

  Future<R> useFirstPage<R>(FutureOr<R> Function(List<E> items) action) =>
      query.useFirstPage(action);

  Future<R> useAll<R>(FutureOr<R> Function(List<E> items) action) =>
      query.useAll(action);

  /// Infrastructure entry point used by generated query-owned actions.
  ///
  /// Application code receives named methods such as `removeAll` or
  /// `markReadAll` on its generated entity list. Each database-backed batch is
  /// retained only for its transaction, committed in canonical query order,
  /// and released before the next page is loaded.
  Future<EntityBulkMutationResult> runGeneratedBulkAction(
    Future<bool> Function(E entity) action, {
    required Future<void> Function(FutureOr<void> Function() body)
    runTransaction,
  }) {
    return query.runGeneratedBulkAction(action, runTransaction: runTransaction);
  }

  /// Infrastructure entry point used by a named generated process binding.
  Future<void> runGeneratedProcess(Future<void> Function(E entity) action) =>
      query.runGeneratedProcess(action);

  Stream<EntityQueryState<E>> watchStates({
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) => query.watchStates(observeFields: observeFields);

  Stream<EntityQueryState<E>> watchCompleteStates({
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) => query.watchCompleteStates(observeFields: observeFields);

  void dispose() => query.dispose();
}

/// Result of one generated query-owned or hierarchy lifecycle operation.
final class EntityBulkMutationResult {
  const EntityBulkMutationResult({
    required this.matched,
    required this.changed,
  });

  final int matched;
  final int changed;

  int get skipped => matched - changed;
}

final class _EntityQueryObservation<E> {
  const _EntityQueryObservation(this.state);

  final EntityQueryState<E> state;
}

/// Runs two independent exhaustive queries in parallel and releases both
/// leases after [action] completes or any load/action fails.
extension LocalEntityQueryPairLease<A, B>
    on (LocalEntityQuery<A>, LocalEntityQuery<B>) {
  Future<R> useAll<R>(
    FutureOr<R> Function(List<A> first, List<B> second) action,
  ) async {
    try {
      final first = $1.loadAll();
      final second = $2.loadAll();
      await _waitForQueryLoads([first, second]);
      return await action(await first, await second);
    } finally {
      $1.dispose();
      $2.dispose();
    }
  }
}

/// Runs three independent exhaustive queries in parallel under one lease.
extension LocalEntityQueryTripleLease<A, B, C>
    on (LocalEntityQuery<A>, LocalEntityQuery<B>, LocalEntityQuery<C>) {
  Future<R> useAll<R>(
    FutureOr<R> Function(List<A> first, List<B> second, List<C> third) action,
  ) async {
    try {
      final first = $1.loadAll();
      final second = $2.loadAll();
      final third = $3.loadAll();
      await _waitForQueryLoads([first, second, third]);
      return await action(await first, await second, await third);
    } finally {
      $1.dispose();
      $2.dispose();
      $3.dispose();
    }
  }
}

/// Runs four independent exhaustive queries in parallel under one lease.
extension LocalEntityQueryQuadrupleLease<A, B, C, D>
    on
        (
          LocalEntityQuery<A>,
          LocalEntityQuery<B>,
          LocalEntityQuery<C>,
          LocalEntityQuery<D>,
        ) {
  Future<R> useAll<R>(
    FutureOr<R> Function(
      List<A> first,
      List<B> second,
      List<C> third,
      List<D> fourth,
    )
    action,
  ) async {
    try {
      final first = $1.loadAll();
      final second = $2.loadAll();
      final third = $3.loadAll();
      final fourth = $4.loadAll();
      await _waitForQueryLoads([first, second, third, fourth]);
      return await action(await first, await second, await third, await fourth);
    } finally {
      $1.dispose();
      $2.dispose();
      $3.dispose();
      $4.dispose();
    }
  }
}

/// Runs six independent exhaustive queries in parallel under one lease.
extension LocalEntityQuerySextupleLease<A, B, C, D, E, F>
    on
        (
          LocalEntityQuery<A>,
          LocalEntityQuery<B>,
          LocalEntityQuery<C>,
          LocalEntityQuery<D>,
          LocalEntityQuery<E>,
          LocalEntityQuery<F>,
        ) {
  Future<R> useAll<R>(
    FutureOr<R> Function(
      List<A> first,
      List<B> second,
      List<C> third,
      List<D> fourth,
      List<E> fifth,
      List<F> sixth,
    )
    action,
  ) async {
    try {
      final first = $1.loadAll();
      final second = $2.loadAll();
      final third = $3.loadAll();
      final fourth = $4.loadAll();
      final fifth = $5.loadAll();
      final sixth = $6.loadAll();
      await _waitForQueryLoads([first, second, third, fourth, fifth, sixth]);
      return await action(
        await first,
        await second,
        await third,
        await fourth,
        await fifth,
        await sixth,
      );
    } finally {
      $1.dispose();
      $2.dispose();
      $3.dispose();
      $4.dispose();
      $5.dispose();
      $6.dispose();
    }
  }
}

Future<void> _waitForQueryLoads(Iterable<Future<Object?>> loads) =>
    Future.wait<void>(loads.map((load) => load.then<void>((_) {})));

/// Shares query work by value while each consumer owns an independent lease.
final class LocalEntityQueryCache<E> {
  LocalEntityQueryCache({required ReadOnlyObservableList<E> source})
    : _source = source,
      _loader = null;

  LocalEntityQueryCache.database({
    required EntityQueryPageLoader<E> loader,
    required Stream<EntityProjectionChange<E>> invalidations,
  }) : _source = null,
       _loader = loader {
    _invalidationSubscription = invalidations.listen((change) {
      for (final entry in _queries.entries.toList(growable: false)) {
        if (change._affects(entry.key)) entry.value.controller.invalidate();
      }
    });
  }

  final ReadOnlyObservableList<E>? _source;
  final EntityQueryPageLoader<E>? _loader;
  final Map<EntityQuerySpec<E>, _CachedLocalEntityQuery<E>> _queries = {};
  StreamSubscription<EntityProjectionChange<E>>? _invalidationSubscription;
  bool _disposed = false;

  LocalEntityQuery<E> acquire(EntityQuerySpec<E> spec) {
    if (_disposed) throw StateError('The query cache is disposed.');
    final cached = _queries.putIfAbsent(
      spec,
      () => _CachedLocalEntityQuery(switch ((_source, _loader)) {
        (final source?, null) => _LocalEntityQueryController.inMemory(
          source: source,
          spec: spec,
        ),
        (null, final loader?) => _LocalEntityQueryController.database(
          loader: loader,
          spec: spec,
        ),
        _ => throw StateError('Invalid query cache configuration.'),
      }),
    );
    cached.leaseCount++;
    return LocalEntityQuery._(cached.controller, () => _release(spec, cached));
  }

  /// Acquires one cached query per listener and releases it after that
  /// listener's state subscription is cancelled.
  ///
  /// Generated sets use this for framework-neutral reactive adapters so query
  /// reference counting cannot leak into feature code.
  Stream<EntityQueryState<E>> watch(
    EntityQuerySpec<E> spec, {
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) => Stream.multi((controller) {
    final query = acquire(spec);
    final subscription = query
        .watchStates(observeFields: observeFields)
        .listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        );
    controller.onCancel = () async {
      await subscription.cancel();
      query.dispose();
    };
  });

  /// Watches an exhaustive query while retaining one cache lease per listener.
  ///
  /// Partial database pages are not emitted. Stale complete data remains
  /// visible during refresh, then every page of the replacement snapshot is
  /// loaded before the next data state is published.
  Stream<EntityQueryState<E>> watchComplete(
    EntityQuerySpec<E> spec, {
    Iterable<PersistedEntityFieldReference<E>> observeFields = const [],
  }) => Stream.multi((controller) {
    final query = acquire(spec);
    final subscription = query
        .watchCompleteStates(observeFields: observeFields)
        .listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        );
    controller.onCancel = subscription.cancel;
  });

  void _release(EntityQuerySpec<E> spec, _CachedLocalEntityQuery<E> cached) {
    if (cached.leaseCount == 0) return;
    cached.leaseCount--;
    if (cached.leaseCount != 0) return;
    if (identical(_queries[spec], cached)) _queries.remove(spec);
    cached.controller.dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cached in _queries.values) {
      cached.controller.dispose();
    }
    _queries.clear();
    final subscription = _invalidationSubscription;
    _invalidationSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }
}

final class _CachedLocalEntityQuery<E> {
  _CachedLocalEntityQuery(this.controller);

  final _LocalEntityQueryController<E> controller;
  int leaseCount = 0;
}

final class _LocalEntityQueryController<E> {
  _LocalEntityQueryController.inMemory({
    required ReadOnlyObservableList<E> source,
    required this.spec,
  }) : _source = source,
       _loader = null,
       _visibleLimit = Observable(spec.pageSize) {
    _initializeState();
  }

  _LocalEntityQueryController.database({
    required EntityQueryPageLoader<E> loader,
    required this.spec,
  }) : _source = null,
       _loader = loader,
       _visibleLimit = Observable(spec.pageSize) {
    _initializeState();
    unawaited(_reload());
  }

  void _initializeState() {
    state = Computed(() {
      if (_disposed.value) return EntityQueryDisposed<E>();
      if (_loader != null) {
        // The loader already applies the structural predicate and ordering.
        // Reading entity fields again here would duplicate SQL work and make
        // this controller subscribe to every loaded row's query fields.
        final visible = List<E>.unmodifiable(_databaseItems);
        return switch (_databasePhase.value) {
          _DatabaseQueryPhase.initialLoading => EntityQueryInitialLoading<E>(),
          _DatabaseQueryPhase.stale => EntityQueryStaleData<E>(
            items: visible,
            hasMore: _databaseHasMore.value,
          ),
          _DatabaseQueryPhase.failure => EntityQueryFailure<E>(
            error: _databaseError.value!,
            items: visible,
            hasMore: _databaseHasMore.value,
          ),
          _DatabaseQueryPhase.ready when visible.isEmpty =>
            EntityQueryEmpty<E>(),
          _DatabaseQueryPhase.ready => EntityQueryData<E>(
            items: visible,
            hasMore: _databaseHasMore.value,
          ),
        };
      }
      final result = _source!.where(spec.where.test).toList(growable: false);
      if (spec.orderBy case final order?) result.sort(order.compare);
      final visibleLimit = _visibleLimit.value;
      final hasMore = result.length > visibleLimit;
      final visible = List<E>.unmodifiable(result.take(visibleLimit));
      if (visible.isEmpty) return EntityQueryEmpty<E>();
      return EntityQueryData<E>(items: visible, hasMore: hasMore);
    });
  }

  final ReadOnlyObservableList<E>? _source;
  final EntityQueryPageLoader<E>? _loader;
  final EntityQuerySpec<E> spec;
  final Observable<int> _visibleLimit;
  final Observable<bool> _disposed = Observable(false);
  final ObservableList<E> _databaseItems = ObservableList();
  final Observable<_DatabaseQueryPhase> _databasePhase = Observable(
    _DatabaseQueryPhase.initialLoading,
  );
  final Observable<bool> _databaseHasMore = Observable(false);
  final Observable<Object?> _databaseError = Observable(null);
  final List<void Function()> _databasePageReleases = [];
  EntityQueryCursor? _databaseCursor;
  int _loadGeneration = 0;
  Future<void>? _activeLoad;
  Completer<void>? _pendingReload;
  late final Computed<EntityQueryState<E>> state;

  bool get databaseBacked => _loader != null;

  Future<EntityQueryPage<E>> loadDetachedPage({
    required EntityQueryCursor? after,
    required int limit,
  }) {
    final loader = _loader;
    if (loader == null) {
      throw StateError('Only database-backed queries expose detached pages.');
    }
    if (_disposed.value) {
      throw StateError('Cannot load a disposed entity query.');
    }
    return loader(spec, after: after, limit: limit);
  }

  Future<void> loadNextPage() async {
    if (_disposed.value || !state.value.hasMore) return;
    if (_loader != null) {
      await _loadNextDatabasePage();
      return;
    }
    runInAction(() => _visibleLimit.value += spec.pageSize);
  }

  void invalidate() {
    if (_disposed.value || _loader == null) return;
    unawaited(_reload());
  }

  Future<void> refresh() =>
      _disposed.value || _loader == null ? Future<void>.value() : _reload();

  Future<void> waitForIdle() async {
    while (true) {
      final active = _activeLoad;
      if (active == null) return;
      await active;
    }
  }

  void reportExhaustiveFailure(Object error) {
    if (_disposed.value || _loader == null) return;
    runInAction(() {
      _databaseError.value = error;
      _databaseHasMore.value = false;
      _databasePhase.value = _DatabaseQueryPhase.failure;
    });
  }

  Future<void> _reload() {
    final active = _activeLoad;
    if (active != null) {
      final existing = _pendingReload;
      if (existing != null) return existing.future;
      _loadGeneration++;
      final pending = Completer<void>();
      _pendingReload = pending;
      return pending.future;
    }
    return _startReload();
  }

  Future<void> _startReload() {
    final generation = ++_loadGeneration;
    final desiredCount = math.max(spec.pageSize, _databaseItems.length);
    runInAction(() {
      _databaseError.value = null;
      _databasePhase.value = _databaseItems.isEmpty
          ? _DatabaseQueryPhase.initialLoading
          : _DatabaseQueryPhase.stale;
    });
    final operation = _loadDatabasePage(
      generation: generation,
      after: null,
      limit: desiredCount,
      replace: true,
    );
    return _track(operation);
  }

  Future<void> _loadNextDatabasePage() {
    final active = _activeLoad;
    if (active != null) return active;
    final generation = ++_loadGeneration;
    runInAction(() {
      _databaseError.value = null;
      _databasePhase.value = _DatabaseQueryPhase.stale;
    });
    final operation = _loadDatabasePage(
      generation: generation,
      after: _databaseCursor,
      limit: spec.pageSize,
      replace: false,
    );
    return _track(operation);
  }

  Future<void> _track(Future<void> operation) {
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (!identical(_activeLoad, tracked)) return;
      _activeLoad = null;
      final pending = _pendingReload;
      if (pending == null) return;
      _pendingReload = null;
      if (_disposed.value) {
        pending.complete();
        return;
      }
      _startReload().then(pending.complete, onError: pending.completeError);
    });
    _activeLoad = tracked;
    return tracked;
  }

  Future<void> _loadDatabasePage({
    required int generation,
    required EntityQueryCursor? after,
    required int limit,
    required bool replace,
  }) async {
    try {
      final page = await _loader!(spec, after: after, limit: limit);
      if (page.hasMore && page.nextCursor == null) {
        page.release?.call();
        throw StateError('A page with more results must provide a cursor.');
      }
      if (_disposed.value || generation != _loadGeneration) {
        page.release?.call();
        return;
      }
      runInAction(() {
        if (replace) {
          _releaseDatabasePages();
          _databaseItems.clear();
        }
        _databaseItems.addAll(page.items);
        _databaseCursor = page.nextCursor;
        if (page.release case final release?) {
          _databasePageReleases.add(release);
        }
        _databaseHasMore.value = page.hasMore;
        _databaseError.value = null;
        _databasePhase.value = _DatabaseQueryPhase.ready;
      });
    } catch (error) {
      if (_disposed.value || generation != _loadGeneration) return;
      runInAction(() {
        _databaseError.value = error;
        _databasePhase.value = _DatabaseQueryPhase.failure;
      });
    }
  }

  void dispose() {
    if (_disposed.value) return;
    _loadGeneration++;
    final pending = _pendingReload;
    _pendingReload = null;
    if (pending != null && !pending.isCompleted) pending.complete();
    runInAction(() {
      _disposed.value = true;
      _databaseCursor = null;
      _releaseDatabasePages();
      _databaseItems.clear();
    });
  }

  void _releaseDatabasePages() {
    for (final release in _databasePageReleases) {
      release();
    }
    _databasePageReleases.clear();
  }
}

enum _DatabaseQueryPhase { initialLoading, ready, stale, failure }

int _compareNullable<V extends Comparable<dynamic>>(
  V? left,
  V? right, {
  required NullPlacement nulls,
  bool descending = false,
}) {
  if (identical(left, right)) return 0;
  if (left == null) return nulls == NullPlacement.first ? -1 : 1;
  if (right == null) return nulls == NullPlacement.first ? 1 : -1;
  return descending ? right.compareTo(left) : left.compareTo(right);
}

bool _iterableEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!entityValuesEqual(left[index], right[index])) return false;
  }
  return true;
}

List<V> _normalizedQueryValues<V>(Iterable<V> source) {
  final unique = <String, V>{};
  for (final value in source) {
    unique.putIfAbsent(_stableQueryValue(value), () => value);
  }
  final keyed =
      unique.entries
          .map((entry) => (value: entry.value, key: entry.key))
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return List<V>.unmodifiable(keyed.map((entry) => entry.value));
}

String _stableQueryValue(Object? value) => switch (value) {
  null => 'null',
  final String value => 'string:${jsonEncode(value)}',
  final bool value => 'bool:$value',
  final int value => 'int:$value',
  final double value => 'double:$value',
  final LocalDate value => 'local-date:${value.value}',
  final DateTime value => 'date:${value.toUtc().toIso8601String()}',
  final Enum value => 'enum:${value.runtimeType}:${value.name}',
  final List<Object?> value =>
    'list:[${value.map(_stableQueryValue).join(',')}]',
  final Map<String, Object?> value =>
    'map:{${value.entries.map((entry) => '${jsonEncode(entry.key)}:${_stableQueryValue(entry.value)}').join(',')}}',
  final PersistedScalarValue<Object> value =>
    'scalar:${value.runtimeType}:${_stableQueryValue(value.toScalar())}',
  _ => throw StateError(
    'Generated entity queries do not support `${value.runtimeType}` values.',
  ),
};

/// Compares generated entity values by value, including homogeneous lists.
///
/// Dart lists use identity equality by default. Persisted list fields instead
/// need deterministic no-op detection and query identity without importing a
/// Flutter-only collection helper into the entity-graph runtime.
bool entityValuesEqual(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is PersistedScalarValue && right is PersistedScalarValue) {
    return left.runtimeType == right.runtimeType &&
        entityValuesEqual(left.toScalar(), right.toScalar());
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!entityValuesEqual(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !entityValuesEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

/// Computes a structural hash compatible with [entityValuesEqual].
///
/// Persisted JSON values, lists, and maps use Dart identity equality by
/// default. Domain value objects can use this helper to implement a matching
/// `hashCode` without duplicating the runtime's recursive value rules.
int entityValueHash(Object? value) {
  if (value is PersistedScalarValue) {
    return Object.hash(value.runtimeType, entityValueHash(value.toScalar()));
  }
  if (value is List) {
    return Object.hashAll(value.map(entityValueHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, entityValueHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}

/// Structural, order-independent key for a generated unordered unique pair.
///
/// Hashing and equality use persisted-value semantics, so generated lookup
/// indexes need neither sorting nor lossy string conversion.
final class UnorderedEntityPairKey<T> {
  const UnorderedEntityPairKey(this.first, this.second);

  final T first;
  final T second;

  @override
  bool operator ==(Object other) =>
      other is UnorderedEntityPairKey<T> &&
      ((entityValuesEqual(first, other.first) &&
              entityValuesEqual(second, other.second)) ||
          (entityValuesEqual(first, other.second) &&
              entityValuesEqual(second, other.first)));

  @override
  int get hashCode => entityValueHash(first) ^ entityValueHash(second);
}

/// Validates a JSON-compatible value and returns a recursively immutable,
/// deterministically ordered representation.
///
/// Object keys are sorted so semantically equal values have identical SQLite
/// text, synchronization payload, predicate, and hash representations.
Object? canonicalJsonValue(Object? source, {required String field}) {
  Object? canonicalize(Object? value) => switch (value) {
    null || String() || bool() || int() => value,
    final double value when value.isFinite && value == value.truncate() =>
      value.toInt(),
    final double value when value.isFinite => value,
    final num value when value.isFinite => value,
    final List values => List<Object?>.unmodifiable(values.map(canonicalize)),
    final Map values when values.keys.every((key) => key is String) =>
      Map<String, Object?>.unmodifiable(
        Map.fromEntries(
          values.entries
              .map(
                (entry) =>
                    MapEntry(entry.key as String, canonicalize(entry.value)),
              )
              .toList(growable: false)
            ..sort((left, right) => left.key.compareTo(right.key)),
        ),
      ),
    _ => throw FormatException('Invalid JSON value for `$field`.'),
  };

  return canonicalize(source);
}

/// Canonical object-root JSON representation used by generated value codecs.
JsonMap canonicalJsonObject(Object? source, {required String field}) {
  final canonical = canonicalJsonValue(source, field: field);
  if (canonical is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object for `$field`.');
  }
  return canonical;
}

/// Canonical array-root JSON representation used by generated value codecs.
List<Object?> canonicalJsonArray(Object? source, {required String field}) {
  final canonical = canonicalJsonValue(source, field: field);
  if (canonical is! List<Object?>) {
    throw FormatException('Expected a JSON array for `$field`.');
  }
  return canonical;
}

enum FieldConflictPolicy { localWins, serverWins }

/// Reserved infrastructure names shared by every synchronized entity.
///
/// Entity declarations cannot redeclare or override these fields, so emitting
/// the same four strings in every descriptor would be redundant configuration.
abstract final class EntityConventions {
  static const idFieldName = 'id';
  static const idColumnName = 'id';
  static const ownerFieldName = 'ownerId';
  static const ownerColumnName = 'owner_id';
  static const createdAtFieldName = 'createdAt';
  static const updatedAtFieldName = 'updatedAt';
  static const updatedAtColumnName = 'updated_at';
  static const deletedAtFieldName = 'deletedAt';
  static const deletedAtColumnName = 'deleted_at';
  static const archivedAtFieldName = 'archivedAt';
  static const archivedAtColumnName = 'archived_at';
  static const serverVersionFieldName = 'serverVersion';
  static const serverVersionColumnName = 'server_version';
  static const orderRankFieldName = 'orderRank';
  static const orderRankColumnName = 'order_rank';
}

abstract interface class EntityIdentityDescriptor<E> {
  String get entityType;
}

final class EntityIdentity<E> {
  const EntityIdentity({required this.descriptor, required this.id});

  final EntityIdentityDescriptor<E> descriptor;
  final LocalId<E> id;

  String get entityType => descriptor.entityType;
  String get rawId => id.value;

  @override
  bool operator ==(Object other) =>
      other is EntityIdentity<E> &&
      other.entityType == entityType &&
      other.id == id;

  @override
  int get hashCode => Object.hash(entityType, id);
}

sealed class EntityPatch {
  factory EntityPatch.fromWire(JsonMap values) = _WireEntityPatch;

  EntityPatch._(JsonMap values)
    : _values = Map<String, Object?>.unmodifiable(values);

  final JsonMap _values;

  bool get isEmpty => _values.isEmpty;
  Object? operator [](String field) => _values[field];
  Iterable<MapEntry<String, Object?>> get entries => _values.entries;
  bool containsKey(String field) => _values.containsKey(field);
  bool containsField(String field) => _values.containsKey(field);
  JsonMap toWire() => JsonMap.of(_values);
}

final class _WireEntityPatch extends EntityPatch {
  _WireEntityPatch(super.values) : super._();
}

/// A field/value patch nominally bound to one domain entity type.
final class TypedEntityPatch<E> extends EntityPatch {
  TypedEntityPatch._(super.values) : super._();

  factory TypedEntityPatch.empty() => TypedEntityPatch<E>._(const {});

  TypedEntityPatch<E> merge(TypedEntityPatch<E> other) =>
      TypedEntityPatch<E>._({..._values, ...other._values});
}

abstract interface class EntitySemanticCommand<E> {
  String get name;

  JsonMap toWire();
}

final class SetCollaboratorCommand<E, A> implements EntitySemanticCommand<E> {
  const SetCollaboratorCommand({
    required this.collaboratorId,
    required this.active,
  });

  factory SetCollaboratorCommand.fromWire(
    JsonMap payload, {
    required LocalId<A> Function(String source) parseId,
  }) {
    if (payload.length != 2 ||
        !payload.containsKey('userId') ||
        !payload.containsKey('active')) {
      throw const FormatException(
        'setCollaborator requires only userId and active.',
      );
    }
    final userId = payload['userId'];
    final active = payload['active'];
    if (userId is! String || active is! bool) {
      throw const FormatException('setCollaborator has invalid field types.');
    }
    return SetCollaboratorCommand(
      collaboratorId: parseId(userId),
      active: active,
    );
  }

  final LocalId<A> collaboratorId;
  final bool active;

  @override
  String get name => 'setCollaborator';

  @override
  JsonMap toWire() => {'userId': collaboratorId.value, 'active': active};
}

/// Semantic placement inside one generated canonical ordered scope.
enum OrderedPlacement { before, after, first, last }

/// Semantic placement carried by one ordered create operation.
///
/// The local rank remains an optimistic storage detail. A backend serializes
/// the canonical scope and resolves this intent against its current members,
/// so a stale client still creates at the requested boundary.
final class OrderedCreateIntent {
  OrderedCreateIntent({
    required this.placement,
    required this.scopeBaseVersion,
  }) {
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw ArgumentError.value(
        placement,
        'placement',
        'Ordered creation supports only first or last placement.',
      );
    }
  }

  factory OrderedCreateIntent.fromWire(JsonMap payload) {
    if (payload.length != 2 ||
        !payload.containsKey('placement') ||
        !payload.containsKey('scopeBaseVersion')) {
      throw const FormatException(
        'orderedCreate requires only placement and scopeBaseVersion.',
      );
    }
    final rawPlacement = payload['placement'];
    final placement = rawPlacement is String
        ? OrderedPlacement.values
              .where((candidate) => candidate.name == rawPlacement)
              .firstOrNull
        : null;
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw const FormatException(
        'orderedCreate.placement must be first or last.',
      );
    }
    return OrderedCreateIntent(
      placement: placement!,
      scopeBaseVersion: parseOrderScopeVersion(payload['scopeBaseVersion']),
    );
  }

  final OrderedPlacement placement;
  final OrderScopeVersion scopeBaseVersion;

  JsonMap toWire() => {
    'placement': placement.name,
    'scopeBaseVersion': scopeBaseVersion.value,
  };
}

/// A semantic movement inside one generated canonical ordered scope.
///
/// The opaque local rank and snapshot neighbors are intentionally absent. A
/// backend serializes the scope and resolves the named anchor against the
/// current canonical order, so concurrent operations preserve user intent.
final class MoveOrderedCommand<E> implements EntitySemanticCommand<E> {
  const MoveOrderedCommand({
    required this.placement,
    required this.anchorId,
    required this.scopeBaseVersion,
  }) : assert(
         (placement == OrderedPlacement.before ||
                 placement == OrderedPlacement.after) ==
             (anchorId != null),
         'Before/after require one anchor; first/last forbid one.',
       );

  factory MoveOrderedCommand.fromWire(
    JsonMap payload, {
    required LocalId<E> Function(String source) parseId,
  }) {
    if (payload.length != 3 ||
        !payload.containsKey('placement') ||
        !payload.containsKey('anchorId') ||
        !payload.containsKey('scopeBaseVersion')) {
      throw const FormatException(
        'moveInOrder requires only placement, anchorId, and '
        'scopeBaseVersion.',
      );
    }
    final rawPlacement = payload['placement'];
    if (rawPlacement is! String) {
      throw const FormatException('moveInOrder.placement must be a string.');
    }
    final placement = OrderedPlacement.values
        .where((candidate) => candidate.name == rawPlacement)
        .firstOrNull;
    if (placement == null) {
      throw FormatException(
        'moveInOrder.placement `$rawPlacement` is unsupported.',
      );
    }
    final rawAnchorId = payload['anchorId'];
    if (rawAnchorId != null && rawAnchorId is! String) {
      throw const FormatException(
        'moveInOrder.anchorId must be a UUID or null.',
      );
    }
    final anchored =
        placement == OrderedPlacement.before ||
        placement == OrderedPlacement.after;
    if (anchored != (rawAnchorId != null)) {
      throw const FormatException(
        'moveInOrder before/after require one anchor while first/last '
        'forbid one.',
      );
    }
    return MoveOrderedCommand(
      placement: placement,
      anchorId: rawAnchorId == null ? null : parseId(rawAnchorId as String),
      scopeBaseVersion: parseOrderScopeVersion(payload['scopeBaseVersion']),
    );
  }

  final OrderedPlacement placement;
  final LocalId<E>? anchorId;
  final OrderScopeVersion scopeBaseVersion;

  @override
  String get name => 'moveInOrder';

  @override
  JsonMap toWire() => {
    'placement': placement.name,
    'anchorId': anchorId?.value,
    'scopeBaseVersion': scopeBaseVersion.value,
  };
}

/// A semantic transfer between two generated canonical ordering scopes.
///
/// Only the non-owner discriminator patch crosses the protocol boundary. The
/// backend derives both complete typed scopes from canonical descriptor fields,
/// locks them in deterministic order, and allocates the destination rank.
final class TransferOrderedCommand<E> implements EntitySemanticCommand<E> {
  TransferOrderedCommand({
    required this.targetScope,
    required this.placement,
    required this.sourceScopeBaseVersion,
    required this.targetScopeBaseVersion,
  }) {
    if (targetScope.isEmpty) {
      throw ArgumentError.value(
        targetScope,
        'targetScope',
        'An ordered transfer must change a scope discriminator.',
      );
    }
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw ArgumentError.value(
        placement,
        'placement',
        'An ordered transfer supports only first or last placement.',
      );
    }
  }

  factory TransferOrderedCommand.fromWire(
    JsonMap payload, {
    required String entityType,
    required List<EntityFieldDescriptor> targetScopeFields,
  }) {
    if (payload.length != 4 ||
        !payload.containsKey('targetScope') ||
        !payload.containsKey('placement') ||
        !payload.containsKey('sourceScopeBaseVersion') ||
        !payload.containsKey('targetScopeBaseVersion')) {
      throw const FormatException(
        'transferInOrder requires only targetScope, placement, '
        'sourceScopeBaseVersion, and targetScopeBaseVersion.',
      );
    }
    final rawScope = canonicalJsonObject(
      payload['targetScope'],
      field: 'transferInOrder.targetScope',
    );
    final expectedNames = targetScopeFields.map((field) => field.name).toSet();
    if (rawScope.keys.toSet().length != expectedNames.length ||
        !rawScope.keys.toSet().containsAll(expectedNames)) {
      throw const FormatException(
        'transferInOrder.targetScope must contain every generated '
        'discriminator exactly once.',
      );
    }
    final canonicalScope = <String, Object?>{};
    for (final field in targetScopeFields) {
      canonicalScope[field.name] = field.decodeWireValue(
        rawScope[field.name],
        entityType: entityType,
      );
    }
    final rawPlacement = payload['placement'];
    final placement = rawPlacement is String
        ? OrderedPlacement.values
              .where((candidate) => candidate.name == rawPlacement)
              .firstOrNull
        : null;
    if (placement != OrderedPlacement.first &&
        placement != OrderedPlacement.last) {
      throw const FormatException(
        'transferInOrder.placement must be first or last.',
      );
    }
    return TransferOrderedCommand(
      targetScope: EntityPatch.fromWire(canonicalScope),
      placement: placement!,
      sourceScopeBaseVersion: parseOrderScopeVersion(
        payload['sourceScopeBaseVersion'],
      ),
      targetScopeBaseVersion: parseOrderScopeVersion(
        payload['targetScopeBaseVersion'],
      ),
    );
  }

  final EntityPatch targetScope;
  final OrderedPlacement placement;
  final OrderScopeVersion sourceScopeBaseVersion;
  final OrderScopeVersion targetScopeBaseVersion;

  @override
  String get name => 'transferInOrder';

  @override
  JsonMap toWire() => {
    'targetScope': targetScope.toWire(),
    'placement': placement.name,
    'sourceScopeBaseVersion': sourceScopeBaseVersion.value,
    'targetScopeBaseVersion': targetScopeBaseVersion.value,
  };
}

/// An exact replacement of one complete generated bounded ordered scope.
///
/// Unlike neighbor movement, this command intentionally carries every active
/// member identity. Backends reject incomplete or duplicate membership before
/// assigning canonical ranks in one serialized scope transaction.
final class ReorderOrderedCommand<E> implements EntitySemanticCommand<E> {
  ReorderOrderedCommand({
    required Iterable<LocalId<E>> orderedIds,
    required this.scopeBaseVersion,
  }) : orderedIds = List<LocalId<E>>.unmodifiable(orderedIds) {
    if (this.orderedIds.isEmpty) {
      throw ArgumentError.value(
        this.orderedIds,
        'orderedIds',
        'An exact ordered scope cannot be empty.',
      );
    }
    if (this.orderedIds.toSet().length != this.orderedIds.length) {
      throw ArgumentError.value(
        this.orderedIds,
        'orderedIds',
        'An exact ordered scope cannot contain duplicate identities.',
      );
    }
  }

  factory ReorderOrderedCommand.fromWire(
    JsonMap payload, {
    required LocalId<E> Function(String source) parseId,
  }) {
    if (payload.length != 2 ||
        !payload.containsKey('orderedIds') ||
        !payload.containsKey('scopeBaseVersion')) {
      throw const FormatException(
        'reorder requires only orderedIds and scopeBaseVersion.',
      );
    }
    final rawIds = payload['orderedIds'];
    if (rawIds is! List || rawIds.any((id) => id is! String)) {
      throw const FormatException('reorder.orderedIds must be a string array.');
    }
    try {
      return ReorderOrderedCommand(
        orderedIds: rawIds.cast<String>().map(parseId),
        scopeBaseVersion: parseOrderScopeVersion(payload['scopeBaseVersion']),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }

  final List<LocalId<E>> orderedIds;
  final OrderScopeVersion scopeBaseVersion;

  @override
  String get name => 'reorder';

  @override
  JsonMap toWire() => {
    'orderedIds': [for (final id in orderedIds) id.value],
    'scopeBaseVersion': scopeBaseVersion.value,
  };
}

/// One active member in an exact normalized relationship replacement.
final class ActiveRelationshipMember<L, T> {
  const ActiveRelationshipMember({
    required this.linkId,
    required this.targetId,
  });

  final LocalId<L> linkId;
  final LocalId<T> targetId;

  JsonMap toWire() => {'linkId': linkId.value, 'targetId': targetId.value};
}

/// Exact active membership and order for one proved-bounded relationship.
///
/// Link identities are explicit so an inactive pair is reactivated rather than
/// recreated and a newly linked pair keeps the identity allocated locally.
/// [baseActiveLinkIds] is the complete active membership observed by the
/// caller. A backend compares it with its serialized canonical scope before
/// applying the replacement, turning concurrent membership or ordering changes
/// into one typed conflict instead of silently overwriting them.
final class ReplaceActiveRelationshipCommand<L, S, T>
    implements EntitySemanticCommand<L> {
  ReplaceActiveRelationshipCommand({
    required this.sourceId,
    required Iterable<LocalId<L>> baseActiveLinkIds,
    required Iterable<ActiveRelationshipMember<L, T>> activeMembers,
  }) : baseActiveLinkIds = List.unmodifiable(baseActiveLinkIds),
       activeMembers = List.unmodifiable(activeMembers) {
    if (this.baseActiveLinkIds.toSet().length !=
        this.baseActiveLinkIds.length) {
      throw ArgumentError.value(
        this.baseActiveLinkIds,
        'baseActiveLinkIds',
        'Relationship base membership cannot contain duplicate links.',
      );
    }
    final linkIds = this.activeMembers.map((member) => member.linkId).toList();
    final targetIds = this.activeMembers
        .map((member) => member.targetId)
        .toList();
    if (linkIds.toSet().length != linkIds.length ||
        targetIds.toSet().length != targetIds.length) {
      throw ArgumentError.value(
        this.activeMembers,
        'activeMembers',
        'Relationship replacement requires unique link and target identities.',
      );
    }
  }

  factory ReplaceActiveRelationshipCommand.fromWire(
    JsonMap payload, {
    required LocalId<L> Function(String source) parseLinkId,
    required LocalId<S> Function(String source) parseSourceId,
    required LocalId<T> Function(String source) parseTargetId,
  }) {
    if (payload.length != 3 ||
        !payload.containsKey('sourceId') ||
        !payload.containsKey('baseActiveLinkIds') ||
        !payload.containsKey('activeMembers')) {
      throw const FormatException(
        'replaceRelationship requires only sourceId, baseActiveLinkIds, and '
        'activeMembers.',
      );
    }
    final rawSourceId = payload['sourceId'];
    final rawBaseIds = payload['baseActiveLinkIds'];
    final rawMembers = payload['activeMembers'];
    if (rawSourceId is! String ||
        rawBaseIds is! List ||
        rawBaseIds.any((id) => id is! String) ||
        rawMembers is! List) {
      throw const FormatException(
        'replaceRelationship has invalid field types.',
      );
    }
    final members = <ActiveRelationshipMember<L, T>>[];
    for (final rawMember in rawMembers) {
      final member = canonicalJsonObject(
        rawMember,
        field: 'replaceRelationship.activeMembers',
      );
      if (member.length != 2 ||
          member['linkId'] is! String ||
          member['targetId'] is! String) {
        throw const FormatException(
          'Each active relationship member requires only linkId and targetId.',
        );
      }
      members.add(
        ActiveRelationshipMember(
          linkId: parseLinkId(member['linkId']! as String),
          targetId: parseTargetId(member['targetId']! as String),
        ),
      );
    }
    try {
      return ReplaceActiveRelationshipCommand(
        sourceId: parseSourceId(rawSourceId),
        baseActiveLinkIds: rawBaseIds.cast<String>().map(parseLinkId),
        activeMembers: members,
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }

  final LocalId<S> sourceId;
  final List<LocalId<L>> baseActiveLinkIds;
  final List<ActiveRelationshipMember<L, T>> activeMembers;

  @override
  String get name => 'replaceRelationship';

  @override
  JsonMap toWire() => {
    'sourceId': sourceId.value,
    'baseActiveLinkIds': [for (final id in baseActiveLinkIds) id.value],
    'activeMembers': [for (final member in activeMembers) member.toWire()],
  };
}

/// Local-only optimistic state associated with one semantic scope command.
///
/// It is stored in the durable queue for merge and rollback, but is excluded
/// from [PushOperation.toRemoteWire]. The remote protocol receives only the
/// semantic command and derives canonical storage fields itself.
enum LocalEntityStateOperation { create, patch }

final class LocalEntityStatePatch {
  LocalEntityStatePatch({
    required this.identity,
    required this.localRevision,
    required this.patch,
    this.operation = LocalEntityStateOperation.patch,
  }) {
    if (localRevision < 0) {
      throw RangeError.value(
        localRevision,
        'localRevision',
        'Must be non-negative.',
      );
    }
    if (patch.isEmpty) {
      throw ArgumentError.value(
        patch,
        'patch',
        'Local semantic state bookkeeping cannot be empty.',
      );
    }
  }

  final EntityIdentity<dynamic> identity;
  final int localRevision;
  final EntityPatch patch;
  final LocalEntityStateOperation operation;

  JsonMap toWire() => {
    'entityType': identity.entityType,
    'entityId': identity.rawId,
    'localRevision': localRevision,
    'operation': operation.name,
    'patch': patch.toWire(),
  };
}

sealed class PushOperation {
  const PushOperation({
    required this.operationId,
    required this.identity,
    required this.baseServerVersion,
    required this.localRevision,
    required this.protocolVersion,
  });

  final SyncOperationId operationId;
  final EntityIdentity<dynamic> identity;
  final ServerVersion baseServerVersion;
  final int localRevision;
  final int protocolVersion;
  EntityPatch get patch;

  SyncMutationOperation get operation;
  String? get commandName => null;
  OrderedCreateIntent? get orderedCreate => null;
  EntityPatch get remotePatch => patch;
  bool get persistsEntityState => false;
  EntityPatch? get persistedStatePatch => null;
  List<LocalEntityStatePatch> get localStatePatches => const [];

  JsonMap toWire() => {
    'operationId': operationId.value,
    'operation': operation.name,
    'entityType': identity.entityType,
    'entityId': identity.rawId,
    'baseServerVersion': baseServerVersion.value,
    'localRevision': localRevision,
    'protocolVersion': protocolVersion,
    'commandName': ?commandName,
    if (orderedCreate case final intent?) 'orderedCreate': intent.toWire(),
    if (persistsEntityState) 'persistsEntityState': true,
    if (persistedStatePatch case final statePatch?)
      'statePatch': statePatch.toWire(),
    if (localStatePatches.isNotEmpty)
      'localStatePatches': [
        for (final statePatch in localStatePatches) statePatch.toWire(),
      ],
    'patch': patch.toWire(),
  };

  /// Transport payload without local optimistic-state bookkeeping.
  ///
  /// [toWire] is the durable local queue representation. Remote adapters must
  /// use this projection so internal ranks and rollback patches never become
  /// part of the service protocol.
  JsonMap toRemoteWire() => {
    'operationId': operationId.value,
    'operation': operation.name,
    'entityType': identity.entityType,
    'entityId': identity.rawId,
    'baseServerVersion': baseServerVersion.value,
    'localRevision': localRevision,
    'protocolVersion': protocolVersion,
    'commandName': ?commandName,
    if (orderedCreate case final intent?) 'orderedCreate': intent.toWire(),
    'patch': remotePatch.toWire(),
  };
}

final class CreatePushOperation extends PushOperation {
  CreatePushOperation({
    required super.operationId,
    required super.identity,
    required super.baseServerVersion,
    required super.localRevision,
    required super.protocolVersion,
    required this.patch,
    this.orderedCreate,
    Iterable<LocalEntityStatePatch> localStatePatches = const [],
  }) : _localStatePatches = List.unmodifiable(localStatePatches);

  @override
  final EntityPatch patch;

  @override
  final OrderedCreateIntent? orderedCreate;

  final List<LocalEntityStatePatch> _localStatePatches;

  @override
  List<LocalEntityStatePatch> get localStatePatches => _localStatePatches;

  @override
  EntityPatch get remotePatch {
    if (orderedCreate == null) return patch;
    final wire = Map<String, Object?>.of(patch.toWire())
      ..remove(EntityConventions.orderRankFieldName);
    return EntityPatch.fromWire(wire);
  }

  @override
  SyncMutationOperation get operation => SyncMutationOperation.create;
}

final class PatchPushOperation extends PushOperation {
  const PatchPushOperation({
    required super.operationId,
    required super.identity,
    required super.baseServerVersion,
    required super.localRevision,
    required super.protocolVersion,
    required this.patch,
  });

  @override
  final EntityPatch patch;

  @override
  SyncMutationOperation get operation => SyncMutationOperation.patch;
}

final class DeletePushOperation extends PushOperation {
  const DeletePushOperation({
    required super.operationId,
    required super.identity,
    required super.baseServerVersion,
    required super.localRevision,
    required super.protocolVersion,
    required this.patch,
  });

  @override
  final EntityPatch patch;

  @override
  SyncMutationOperation get operation => SyncMutationOperation.delete;

  @override
  bool get persistsEntityState => true;
}

final class CommandPushOperation extends PushOperation {
  CommandPushOperation({
    required super.operationId,
    required super.identity,
    required super.baseServerVersion,
    required super.localRevision,
    required super.protocolVersion,
    required this.command,
    this.storesEntityState = false,
    this.statePatch,
    Iterable<LocalEntityStatePatch> scopeStatePatches = const [],
  }) : scopeStatePatches = List<LocalEntityStatePatch>.unmodifiable(
         scopeStatePatches,
       ),
       assert(
         storesEntityState ==
             (statePatch != null || scopeStatePatches.isNotEmpty),
         'A state-persisting command requires local state bookkeeping.',
       ) {
    if (storesEntityState !=
        (statePatch != null || this.scopeStatePatches.isNotEmpty)) {
      throw ArgumentError(
        'A state-persisting command requires local state bookkeeping.',
      );
    }
  }

  final EntitySemanticCommand<dynamic> command;
  final bool storesEntityState;
  final EntityPatch? statePatch;
  final List<LocalEntityStatePatch> scopeStatePatches;

  String get name => command.name;

  @override
  EntityPatch get patch => EntityPatch.fromWire(command.toWire());

  @override
  SyncMutationOperation get operation => SyncMutationOperation.command;

  @override
  String get commandName => name;

  @override
  bool get persistsEntityState => storesEntityState;

  @override
  EntityPatch? get persistedStatePatch => statePatch;

  @override
  List<LocalEntityStatePatch> get localStatePatches => scopeStatePatches;
}

final class LocalEntityMutation {
  LocalEntityMutation({
    required this.operationId,
    required this.identity,
    required this.baseServerVersion,
    required this.localRevision,
    required this.patch,
    required this.createdAt,
    this.syncPatch,
    this.operation = SyncMutationOperation.patch,
    this.kind = PushSyncWorkKind.statePatch,
    this.semanticCommand,
    this.activityOperation,
    this.orderedCreate,
    this.persistsEntityState = false,
    this.suppressOutboundIntent = false,
    Iterable<LocalEntityStatePatch> scopeStatePatches = const [],
  }) : scopeStatePatches = List<LocalEntityStatePatch>.unmodifiable(
         scopeStatePatches,
       );

  final SyncOperationId operationId;
  final EntityIdentity<dynamic> identity;
  final ServerVersion baseServerVersion;
  final int localRevision;
  final EntityPatch patch;
  final EntityPatch? syncPatch;
  final DateTime createdAt;
  final SyncMutationOperation operation;
  final PushSyncWorkKind kind;
  final EntitySemanticCommand<dynamic>? semanticCommand;
  final ActivityOperation? activityOperation;
  final OrderedCreateIntent? orderedCreate;
  final bool persistsEntityState;
  final bool suppressOutboundIntent;
  final List<LocalEntityStatePatch> scopeStatePatches;

  String get entityType => identity.entityType;
  String get entityId => identity.rawId;
}

sealed class SyncWorkFailure {
  const SyncWorkFailure({required this.code, required this.detail});

  final String code;
  final String? detail;
}

final class RetryableSyncWorkFailure extends SyncWorkFailure {
  const RetryableSyncWorkFailure({required super.code, required super.detail});
}

final class RejectedSyncWorkFailure extends SyncWorkFailure {
  const RejectedSyncWorkFailure({
    required super.code,
    required super.detail,
    required this.category,
  });

  final SyncRejectionCategory category;
}

final class ConflictSyncWorkFailure extends SyncWorkFailure {
  const ConflictSyncWorkFailure({required super.code, required super.detail});
}

SyncRejectionCategory syncRejectionCategoryForCode(String code) =>
    switch (code) {
      'authorization_denied' => SyncRejectionCategory.authorization,
      'invalid_operation' ||
      'invalid_local_operation' ||
      'validation_rejected' ||
      'unsupported_command' => SyncRejectionCategory.validation,
      'unsupported_protocol_version' ||
      'protocol_upcast_failed' ||
      'unknown_entity_type' => SyncRejectionCategory.protocol,
      'relationship_denied' ||
      'dependency_rejected' => SyncRejectionCategory.relationship,
      'entity_not_found' => SyncRejectionCategory.notFound,
      'server_contract_violation' ||
      'invalid_server_response' ||
      'entity_type_mismatch' => SyncRejectionCategory.serverContract,
      _ => SyncRejectionCategory.other,
    };

sealed class SyncWorkItem {
  const SyncWorkItem({
    required this.id,
    required this.target,
    required this.operationId,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.nextAttemptAt,
    this.lastFailure,
  });

  final int id;
  final SyncTargetId target;
  final SyncOperationId operationId;
  final SyncWorkStatus status;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime? nextAttemptAt;
  final SyncWorkFailure? lastFailure;

  SyncDirection get direction;

  SyncWorkKind get kind;
}

final class PushSyncWorkItem extends SyncWorkItem {
  PushSyncWorkItem({
    required super.id,
    required super.target,
    required this.operation,
    required this.pushKind,
    required super.status,
    required super.attemptCount,
    required super.createdAt,
    required super.nextAttemptAt,
    super.lastFailure,
  }) : super(operationId: operation.operationId) {
    final semantic = pushKind == PushSyncWorkKind.semanticCommand;
    final semanticOperation =
        operation is DeletePushOperation || operation is CommandPushOperation;
    if (semantic != semanticOperation) {
      throw ArgumentError(
        'Push work kind does not match ${operation.operation.name} operation.',
      );
    }
  }

  final PushOperation operation;
  final PushSyncWorkKind pushKind;

  @override
  SyncDirection get direction => SyncDirection.push;

  @override
  SyncWorkKind get kind => switch (pushKind) {
    PushSyncWorkKind.statePatch => SyncWorkKind.statePatch,
    PushSyncWorkKind.semanticCommand => SyncWorkKind.semanticCommand,
  };

  PushSyncWorkItem upcast(EntityDescriptorBase descriptor) {
    final wire = operation.toWire();
    final upgradedPayload = upcastSyncOperation(descriptor, wire);
    if (identical(upgradedPayload, wire)) return this;
    return PushSyncWorkItem(
      id: id,
      target: target,
      operation: _decodePushOperation(descriptor, upgradedPayload),
      pushKind: pushKind,
      status: status,
      attemptCount: attemptCount,
      createdAt: createdAt,
      nextAttemptAt: nextAttemptAt,
      lastFailure: lastFailure,
    );
  }
}

final class PullSyncWorkItem extends SyncWorkItem {
  const PullSyncWorkItem({
    required super.id,
    required super.target,
    required super.operationId,
    required super.status,
    required super.attemptCount,
    required super.createdAt,
    required super.nextAttemptAt,
    super.lastFailure,
  });

  @override
  SyncDirection get direction => SyncDirection.pull;

  @override
  SyncWorkKind get kind => SyncWorkKind.pullChanges;
}

abstract interface class SyncQueueHost {
  ReadOnlyObservableList<SyncWorkItem> get syncWork;

  Observable<SyncState> get syncState;

  Future<void> refreshSyncWork();

  Future<void> schedulePull();

  Future<void> retryNow();
}

final class SyncQueue {
  const SyncQueue(this._host);

  final SyncQueueHost _host;

  ReadOnlyObservableList<SyncWorkItem> get items => _host.syncWork;

  Observable<SyncState> get state => _host.syncState;

  Future<void> refresh() => _host.refreshSyncWork();

  Future<void> requestPull() => _host.schedulePull();

  Future<void> retryNow() => _host.retryNow();

  Future<void> synchronize() async {
    await requestPull();
    await retryNow();
  }
}

final class RemoteEntityFields {
  RemoteEntityFields._(this.descriptor, JsonMap values)
    : _values = Map<String, Object?>.unmodifiable(values);

  static RemoteEntityFields decode(
    EntityDescriptorBase descriptor,
    JsonMap wire, {
    required bool complete,
  }) {
    final fieldsByName = {
      for (final field in descriptor.fields) field.name: field,
    };
    final unknown = wire.keys.where((name) => !fieldsByName.containsKey(name));
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown ${descriptor.entityType} remote field `${unknown.first}`.',
      );
    }
    if (!wire.containsKey(EntityConventions.idFieldName)) {
      throw FormatException(
        '${descriptor.entityType} remote fields are missing identity '
        '`${EntityConventions.idFieldName}`.',
      );
    }
    if (complete) {
      for (final field in descriptor.fields) {
        if (!wire.containsKey(field.name)) {
          throw FormatException(
            'Complete ${descriptor.entityType} record is missing '
            '`${field.name}`.',
          );
        }
      }
    }
    final canonical = <String, Object?>{};
    for (final entry in wire.entries) {
      final field = fieldsByName[entry.key]!;
      canonical[entry.key] = field.decodeWireValue(
        entry.value,
        entityType: descriptor.entityType,
      );
    }
    return RemoteEntityFields._(descriptor, canonical);
  }

  final EntityDescriptorBase descriptor;
  final JsonMap _values;

  EntityIdentity<dynamic> get identity {
    final rawId = _values[EntityConventions.idFieldName];
    if (rawId is! String) {
      throw FormatException(
        '${descriptor.entityType}.${EntityConventions.idFieldName} is not a string.',
        rawId,
      );
    }
    return descriptor.parseIdentity(rawId);
  }

  Object? operator [](String field) => _values[field];
  bool containsKey(String field) => _values.containsKey(field);
  Iterable<MapEntry<String, Object?>> get entries => _values.entries;
  JsonMap toWire() => JsonMap.of(_values);
}

final class RemoteEntityChange {
  RemoteEntityChange({
    required this.identity,
    required this.serverVersion,
    required this.fields,
    required this.serverSequence,
    this.sourceOperationId,
    this.isRevocation = false,
  }) {
    final recordIdentity = fields.identity;
    if (recordIdentity.entityType != identity.entityType ||
        recordIdentity.rawId != identity.rawId) {
      throw const FormatException(
        'Remote record and envelope identities do not match.',
      );
    }
    final versionField = EntityConventions.serverVersionFieldName;
    if (fields.containsKey(versionField) &&
        parseServerVersion(fields[versionField]) != serverVersion) {
      throw const FormatException(
        'Remote record and envelope server versions do not match.',
      );
    }
  }

  final EntityIdentity<dynamic> identity;
  final ServerVersion serverVersion;
  final RemoteEntityFields fields;
  final ServerSequence serverSequence;
  final SyncOperationId? sourceOperationId;
  final bool isRevocation;
}

/// A complete point-in-time entity record fetched outside the ordered graph
/// change stream. It does not advance the pull cursor.
final class RemoteEntitySnapshot {
  RemoteEntitySnapshot({
    required this.identity,
    required this.serverVersion,
    required this.fields,
  }) {
    final recordIdentity = fields.identity;
    if (recordIdentity.entityType != identity.entityType ||
        recordIdentity.rawId != identity.rawId) {
      throw const FormatException(
        'Remote snapshot record and requested identities do not match.',
      );
    }
    final versionField = EntityConventions.serverVersionFieldName;
    if (fields.containsKey(versionField) &&
        parseServerVersion(fields[versionField]) != serverVersion) {
      throw const FormatException(
        'Remote snapshot record and envelope server versions do not match.',
      );
    }
  }

  final EntityIdentity<dynamic> identity;
  final ServerVersion serverVersion;
  final RemoteEntityFields fields;
}

final class PushResult {
  PushResult({
    required this.canonicalChange,
    Iterable<RemoteEntityChange> relatedChanges = const [],
    Iterable<OrderScopeVersionReceipt> orderScopeVersions = const [],
  }) : relatedChanges = List<RemoteEntityChange>.unmodifiable(relatedChanges),
       orderScopeVersions = List<OrderScopeVersionReceipt>.unmodifiable(
         orderScopeVersions,
       );

  final RemoteEntityChange canonicalChange;
  final List<RemoteEntityChange> relatedChanges;
  final List<OrderScopeVersionReceipt> orderScopeVersions;

  Iterable<RemoteEntityChange> get canonicalChanges sync* {
    yield canonicalChange;
    yield* relatedChanges;
  }

  void validateFor(PushSyncWorkItem item) {
    final operation = item.operation;
    if (canonicalChange.identity.entityType != operation.identity.entityType ||
        canonicalChange.identity.rawId != operation.identity.rawId) {
      throw const RejectedSyncException.serverContract(
        code: 'push_identity_mismatch',
        message: 'Push result identity does not match the submitted operation.',
      );
    }
    final identities = <String>{};
    for (final change in canonicalChanges) {
      if (change.sourceOperationId != operation.operationId) {
        throw const RejectedSyncException.serverContract(
          code: 'push_receipt_mismatch',
          message:
              'Push result receipt does not match the submitted operation.',
        );
      }
      if (change.isRevocation) {
        throw const RejectedSyncException.serverContract(
          code: 'push_revocation_result',
          message: 'A push result cannot revoke an acknowledged entity.',
        );
      }
      final key = '${change.identity.entityType}\u0000${change.identity.rawId}';
      if (!identities.add(key)) {
        throw const RejectedSyncException.serverContract(
          code: 'duplicate_push_result_identity',
          message: 'A push result cannot acknowledge one identity twice.',
        );
      }
    }
    final scopes = <String>{};
    for (final receipt in orderScopeVersions) {
      final key = jsonEncode(receipt.scope);
      if (!scopes.add(key)) {
        throw const RejectedSyncException.serverContract(
          code: 'duplicate_order_scope_receipt',
          message: 'A push result cannot acknowledge one ordered scope twice.',
        );
      }
    }
  }
}

final class PullResult {
  PullResult({
    required this.requestedAfter,
    required Iterable<RemoteEntityChange> changes,
    required this.nextSequence,
    required this.hasMore,
  }) : changes = List.unmodifiable(changes) {
    if (nextSequence.value < requestedAfter.value) {
      throw ArgumentError.value(
        nextSequence,
        'nextSequence',
        'A pull cursor cannot move backward.',
      );
    }
    var previous = requestedAfter.value;
    for (final change in this.changes) {
      final sequence = change.serverSequence.value;
      if (sequence <= previous || sequence > nextSequence.value) {
        throw ArgumentError.value(
          change.serverSequence,
          'changes',
          'Changes must be strictly ordered after the requested cursor and '
              'must not exceed the next cursor.',
        );
      }
      previous = sequence;
    }
    if (hasMore &&
        (this.changes.isEmpty ||
            nextSequence != this.changes.last.serverSequence)) {
      throw ArgumentError.value(
        nextSequence,
        'nextSequence',
        'A continued page must end exactly at its next cursor.',
      );
    }
  }

  final List<RemoteEntityChange> changes;
  final ServerSequence requestedAfter;
  final ServerSequence nextSequence;
  final bool hasMore;
}

/// How completeness of one generated inverse relationship was resolved.
///
/// This is deliberately distinct from an entity set's own [Cardinality].
/// A relationship can be complete because every link is bounded, or because
/// its unique target set is bounded even when the link table is not. When
/// neither fact proves completeness, generation safely defaults to unbounded.
enum RelationshipCardinalityResolution {
  unboundedByDefault,
  boundedByLinkEntity,
  boundedByOwnerInverse,
  boundedByTargetEntity;

  Cardinality get cardinality => switch (this) {
    RelationshipCardinalityResolution.unboundedByDefault =>
      Cardinality.unbounded,
    RelationshipCardinalityResolution.boundedByLinkEntity ||
    RelationshipCardinalityResolution.boundedByOwnerInverse ||
    RelationshipCardinalityResolution.boundedByTargetEntity =>
      Cardinality.bounded,
  };
}

/// Generated, storage-independent metadata for one normalized relationship.
///
/// The definition is emitted from the unique pair and references already
/// present on the link entity. Runtime adapters consume this resolved fact
/// instead of re-inferring cardinality or endpoint roles independently.
final class RelationshipDefinition {
  const RelationshipDefinition({
    required this.linkEntityType,
    required this.sourceEntityType,
    required this.targetEntityType,
    required this.sourceFieldName,
    required this.targetFieldName,
    required this.activeFieldName,
    required this.cardinalityResolution,
    required this.ordered,
  });

  final String linkEntityType;
  final String sourceEntityType;
  final String targetEntityType;
  final String sourceFieldName;
  final String targetFieldName;
  final String activeFieldName;
  final RelationshipCardinalityResolution cardinalityResolution;
  final bool ordered;

  Cardinality get cardinality => cardinalityResolution.cardinality;

  @override
  bool operator ==(Object other) =>
      other is RelationshipDefinition &&
      linkEntityType == other.linkEntityType &&
      sourceEntityType == other.sourceEntityType &&
      targetEntityType == other.targetEntityType &&
      sourceFieldName == other.sourceFieldName &&
      targetFieldName == other.targetFieldName &&
      activeFieldName == other.activeFieldName &&
      cardinalityResolution == other.cardinalityResolution &&
      ordered == other.ordered;

  @override
  int get hashCode => Object.hash(
    linkEntityType,
    sourceEntityType,
    targetEntityType,
    sourceFieldName,
    targetFieldName,
    activeFieldName,
    cardinalityResolution,
    ordered,
  );
}

/// One aggregate-to-component edge derived from an `@Composition` field.
///
/// This is graph metadata rather than handwritten configuration: the graph
/// definition derives it from generated field descriptors and validates the
/// contract once before any runtime starts.
final class CompositionDefinition {
  const CompositionDefinition({
    required this.aggregateEntityType,
    required this.fieldName,
    required this.componentEntityType,
  });

  final String aggregateEntityType;
  final String fieldName;
  final String componentEntityType;

  @override
  bool operator ==(Object other) =>
      other is CompositionDefinition &&
      aggregateEntityType == other.aggregateEntityType &&
      fieldName == other.fieldName &&
      componentEntityType == other.componentEntityType;

  @override
  int get hashCode =>
      Object.hash(aggregateEntityType, fieldName, componentEntityType);
}

/// One generated source-to-activity-entry relationship.
///
/// The source descriptor supplies the label and the activity entry owns the
/// normalized immutable fields. Runtime mutation coordination consumes this
/// metadata without discovering capabilities dynamically.
final class ActivityTrackingDefinition {
  const ActivityTrackingDefinition({
    required this.sourceEntityType,
    required this.activityEntityType,
  });

  final String sourceEntityType;
  final String activityEntityType;

  @override
  bool operator ==(Object other) =>
      other is ActivityTrackingDefinition &&
      sourceEntityType == other.sourceEntityType &&
      activityEntityType == other.activityEntityType;

  @override
  int get hashCode => Object.hash(sourceEntityType, activityEntityType);
}

/// Stable generated identity for one application-owned sync target.
///
/// [typeIdentity] is the exact package URI and enum type selected at compile
/// time. [wireName] is the durable routing value persisted with work. Domain
/// code uses the enum constant; generic runtimes use this erased descriptor.
final class SyncTargetId {
  const SyncTargetId({required this.typeIdentity, required this.wireName});

  /// Explicit compatibility seam for isolated descriptor-level runtime tests.
  static const testOnly = SyncTargetId(
    typeIdentity: 'package:nodus/testing.dart#TestSyncTarget',
    wireName: 'test',
  );

  final String typeIdentity;
  final String wireName;

  @override
  bool operator ==(Object other) =>
      other is SyncTargetId &&
      typeIdentity == other.typeIdentity &&
      wireName == other.wireName;

  @override
  int get hashCode => Object.hash(typeIdentity, wireName);
}

/// Resolved synchronization authority and target for one entity descriptor.
final class SyncBindingDefinition {
  const SyncBindingDefinition({
    required this.entityType,
    required this.mode,
    this.target,
  });

  final String entityType;
  final SyncMode mode;
  final SyncTargetId? target;

  @override
  bool operator ==(Object other) =>
      other is SyncBindingDefinition &&
      entityType == other.entityType &&
      mode == other.mode &&
      target == other.target;

  @override
  int get hashCode => Object.hash(entityType, mode, target);
}

/// Runtime adapter bindings for one generated entity graph.
///
/// Applications construct the generated typed registry; this erased registry
/// is the narrow scheduler/runtime boundary. It rejects missing, extra, or
/// graph-incompatible adapters before any local session starts.
final class SyncAdapterRegistry {
  factory SyncAdapterRegistry({
    required EntityGraphDefinition definition,
    required Map<SyncTargetId, SyncAdapter> adapters,
  }) {
    final expected = {
      for (final binding in definition.syncBindings) ?binding.target,
    };
    if (adapters.length != expected.length ||
        !adapters.keys.toSet().containsAll(expected)) {
      throw ArgumentError.value(
        adapters.keys,
        'adapters',
        'The sync adapter registry must bind every used generated target '
            'exactly once.',
      );
    }
    for (final entry in adapters.entries) {
      final requiresPush = definition.pushSyncTargets.contains(entry.key);
      final requiresPull = definition.pullSyncTargets.contains(entry.key);
      if (requiresPush && entry.value is! PushSyncAdapter) {
        throw ArgumentError.value(
          entry.value,
          'adapters',
          'Target `${entry.key.wireName}` requires idempotent versioned push.',
        );
      }
      if (requiresPull && entry.value is! PullSyncAdapter) {
        throw ArgumentError.value(
          entry.value,
          'adapters',
          'Target `${entry.key.wireName}` requires ordered cursor recovery.',
        );
      }
      final expectedDefinition = definition.syncSubgraphFor(entry.key);
      final backendDefinition = entry.value.definition;
      if (!expectedDefinition.isTransportCompatibleWith(backendDefinition)) {
        throw ArgumentError.value(
          backendDefinition,
          'adapters',
          'Adapter `${entry.key.wireName}` was built for an over-broad, stale, '
              'or different target descriptor subgraph.',
        );
      }
    }
    return SyncAdapterRegistry._(
      definition: definition,
      adapters: Map.unmodifiable(adapters),
    );
  }

  const SyncAdapterRegistry._({
    required this.definition,
    required Map<SyncTargetId, SyncAdapter> adapters,
  }) : _adapters = adapters;

  final EntityGraphDefinition definition;
  final Map<SyncTargetId, SyncAdapter> _adapters;

  Iterable<SyncTargetId> get targets => _adapters.keys;

  SyncAdapter backendFor(SyncTargetId target) =>
      _adapters[target] ??
      (throw StateError('No sync adapter is bound for `${target.wireName}`.'));

  SyncAdapter? backendForEntity(String entityType) {
    final binding = definition.syncBindings.singleWhere(
      (binding) => binding.entityType == entityType,
    );
    final target = binding.target;
    return target == null ? null : backendFor(target);
  }
}

/// The generated, immutable definition of one local entity graph.
///
/// Backends consume this value directly so applications cannot accidentally
/// reconstruct a graph from a stale descriptor subset or duplicate its
/// generated pull contract. The schema version is included because this is the
/// single public description of the graph, even though transports only need
/// [descriptors], [relationships], [syncBindings], and [pullRpcName].
final class EntityGraphDefinition {
  factory EntityGraphDefinition.single(EntityDescriptorBase descriptor) =>
      EntityGraphDefinition(
        schemaVersion: 1,
        descriptors: [descriptor],
        relationships: const [],
        syncBindings: [
          SyncBindingDefinition(
            entityType: descriptor.entityType,
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
        ],
        pullRpcName: 'pull_${descriptor.tableName}_changes',
      );

  factory EntityGraphDefinition({
    required int schemaVersion,
    required Iterable<EntityDescriptorBase> descriptors,
    required Iterable<RelationshipDefinition> relationships,
    Iterable<ActivityTrackingDefinition> activityTrackings = const [],
    required Iterable<SyncBindingDefinition> syncBindings,
    required String pullRpcName,
  }) {
    if (schemaVersion < 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'A graph schema version must be positive.',
      );
    }
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(pullRpcName)) {
      throw ArgumentError.value(
        pullRpcName,
        'pullRpcName',
        'A graph pull RPC must be a lowercase SQL identifier.',
      );
    }
    final frozenDescriptors = List<EntityDescriptorBase>.unmodifiable(
      descriptors,
    );
    if (frozenDescriptors.isEmpty) {
      throw ArgumentError.value(
        descriptors,
        'descriptors',
        'An entity graph must contain at least one entity.',
      );
    }
    final entityTypes = {
      for (final descriptor in frozenDescriptors) descriptor.entityType,
    };
    final tableNames = {
      for (final descriptor in frozenDescriptors) descriptor.tableName,
    };
    if (entityTypes.length != frozenDescriptors.length ||
        tableNames.length != frozenDescriptors.length) {
      throw ArgumentError.value(
        descriptors,
        'descriptors',
        'Entity types and table names must be unique within a graph.',
      );
    }
    final frozenRelationships = List<RelationshipDefinition>.unmodifiable(
      relationships,
    );
    _validateRelationshipDefinitions(
      descriptors: frozenDescriptors,
      relationships: frozenRelationships,
    );
    final compositions = _deriveCompositionDefinitions(frozenDescriptors);
    final frozenActivityTrackings =
        List<ActivityTrackingDefinition>.unmodifiable(activityTrackings);
    _validateActivityTrackingDefinitions(
      descriptors: frozenDescriptors,
      activityTrackings: frozenActivityTrackings,
    );
    final frozenSyncBindings = List<SyncBindingDefinition>.unmodifiable(
      syncBindings,
    );
    _validateSyncBindings(
      descriptors: frozenDescriptors,
      bindings: frozenSyncBindings,
    );
    final protocolVersion = frozenDescriptors
        .map((descriptor) => descriptor.protocolVersion)
        .reduce((left, right) => left > right ? left : right);
    return EntityGraphDefinition._(
      schemaVersion: schemaVersion,
      protocolVersion: protocolVersion,
      descriptors: frozenDescriptors,
      relationships: frozenRelationships,
      compositions: compositions,
      activityTrackings: frozenActivityTrackings,
      syncBindings: frozenSyncBindings,
      pullRpcName: pullRpcName,
    );
  }

  const EntityGraphDefinition._({
    required this.schemaVersion,
    required this.protocolVersion,
    required this.descriptors,
    required this.relationships,
    required this.compositions,
    required this.activityTrackings,
    required this.syncBindings,
    required this.pullRpcName,
  });

  final int schemaVersion;
  final int protocolVersion;
  final List<EntityDescriptorBase> descriptors;
  final List<RelationshipDefinition> relationships;
  final List<CompositionDefinition> compositions;
  final List<ActivityTrackingDefinition> activityTrackings;
  final List<SyncBindingDefinition> syncBindings;
  final String pullRpcName;

  SyncBindingDefinition syncBindingFor(String entityType) =>
      syncBindings.singleWhere((binding) => binding.entityType == entityType);

  EntitySemanticCommand<dynamic> decodeSemanticCommand({
    required EntityDescriptorBase descriptor,
    required String name,
    required JsonMap payload,
  }) {
    if (name == 'replaceRelationship') {
      final relationship = relationships
          .where(
            (candidate) =>
                candidate.linkEntityType == descriptor.entityType &&
                candidate.cardinality == Cardinality.bounded,
          )
          .firstOrNull;
      if (relationship == null) {
        throw const RejectedSyncException.validation(
          code: 'unsupported_command',
          message: 'Exact replacement is unavailable for this relationship.',
        );
      }
      return ReplaceActiveRelationshipCommand<
        dynamic,
        dynamic,
        dynamic
      >.fromWire(
        payload,
        parseLinkId: parseLocalId<dynamic>,
        parseSourceId: parseLocalId<dynamic>,
        parseTargetId: parseLocalId<dynamic>,
      );
    }
    return descriptor.decodeSemanticCommand(name, payload);
  }

  Set<SyncTargetId> get syncTargets =>
      Set.unmodifiable({for (final binding in syncBindings) ?binding.target});

  Set<SyncTargetId> get pullSyncTargets => Set.unmodifiable({
    for (final binding in syncBindings)
      if (binding.mode == SyncMode.replicated ||
          binding.mode == SyncMode.imported)
        ?binding.target,
  });

  Set<SyncTargetId> get pushSyncTargets => Set.unmodifiable({
    for (final binding in syncBindings)
      if (binding.mode == SyncMode.replicated ||
          binding.mode == SyncMode.exported)
        ?binding.target,
  });

  /// Returns the exact transport-visible descriptor group owned by [target].
  ///
  /// Local-only entities and bindings for other targets are excluded. The
  /// generator rejects ordinary cross-target constraints before this runtime
  /// boundary, so a graph-aware adapter never needs unrelated descriptors.
  EntityGraphDefinition syncSubgraphFor(SyncTargetId target) {
    if (!syncTargets.contains(target)) {
      throw ArgumentError.value(
        target,
        'target',
        'The target is not used by this entity graph.',
      );
    }
    final selectedBindings = [
      for (final binding in syncBindings)
        if (binding.target == target) binding,
    ];
    final selectedTypes = {
      for (final binding in selectedBindings) binding.entityType,
    };
    return EntityGraphDefinition(
      schemaVersion: schemaVersion,
      descriptors: [
        for (final descriptor in descriptors)
          if (selectedTypes.contains(descriptor.entityType)) descriptor,
      ],
      relationships: [
        for (final relationship in relationships)
          if (selectedTypes.contains(relationship.linkEntityType) &&
              selectedTypes.contains(relationship.sourceEntityType) &&
              selectedTypes.contains(relationship.targetEntityType))
            relationship,
      ],
      activityTrackings: [
        for (final tracking in activityTrackings)
          if (selectedTypes.contains(tracking.sourceEntityType) &&
              selectedTypes.contains(tracking.activityEntityType))
            tracking,
      ],
      syncBindings: selectedBindings,
      pullRpcName: pullRpcName,
    );
  }

  /// Whether two definitions describe the same transport-visible graph.
  ///
  /// Drift schema versions are deliberately excluded: a local-only migration
  /// does not make a backend stale. Entity descriptor types, tables, protocol
  /// versions, collaboration tables, resolved relationships, and the pull
  /// entry point must agree.
  bool isTransportCompatibleWith(EntityGraphDefinition other) {
    if (pullRpcName != other.pullRpcName ||
        protocolVersion != other.protocolVersion ||
        descriptors.length != other.descriptors.length ||
        relationships.length != other.relationships.length ||
        activityTrackings.length != other.activityTrackings.length ||
        syncBindings.length != other.syncBindings.length) {
      return false;
    }
    final otherByType = {
      for (final descriptor in other.descriptors)
        descriptor.entityType: descriptor,
    };
    for (final descriptor in descriptors) {
      final candidate = otherByType[descriptor.entityType];
      if (candidate == null ||
          candidate.runtimeType != descriptor.runtimeType ||
          candidate.tableName != descriptor.tableName ||
          candidate.protocolVersion != descriptor.protocolVersion ||
          candidate.collaborationTableName !=
              descriptor.collaborationTableName) {
        return false;
      }
    }
    final otherRelationships = other.relationships.toSet();
    final otherCompositions = other.compositions.toSet();
    final otherActivityTrackings = other.activityTrackings.toSet();
    final otherSyncBindings = other.syncBindings.toSet();
    return relationships.every(otherRelationships.contains) &&
        compositions.length == otherCompositions.length &&
        compositions.every(otherCompositions.contains) &&
        activityTrackings.every(otherActivityTrackings.contains) &&
        syncBindings.every(otherSyncBindings.contains);
  }

  /// Rejects an adapter built for a different generated graph.
  void validateBackend(SyncAdapter backend) {
    if (!isTransportCompatibleWith(backend.definition)) {
      throw ArgumentError.value(
        backend.definition,
        'backend',
        'The backend entity graph does not match the generated entity graph.',
      );
    }
  }
}

List<CompositionDefinition> _deriveCompositionDefinitions(
  List<EntityDescriptorBase> descriptors,
) {
  final entityTypes = {
    for (final descriptor in descriptors) descriptor.entityType,
  };
  final compositions = <CompositionDefinition>[];
  for (final aggregate in descriptors) {
    for (final field in aggregate.fields) {
      final reference = field.reference;
      if (reference == null || !reference.composition) continue;
      if (field.nullable || field.mutable) {
        throw ArgumentError.value(
          field,
          'descriptors',
          'A composition identity must be immutable and non-null.',
        );
      }
      if (!entityTypes.contains(reference.targetEntityType)) {
        throw ArgumentError.value(
          field,
          'descriptors',
          'Every composition target must belong to the entity graph.',
        );
      }
      compositions.add(
        CompositionDefinition(
          aggregateEntityType: aggregate.entityType,
          fieldName: field.name,
          componentEntityType: reference.targetEntityType,
        ),
      );
    }
  }
  return List<CompositionDefinition>.unmodifiable(compositions);
}

void _validateActivityTrackingDefinitions({
  required List<EntityDescriptorBase> descriptors,
  required List<ActivityTrackingDefinition> activityTrackings,
}) {
  final byType = {
    for (final descriptor in descriptors) descriptor.entityType: descriptor,
  };
  final sources = <String>{};
  final entries = <String>{};
  const requiredEntryFields = {
    'subjectId',
    'actorId',
    'operation',
    'label',
    'sourceOperationId',
    'occurredAt',
  };
  for (final tracking in activityTrackings) {
    final source = byType[tracking.sourceEntityType];
    final entry = byType[tracking.activityEntityType];
    if (source is! ActivityTrackedEntityDescriptor ||
        entry is! ActivityEntryEntityDescriptor) {
      throw ArgumentError.value(
        tracking,
        'activityTrackings',
        'Activity tracking endpoints must use their generated descriptor '
            'capabilities.',
      );
    }
    final entryDescriptor = entry!;
    if (!sources.add(tracking.sourceEntityType) ||
        !entries.add(tracking.activityEntityType)) {
      throw ArgumentError.value(
        activityTrackings,
        'activityTrackings',
        'Each tracked source and activity entry must participate exactly once.',
      );
    }
    final fields = {
      for (final field in entryDescriptor.fields) field.name: field,
    };
    if (!fields.keys.toSet().containsAll(requiredEntryFields) ||
        requiredEntryFields.any((name) => fields[name]!.mutable)) {
      throw ArgumentError.value(
        entryDescriptor,
        'descriptors',
        'An activity entry must contain the complete immutable generated '
            'activity field set.',
      );
    }
  }
}

void _validateRelationshipDefinitions({
  required List<EntityDescriptorBase> descriptors,
  required List<RelationshipDefinition> relationships,
}) {
  final byType = {
    for (final descriptor in descriptors) descriptor.entityType: descriptor,
  };
  final linkTypes = <String>{};
  for (final relationship in relationships) {
    final link = byType[relationship.linkEntityType];
    final source = byType[relationship.sourceEntityType];
    final target = byType[relationship.targetEntityType];
    if (link == null || source == null || target == null) {
      throw ArgumentError.value(
        relationship,
        'relationships',
        'Every relationship endpoint and link must belong to the graph.',
      );
    }
    if (!linkTypes.add(relationship.linkEntityType)) {
      throw ArgumentError.value(
        relationships,
        'relationships',
        'A link entity can define only one inferred relationship.',
      );
    }

    EntityFieldDescriptor field(String name) {
      final matches = link.fields.where((field) => field.name == name);
      if (matches.length != 1) {
        throw ArgumentError.value(
          relationship,
          'relationships',
          'Relationship fields must resolve exactly once on the link entity.',
        );
      }
      return matches.single;
    }

    final sourceField = field(relationship.sourceFieldName);
    final targetField = field(relationship.targetFieldName);
    final activeField = field(relationship.activeFieldName);
    if (relationship.sourceFieldName == relationship.targetFieldName ||
        sourceField.reference?.targetEntityType != source.entityType ||
        targetField.reference?.targetEntityType != target.entityType ||
        sourceField.nullable ||
        targetField.nullable ||
        activeField.kind != EntityFieldKind.boolean ||
        activeField.nullable) {
      throw ArgumentError.value(
        relationship,
        'relationships',
        'Relationship endpoint and active-field metadata does not match the '
            'link descriptor.',
      );
    }
    if (relationship.ordered != (link is OrderedDescriptor)) {
      throw ArgumentError.value(
        relationship,
        'relationships',
        'Relationship ordering must match the link descriptor capability.',
      );
    }
    final expectedResolution = link.cardinality == Cardinality.bounded
        ? RelationshipCardinalityResolution.boundedByLinkEntity
        : sourceField.reference?.inverseCardinality == Cardinality.bounded
        ? RelationshipCardinalityResolution.boundedByOwnerInverse
        : target.cardinality == Cardinality.bounded
        ? RelationshipCardinalityResolution.boundedByTargetEntity
        : RelationshipCardinalityResolution.unboundedByDefault;
    if (relationship.cardinalityResolution != expectedResolution) {
      throw ArgumentError.value(
        relationship,
        'relationships',
        'Relationship cardinality must be resolved from the generated link '
            'and target descriptors.',
      );
    }
    final uniqueConstraints = link is EntityUniqueConstraintDescriptor
        ? (link as EntityUniqueConstraintDescriptor).uniqueConstraints
        : const <EntityUniqueConstraint>[];
    final uniquePair = uniqueConstraints.any(
      (constraint) =>
          constraint.condition == null &&
          constraint.fieldNames.length == 2 &&
          constraint.fieldNames.toSet().length == 2 &&
          constraint.fieldNames.toSet().containsAll([
            relationship.sourceFieldName,
            relationship.targetFieldName,
          ]),
    );
    if (!uniquePair) {
      throw ArgumentError.value(
        relationship,
        'relationships',
        'A normalized relationship requires one unconditional unique '
            'source-target pair.',
      );
    }
  }
}

void _validateSyncBindings({
  required List<EntityDescriptorBase> descriptors,
  required List<SyncBindingDefinition> bindings,
}) {
  final descriptorTypes = {
    for (final descriptor in descriptors) descriptor.entityType,
  };
  final bindingTypes = {for (final binding in bindings) binding.entityType};
  if (bindings.length != descriptors.length ||
      bindingTypes.length != bindings.length ||
      !bindingTypes.containsAll(descriptorTypes)) {
    throw ArgumentError.value(
      bindings,
      'syncBindings',
      'Every graph entity requires exactly one generated sync binding.',
    );
  }
  final targetTypes = <String>{};
  for (final binding in bindings) {
    final target = binding.target;
    if ((binding.mode == SyncMode.localOnly) != (target == null)) {
      throw ArgumentError.value(
        binding,
        'syncBindings',
        'localOnly entities have no target; every other sync mode requires '
            'one.',
      );
    }
    if (target == null) continue;
    if (!RegExp(
          r'^package:[^#]+#[A-Za-z][A-Za-z0-9_]*$',
        ).hasMatch(target.typeIdentity) ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(target.wireName)) {
      throw ArgumentError.value(
        target,
        'syncBindings',
        'Sync targets require one package enum identity and a stable '
            'lowercase wire name.',
      );
    }
    targetTypes.add(target.typeIdentity);
  }
  if (targetTypes.length > 1) {
    throw ArgumentError.value(
      bindings,
      'syncBindings',
      'One graph cannot mix sync-target enum types.',
    );
  }
}

/// Base contract for a generated target adapter.
///
/// Every adapter carries the exact transport-visible descriptor subgraph it was
/// built for. Registry binding validates that definition before opening local
/// persistence, so directional capability markers cannot bypass compatibility.
abstract interface class SyncAdapter {
  EntityGraphDefinition get definition;
}

/// Adapter capability for idempotent, version-checked outbound operations.
abstract interface class PushSyncAdapter implements SyncAdapter {
  Future<PushResult> push(PushSyncWorkItem item);
}

/// Adapter capability for authoritative ordered cursor recovery.
abstract interface class PullSyncAdapter implements SyncAdapter {
  Future<PullResult> pull({required ServerSequence afterSequence});
}

/// Adapter capability for targets that own both outbound and inbound lanes.
abstract interface class PushPullSyncAdapter
    implements PushSyncAdapter, PullSyncAdapter {}

/// Optional transport capability for demand-driven entity reads.
///
/// Implementations must rely on the transport's normal row authorization. A
/// snapshot never advances graph pull state and is merged into the same local
/// projection/conflict machinery as ordered changes.
abstract interface class SnapshotSyncAdapter implements SyncAdapter {
  Future<RemoteEntitySnapshot?> fetchSnapshot(EntityIdentity<dynamic> identity);
}

/// Generated, target-scoped input for constructing one synchronization
/// adapter.
///
/// A connector receives the authenticated account and the exact descriptor
/// subgraph for its target. This keeps transport packages independent from an
/// application's generated graph types while preventing applications from
/// rebuilding descriptor groups or adapter registries by hand.
final class SyncConnectorContext {
  factory SyncConnectorContext({
    required String accountId,
    required SyncTargetId target,
    required EntityGraphDefinition definition,
  }) {
    if (accountId.isEmpty) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'A connector requires an authenticated account ID.',
      );
    }
    if (definition.syncTargets.length != 1 ||
        !definition.syncTargets.contains(target)) {
      throw ArgumentError.value(
        definition,
        'definition',
        'A connector requires the exact single-target descriptor subgraph.',
      );
    }
    return SyncConnectorContext._(
      accountId: accountId,
      target: target,
      definition: definition,
    );
  }

  const SyncConnectorContext._({
    required this.accountId,
    required this.target,
    required this.definition,
  });

  final String accountId;
  final SyncTargetId target;
  final EntityGraphDefinition definition;
}

/// Constructs one target adapter from generated, target-scoped metadata.
///
/// Generated `open<Target>` factories accept this callback and own local
/// storage plus typed registry assembly. The adapter may be constructed
/// synchronously or after asynchronous client setup.
typedef SyncConnector<A extends SyncAdapter> =
    FutureOr<A> Function(SyncConnectorContext context);

abstract interface class RemoteChangeSignalSource {
  Stream<void> get remoteChangeSignals;

  Future<void> disposeRemoteChangeSignals();
}

abstract interface class SyncPersistence {
  Future<SyncWorkItem?> claimNext(SyncTargetId target);

  Future<ServerSequence> readPullCursor(SyncTargetId target);

  Future<void> completePush(PushSyncWorkItem item, PushResult result);

  Future<void> completePull(PullSyncWorkItem item, PullResult result);

  Future<SyncFailureOutcome> handleFailure(
    SyncWorkItem item,
    Object error,
    StackTrace stackTrace,
  );
}

final class SyncFailureOutcome {
  const SyncFailureOutcome({required this.continueDraining, this.retryAt});

  final bool continueDraining;
  final DateTime? retryAt;
}

typedef ScheduleSyncWake = void Function(SyncTargetId target, DateTime retryAt);

final class SyncWorker {
  SyncWorker({
    required this.target,
    required SyncPersistence persistence,
    required SyncAdapter backend,
    required ScheduleSyncWake scheduleWake,
  }) : _persistence = persistence,
       _backend = backend,
       _scheduleWake = scheduleWake;

  final SyncTargetId target;
  final SyncPersistence _persistence;
  final SyncAdapter _backend;
  final ScheduleSyncWake _scheduleWake;
  Future<void>? _activeDrain;
  bool _rerunRequested = false;

  Future<void> drain() {
    final active = _activeDrain;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    final started = _runRequestedDrains();
    _activeDrain = started.whenComplete(() => _activeDrain = null);
    return _activeDrain!;
  }

  Future<void> waitForIdle() => _activeDrain ?? Future<void>.value();

  Future<void> _runRequestedDrains() async {
    do {
      _rerunRequested = false;
      final pausedForRetry = await _drain();
      if (pausedForRetry) {
        _rerunRequested = false;
        return;
      }
    } while (_rerunRequested);
  }

  Future<bool> _drain() async {
    while (true) {
      final item = await _persistence.claimNext(target);
      if (item == null) return false;

      try {
        if (item.target != target) {
          throw RejectedSyncException.protocol(
            code: 'sync_target_mismatch',
            message:
                'Worker `${target.wireName}` claimed work routed to '
                '`${item.target.wireName}`.',
          );
        }
        switch (item) {
          case PushSyncWorkItem():
            final adapter = switch (_backend) {
              final PushSyncAdapter value => value,
              _ => throw RejectedSyncException.protocol(
                code: 'sync_adapter_capability_mismatch',
                message:
                    'Target `${target.wireName}` claimed push work without '
                    'a push-capable adapter.',
              ),
            };
            final result = await adapter.push(item);
            result.validateFor(item);
            await _persistence.completePush(item, result);
          case PullSyncWorkItem():
            final cursor = await _persistence.readPullCursor(target);
            final adapter = switch (_backend) {
              final PullSyncAdapter value => value,
              _ => throw RejectedSyncException.protocol(
                code: 'sync_adapter_capability_mismatch',
                message:
                    'Target `${target.wireName}` claimed pull work without '
                    'a pull-capable adapter.',
              ),
            };
            final result = await adapter.pull(afterSequence: cursor);
            if (result.requestedAfter != cursor) {
              throw RejectedSyncException.serverContract(
                code: 'pull_cursor_mismatch',
                message:
                    'Backend returned a pull page for '
                    '${result.requestedAfter.value}; expected ${cursor.value}.',
              );
            }
            await _persistence.completePull(item, result);
        }
      } catch (error, stackTrace) {
        final outcome = await _persistence.handleFailure(
          item,
          error,
          stackTrace,
        );
        final retryAt = outcome.retryAt;
        if (retryAt != null) _scheduleWake(target, retryAt);
        if (outcome.continueDraining) continue;
        return true;
      }
    }
  }
}

final class MergeResolution {
  const MergeResolution({
    required this.visibleFields,
    required this.rebasedPendingPatch,
  });

  final JsonMap visibleFields;
  final JsonMap rebasedPendingPatch;
}

MergeResolution mergeRemoteFields({
  required JsonMap visibleFields,
  required JsonMap pendingPatch,
  required JsonMap remoteFields,
  required Map<String, FieldConflictPolicy> policies,
  required ServerVersion remoteVersion,
  required ServerVersion pendingBaseVersion,
}) {
  final visible = JsonMap.of(visibleFields);
  final pending = JsonMap.of(pendingPatch);
  visible.addAll(pending);
  final remoteIsNewerThanPendingBase =
      remoteVersion.value > pendingBaseVersion.value;

  for (final entry in remoteFields.entries) {
    final hasPendingValue = pending.containsKey(entry.key);
    if (!hasPendingValue) {
      visible[entry.key] = entry.value;
      continue;
    }

    switch (policies[entry.key] ?? FieldConflictPolicy.serverWins) {
      case FieldConflictPolicy.localWins:
        break;
      case FieldConflictPolicy.serverWins:
        if (remoteIsNewerThanPendingBase) {
          visible[entry.key] = entry.value;
          pending.remove(entry.key);
        }
    }
  }

  return MergeResolution(visibleFields: visible, rebasedPendingPatch: pending);
}

final class LocalPersistenceFailure {
  const LocalPersistenceFailure({required this.mutation, required this.error});

  final LocalEntityMutation mutation;
  final Object error;
}

typedef PersistMutation = Future<void> Function(LocalEntityMutation mutation);
typedef PersistMutationBatch =
    Future<void> Function(List<LocalEntityMutation> mutations);

final class _PendingMutation {
  _PendingMutation(this.mutation, this.rollbackIfCurrent, {this.onSettled});

  LocalEntityMutation mutation;
  final void Function() rollbackIfCurrent;
  final void Function()? onSettled;
  final Completer<LocalMutationCommitResult> _completion = Completer();

  Future<LocalMutationCommitResult> get committed => _completion.future;

  void complete(LocalMutationCommitResult result) {
    if (!_completion.isCompleted) _completion.complete(result);
  }
}

final class MutationCoordinator {
  MutationCoordinator({
    required PersistMutation persist,
    this.clock = const SystemClock(),
    this.diagnostics = const NoopLocalEntityDiagnostics(),
  }) : _persist = ((mutations) async {
         for (final mutation in mutations) {
           await persist(mutation);
         }
       }) {
    failures = ReadOnlyObservableList(_failures);
  }

  MutationCoordinator.batches({
    required PersistMutationBatch persist,
    this.clock = const SystemClock(),
    this.diagnostics = const NoopLocalEntityDiagnostics(),
  }) : _persist = persist {
    failures = ReadOnlyObservableList(_failures);
  }

  final PersistMutationBatch _persist;
  final Clock clock;
  final LocalEntityDiagnostics diagnostics;
  final ObservableList<LocalPersistenceFailure> _failures = ObservableList();
  late final ReadOnlyObservableList<LocalPersistenceFailure> failures;
  Future<void> _tail = Future<void>.value();
  int _pendingCount = 0;
  int _reportedFailureCount = 0;

  Future<LocalMutationCommitResult> schedule(
    LocalEntityMutation mutation, {
    required void Function() rollbackIfCurrent,
    void Function()? onSettled,
  }) {
    final pending = _PendingMutation(
      mutation,
      rollbackIfCurrent,
      onSettled: onSettled,
    );
    _scheduleBatch([pending]);
    return pending.committed;
  }

  void _scheduleBatch(List<_PendingMutation> batch) {
    if (batch.isEmpty) return;
    final immutableBatch = List<_PendingMutation>.unmodifiable(batch);
    _pendingCount += immutableBatch.length;
    _tail = _tail.then((_) async {
      var result = const LocalMutationCommitResult.success();
      try {
        await _persist([
          for (final pending in immutableBatch) pending.mutation,
        ]);
      } catch (error, stackTrace) {
        result = LocalMutationCommitResult.failure(error, stackTrace);
        runInAction(() {
          for (final pending in immutableBatch.reversed) {
            pending.rollbackIfCurrent();
          }
          for (final pending in immutableBatch) {
            _failures.add(
              LocalPersistenceFailure(mutation: pending.mutation, error: error),
            );
          }
        });
        for (final pending in immutableBatch) {
          final mutation = pending.mutation;
          _recordDiagnosticSafely(
            diagnostics,
            LocalPersistenceFailureDiagnostic(
              occurredAt: clock.nowUtc(),
              operationId: mutation.operationId,
              identity: mutation.identity,
              operation: mutation.operation,
              localRevision: mutation.localRevision,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      } finally {
        for (final pending in immutableBatch) {
          pending.onSettled?.call();
          pending.complete(result);
        }
        _pendingCount -= immutableBatch.length;
      }
    });
  }

  Future<void> flush({bool throwOnError = true}) async {
    if (_pendingCount != 0) await _tail;
    if (throwOnError && failures.length > _reportedFailureCount) {
      _reportedFailureCount = failures.length;
      throw failures.last.error;
    }
  }
}
