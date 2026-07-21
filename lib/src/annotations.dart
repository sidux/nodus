library;

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
       additionalReadableStates = const [];

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
final class CompoundIndex {
  const CompoundIndex(
    this.fields, {
    this.unique = false,
    this.scope = IndexScope.field,
    this.condition,
    this.activeOnly = false,
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
      activeOnly = false,
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
      activeOnly = true,
      exactLookup = true,
      keyset = false,
      unordered = true;

  final List<Symbol> fields;
  final bool unique;
  final IndexScope scope;
  final IndexCondition? condition;

  /// Restricts this unique index to entities that have not been soft deleted.
  final bool activeOnly;

  /// Declares a conditional, active-only, or nullable key as an exact public
  /// lookup contract. Unconditional non-null unique keys are exact by default.
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
  const AllowedTransition(this.from, this.to, {this.by = const []});

  final Object from;
  final Object to;

  /// Principals allowed to originate this edge.
  ///
  /// An empty list inherits every principal with an update grant. Specify this
  /// only when workflow roles have different authority over the same field.
  final List<RlsPrincipal> by;
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

/// Derives the synchronized row owner from one typed entity reference.
///
/// This is independent from [AccessReference]: an invitation may inherit its
/// owner from a target while remaining visible through participant grants.
final class OwnerReference {
  const OwnerReference({this.targetField});

  /// Optional identity field on the referenced entity from which ownership is
  /// derived. Omitting it uses the referenced entity's conventional owner.
  ///
  /// This is useful for relationship targets whose participant, rather than
  /// relationship owner, owns the child record. The referenced field must be
  /// immutable, non-null, and have the same nominal owner type.
  final Symbol? targetField;
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
  const Action({this.values = const []});

  final List<ActionValue> values;
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
