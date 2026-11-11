library;

import 'package:uuid/uuid.dart';

extension type const LocalId<T>._(String value) {
  factory LocalId(String source) => parseLocalId<T>(source);
}

final RegExp _localIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isValidLocalId(String source) {
  return _localIdPattern.hasMatch(source.trim().toLowerCase());
}

LocalId<T> parseLocalId<T>(String source) {
  final normalized = source.trim().toLowerCase();
  if (!_localIdPattern.hasMatch(normalized)) {
    throw FormatException('Expected a UUID local ID.', source);
  }
  return LocalId<T>._(normalized);
}

/// The UUIDv5 of [namespace] and [name], which every device derives alike.
LocalId<T> derivedLocalId<T>(String namespace, String name) =>
    parseLocalId<T>(const Uuid().v5(namespace, name));

LocalId<T>? tryParseLocalId<T>(String source) {
  if (!isValidLocalId(source)) return null;
  return LocalId<T>._(source.trim().toLowerCase());
}

/// A timezone-free Gregorian calendar date serialized as `yyyy-MM-dd`.
final class LocalDate implements Comparable<LocalDate> {
  const LocalDate._(this.value);

  final String value;

  factory LocalDate(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw RangeError.range(year, 1, 9999, 'year');
    }
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError.value('$year-$month-$day', 'date', 'Invalid date.');
    }
    return LocalDate._(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );
  }

  factory LocalDate.parse(String source) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(source);
    if (match == null) throw FormatException('Expected yyyy-MM-dd.', source);
    try {
      return LocalDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on ArgumentError {
      throw FormatException('Invalid calendar date.', source);
    }
  }

  factory LocalDate.fromDateTime(DateTime value) =>
      LocalDate(value.year, value.month, value.day);

  int get year => int.parse(value.substring(0, 4));
  int get month => int.parse(value.substring(5, 7));
  int get day => int.parse(value.substring(8, 10));

  DateTime toDateTime() => DateTime(year, month, day);

  @override
  int compareTo(LocalDate other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is LocalDate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Opaque persistent ordering key used by generated ordered collections.
///
/// The fixed-width decimal representation sorts identically as text in SQLite,
/// PostgreSQL, and Dart while PostgreSQL can rebalance it with exact `numeric`
/// arithmetic. Domain entities never expose this key; only
/// generated collection infrastructure allocates or mutates it.
final class OrderRank implements Comparable<OrderRank> {
  const OrderRank._(this.value);

  factory OrderRank.parse(String source) {
    final normalized = source.trim().toLowerCase();
    if (!isValid(source)) {
      throw FormatException(
        'Expected a non-boundary fixed-width decimal order rank.',
        source,
      );
    }
    return OrderRank._(normalized);
  }

  final String value;

  static bool isValid(String source) {
    final normalized = source.trim().toLowerCase();
    if (!_orderRankPattern.hasMatch(normalized)) return false;
    final value = BigInt.parse(normalized);
    return value > BigInt.zero && value < _maximumOrderRankValue;
  }

  static OrderRank? tryParse(String source) {
    if (!isValid(source)) return null;
    return OrderRank._(source.trim().toLowerCase());
  }

  @override
  int compareTo(OrderRank other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is OrderRank && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

const int _orderRankBitWidth = 256;
const int _orderRankTextWidth = 78;
final RegExp _orderRankPattern = RegExp(r'^[0-9]{78}$');
final BigInt _maximumOrderRankValue =
    (BigInt.one << _orderRankBitWidth) - BigInt.one;

/// Signals that no rank exists between the requested canonical neighbors.
///
/// Generated ordered collections catch this at the collection boundary,
/// rebalance that complete scope atomically, and retry. It remains public only
/// so generated code in consumer packages can use the typed failure.
final class OrderRankSpaceExhaustedException implements Exception {
  const OrderRankSpaceExhaustedException();

  @override
  String toString() =>
      'OrderRankSpaceExhaustedException: the canonical scope must be rebalanced.';
}

/// Allocates [count] deterministic ranks strictly between two existing ranks.
///
/// A null lower or upper neighbor represents the start or end of the scope.
/// Null is returned when the interval is exhausted so generated infrastructure
/// can atomically rebalance the complete canonical scope and retry.
abstract final class GeneratedOrderRanks {
  static String get upperBoundaryValue =>
      _maximumOrderRankValue.toString().padLeft(_orderRankTextWidth, '0');

  static List<OrderRank>? allocate({
    required int count,
    OrderRank? after,
    OrderRank? before,
  }) {
    if (count < 0) {
      throw RangeError.value(count, 'count', 'Must be non-negative.');
    }
    if (count == 0) return const <OrderRank>[];
    final lower = after == null ? BigInt.zero : BigInt.parse(after.value);
    final upper = before == null
        ? _maximumOrderRankValue
        : BigInt.parse(before.value);
    if (lower >= upper) {
      throw ArgumentError.value(
        (after, before),
        'neighbors',
        'The lower rank must sort before the upper rank.',
      );
    }
    final step = (upper - lower) ~/ BigInt.from(count + 1);
    if (step == BigInt.zero) return null;
    return List<OrderRank>.unmodifiable([
      for (var index = 1; index <= count; index += 1)
        OrderRank._(
          (lower + (step * BigInt.from(index))).toString().padLeft(
            _orderRankTextWidth,
            '0',
          ),
        ),
    ]);
  }

  static OrderRank? between({OrderRank? after, OrderRank? before}) =>
      allocate(count: 1, after: after, before: before)?.single;
}

enum Cardinality { bounded, unbounded }

/// Declares the authority and direction of one entity's synchronization.
///
/// Omit this when graph/entity target inference can select [replicated] or
/// [localOnly] safely. Imported and exported authority are never inferred.
enum SyncMode { localOnly, replicated, imported, exported }

/// Defines where an entity's authenticated owner identity is stored.
///
/// [separate] is the default for ordinary user-owned records and generates the
/// conventional `ownerId`/`owner_id` field. [identity] is for account-root
/// records whose entity ID is itself the authenticated owner ID; it avoids a
/// duplicate owner column and requires `Self` and `Owner` to be the same type.
enum Ownership { separate, identity }

enum ConflictStrategy { localWins, serverWins }

/// Declares which side is allowed to originate a persisted field value.
///
/// [client] is inferred for ordinary domain state. [server] is reserved for
/// trusted workflow state: it is initialized locally from its declared
/// default, omitted from create/patch payloads, and may only change when a
/// canonical server record is synchronized back into the entity graph.
enum FieldAuthority { client, server }

/// Deterministic canonicalization applied at every persisted-field boundary.
enum FieldNormalization {
  none,

  /// Trims leading and trailing whitespace while preserving an empty String.
  trim,

  /// Trims a nullable String and canonicalizes an empty result to null.
  trimToNull,
}

enum RlsOperation { select, insert, update, delete }

enum RlsPrincipal {
  owner,
  participant,
  collaborator,
  reference,
  relationship,
  authenticated,
}

enum CollaborationLifecycle { direct, workflow }

/// Controls whether a broad authenticated SELECT grant also participates in
/// the ordered graph pull.
///
/// [inferred] synchronizes bounded entities and keeps unbounded entities
/// demand-driven. Owner and collaborator visibility is always synchronized.
enum AuthenticatedReadSync { inferred, onDemand, graph }

enum SyncCommandValue { parameter, clockNow, clear }

enum ActionValueKind { literal, clockNow, clear }

/// The only delete behaviors supported consistently by Drift and PostgreSQL.
enum ReferenceDeleteAction { restrict, cascade, setNull }

final class RlsGrant {
  const RlsGrant(this.operation, this.principal);

  final RlsOperation operation;
  final RlsPrincipal principal;
}

final class CollaborationAccess {
  const CollaborationAccess({
    this.membershipTable,
    this.entityForeignKey,
    this.userForeignKey,
    this.activeField,
  }) : lifecycle = CollaborationLifecycle.direct,
       statusField = null,
       acceptedState = null,
       additionalReadableStates = const [],
       editPermissionField = null;

  /// Uses a normal synchronized entity as the collaboration membership.
  ///
  /// Its table, target reference, participant identity, status field, accepted
  /// state, unique pair key, access publication, and revocation behavior are
  /// inferred by convention and validated across the complete entity graph.
  const CollaborationAccess.workflow({
    this.membershipTable,
    this.entityForeignKey,
    this.userForeignKey,
    this.statusField,
    this.acceptedState,
    this.additionalReadableStates = const [],
    this.editPermissionField,
  }) : lifecycle = CollaborationLifecycle.workflow,
       activeField = null;

  final CollaborationLifecycle lifecycle;
  final String? membershipTable;
  final String? entityForeignKey;
  final String? userForeignKey;
  final String? activeField;
  final String? statusField;

  /// Enum value granting access when `accepted` is not the domain vocabulary.
  final Object? acceptedState;

  /// Workflow states that may read the target before or after full access.
  ///
  /// The accepted state is always readable and must not be repeated here.
  /// Additional states expose only the target row; collaborator mutations and
  /// reference-derived graph access still require [acceptedState].
  final List<Object> additionalReadableStates;

  /// Membership boolean column that separates editors from read-only members.
  ///
  /// When declared, every accepted member keeps read access to the target and
  /// its reference-derived graph, but only members whose column is true gain
  /// collaborator mutations, reference writes through the target, and
  /// relationship-derived update or delete access. When omitted, every
  /// accepted member is an editor.
  final String? editPermissionField;
}

final class Entity {
  const Entity({
    this.cardinality = Cardinality.unbounded,
    this.table,
    this.setAccessor,
    this.grants,
    this.authenticatedReadSync = AuthenticatedReadSync.inferred,
    this.ownership = Ownership.separate,
    this.collaboration,
    this.referenceAccessGuards = const [],
    this.exclusiveFieldGroups = const [],
    this.indexes = const [],
    this.orderScope,
    this.sync,
    this.syncTarget,
    this.coIdentityWith = const [],
    this.convergentCreates = false,
    this.identity,
  });

  final String? table;

  /// Overrides the inferred lower-camel table vocabulary on the entity graph.
  ///
  /// For example, `work_items` becomes `workItems`, while an overridden table
  /// `people` becomes `people`. Use this only when that resolved vocabulary
  /// collides with another generated entity-graph member.
  final String? setAccessor;

  /// Identity-owned entity types that deliberately share this entity's
  /// external authority UUID.
  ///
  /// Generation validates the target graph entity, ownership, and sync target
  /// before exposing nominal ID conversions in both directions.
  final List<Type> coIdentityWith;

  /// Replaces the complete inferred grant set for exceptional security rules.
  final List<RlsGrant>? grants;

  /// Whether this entity may be preloaded as a complete in-memory set.
  ///
  /// Unbounded is the safe default: it never promises that the complete
  /// readable dataset can be preloaded. Declare bounded only when the domain
  /// guarantees a small complete projection. Bounded entities preload and
  /// expose that complete observable set; unbounded entities retain identities
  /// only through query or lookup leases.
  final Cardinality cardinality;
  final AuthenticatedReadSync authenticatedReadSync;
  final Ownership ownership;

  /// Enables conventional collaborator policies. Omit for owner-only data.
  final CollaborationAccess? collaboration;

  /// Existing-row write operations that require both their normal grant and
  /// access through every [AccessReference] group on the entity.
  ///
  /// This models actor-owned child records such as a participant's session or
  /// completion: the authenticated owner may update or remove the child only
  /// while they can still read its referenced aggregate. Create access is
  /// already inferred and validated for every typed reference. Select remains
  /// an ordinary [RlsGrant] so graph publication and revocation stay explicit.
  final List<RlsOperation> referenceAccessGuards;

  /// Persisted nullable fields for which at most one may contain a value.
  ///
  /// This is explicit domain policy; generation validates the symbols and
  /// applies the same invariant in Dart, Drift, and PostgreSQL.
  final List<ExclusiveFieldGroup> exclusiveFieldGroups;

  /// Compound indexes whose names, columns, and storage declarations are
  /// generated from persisted Dart field symbols.
  final List<CompoundIndex> indexes;

  /// Overrides the inferred canonical [Ordered] scope with persisted fields.
  ///
  /// Omit when ownership or an ordered relationship source is unambiguous.
  /// Composite and otherwise ambiguous scopes name only the smallest immutable
  /// discriminator tuple. Separately owned entities infer and prepend their
  /// owner; repeating it is invalid because ownership is already known.
  final List<Symbol>? orderScope;

  /// Overrides synchronization authority when it cannot be inferred safely.
  final SyncMode? sync;

  /// Overrides the graph's typed sync target with one enum constant.
  ///
  /// Transport implementations never belong in entity declarations.
  final Object? syncTarget;

  /// Declares that every device creates this entity under the identity its
  /// unique key derives, so creates of one identity from several devices are
  /// one creation rather than a collision.
  ///
  /// A create meeting the row its identity already names, with the same
  /// owner and unique key, is accepted as that row: its own values yield to
  /// the server's, and the work queued after it applies on top. Use this only
  /// when the application derives the identity from the unique key, such as
  /// a UUIDv5 of an owner and a date; any other identity still conflicts.
  final bool convergentCreates;

  /// Derives that identity from the unique key, so the application and every
  /// schema-capable target compute the same one. Requires [convergentCreates].
  final DerivedIdentity? identity;
}

/// The identity every device and target gives a row with one unique key:
/// the UUIDv5 of [namespace] and the [key] fields' values joined by `/`.
///
/// A reference contributes its identity, a date its ISO form, and a
/// persisted variant its case name followed by its reference, such as
/// `task/<id>`. Generation exposes `<entity>IdFor(...)` taking the key in
/// order and the same derivation to every schema-capable target.
final class DerivedIdentity {
  const DerivedIdentity(this.namespace, this.key);

  final String namespace;
  final List<Symbol> key;
}

final class ExclusiveFieldGroup {
  const ExclusiveFieldGroup(this.fields, {this.allowNone = true});

  final List<Symbol> fields;

  /// Whether every field may be null. Set to false for an exactly-one rule.
  final bool allowNone;
}

/// Persists one sealed domain value as mutually exclusive native columns.
///
/// The annotated entity field must have a sealed class type. Each direct final
/// subtype is one variant and exposes its native scalar or `LocalId<E>`
/// components as public final fields initialized by its unnamed constructor.
/// Generation owns flattening, reconstruction, validation, schema checks,
/// drafts, patches, references, and synchronization. A discriminator is not
/// stored when the populated component columns identify the variant.
final class PersistedVariant {
  const PersistedVariant();
}

/// Declares a compound storage index that cannot be represented by [Indexed].
///
/// Indexes are physical query policy, so they remain explicit. Table names,
/// column names, owner fields, and backend metadata are inferred. Use
/// [IndexScope.owner] to prefix the conventional owner without repeating it.
///
/// An unconditional unique key belongs to live entities only: a deleted
/// entity's tombstone never holds it. A [condition] is the complete membership
/// predicate of a conditional unique index.
final class CompoundIndex {
  const CompoundIndex(
    this.fields, {
    this.unique = false,
    this.scope = IndexScope.field,
    this.condition,
    this.exactLookup = false,
  }) : keyset = false,
       unordered = false,
       unorderedWithOwnerField = null;

  /// Declares an index for a generated keyset query.
  ///
  /// [fields] contains only the business predicate and ordering fields. The
  /// generator appends the conventional entity identity used as the stable
  /// pagination tie-breaker.
  const CompoundIndex.query(this.fields, {this.scope = IndexScope.field})
    : unique = false,
      condition = null,
      exactLookup = false,
      keyset = true,
      unordered = false,
      unorderedWithOwnerField = null;

  /// Declares one unique, direction-independent pair of the inferred owner and
  /// another immutable identity field.
  ///
  /// This models reciprocal relationships such as friendships without storing
  /// a second canonical-order field or allowing `(A, B)` and `(B, A)` rows.
  const CompoundIndex.unorderedWithOwner(this.unorderedWithOwnerField)
    : fields = const <Symbol>[],
      unique = true,
      scope = IndexScope.owner,
      condition = null,
      exactLookup = true,
      keyset = false,
      unordered = true;

  final List<Symbol> fields;
  final bool unique;
  final IndexScope scope;
  final IndexCondition? condition;

  /// Declares a conditional or nullable key as an exact public lookup
  /// contract. Unconditional non-null unique keys are exact by default.
  final bool exactLookup;
  final bool keyset;
  final bool unordered;
  final Symbol? unorderedWithOwnerField;
}

/// Restricts an index to rows whose scalar field has one of the declared
/// values.
///
/// Conditions are physical storage policy and must be repeated by any query
/// intended to use the partial index. Values are compile-time checked against
/// the persisted field type and encoded by the generated field codec.
final class IndexCondition {
  const IndexCondition.oneOf(this.field, this.values);

  final Symbol field;
  final List<Object> values;
}

/// Excludes an instance field from convention-based entity persistence.
final class Transient {
  const Transient();
}

final class Persisted {
  const Persisted({
    this.column,
    this.defaultValue,
    this.conflict = ConflictStrategy.serverWins,
    this.authority = FieldAuthority.client,
    this.minLength,
    this.maxLength,
    this.allowWhitespace = false,
    this.minValue,
    this.maxValue,
    this.allowedValues = const [],
    this.reserved = const [],
    this.reservedUnless,
    this.reservedMessage = 'This value is reserved.',
    this.greaterThan,
    this.greaterThanOrEqual,
    this.requires,
    this.notEqualTo,
    this.sinceProtocolVersion = 1,
    this.renamedFrom,
    this.transitions = const [],
    this.updateBy = const [],
    this.editable,
    this.normalization = FieldNormalization.none,
    this.yieldingValues = const [],
  });

  final String? column;
  final Object? defaultValue;
  final ConflictStrategy conflict;
  final FieldAuthority authority;
  final int? minLength;
  final int? maxLength;

  /// Whether whitespace counts toward [minLength].
  ///
  /// Keep the default for ordinary human-readable text. Enable this only for
  /// whitespace-significant formats such as normalized editor operations.
  final bool allowWhitespace;
  final int? minValue;
  final int? maxValue;

  /// Closed set accepted by a persisted String field across every backend.
  final List<String> allowedValues;

  /// Values a persisted String field never takes, ignoring case and
  /// surrounding whitespace, while [reservedUnless] is unset; every backend
  /// refuses them with [reservedMessage].
  final List<String> reserved;

  /// A field that, while set, lets the row take a [reserved] value, such as
  /// the row the application provides under that name.
  final Symbol? reservedUnless;
  final String reservedMessage;

  /// Another persisted numeric field that this value must exceed.
  ///
  /// A symbol keeps the declaration tied to the Dart field name while the
  /// generator validates and maps it across every storage boundary.
  final Symbol? greaterThan;

  /// Another persisted numeric field that this value must equal or exceed.
  ///
  /// Generation applies the invariant to candidate Dart snapshots and to
  /// every generated storage schema.
  final Symbol? greaterThanOrEqual;

  /// Another nullable persisted field that must be present whenever this
  /// field is present.
  ///
  /// Use this for dependent optional values such as an upper bound that has no
  /// meaning without its lower bound. Generation applies the implication in
  /// Dart, Drift, and PostgreSQL.
  final Symbol? requires;

  /// Another persisted scalar field that this value must differ from.
  ///
  /// Nullable pairs are constrained only when both values are present. The
  /// generator applies the rule to candidate Dart snapshots and both storage
  /// schemas, so identity inequalities are never application-only checks.
  final Symbol? notEqualTo;

  /// First sync protocol version using this payload key.
  final int sinceProtocolVersion;

  /// Payload key used by the immediately preceding retained protocol.
  final String? renamedFrom;

  /// Overrides whether this field participates in the generated edit draft.
  ///
  /// Nodus normally infers ordinary editable fields from client-authoritative
  /// scalar fields on an update-capable entity. Use `false` for a creation-time
  /// fact that must remain immutable even though sibling fields can change.
  /// Infrastructure, lifecycle, transition, and relationship fields remain
  /// action-owned and cannot be made draft-editable with this override.
  final bool? editable;

  /// Canonicalization applied consistently to creates, drafts, queries,
  /// storage, synchronization, and remote materialization.
  final FieldNormalization normalization;

  /// Enum values a device sets only on the application's own initiative,
  /// which yield to any concurrent value from elsewhere whatever [conflict]
  /// says, while every other value follows [conflict].
  ///
  /// For example, a placement an automatic planner chose yields to one the
  /// user chose on another device, but not the other way round.
  final List<Object> yieldingValues;

  /// Allowed client-originated edges for a mutable persisted enum field.
  ///
  /// Creation and trusted remote hydration are not transitions. Repeating an
  /// unchanged value is always a no-op. Every actual local/server push change
  /// must match one declared edge when this list is non-empty.
  final List<AllowedTransition> transitions;

  /// Principals allowed to update this field.
  ///
  /// An empty list inherits every principal with an entity update grant. Use
  /// this only when participants or collaborators may update the entity but a
  /// particular field belongs to one role. Transition-specific [AllowedTransition.by]
  /// rules remain an additional restriction for enum workflow edges.
  final List<RlsPrincipal> updateBy;
}

/// One allowed client-originated state transition.
final class AllowedTransition {
  const AllowedTransition(
    this.from,
    this.to, {
    this.by = const [],
    this.relationshipBlockedBy = const [],
  });

  final Object from;
  final Object to;

  /// Principals allowed to originate this edge.
  ///
  /// An empty list inherits every principal with an update grant. Specify this
  /// only when workflow roles have different authority over the same field.
  final List<RlsPrincipal> by;

  /// Refuses this edge to principals who update the entity only through a
  /// relationship elsewhere in the graph while any of these referrers exists.
  ///
  /// The entity's own principals keep the edge. Relationship grants are
  /// revocable projections authorized remotely, so the generated server
  /// guard is the authority for this condition, as it is for the grant.
  /// The edge must leave [by] empty so that it inherits the relationship
  /// update grant it restricts.
  final List<ActiveReferrer> relationshipBlockedBy;
}

/// Rows of [entity] that reference the guarded row through [field] while
/// their conventional `status` is one of [activeStates].
///
/// Omit [activeStates] to match every live referrer. A soft-deletable
/// referrer only matches while it is not deleted.
final class ActiveReferrer {
  const ActiveReferrer(
    this.entity,
    this.field, {
    this.activeStates = const [],
    this.through,
    this.unless,
  });

  final Type entity;
  final Symbol field;
  final List<Object> activeStates;

  /// Reaches the guarded row through a bridge: [field] then references a row
  /// that [through] matches instead of the guarded row itself.
  final ActiveReferrer? through;

  /// Matches only while no row that this referrer describes exists.
  final ActiveReferrer? unless;
}

enum IndexScope {
  /// Index only the annotated field.
  field,

  /// Prefix the index with the conventionally generated owner field.
  owner,
}

final class Indexed {
  const Indexed({this.unique = false, this.scope = IndexScope.field});

  final bool unique;
  final IndexScope scope;
}

/// Declares that a persisted `LocalId<T>` field references entity `T`.
///
/// The target entity, target table, target identifier, and generated accessor
/// are derived from the nominal Dart type and the required `...Id` field-name
/// convention. Delete behavior is explicit because it is domain policy and
/// cannot be inferred safely.
final class Reference {
  const Reference({
    this.inverse,
    required this.onDelete,
    this.inverseCardinality,
    this.aggregateMember = false,
    this.hierarchy = false,
    this.inheritsAccess = false,
    this.inheritsCollaboration = false,
  });

  /// Domain name of the generated inverse query on the target entity.
  final String? inverse;
  final ReferenceDeleteAction onDelete;

  /// Cardinality of this reference's inverse collection for one target.
  ///
  /// This is distinct from the source entity's global [Entity.cardinality]. A
  /// child table can be unbounded for an account while every parent owns one
  /// small, complete collection. Omit this to inherit the source entity's
  /// cardinality. Declare [Cardinality.bounded] only when loading every active
  /// child for one target is a domain-safe, complete operation.
  final Cardinality? inverseCardinality;

  /// Whether the referenced target owns this child in its aggregate draft.
  ///
  /// Aggregate members require a bounded inverse collection, a non-null
  /// reference, cascade deletion, and generated create/update/delete behavior.
  /// This declaration owns editing durability; it does not change independent
  /// entity identity, synchronization, or reference authorization.
  final bool aggregateMember;

  /// Whether this nullable self-reference is the parent edge of a hierarchy.
  ///
  /// Nodus generates paged subtree remove/restore operations and, for
  /// [Archivable] entities, archive/unarchive operations. A hierarchy must
  /// target its declaring entity and use cascade deletion so descendants
  /// cannot outlive their parent lifecycle.
  final bool hierarchy;

  /// Whether a [hierarchy] child shares the access relationships elsewhere in
  /// the graph grant on its ancestors.
  ///
  /// A goal that links a task then also shares its subtasks, at any depth,
  /// and moving a subtree under another parent moves its access with it. A
  /// descendant whose owner leaves follows the owner of its parent. Owner and
  /// collaborator access stay with each row unless [inheritsCollaboration].
  final bool inheritsAccess;

  /// Whether a [hierarchy] child counts the accepted collaborators of its
  /// ancestors as its own, with the edit permission they hold there.
  ///
  /// Members of a shared goal then work on its subgoals at any depth, and on
  /// everything those subgoals share. Only accepted membership is inherited:
  /// a pending invitation reveals its own row only. When a row has direct and
  /// inherited membership, the most permissive applies. Moving a subtree
  /// moves its collaborators with it, and a retiring owner's tree passes with
  /// its root. Requires workflow [CollaborationAccess] on the entity.
  final bool inheritsCollaboration;
}

/// Selects one entity and the persisted fields that can trigger declared work.
///
/// An empty [fields] list observes every projection change. Field symbols are
/// validated against the source entity and let generation avoid scheduling a
/// process or projection for irrelevant patches.
final class WorkSource {
  const WorkSource(this.entity, {this.fields = const []});

  final Type entity;
  final List<Symbol> fields;
}

/// Declares one durable, entity-triggered process owned by domain outcomes.
///
/// Generation exposes a domain-named installer on the entity graph. Nodus owns
/// trigger coalescing, durable intent, operation identity, leasing, restart
/// recovery, and retry/backoff; application code supplies only the domain
/// handler that applies the outcome through generated entity APIs.
final class EntityProcess {
  const EntityProcess({
    required this.name,
    required this.source,
    this.wakeOn = const [],
  });

  final String name;

  /// The entity whose rows the handler revisits, and whose changes wake it.
  final WorkSource source;

  /// Other entities whose changes also wake the process, so a reconciliation
  /// over a small [source] (such as completed goals) reacts to a large one
  /// (such as tasks) without revisiting every row of it.
  final List<WorkSource> wakeOn;
}

/// Declares a derived, non-authoritative destination projection.
///
/// The named generated lane receives source-change notifications and rebuilds
/// deterministically through the supplied mapper/adapter. Projection failure
/// never rolls back authoritative entity state.
final class SecondaryProjection {
  const SecondaryProjection({required this.name, required this.sources});

  final String name;
  final List<WorkSource> sources;
}

/// Declares that this entity owns one independently persisted [Component].
///
/// The nominal target type and generated accessors are inferred exactly as for
/// [Reference]. Composition additionally derives a non-null immutable
/// restrictive foreign key, a unique target assignment, relationship-derived
/// target authorization, and graph dependency metadata. The component must be
/// created inside the same generated graph transaction as its aggregate root.
/// Delete behavior is not configurable: a component cannot be deleted while
/// its aggregate still references it.
final class Composition {
  const Composition({this.inverse});

  /// Domain name of the generated inverse query on the component.
  final String? inverse;
}

/// Marks a persisted `LocalId<Owner>` as an authenticated participant identity.
///
/// Participant access is opt-in through [RlsPrincipal.participant] grants. More
/// than one field may be marked; a matching authenticated identity in any field
/// satisfies the grant. Participant identities are immutable because changing
/// an access audience requires an explicit relationship lifecycle rather than a
/// field patch that could strand stale synchronized state.
final class AccessParticipant {
  const AccessParticipant();
}

/// Inherits row authorization through a typed entity reference.
///
/// Every marked reference must be readable by the authenticated actor, so
/// multiple access references are AND-composed. Nullable alternatives are
/// inferred only when every member belongs to the same exactly-one
/// [ExclusiveFieldGroup]; those alternatives are OR-composed without repeating
/// the relationship group in authorization configuration.
final class AccessReference {
  const AccessReference();
}

/// Propagates authorization from a relationship entity to this referenced
/// target.
///
/// The relationship must also contain at least one [AccessReference]. Those
/// source references remain AND-composed and form the access audience. The
/// generated graph grants that audience access to the referenced target while
/// this relationship is active, publishes snapshots and revocations when the
/// relationship or source collaboration changes, and prevents insertion from
/// being used to gain access to an unrelated target.
///
/// By default the path mirrors the target's owner operations except insert,
/// which is never meaningful for an existing referenced row. [operations] is
/// only needed to narrow that inferred capability.
final class AccessTarget {
  const AccessTarget({
    this.operations,
    this.activeStates = const [],
    this.targetField,
  });

  final List<RlsOperation>? operations;

  /// Conventional `status` values for which this relationship grants access.
  ///
  /// Omit when the relationship is always active or uses the conventional
  /// boolean `active` field. Enum constants are validated against the entity's
  /// persisted `status` field and encoded once for generated SQL.
  final List<Object> activeStates;

  /// Optional immutable entity reference on the referenced bridge whose target
  /// receives the declared access.
  ///
  /// The bridge itself is made selectable so synchronized clients can resolve
  /// the path. For example, an assignment can reference a `TaskMember` once
  /// while granting its reviewer read access to both that membership and the
  /// membership's `taskId`, without persisting a duplicate task identity.
  final Symbol? targetField;
}

/// Lets principals who may update the referenced entity through a
/// relationship elsewhere in the graph act for this row's owner.
///
/// They read the row and write the rows that inherit access from it through
/// [AccessReference], as its owner does. They gain no write on the row itself
/// and do not join the audience of its own [AccessTarget] paths. For example,
/// an editor of a shared goal reads the reviewer assignment of a task linked
/// into the goal and asks that reviewer for a check, while the task's own
/// readers through the assignment remain its reviewer alone.
final class RelationshipEditorAccess {
  const RelationshipEditorAccess({this.targetField, this.includeOwner = false});

  /// Immutable reference on the referenced bridge whose target's relationship
  /// editors act for the row, as in [AccessTarget.targetField].
  final Symbol? targetField;

  /// Whether that entity's owner acts for the row as well, for a row owned
  /// by someone else, such as a check an assignee asked for on the owner's
  /// task.
  final bool includeOwner;
}

/// Derives the synchronized row owner from one typed entity reference.
///
/// This is independent from [AccessReference]: an invitation may inherit its
/// owner from a target while remaining visible through participant grants.
final class OwnerReference {
  const OwnerReference({this.targetField, this.writeThrough = true});

  /// Optional identity field on the referenced entity from which ownership is
  /// derived. Omitting it uses the referenced entity's conventional owner.
  ///
  /// This is useful for relationship targets whose participant, rather than
  /// relationship owner, owns the child record. The referenced field must be
  /// immutable, non-null, and have the same nominal owner type.
  final Symbol? targetField;

  /// Whether principals who may edit the referenced entity may also create
  /// this row for its owner through an `RlsPrincipal.reference` insert grant.
  ///
  /// Set it to false when only the derived owner may decide the row, for
  /// example who checks the owner's work: an editor of the owner's goal must
  /// not appoint themselves as its checker.
  final bool writeThrough;
}

/// Declares one atomic, generated domain mutation.
///
/// Required method parameters are mapped to persisted fields with the same
/// name. Constant, clock-derived, and null assignments cover lifecycle actions
/// whose values do not come from callers. Every target field must be declared
/// `abstract final`, making the generated action its only public mutation path.
/// Name the action for its domain meaning; the generic name `edit` is reserved
/// for ordinary generated draft behavior.
final class Action {
  const Action({
    this.values = const [],
    this.derive = const {},
    this.requires = const [],
    this.recorded,
    this.routeToCheck,
    this.bulk = false,
    this.rebase,
  });

  final List<ActionValue> values;

  /// Linked work that must be finished first; the generated
  /// `require<Action>` checks it, and so does the action's agent tool.
  final List<RequireLinked> requires;

  /// Records each run as a row of another entity, such as who reopened a
  /// task and why; the generated `<action>WithRecord` and the agent tool do.
  final Recorded? recorded;

  /// When a status edge this action takes waits for an accepted checker
  /// (`relationshipBlockedBy`), the agent tool asks that checker instead of
  /// refusing: it runs [RouteToCheck.action] and adds a request row.
  final RouteToCheck? routeToCheck;

  /// Fields the action sets from its parameters, so every caller derives
  /// them alike: a [CopyOf] or [Banded] of a parameter, or [ClockNow]. The
  /// generated method and agent tool compute them; the method does not take
  /// them.
  final Map<Symbol, StartingValue> derive;

  /// Moves this action's values onto a new base when the state it was made
  /// on changes under it before the server applies it: a convergent create
  /// meeting another device's row, or a concurrent remote change.
  ///
  /// A pure static method of the entity, or a top-level function of its
  /// library, taking the action's values at the state it was made on, at
  /// the state it now lands on, and as queued, each as one record named
  /// like the action's parameters, and returning the values to send instead.
  /// For example, a shift of an energy score by finished work moves the
  /// score it lands on by the same amount instead of overwriting it.
  /// Only an action that assigns nothing but its parameters may declare it.
  final Function? rebase;

  /// Generates the same semantic action on a typed entity selection.
  ///
  /// The resulting `<Entity>List.<action>All(...)` processes canonical pages
  /// through graph transactions. Opt in only when applying one value/parameter
  /// set independently to every selected entity is the complete domain intent.
  final bool bulk;
}

/// One non-parameter assignment performed by an [Action].
final class ActionValue {
  const ActionValue(this.field, this.value) : kind = ActionValueKind.literal;

  const ActionValue.clockNow(this.field)
    : value = null,
      kind = ActionValueKind.clockNow;

  const ActionValue.clear(this.field)
    : value = null,
      kind = ActionValueKind.clear;

  final Symbol field;
  final Object? value;
  final ActionValueKind kind;
}

/// Declares an exceptional field-backed delete/tombstone command.
///
/// The delete operation is inferred. Ordinary field updates are typed state
/// patches; collaboration uses its generated typed command contract. The
/// annotated method is a non-generic `Future<void>` method, and its target is
/// read-only because the generated command owns that field's only public
/// transition. Awaiting it proves local entity and sync-intent durability.
final class SyncCommand {
  const SyncCommand({
    required this.targetField,
    this.value = SyncCommandValue.parameter,
  });

  final String targetField;
  final SyncCommandValue value;
}

/// Exposes an entity to AI agents through the generated agent tool surface.
///
/// The entity's rows become readable through generated list and get tools,
/// under the same row-level security as the account that signed the agent in.
/// [create] and [edit] add tools for the generated create payload and the
/// ordinary edit draft. Declared actions join only when annotated with
/// [AgentTool]. A token issued to an agent can touch nothing else.
///
/// Expose an intent only once every rule it implies runs on the server: the
/// agent sends that intent alone, so a rule kept in client code would be
/// skipped.
final class AgentAccess {
  const AgentAccess({
    this.create = false,
    this.edit = false,
    this.link = false,
    this.remove = false,
    this.archive = false,
    this.hide = const [],
    this.locked = const [],
    this.linkTool,
    this.unlinkTool,
    this.liftChildren = false,
    this.reorder = false,
  });

  final bool create;
  final bool edit;

  /// Adds `link_<target>_to_<owner>` and `unlink_<target>_from_<owner>`
  /// tools to an activatable relationship: linking activates the pair's row
  /// or creates it last in the owner's order, and unlinking deactivates it.
  final bool link;

  /// Adds `delete_<entity>` and `restore_<entity>` tools to a soft-deletable
  /// entity. A hierarchy is removed with its descendants and restored with
  /// those removed with it.
  final bool remove;

  /// Adds `archive_<entity>` and `unarchive_<entity>` tools to an archivable
  /// entity. A hierarchy is archived with the descendants the caller owns
  /// and unarchived with those archived with it.
  final bool archive;

  /// Fields agents may read but never set, such as one only the
  /// application manages.
  final List<Symbol> hide;

  /// Fields that, while set (non-null, or true), lock a row against agents:
  /// they may read it but not edit, remove, archive, or act on it, such as a
  /// row the application provides.
  final List<Symbol> locked;

  /// Names the [link] tools instead of `link_<target>_to_<owner>` and
  /// `unlink_<target>_from_<owner>`, for a relationship whose ends read
  /// alike.
  final String? linkTool;
  final String? unlinkTool;

  /// Deleting a row of a hierarchy moves its children up to its parent
  /// instead of deleting them with it.
  final bool liftChildren;

  /// Adds a `move_<entity>` tool to an ordered entity, placing a row first,
  /// last, or next to another row of its list.
  final bool reorder;
}

/// Exposes a declared [Action] of an [AgentAccess] entity as an agent tool.
///
/// The action's documentation comment becomes the tool description.
final class AgentTool {
  const AgentTool({this.name, this.refusals = const []});

  /// The tool's name instead of `<action>_<entity>`.
  final String? name;

  /// Boolean fields of the row that refuse the tool, for an action only the
  /// application completes, such as one sent to a checker.
  final List<Refusal> refusals;
}

/// Sends an [Action] whose edge waits for an accepted checker to that
/// checker: the agent tool runs [action], with the same parameters, and
/// creates a [request] row referencing the checker's row, unless one is
/// still at its starting state.
final class RouteToCheck {
  const RouteToCheck(this.action, {required this.request});

  final Symbol action;
  final Type request;
}

/// The row an [Action] records each run as: an [entity] row referencing
/// the acting row through [subject], naming who acted through [by], and
/// keeping the caller's [comment]. The action runs only while the row's
/// fields hold one of the [from] values, and is refused otherwise with
/// [fromMessage].
final class Recorded {
  const Recorded(
    this.entity, {
    required this.subject,
    required this.by,
    this.comment,
    this.from = const {},
    this.fromMessage = 'This action does not apply now.',
  });

  final Type entity;
  final Symbol subject;
  final Symbol by;
  final Symbol? comment;
  final Map<Symbol, List<Object>> from;
  final String fromMessage;
}

/// Refuses an [Action] while a row linked to this one through the [link]
/// entity is still open. A linked row counts only while its fields hold
/// one of the [counting] values, and is done when they hold one of the
/// [done] values, or, with [checkedIn], once it owes no check-in today
/// under its entity's [CheckIns]. Archived and deleted rows do not count.
final class RequireLinked {
  const RequireLinked(
    this.link, {
    required this.label,
    this.done = const {},
    this.counting = const {},
    this.checkedIn = false,
  });

  final Type link;

  /// What the linked rows are called in the refusal, in the plural.
  final String label;
  final Map<Symbol, List<Object>> done;
  final Map<Symbol, List<Object>> counting;
  final bool checkedIn;
}

/// Declares that the ordered rows of this entity form a document's plain text.
///
/// [document] names the reference to the composed document and [text] the
/// text field. Agents read the document as the rows' text joined in order and
/// write it as one row holding the whole text followed by [terminator], so an
/// [AgentAccess] entity composing that document takes and returns its content
/// as a string.
final class AgentText {
  const AgentText({
    required this.document,
    required this.text,
    this.terminator = '',
  });

  final Symbol document;
  final Symbol text;

  /// Appended to written text when the document format ends every row with
  /// a delimiter, such as a newline.
  final String terminator;
}

/// Declares multi-step changes to the members of an aggregate collection,
/// written once and generated into a method on the aggregate root and into
/// every schema-capable target, so the application and an agent apply the
/// same rule.
///
/// [collection] names the inverse collection of the member's aggregate
/// reference, such as `#items`. The member has a [DerivedIdentity] whose key
/// is the aggregate reference followed by one field; that field is the
/// operation's first parameter and names the member, live or removed.
final class MemberOperations {
  const MemberOperations(this.collection, this.operations, {this.root});

  final Symbol collection;
  final List<MemberOperation> operations;

  /// How an agent finds the root: the owner's one for today, made when
  /// missing. Required for operations exposed to agents.
  final DayRoot? root;
}

/// A root keyed by its owner and a date, which agents reach for the owner's
/// current day and which an operation makes when the day has none yet.
///
/// The root needs a [DerivedIdentity] on its owner and [date]. [timezone]
/// names the owner's IANA timezone field, which decides the current day.
/// [initial] gives each required field without a default its starting
/// value; the application reads the same values through the generated
/// `<root>StartingValues`.
final class DayRoot {
  const DayRoot({
    required this.date,
    required this.timezone,
    this.initial = const {},
  });

  final Symbol date;
  final Symbol timezone;
  final Map<Symbol, StartingValue> initial;
}

/// The starting value of a [DayRoot] field.
sealed class StartingValue {
  const StartingValue();
}

/// The rounded mean of [field] over the owner's roots on the same weekday
/// in the [days] before the date that have [present] set, when at least
/// [minimum] do; otherwise [fallback]. The result is kept within the
/// field's declared bounds.
final class WeekdayAverage extends StartingValue {
  const WeekdayAverage(
    this.field, {
    required this.present,
    required this.days,
    required this.minimum,
    required this.fallback,
  });

  final Symbol field;
  final Symbol present;
  final int days;
  final int minimum;
  final int fallback;
}

/// The current time of the writer's clock.
final class ClockNow extends StartingValue {
  const ClockNow();
}

/// The starting value of another [field] declared before it.
final class CopyOf extends StartingValue {
  const CopyOf(this.field);

  final Symbol field;
}

/// The value of [values] whose band the starting [field] falls in: below
/// `bounds[0]` gives `values[0]`, and so on, with the last value from the
/// last bound up.
final class Banded extends StartingValue {
  const Banded(this.field, {required this.bounds, required this.values});

  final Symbol field;
  final List<int> bounds;
  final List<Object> values;
}

/// One declared change to an aggregate member, named for its domain intent.
///
/// The steps run in order inside one transaction. [description] documents
/// the generated method and, when [agentTool] exposes it, the agent tool.
final class MemberOperation {
  const MemberOperation(
    this.name, {
    required this.description,
    required this.steps,
    this.parameters = const [],
    this.agentTool,
  });

  final Symbol name;
  final String description;
  final List<OperationParameter> parameters;
  final List<MemberStep> steps;

  /// Exposes the operation to agents under this tool name; the root needs a
  /// [DayRoot] and the member [AgentAccess].
  final String? agentTool;
}

/// An optional named parameter of a [MemberOperation].
final class OperationParameter {
  /// A value of the member field [field], such as a part of the day.
  const OperationParameter(
    this.name, {
    required Symbol this.field,
    required this.description,
  }) : member = false;

  /// Another member of the same aggregate, named by its key.
  const OperationParameter.member(this.name, {required this.description})
    : field = null,
      member = true;

  final Symbol name;
  final Symbol? field;
  final bool member;

  /// Documents the parameter in the generated method and agent tool.
  final String description;
}

/// One step of a [MemberOperation].
sealed class MemberStep {
  const MemberStep();
}

/// Refuses the operation with [message] unless [condition] holds.
final class Require extends MemberStep {
  const Require(this.condition, this.message);

  final OperationCondition condition;
  final String message;
}

/// Runs [then] when [condition] holds, otherwise [otherwise].
final class When extends MemberStep {
  const When(this.condition, this.then, {this.otherwise = const []});

  final OperationCondition condition;
  final List<MemberStep> then;
  final List<MemberStep> otherwise;
}

/// Ends the operation.
final class Stop extends MemberStep {
  const Stop();
}

/// Makes the member live: a live one stays, a removed one is restored, reset
/// through [reset] and appended, and an absent one is created under its
/// derived identity at the end of the order. [values] fill the created or
/// reset fields; every other field keeps its declared default.
final class EnsureMember extends MemberStep {
  const EnsureMember({this.values = const {}, this.reset});

  final Map<Symbol, OperationValue> values;

  /// A declared action of the member whose parameters are all fields.
  final Symbol? reset;
}

/// Runs the member's declared [action] with [arguments]; other parameters
/// take the member field's declared default.
final class Act extends MemberStep {
  const Act(this.action, {this.arguments = const {}});

  final Symbol action;
  final Map<Symbol, OperationValue> arguments;
}

/// Moves the member within its aggregate's order.
final class Place extends MemberStep {
  /// After the last live member matching [group], or first when none does.
  const Place.afterLast(OperationCondition this.group)
    : after = null,
      before = null;

  /// Next to the member named by parameter [after], else by [before], when
  /// that member is live and on the member's side of [group]. A member
  /// outside [group] asked to follow one inside it goes after the last
  /// member of [group].
  const Place.nextTo({
    required this.after,
    required this.before,
    required OperationCondition this.group,
  });

  final OperationCondition? group;
  final Symbol? after;
  final Symbol? before;
}

/// A condition on the member, which is false for any field of an absent one.
sealed class OperationCondition {
  const OperationCondition();
}

/// Holds while the member is live.
final class MemberLive extends OperationCondition {
  const MemberLive();
}

/// Compares a member field or parameter.
final class Compare extends OperationCondition {
  /// The member field is one of [values].
  const Compare.isIn(this.subject, this.values)
    : kind = CompareKind.isIn,
      other = null;

  const Compare.isNull(this.subject)
    : kind = CompareKind.isNull,
      values = const [],
      other = null;

  const Compare.isTrue(this.subject)
    : kind = CompareKind.isTrue,
      values = const [],
      other = null;

  /// Both are present and different.
  const Compare.differs(this.subject, OperationValue this.other)
    : kind = CompareKind.differs,
      values = const [];

  final OperationValue subject;
  final CompareKind kind;
  final List<Object> values;
  final OperationValue? other;
}

enum CompareKind { isIn, isNull, isTrue, differs }

final class Not extends OperationCondition {
  const Not(this.condition);

  final OperationCondition condition;
}

final class All extends OperationCondition {
  const All(this.conditions);

  final List<OperationCondition> conditions;
}

/// A value an operation reads.
sealed class OperationValue {
  const OperationValue();
}

/// A field of the member.
final class MemberField extends OperationValue {
  const MemberField(this.field);

  final Symbol field;
}

/// An operation parameter.
final class Parameter extends OperationValue {
  const Parameter(this.name);

  final Symbol name;
}

/// A field of the entity a reference inside the member's key names, such as
/// the habit a planned source points at. Null when the key names another
/// case or the row is not readable.
final class KeyTarget extends OperationValue {
  const KeyTarget(this.reference, this.field);

  final Symbol reference;
  final Symbol field;
}

/// Names the bits of a `PersistedScalarValue<int>` set, so tools outside
/// Dart, such as agent tools, read and write it as a list of these names:
/// the name at index `i` is bit `1 << i`.
final class ScalarFlags {
  const ScalarFlags(this.names);

  final List<String> names;
}

/// The parts of a day an enum names, so declarations find the part a moment
/// falls in: the part with the latest start hour at or before the moment's
/// local hour. [wholeDay] names the part that stands for the whole day.
///
/// Generates `<enum>At(DateTime moment)` for the application, and the same
/// rule in every schema-capable target.
final class DayParts {
  const DayParts(this.starts, {required this.wholeDay});

  /// Each part with the hour it starts at; one starts at 0.
  final Map<Object, int> starts;
  final Object wholeDay;
}

/// Declares how the log entity it annotates records check-ins of a
/// scheduled subject, such as a habit: the rules are written once and
/// generated into `beginCheckIn` and `undoCheckIn` on the subject and into
/// every schema-capable target, so the application and an agent apply the
/// same rules.
///
/// A check-in belongs to the owner's local day and to a part of that day,
/// named by an enum with [DayParts]. It is refused when a [refusals] field
/// of the subject is set, when [scheduledParts] covers neither the part nor
/// the whole day, and when the part is not the current one unless the whole
/// day is scheduled. A subject scheduled for the whole day is checked in for
/// the whole day.
///
/// Without an active [intervals] case a check-in is one per owner, day, and
/// part: checking in again updates it, and checking in after an undo brings
/// it back. With one, each check-in is a new row and is refused until the
/// interval since the owner's latest has passed.
///
/// `beginLogDay` records a past day: one the subject existed on ([since])
/// and is scheduled on ([days]), for the part given or else every part it
/// is scheduled for, skipping parts already logged that day.
final class CheckIns {
  const CheckIns({
    required this.subject,
    required this.date,
    required this.part,
    required this.at,
    required this.timezone,
    required this.scheduledParts,
    required this.undoneAs,
    this.intervals = const [],
    this.refusals = const [],
    this.agentRefusals = const [],
    this.details = const [],
    this.days,
    this.since,
    this.unscheduled = const [],
    this.loggedAtHour = 12,
    this.checkInTool,
    this.undoTool,
    this.logTool,
  });

  /// The reference to the scheduled subject.
  final Symbol subject;

  /// The local day of the check-in.
  final Symbol date;

  /// The part of the day, an enum with [DayParts].
  final Symbol part;

  /// When the check-in happened.
  final Symbol at;

  /// The owner's IANA timezone field, which decides an agent's local day.
  final Symbol timezone;

  /// The subject field listing the parts it is scheduled for: an `Iterable`
  /// of the part enum whose [ScalarFlags] names match the enum's values.
  final Symbol scheduledParts;

  /// Subject variant cases that make check-ins events spaced by an interval.
  final List<Every> intervals;

  /// Subject booleans that refuse a check-in.
  final List<Refusal> refusals;

  /// Subject booleans that refuse an agent's check-in, for work only the
  /// application completes, such as sending it to a checker.
  final List<Refusal> agentRefusals;

  /// Log fields a check-in may set; each takes its declared default unless
  /// given.
  final List<Symbol> details;

  /// Records each undone check-in.
  final UndoneAs undoneAs;

  /// Exposes checking in to agents under this tool name.
  final String? checkInTool;

  /// Exposes undoing a check-in to agents under this tool name.
  final String? undoTool;

  /// A subject variant field of [ScalarFlags] naming the weekdays, sunday
  /// first, that limits which past days can be logged while it is set.
  final Symbol? days;

  /// The subject's time field before whose local day nothing is logged.
  final Symbol? since;

  /// Subject variant case fields that, while their case is active, leave
  /// the subject with no scheduled days: it owes no check-in on any day.
  /// An [intervals] case owes none either; `owesCheckInOn` is true only for
  /// a scheduled day the owner has not fully checked in.
  final List<Symbol> unscheduled;

  /// The local hour a logged past day records when no time is given.
  final int loggedAtHour;

  /// Exposes logging a past day to agents under this tool name.
  final String? logTool;
}

/// A subject variant case whose check-ins are spaced by its [field].
final class Every {
  /// [field] hours after the latest check-in.
  const Every.hours(this.field) : days = false;

  /// [field] local days after the day of the latest check-in.
  const Every.days(this.field) : days = true;

  final Symbol field;
  final bool days;
}

/// Refuses a check-in with [message] while the subject's [field] is true.
final class Refusal {
  const Refusal(this.field, this.message);

  final Symbol field;
  final String message;
}

/// The entity recording undone check-ins, created for each with the subject,
/// date, and part fields of the same names, and [comment] when given.
final class UndoneAs {
  const UndoneAs(this.entity, {required this.comment});

  final Type entity;
  final Symbol comment;
}

/// Declares that the active links of the [Activatable] entity it annotates,
/// each from one row to another of the same entity, never form a cycle: no
/// row reaches itself by following links from [from] to [to]. With
/// [hierarchy], a link also never joins a row to one of its ancestors or
/// descendants in that entity's hierarchy.
///
/// Every schema-capable target enforces it on every write, and the
/// application checks it first through the generated `require<Entity>`.
final class Acyclic {
  const Acyclic({
    required this.from,
    required this.to,
    required this.cycle,
    this.hierarchy,
  });

  final Symbol from;
  final Symbol to;

  /// The message refusing a link that would close a cycle.
  final String cycle;

  /// The message refusing a link along the hierarchy; enforces that rule
  /// when set.
  final String? hierarchy;
}

/// Declares that each row of the entity it annotates answers the question
/// row its [question] reference names: the answer's variant case is the
/// field [cases] maps the question's [kind] to, a [number] keeps within the
/// question's [min] and [max], and a chosen [option] belongs to the question
/// through the option's [optionQuestion] reference.
///
/// Every schema-capable target enforces it on each write of an answer; the
/// application checks it first through the generated `require<Entity>`.
/// When the rows belong to a [CheckIns] log, its agent tools take answers
/// keyed by question id.
final class Answers {
  const Answers({
    required this.question,
    required this.kind,
    required this.cases,
    required this.label,
    this.number,
    this.min,
    this.max,
    this.option,
    this.optionQuestion,
  });

  final Symbol question;
  final Symbol kind;
  final Map<Object, Symbol> cases;

  /// The question field naming it in refusals.
  final Symbol label;
  final Symbol? number;
  final Symbol? min;
  final Symbol? max;
  final Symbol? option;
  final Symbol? optionQuestion;
}
