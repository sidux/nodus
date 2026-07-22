# Entity-First Local-First Architecture

## 1. Scope and authority

This document defines the reusable architecture contract. It is intentionally
application-independent: it MUST NOT contain product feature names, application
file inventories, rollout status, schema-version history, data-cleanup stories,
or one-off business workflows. Those belong in a separate implementation
migration inventory.

`MUST`, `MUST NOT`, `SHOULD`, and `MAY` are normative. Current code does not
weaken these rules. A current violation is migration debt, not a competing
pattern.

Conformance is evaluated from responsibilities and observable behavior, not
from names, source spelling, generated formatting, or the continued existence
of an old file. Supporting documentation, tests, examples, and migration
inventories cannot create an exception to this document. Tests MUST protect a
current architectural invariant through public types, runtime behavior,
generated metadata, or an executed schema; they MUST NOT turn prose wording,
implementation text, or completed migration history into a second contract.

The companion [PlantUML architecture atlas](Architecture.puml) presents this
contract in four self-contained views: declaration and generation, runtime data
flow, synchronization and ordering semantics, and dependency/conformance
boundaries. The prose in this document remains normative when a visual label
must be abbreviated.

The target experience is:

```dart
final document = await entityGraph.documents.create(
  title: 'Intent declared once',
);

final edit = document.beginEdit()..title = 'One typed change surface';
await edit.save();
await document.setCollaborator(collaboratorId, active: true);

final owned = DocumentList.owned(entityGraph);
```

The receiver communicates domain ownership. Existing-entity behavior is called
on the entity instance, selections are constructed through the generated typed
`<Entity>List` or `<Entity>Lookup`, and creation is entered through the
generated set owned by the compatible entity graph. A feature-facing
`DocumentCommands`, `DocumentQueries`, or similar forwarding object is not a
domain boundary and MUST NOT exist. The word *command* is reserved for an
internal durable operation envelope used by persistence and synchronization;
that internal representation MUST NOT determine the public API shape.

From one entity graph, plus filesystem page contracts for navigation, build-time
generation derives persistence, local state, synchronization, serialization,
relationships, query APIs, security metadata, typed routes, and repetitive UI
integration. Handwritten code expresses business meaning, not mechanics.

The handwritten abstract `<Entity>` is the public domain type. Generation emits
its private or package-internal concrete record and a generated `<Entity>Set`.
Entity discovery applies to every `domain/` subtree, including reusable shared
domains; it MUST NOT assume that all entities belong to an application feature.
The canonical creation API is
`await entityGraph.<entities>.create(...)`. This keeps graph compatibility
compile-time checked, preserves handwritten computed properties and business
methods on the real domain type, and requires no duplicated forwarding factory
or schema-to-runtime type translation.

Conceptually creation belongs to the entity type, so
`<Entity>.create(entityGraph, ...)` is the preferred spelling once Dart can
generate that static member without duplication. Ordinary `build_runner`
output cannot inject a static member into an already declared Dart class.
Until a stable augmentation mechanism exists, the canonical executable spelling
is `entityGraph.<entities>.create(...)`; a handwritten forwarding factory,
second entity declaration, generated public replacement type, type alias, or
duplicated parameter list is worse than the mechanical set receiver and is
forbidden. A hidden global entity graph, ambient zone, service locator, or
concrete synchronization adapter is also forbidden.

The explicit `entityGraph` receiver identifies the authenticated account's
local database, identity map, transaction coordinator, clock, ID source, and
synchronization-target registry.

## 2. Artifact decision rules

Every artifact is decided by the first matching row:

| Intent | Required form | Handwritten alternative |
| --- | --- | --- |
| Declare an entity | one abstract domain type annotated with `@Entity(...)` | `@LocalEntity`, duplicate DTO/record declarations, and compatibility aliases forbidden |
| Declare the runtime graph | package-wide discovery from `@Entity` plus tool-owned `nodus.lock` | handwritten graph roots, entity registries, and service-locator graphs forbidden |
| Declare persisted state | entity field, type, default, constraint, capability, or relationship | forbidden duplicate schema/configuration |
| Add a standard optional feature | concise recognized capability such as `Ordered`, `Archivable`, `SoftDeletable`, or `Collaborative<Principal>` | repeated fields, mechanics, capability-specific opt-in annotations, and `...Entity` capability names forbidden |
| Create one entity | generated `await entityGraph.<entities>.create(...)` through `<Entity>Set.create(...)` | CRUD command, repository, service, provider, or handwritten factory forbidden |
| Create entities from a typed source | generated named set or canonical-collection constructor such as `entityGraph.<entities>.fromFile(...)` | public workflow registry, import service, adapter selection, or repeated create plumbing forbidden |
| Edit ordinary fields | generated `entity.beginEdit()` and `await draft.save()` | patch map, setter wrapper, CRUD command, or form-to-database adapter forbidden |
| Execute a mechanically declared action | generated `@Action` method declared on the entity | generator maps explicit parameters/values/guards; it never infers meaning from a method name |
| Execute a real business decision | handwritten pure guard/value method referenced by a generated action, or one owner-rooted transaction | handwritten code owns only irreducible decision logic |
| Change one existing entity or its generated relationships | awaited method on that entity, such as `entity.setCollaborator(...)` | feature-facing `...Commands`, handler, manager, service, or controller wrapper forbidden |
| Record domain-visible entity activity | `ActivityTracked` source plus one generated `ActivityOf<Source, Actor>` entry entity | manual activity writes, transaction wrappers, observers, and preformatted persisted messages forbidden |
| Run a long-lived process owned by an entity outcome | named generated set constructor, entity action, aggregate action, or explicit process entity when its lifecycle is domain-visible | generic application workflow namespace or detached orchestration service forbidden |
| Delete, restore, archive, or apply declared lifecycle | generated or entity-declared awaited method | application wrapper forbidden |
| Apply one declared action or lifecycle transition to a selection | generated query-owned `<action>All`, `removeAll`, `restoreAll`, `archiveAll`, or `unarchiveAll` | materializing the selection and writing an application mutation loop forbidden |
| Propagate lifecycle through a true self hierarchy | `@Reference(hierarchy: true, onDelete: ReferenceDeleteAction.cascade)` plus generated set hierarchy operations | descendant scans, recursive feature loops, and handwritten tree transactions forbidden |
| Select by ownership, reference, participant, unique index, or compound index | generated named `<Entity>List` constructor or inverse relationship | repeated predicate/query wrapper forbidden |
| Select an ad hoc typed subset | generated typed predicate and ordering API | pure named selector MAY add business vocabulary, never I/O mechanics |
| Mutate a declared relationship | generated relationship API | link CRUD service forbidden |
| Enforce a multi-entity invariant | one named domain transaction rooted at its owner | domain service allowed only when no aggregate can own the decision |
| Read entity or query state in Flutter | stable generated identity/query observed by MobX | provider/view-model/other entity or query mirror forbidden |
| Own widget-only interaction state | Flutter Hooks or local widget state | persisted-field copies or application-wide state containers forbidden |
| Coordinate non-entity application state | the narrowest injected composition or workflow boundary | entity/query projection, cache, or duplicate synchronization state forbidden |
| Select a remote destination | inferred typed sync target plus generated connector factory and adapter registry | feature-selected adapter, entity-to-adapter map, manual graph wiring, or direct remote write forbidden |
| Project canonical state to additional destinations | typed generated projection/outbox declaration with inferred codecs and routing | treating a search, analytics, calendar, or webhook sink as another writable authority forbidden |
| Define navigation | filesystem page contract and generated typed route | manual route registry, path constant, or wrapper page forbidden |
| Integrate an external resource or online-only capability | typed stateless port and adapter | allowed only as a documented permanent exception |

Use this disposition algorithm during review:

1. If information is derivable safely from an existing type, value, name,
   default, file, annotation, index, or relationship, generate it.
2. If behavior is a real domain decision, keep its pure handwritten decision at
   the entity or owning aggregate and expose the awaited operation on that same
   receiver.
3. If a process creates or changes an entity, expose it through the generated
   set, owning entity, aggregate, or canonical collection. Model the process as
   its own entity only when identity, progress, cancellation, retry, audit, or a
   zero/many-result lifecycle is real domain state.
4. If behavior crosses an external system and cannot truthfully use local-first
   entity semantics, keep one narrow typed integration boundary behind that
   entity-owned API.
5. If an artifact only renames, forwards, caches, serializes, invalidates, or
   exposes generated entity behavior, delete it.
6. If inference is ambiguous, fail generation with a precise diagnostic and
   require the smallest explicit override.

Names do not grant exceptions. Renaming a repository to `access`, `query`,
`command`, `manager`, `controller`, `data source`, or `service` does not make a
mechanical wrapper architectural.

## 3. Sources of truth

The sources of truth have distinct responsibilities:

```text
Entity declarations
    Handwritten source of domain intent: types, defaults, relationships,
    constraints, capabilities, pure decisions, declared actions, named
    source creation/process intent, and projection intent

EntityGraphDefinition
    Canonical fully resolved semantic manifest and sole input to generated
    entity implementation, storage, observation, query, and synchronization
    emitters

Filesystem page contracts
    Handwritten navigation intent. The route compiler combines this tree with
    only the nominal type/codec catalog from EntityGraphDefinition and produces
    one deterministic RouteGraphDefinition

Drift
    Durable accepted state, optimistic local projection, pending operations,
    conflicts, synchronization work, and cursors for one account/device

EntityGraph
    One live account-scoped runtime containing sets, transactions, queues,
    queries, and synchronization lanes

IdentityMap
    One stable MobX-observable object per loaded entity identity

Remote synchronization targets
    At most one replica authority, import source, or export destination per
    non-local entity, reached through a generated typed target binding;
    additional destinations are non-authoritative generated projections

Flutter Hooks
    Widget-owned ephemeral interaction resources only
```

No layer may become a second source of entity truth:

- database types are generated from domain types;
- wire codecs are generated from the same fields;
- API payloads do not repeat handwritten DTO schemas;
- UI state does not copy persisted entity fields;
- synchronization does not maintain a parallel feature state graph;
- route IDs use the same nominal entity IDs as the domain.

### 3.1 Runtime naming and ownership

The active generated object is an **entity graph**, not a generic model,
repository, database, or service locator. Public generated application types MUST end in
`EntityGraph`; variables and parameters MUST use `entityGraph`. Static metadata
is an `EntityGraphDefinition` and stable entity instances live in an
`IdentityMap`. These terms MUST NOT be used interchangeably.

The generic lifecycle vocabulary is:

```text
<Application>EntityGraph
    One active, authenticated, account-scoped entity graph.

AccountEntityGraphSession
    Serializes opening, switching, and closing entity graphs as identity changes.

AccountEntityGraphScope
    Publishes only entity-graph lifecycle state to a Flutter subtree.
```

Names such as `<Application>Model`, `model`, `AccountModelSession`, or
`AccountModelScope` for these runtime roles are forbidden migration debt. An account
switch MUST close the previous entity graph before publishing the next one;
work acquired through the session MUST keep its entity graph alive until the
operation completes.

The canonical generated application library is `lib/nodus.g.dart`; its Drift
part and reviewed schema-step artifact derive from that same basename. It is the
one application import for generated graph types, entity codecs, descriptors,
sets, lists, lookups, adapter bindings, and database runtime. A handwritten
feature barrel MUST NOT re-export graph internals. The entity-set property is
inferred from table vocabulary; `Entity.setAccessor` is the exceptional
collision override, and a `modelAccessor` alias MUST NOT exist.

### 3.2 Zero-boilerplate graph setup

Adding Nodus to an application requires only the package and one initialization
command:

```sh
flutter pub add nodus
dart run nodus init --target supabase
```

Initialization discovers every `@Entity` library under `lib/`, derives the
application graph name from the pubspec package name, creates committed
`nodus.lock`, and generates or updates the standard Drift builder settings. For
example, package `tasks_example` owns `TasksExampleEntityGraph`,
`TasksExampleSyncAdapters`, and `TasksExampleSyncTarget`. Applications MUST NOT
write `entity_graph.dart`, a graph annotation, a target enum for the default
target, a schema version constant, an entity registry, or Drift graph wiring.

`nodus.lock` is tool-owned reviewed metadata. It contains the package/graph
identity, target configuration, local schema version, and the SHA-256
fingerprint of the fully resolved physical graph. A no-name generation fails
when that fingerprint changes. `dart run nodus migrate <name>` advances the
version, regenerates the graph, and produces the reviewed Drift and configured
target migration. This makes forgetting a version bump impossible and keeps
version changes tied to actual resolved schema changes.

Ordinary applications need no handwritten configuration file. `nodus.yaml` is
reserved for irreducible exceptions such as multiple targets, a durable graph
name override, schema composition, supported target-specific overrides, or an
exceptional reviewed migration. It MUST NOT repeat discoverable entities,
fields, tables, defaults, codecs, ordinary target routing, or schema versions.

### 3.3 Entity-graph construction and lifecycle

The application composition root wires authenticated identity changes into one
`AccountEntityGraphSession`. The session calls the generated
`<Application>EntityGraph.open<Target>(...)` factory for a signed-in account and
serializes opening, switching, and closing. An application-specific
`<Application>EntityGraphHost` MAY own an irreducible platform identity
subscription and that account session. It exposes lifecycle only and MUST NOT
proxy entity sets, queries, mutations, persistence, or synchronization. A
generic `EntityGraphRuntime` wrapper around the generated graph is forbidden.

Generation owns adapter-registry and account-store wiring for every target. A
Flutter composition root supplies only the authenticated nominal account ID and
either a built-in target client or one `SyncConnector` callback to a generated
factory. A single custom target named `rest_api`, for example, receives
`openRestApi(connector: ...)`; multi-target graphs receive the capability-typed
`openWithConnectors(...)` factory. The connector is handed a
`SyncConnectorContext` containing the authenticated account, stable target, and
exact generated target descriptor subgraph. An explicit in-memory factory is
available for demos. The lower-level `open(executor:, syncAdapters:)` remains a
transport conformance-test boundary, not ordinary application setup.
Applications MUST NOT repeat database paths, native executor creation,
descriptor groups, or adapter-registry construction.

Opening an entity graph MUST, in order:

1. validate the generated graph definition and every sync-adapter binding;
2. open the account-specific Drift store and apply reviewed migrations;
3. create one local transaction/queue coordinator;
4. create the generated typed sets plus private identity, mutation, query,
   transaction, local-store, process, and synchronization runtimes required by
   the resolved graph;
5. bind target-specific descriptor groups, cursors, workers, signals, external
   process capabilities, and secondary-projection destinations;
6. hydrate the required local projection and start synchronization;
7. publish one ready entity graph only after initialization succeeds.

Failure closes every partially opened resource before publishing a typed
failure state. On account switch the session rejects new foreground work,
cancels target signals and claimable background work, waits for in-flight local
commits, checkpoints durable remote work, and closes the previous graph before
publishing the next. It MUST NOT wait indefinitely for a network request:
idempotent durable work remains recoverable by the next compatible session.

Foreground operations acquire bounded session leases. A lease keeps the graph
alive only until its local operation or query acquisition completes; it cannot
keep sign-out blocked through an unbounded stream or remote retry.

`AccountEntityGraphScope` exposes signed-out, opening, ready, and failure
lifecycle transitions only; entity/query mutations remain direct MobX
observations and MUST NOT rebuild that scope. Tests inject account storage,
clock, ID source, and sync adapters through the same opening boundary rather
than global overrides hidden from the entity graph.

### 3.4 Public facade and internal runtime boundaries

`<Application>EntityGraph` is the one public account-scoped domain facade, not
one monolithic implementation class. Generated code composes narrow internal
roles such as identity, mutation, query, transaction, local-store, process, and
synchronization runtimes. These roles are private implementation modules inside
the one reusable architecture package; application and feature code cannot
obtain them, use them as a service locator, or bypass the generated sets.

The public graph exposes only generated entity sets, relationships, queries,
canonical collections, aggregate transactions, and bounded lifecycle status.
It MUST NOT expose a raw database, queue, identity map mutator, sync scheduler,
adapter lookup, or generic runtime registry. Internal modules communicate only
through typed contracts derived from the same `EntityGraphDefinition`; they do
not rediscover fields, ownership, routing, or serialization independently.

This distinction permits one simple public entry point without giving one class
every implementation responsibility. A subsystem can be tested, replaced, or
optimized internally without creating an application-visible repository,
provider, service, or second composition API.

## 4. Entity declarations and inference

An entity declaration MUST remain concise and contain only:

- persisted properties and declared defaults;
- nominal identity and typed relationships;
- constraints and invariants;
- computed domain properties;
- pure computed business decisions, guards, and action value methods;
- named source creation, entity-owned process, and projection intent plus a pure
  typed mapper only where semantic mapping cannot be inferred;
- explicit conflict or authorization behavior that cannot be inferred.

It MUST NOT contain Drift, SQL, Supabase, Convex, sync-adapter classes, queue,
serialization, cache, registration, provider, or route mechanics.

The handwritten `<Entity>` is abstract because generated infrastructure supplies
its concrete storage and mutation implementation. It is nevertheless the one
public domain type: handwritten computed properties, pure invariants, and
business methods remain on it. Generation emits a concrete `<Entity>Record`
that extends it with MobX observables, validation, persistence, synchronization
recording, and rollback. Callers refer to `<Entity>`, never to the record.

A concrete handwritten method on that abstract type MAY express an irreducible
single-entity decision by deriving typed values, checking business invariants,
and returning one awaited generated draft/action/lifecycle operation. It MUST
NOT accept an entity graph, session, database, queue, adapter, or provider; do
lookup, persistence, serialization, or invalidation itself; discard the
generated future; or merely rename one generated operation. A typed source-to-
value constructor MAY live on the persisted value when it validates and maps
domain inputs without I/O. This keeps `plan.add(item)` and
`Item.fromSource(source)`-style vocabulary at the domain boundary while all
mutation mechanics remain generated.

When one persisted value may reference one of several entity types, its domain
representation MUST be a sealed union whose variants carry the corresponding
`LocalId<E>`. A separate raw ID plus enum/string discriminator is forbidden
because the two values can disagree. One typed codec MAY preserve an established
flat external wire shape, but it derives the discriminator from the union,
validates both fields while decoding, and rejects unknown variants or invalid
nominal IDs. The wire representation never becomes a second domain model.

`@Entity(...)` is the sole graph-membership declaration annotation. The package
graph is inferred, so a graph declaration annotation MUST NOT exist. Local-first
persistence is universal, while synchronization mode is inferred separately;
there is therefore no second kind of entity or graph for local storage.

The word `local` remains appropriate for mechanics that genuinely distinguish
the Drift-side store, queue, revision, or transaction from a remote target. It
MUST NOT classify the domain entity or create a parallel declaration surface.

### 4.1 Inference precedence

Generation applies metadata in this order:

1. Dart type and nullability;
2. initializer or declared default;
3. field and entity names;
4. typed relationships and indexes;
5. graph-wide conventions;
6. explicit annotation override.

An override replaces only the inferred value it names. It MUST NOT require the
author to restate unrelated inferred metadata.

Safe conventions include:

- entity names derive table, set, descriptor, and protocol names;
- field names derive column and wire names;
- Dart types derive SQL/Drift types and codecs;
- `LocalId<E>` derives nominal UUID storage, validation, and codecs for `E`;
- `@Reference` turns a `LocalId<E>` field into a live relationship and derives
  its foreign key, access graph, inverse metadata, deletion behavior, and
  relationship invalidation;
- `@Composition` turns one immutable non-null `LocalId<Component>` field into
  an aggregate-owned component identity and derives the reference, uniqueness,
  ownership, access propagation, lifecycle, and sync dependency;
- nullability derives requiredness and deletion behavior constraints;
- initializers derive create defaults;
- ownership references derive ordinary owner filtering and security policy;
- unique and compound indexes derive exact lookup/list APIs;
- lifecycle interfaces derive state, default visibility, and safe transitions;
- root-entity and relationship-collection cardinality are resolved separately;
  each defaults to unbounded unless boundedness is proved from an already
  bounded target/link set or declared as an enforced domain and performance
  promise;
- the package's tool-owned default sync target derives ordinary replication
  routing;
- directory and page names derive route paths.

Nominal identity and live relationship are deliberately separate concepts. A
typed identity token that may validly outlive local visibility of its target,
such as historical, audit, diagnostic, inbox, or integration context, MUST use
`LocalId<E>` without `@Reference`. Generation persists it as a native UUID and
preserves nominal Dart safety, but emits no foreign key, target-presence check,
inverse collection, access propagation, or relationship invalidation. This is
not a weak reference: callers cannot dereference it through the graph without
an explicit demand-load/access operation.

`@Reference` is required when the target's existence is part of the current
entity invariant and the graph must maintain the relationship. It MUST NOT be
added merely because a field contains another entity's identity. Historical
identity MUST NOT fall back to `String`, a generic payload, or a fake nullable
relationship to avoid synchronization-order failures.

`@Composition` is the stronger relationship when the aggregate owns exactly
one independently persisted component. It already means `@Reference`, a
restrictive target-delete policy, exclusive target assignment, same-owner
validation, and aggregate-derived access. Authors MUST NOT repeat `@Reference`,
`@Indexed`, `@OwnerReference`, `@AccessReference`, or `@AccessTarget` on the
same field. A nullable component, configurable delete action, shared component
identity, or owner/sync-target mismatch is not composition and MUST fail
generation rather than silently weaken the contract.

When a custom value object is not supported unambiguously, generation MUST fail
at compile time until one reusable codec is registered. Runtime reflection,
best-effort JSON conversion, stringly typed fallback, and silent lossy mapping
are forbidden.

#### Normalized persistence

An entity field MUST map to the most specific native storage type derivable
from its Dart type: boolean, integer, text, UUID/reference, enum, date, timestamp,
or another explicitly supported atomic scalar. Drift and SQL emitters consume
that same resolved type. They MUST NOT select text or JSON merely because it is
easy to serialize.

Numeric inference preserves intent: Dart `int` maps to SQLite `INTEGER` and
PostgreSQL `bigint`; Dart `double` maps to SQLite `REAL` and PostgreSQL
`double precision`. Numeric transport values must be finite, integer fields
reject fractional input, and declared bounds are generated at every boundary.

An ordinary persisted `String` whose surrounding whitespace is not meaningful
declares that fact once with
`@Persisted(normalization: FieldNormalization.trim)`. A nullable optional text
field uses `FieldNormalization.trimToNull` when an empty trimmed value means
absence. The compiler applies the transform before constraints and uses the
same canonical value for creation, aggregate/edit drafts, generated actions,
typed patches and predicates, exact lookups, wire decoding, local storage,
synchronization, remote materialization, Drift checks, and PostgreSQL checks.
Generated field capabilities expose `canonicalize(value)` for the exceptional
case where domain code must key or deduplicate an in-memory collection before
persistence. Feature operations MUST NOT repeat the declared transform.

Normalization is deterministic field representation, not input repair or a
general conversion hook. `trimToNull` requires a nullable `String`; a
non-String field, whitespace-significant field, noncanonical default, or
persisted-variant component with field-level normalization MUST fail
generation. A nominal scalar or persisted variant owns any canonicalization in
its typed constructor so the physical representation remains total and
unambiguous.

Persisted entity declarations MUST NOT contain `Map`, `List`, `Set`, arbitrary
object trees, generic JSON wrappers, or a field whose physical representation
is a JSON array/object. Structure is modeled once instead:

- a repeated value becomes a typed child entity and generated relationship;
- a nominal value with exactly one atomic representation implements
  `PersistedScalarValue<Wire>` and persists as that native scalar;
- a reusable composite value object is flattened into native columns when its
  components are wholly owned and atomically meaningful on the parent;
- an optional or independently identified component becomes a child entity;
- a sealed variant becomes mutually exclusive native variant columns or typed
  references plus generated cross-field checks. A discriminator is generated
  only when the selected variant cannot be derived safely from presence and
  type; a derivable discriminator is forbidden as duplicated state;
- an opaque external payload remains at the integration boundary. If it must be
  queried, observed, synchronized, or available offline, its required facts
  become an explicit typed entity projection before entering the graph.

Generic entity-attribute-value storage is not normalization and is forbidden.
Generation MUST reject a persisted collection or generic JSON shape and explain
the scalar, flattened-component, child-relationship, or boundary alternatives.
A codec may adapt a supported atomic scalar or an external wire contract; it
MUST NOT turn a structured persisted field back into an opaque database blob.

A sealed value stored on an entity declares `@PersistedVariant` on the one
logical field. Its direct cases MUST be public final classes with exactly one
unnamed generative constructor. Every persisted case component MUST be a public
final atomic scalar, enum, or nominal `LocalId<E>`, initialized exactly once by
that constructor, and component names MUST be unique across all cases because
they derive native column and protocol identities. Scalar constraints, indexes,
and relationship/access annotations belong to the case components; they MUST
NOT be repeated on the logical field. Variants cannot nest persisted variants,
compositions, collections, or access participants.

Generation flattens those components into nullable native storage, reconstructs
the sealed value on reads, and exposes only the logical value through public
create and mutation drafts. It MUST generate the same exclusivity, component
presence, reference, codec, patch, and validation behavior across Dart, Drift,
PostgreSQL, synchronization, and graph metadata. Every non-empty case requires
one non-null presence component. A non-null logical variant MAY have one empty
case; a nullable logical variant MUST NOT, because an empty case would be
indistinguishable from no value. Physical component fields are generated
implementation detail and MUST NOT become a second public mutation surface.

Runtime-defined structured input is the narrow exception to an otherwise
static schema, not an EAV escape hatch. It MUST use a first-class definition
entity and a typed response relationship whose value variants are a closed set
of schema-declared native columns or references. Generation MUST enforce one
response per parent-and-definition pair and exactly one populated value
variant. The aggregate write contract MUST validate that the populated variant
matches the referenced definition type. A choice value stores the choice
reference, never a copied label; projections may join the label, including a
tombstoned historical choice. Arbitrary attribute names, dynamically selected
storage types, untyped scalar columns, and application-defined codecs remain
forbidden.

`PersistedScalarValue<Wire>` is the sole declaration-level escape from leaking
a storage primitive into the domain. `Wire` MUST be one supported native
scalar (`String`, `bool`, `int`, or `double`), and the concrete immutable value
type MUST expose exactly one `toScalar()` method and one named
`fromScalar(Wire)` constructor. Generation derives the Drift column,
PostgreSQL type, protocol codec, defaults, constraints, equality queries, and
change detection from `Wire`; no reflection or converter registration is
required. A declared scalar default additionally requires `fromScalar` to be a
const constructor because Dart optional-parameter defaults are compile-time
constants. The conversion MUST be total, deterministic, and canonical. It
MUST NOT serialize a collection, object tree, or JSON document into a string
or number to evade normalization. Multi-component values remain flattened
fields or related entities.

A nullable dependent value declares `@Persisted(requires: #field)` once when
its presence has no meaning without another nullable persisted field. The
generator validates both symbols and emits the same implication for local
construction, edits, remote merge, SQLite, and PostgreSQL. A mutually exclusive
physical field group declares one `ExclusiveFieldGroup`; a sealed domain value
declares one `@PersistedVariant`, which synthesizes its physical group and case
presence checks. The generator then owns candidate validation and physical
checks. Callers, adapters, and handwritten SQL MUST NOT re-implement those
invariants.

An ordered numeric field relationship declares `greaterThan: #field` or
`greaterThanOrEqual: #field` once. Both fields MUST have the same numeric type;
nullable pairs are constrained only when both values are present. Generation
MUST apply the relationship to construction, every participating edit, remote
merge, SQLite, and every generated remote schema. Application validation and
handwritten database checks MUST NOT duplicate it.

### 4.2 Annotations

Annotations express intent that types and conventions cannot express. They MAY
declare such concerns as cardinality, ownership, access propagation, field
authorization, an unusual collaboration policy, an unusual index, a generated
action, a custom codec, a conflict rule, a non-default sync target,
synchronization-mode override, a typed named source constructor, an
entity-owned external-process binding, or a secondary projection whose
existence cannot be derived from the entity alone. Deterministic String
normalization is also explicit because Dart nullability cannot distinguish an
empty optional value from absence.

Annotations MUST NOT repeat table names, ordinary column names, obvious SQL
types, default serialization, standard CRUD registration, or relationships
already represented by a typed field.

Domain-facing declaration names omit the word `Entity` when `@Entity`, the
annotation position, or the argument already supplies that context. The
canonical vocabulary is `Cardinality`, `Ownership`, `SyncMode`,
`FieldAuthority`, `@Reference`, `@Composition`, `Component`, `@Action`, and
`ActionValue`; forms such as
  `EntityCardinality` or `EntityAction` MUST NOT exist as aliases. `Entity`
retains the qualifier because it names the declaration root; `EntityGraph`
retains it because it names the generated runtime and resolved graph contract.
Cross-layer runtime types retain it only where it materially disambiguates the
contract, such as `EntityIdentity`, `EntityQueryState`, and
`EntityGraphDefinition`. Derived action metadata is already unambiguous as
`ActionPolicy`, `ActionDefinition`, and `ActionAssignment`; redundant
`EntityAction...` forms are forbidden. Graph metadata and adapter position also
supply their own context, so the canonical runtime vocabulary is
`RelationshipDefinition`, `CompositionDefinition`, `SyncTargetId`,
`SyncBindingDefinition`, `SyncAdapterRegistry`, `SyncAdapter`, and
`SnapshotSyncAdapter`; corresponding `EntityRelationship...`,
`EntitySync...`, and `EntitySnapshot...` forms are forbidden. Concision is
contextual, not a blind global rename.

### 4.3 Compile-time validation

Generation MUST reject:

- duplicate entity, table, column, route, operation, or generated type names;
- unsupported or ambiguous field types;
- invalid defaults and constraints;
- unresolved relationships or unsafe access-propagation cycles;
- ownership fields that do not reference the declared account type;
- nullable uniqueness exposed as a singular lookup without explicit semantics;
- transitions that target undeclared, immutable, server-owned, or unauthorized
  fields;
- named source constructors with ambiguous ownership/result cardinality,
  unsafe partial entity state, untyped mapping, or a source capability that
  cannot satisfy its declared durability semantics;
- relationship policies that can bypass target authorization;
- a `Component` without an incoming `@Composition`, a composition target that
  is not a `Component`, repeated component assignment, independent component
  lifecycle/collaboration, or aggregate/component owner or sync mismatch;
- undeclared, unbound, duplicated, or capability-incompatible sync targets;
- remotely constrained relationships whose replicated or imported entities use
  different authoritative targets without an explicit cross-target contract;
- a secondary projection declared as writable authority, a projection cycle, or
  a multi-master binding without explicit deterministic merge and recovery
  capabilities;
- schema changes without a compatible migration proposal or explicit reviewed
  break;
- generated artifacts that would collide with handwritten source.

Validation happens at build time. Production behavior MUST NOT depend on runtime
reflection or discovery.

### 4.4 Generated-action and business-logic boundary

A generated action is an abstract `Future<void>` method annotated with
`@Action`. Each required parameter MUST match a writable persisted field by
exact name and compatible type; an explicit `ActionValue` may instead
provide a typed literal, injected clock value, clear operation, or the result of
a named handwritten pure value method. An optional guard names a handwritten
pure boolean or invariant method. Every referenced signature and return type is
validated at generation time.

Referenced guard and value methods MUST be deterministic and side-effect free:
they read only the entity and explicit typed parameters, perform no I/O, use no
ambient clock or randomness, and do not mutate state. Time and IDs enter through
generated injected action values. A failed guard produces a typed domain
error before any optimistic mutation is exposed.

Generation rejects missing, ambiguous, duplicated, immutable, unauthorized, or
type-incompatible targets. It never invents arbitrary business meaning from a
method name and never claims an abstract action has a handwritten body. For
example, `rename({required String title})` changes `title` only because the
parameter explicitly identifies that field.

The ordinary create/edit mutation draft is inferred from editable fields and
MUST NOT require a second authored form model. A real single-entity decision is expressed by pure
computed, guard, or value methods referenced explicitly by its action.
A decision requiring other entities or several mutations is a transaction
rooted at the owning aggregate. External I/O uses the entity-owned process or
typed capability boundary from sections 6.6 and 9 and never runs inside a local
database transaction. Handwritten code owns the decision; generated code owns
the awaited mutation method, validation plumbing, persistence, queueing, and
rollback.
Within-scope ordering is never declared as a synthetic per-entity action. A
genuine domain relationship action may change the exact inferred scope
discriminators; section 6.4 defines the generated atomic transfer mechanics.

### 4.5 Composable entity capabilities

The nominal owner relation and optional orthogonal entity features are declared
through generator-recognized abstract interfaces. Capability names MUST be
concise and MUST NOT repeat the word `Entity`; the annotated declaration
already establishes that context. Canonical names include:

```dart
abstract interface class OwnedBy<Self, Owner> {
  LocalId<Self> get id;
  LocalId<Owner> get ownerId;
  DateTime? get deletedAt;
  ServerVersion get serverVersion;
  GeneratedEntityAccess<Self> get generatedAccess;
}

abstract interface class Ordered {}

abstract interface class Component {}

abstract interface class Archivable {
  DateTime? get archivedAt;
  Future<void> archive();
  Future<void> unarchive();
}

abstract interface class SoftDeletable {
  DateTime? get deletedAt;
  Future<void> remove();
  Future<void> restore();
}

abstract interface class Activatable {
  bool get active;
  Future<void> activate();
  Future<void> deactivate();
}

abstract interface class Collaborative<Principal> {
  Future<void> setCollaborator(
    LocalId<Principal> collaboratorId, {
    required bool active,
  });
}

abstract interface class WorkflowMembership<Target, Principal, Status> {
  LocalId<Principal> get memberId;
  Status get status;
  Future<void> accept();
  Future<void> decline();
  Future<void> revoke();
  Future<void> reinvite();
}

abstract interface class ActivityTracked {
  String get activityLabel;
}

abstract interface class ActivityOf<Subject, Actor> {
  LocalId<Subject> get subjectId;
  LocalId<Actor> get actorId;
  ActivityOperation get operation;
  String get label;
  String get sourceOperationId;
  DateTime get occurredAt;
}
```

An abstract entity composes only the capabilities it needs:

```dart
@Entity()
abstract class Document
    implements
        OwnedBy<Document, Account>,
        Ordered,
        Archivable,
        SoftDeletable,
        Collaborative<Account> {
  abstract final String title;
}
```

`OwnedBy<Self, Owner>` is the one required type-surface contract for the
account-scoped architecture. `Owner` is real domain relationship intent. `Self`
is not configuration and generation validates it equals the annotated class;
it is the minimum F-bound currently required to expose `LocalId<Self>` through
the handwritten domain type. Ordinary `build_runner` output cannot augment the
class with that typed instance getter. The bound MUST disappear if stable Dart
augmentation can generate the member without a replacement public type,
duplicated fields, runtime casts, or loss of nominal ID safety.

The abstract entity inherits each capability contract without repeating its
fields or methods. The generated `DocumentRecord` supplies storage and generated
implementations. Implementing one recognized capability MUST bring the complete
vertical feature: inherited typed API, fields and safe defaults, validation,
indexes, entity or collection operations, Drift mapping, sync protocol,
rollback, and test metadata. Partial capability implementation and runtime mixin
discovery are forbidden.

Capability recognition uses the exact exported interface identity, including
transitive implementation; it never matches an arbitrary interface by spelling
or performs runtime reflection. An entity implementing a recognized capability
MUST NOT redeclare the fields or methods that capability supplies. Repetition is
rejected even when the signatures happen to match, because it creates two
sources for one contract. A metadata override belongs on the smallest explicit
annotation; behavior incompatible with the capability is a different domain
contract and MUST NOT partially impersonate it.

`Ordered` is intentionally a marker and does not expose `int sortOrder` or
another storage representation. Its ordering key is generated and internal.
The public collection API exposes semantic positions and neighbor-based moves.
If presentation genuinely needs a position, the collection MAY expose a
read-only computed index whose cost and completeness are explicit.

Ordered creation carries semantic placement separately from its provisional
local rank. Generated `create` means last and `createFirst` means first. Their
single durable create operation records the placement and the caller's known
scope version; a remote adapter resolves it against the current canonical scope
under that scope's serialization lock. The remote authority MUST NOT trust a
stale client rank as the meaning of first or last. Retry uses the same operation
ID and receipt, and any rank rebalance returns every changed canonical member.

Capability visibility conventions are:

- `SoftDeletable` entities are excluded from ordinary relationship, list, and
  generated set-query selections. Every generated query and list constructor
  defaults to `tombstones: TombstoneVisibility.exclude`; repair, audit, and
  recovery code MUST opt into `TombstoneVisibility.include` or `.only`
  explicitly. A custom `where` predicate only narrows the lifecycle selection
  and MUST NOT bypass it. A direct identity-map lookup MAY return a known
  tombstone so an explicit lifecycle operation can restore or inspect it;
- `Archivable` entities are excluded from ordinary active lists and have
  generated active and archived list constructors;
- `Activatable` relationships expose active links by default. Every generated
  query and list constructor defaults to
  `inactive: InactiveVisibility.exclude`; administration and recovery opt into
  `.include` or `.only`. Generation supplies `active = true`, `activate()`, and
  `deactivate()`; the entity repeats none of them. Generated relationship
  mutation internals include inactive identities so link and exact replacement
  reactivate the unique canonical row instead of creating a duplicate;
- `WorkflowMembership<Target, Principal, Status>` is the conventional
  invite/accept/decline/revoke workflow relationship. The entity declares its
  target reference and any product-specific payload; generation supplies the
  participant reference, the four-state status contract, transition actions,
  self-membership inequality, unique-pair reuse, and `inviteOrReuse`. `Status`
  remains a domain enum but MUST define exactly `pending`, `accepted`,
  `declined`, and `revoked`;
- `Collaborative<Principal>` generates the collaboration relationship,
  authorization metadata, durable semantic operation, and the direct
  `entity.setCollaborator(principalId, active: ...)` API. A separate
  collaborators command object, nested mutation facade, membership repository,
  or handwritten collaboration table is forbidden. An annotation MAY override
  unusual grants or policy, but MUST NOT be required to opt into the standard
  capability;
- `ActivityTracked` declares domain-visible activity, not the internal
  synchronization change log. The entity supplies one pure `activityLabel`
  getter. Exactly one immutable entity implementing `ActivityOf<Source, Actor>`
  belongs to that source in the same graph and uses the same owner, sync mode,
  and target. Generation supplies the entry fields, indexes, typed source list,
  storage, synchronization, and graph metadata. It suppresses public activity
  creation and mutation APIs;
- a tombstone or inactive relationship is outside canonical ordering membership
  because removal and restoration change membership. Archiving only filters a
  view by default and preserves canonical membership and position, so restoring
  an archived entity cannot silently move it. A capability may change this only
  through one explicit order-membership override that also generates the
  corresponding scope-versioned lifecycle operations.

`Component` is also a marker, but it narrows lifecycle and creation. The
component has no independent collaboration or `SoftDeletable` API. Its
relationship select/update grants are derived from the aggregate composition,
and deletion belongs only to generated physical aggregate cleanup. Remote
insertion is owner-authorized solely so dependency-ordered synchronization can
write the component before the restrictive aggregate reference; this does not
grant owner read, update, delete, or a standalone domain creation API. Its
generated set rejects creation outside an active entity-graph transaction. This
prevents an independently durable orphan from becoming a second aggregate root.
An aggregate transaction MUST enqueue creation in causal order: component,
composing root, then component children. The root cannot reference a component
that has not reached the remote target, while children obtain remote
authorization through the completed composition. The outer future is their one
durability boundary. Before scheduling the batch, the generic transaction
coordinator derives composition edges from field descriptors and rejects every
component create that is not referenced by exactly one later aggregate create.
This commit preflight, rather than the presence of a transaction alone, proves
that a successful local commit cannot leave an orphan component.

Universal behavior is inferred by default rather than selected through
interfaces. `OwnedBy<Self, Owner>` publishes nominal identity and ownership to
Dart's static type system; it does not opt into local persistence, IdentityMap
participation, internal revision metadata, tombstones, or sync routing. Those
mechanics are generated for every entity and MUST NOT require `Persisted`,
`Syncable`, or adapter-specific capabilities. Domain-visible `createdAt` or
`updatedAt` fields are generated only when declared directly or introduced by a
semantic capability; conventional names infer clock defaults and automatic
update behavior without an extra annotation. Sync-target routing remains
graph/entity metadata, not a capability such as `SupabaseEntity`.

#### Generated activity tracking

Domain activity is recorded at the generated mutation coordinator, never by a
MobX reaction, database listener, widget, command wrapper, or post-commit
callback. For each actual local durable create, draft save, declared action,
lifecycle transition, collaboration change, or ordered move on an
`ActivityTracked` source, generation MUST:

1. validate and apply the source mutation optimistically;
2. snapshot its pure activity label and typed operation identity;
3. create one immutable activity entry with the source ID, authenticated actor,
   source operation ID, and occurrence time;
4. persist and enqueue the source mutation and entry in the same local mutation
   batch; and
5. roll both back when that batch fails.

A failed guard, invalid mutation, or no-op produces no activity. Applying a
remote source change MUST NOT generate another entry: the original entry is an
ordinary synchronized record and its unique source operation identity provides
deduplication. The historical `subjectId` remains a nominal `LocalId<Source>`
without `@Reference`, so deletion or synchronization order cannot erase or
invalidate history.

Every tracked source mutation keeps its own durable operation boundary. State
patches for an `ActivityTracked` entity MUST NOT coalesce across activity
identities, because each entry proves and references one exact source operation.

An activity entry stores structured facts, never a localized or preformatted
message. Presentation derives text and icons from `ActivityOperation` and the
captured label. A declared `@Action` records its validated action identity;
generation does not infer additional business meaning from the method name.
Application code therefore calls `task.complete()`, `task.archive()`, or
`task.setCollaborator(...)` directly. A `TaskActivityTransactions`-style helper
or a manual `taskActivities.create(...)` call is forbidden.

An explicit annotation is allowed only to override a capability default that
cannot be inferred safely. Incompatible capabilities, ambiguous capability or
ordering scope, conflicting inherited members, repeated supplied members, and
overrides that weaken an invariant fail generation.

## 5. Generated artifacts

### 5.1 One compiler and one canonical definition

Generation is a compiler, not a collection of templates. One public build entry
point inside the `nodus` package MUST run these deterministic internal
stages:

```text
Dart entity declarations + nodus.lock + filesystem page contracts
    -> parse complete declarations
    -> normalize a typed semantic intermediate representation
    -> run ordered inference passes exactly once
    -> run graph-wide validation passes
    -> freeze EntityGraphDefinition + derivation provenance
    -> run independent deterministic emitters
    -> emit one generated public application library and reviewed artifacts
```

The canonical intermediate representation MUST resolve identity, types,
nullability, defaults, ownership, relationships, capabilities, cardinality,
indexes, lifecycle visibility, editability, authority, synchronization mode,
ordering scope, conflict semantics, and codecs before emission. An emitter MUST
consume resolved facts; it MUST NOT guess a name, repeat inference, reinterpret
ownership, or select a target. Drift, MobX, synchronization, SQL-target,
non-SQL-target, diagnostics, and Flutter emitters therefore cannot disagree
about one declaration.

The frozen graph definition includes every inferred normalized relationship:
link entity, source and target endpoint types, source and target fields, active
field, ordered capability, resolved relationship cardinality, and the proof
used for that resolution. Graph construction validates this metadata against
the generated references, unconditional unique pair, endpoint cardinalities,
and ordered descriptor. Runtime adapters consume the frozen relationship fact;
they MUST NOT repeat structural or cardinality inference.

Routing is an internal compiler pass in the same package but has a distinct
input contract: it combines the filesystem page tree with only the resolved
nominal type and external-input codec catalog. It MUST NOT make persistence or
synchronization decisions, and an entity emitter MUST NOT inspect page files.
This is an internal responsibility boundary, not a separate package or setup
surface.

Every derived value retains machine-readable provenance. The package MUST
provide an `explain` report, or an equivalent generated artifact, that shows for
an entity or route the resolved value, the declaration or convention that
produced it, every applied override, generated API signatures, physical indexes,
authority/target routing, and the smallest action for any ambiguity. Inference
must be discoverable rather than magical.

Incremental generation is fingerprinted by declarations and their actual graph
dependencies. Changing one entity regenerates that entity and only graph-wide
artifacts whose resolved definitions changed. No-op generation writes nothing.
Clean and incremental generation time, peak memory, analyzer time, generated
source size, and affected-artifact fan-out have explicit benchmark budgets and
regression gates.

### 5.2 Generated surface and emitters

For each entity graph, generation owns at least:

- transitive expansion and validation of recognized capability interfaces;
- nominal IDs and typed field references;
- descriptors, defaults, constraints, indexes, and codecs;
- MobX-backed concrete record implementations derived from concise public
  entity declarations;
- stable identity sets and typed query/list classes;
- set-based create and named source constructors, draft, lifecycle, transition,
  semantic-action, entity-owned durable-process support, and relationship
  mechanics;
- forward and inverse relationship APIs;
- Drift tables, rows, companions, mappings, and migration metadata;
- target-specific schema or protocol artifacts, including DDL, indexes,
  RLS/grants, change capture, and sync functions where supported;
- push/pull payload codecs and policy-required compatibility upcasters;
- sync-target metadata, typed adapter registry, descriptor subgraphs, queue
  routing, cursors, dependency ordering, and managed connector factories;
- typed route graph derived by the isolated route pass and external-input
  codecs referenced from the shared semantic catalog;
- conformance and migration-inventory metadata.

Generated output MUST be deterministic: identical declarations, page contracts,
and generator versions produce byte-identical output. Ordering MUST never depend
on filesystem iteration, hash iteration, wall-clock time, or machine paths.

Generated files are never edited directly. Custom behavior uses declared
extension points, not copied generated code.

Per-entity generated output owns the concrete record, observable fields,
transitions, codecs, and drafts. Entity-graph output owns the application entity
graph, typed sets, named `<Entity>List` types, cross-entity relationships, and
graph-wide transactions because those artifacts require knowledge of every
descriptor.
Generation MUST expose both through a stable generated public library so callers
do not need to know raw `*.g.dart` filenames or search implementation output to
discover a generated list.

The application-facing generated library is exactly `lib/nodus.g.dart`. It is a
small stable facade that re-exports the generated graph, entity APIs, Flutter
bindings, and public domain declarations. Per-entity implementations, the Drift
database, explanation metadata, and other compiler artifacts live below
`lib/src/generated/`; application code MUST NOT import those paths. Generated
test support lives below `test/` and is never exported by the production facade.
Moving implementation artifacts is a generator concern and MUST NOT require
handwritten `part`, export, graph, or barrel files.

The supported tool workflow is:

- `dart run nodus generate` for incremental application API generation and the
  schema-fingerprint gate;
- `dart run nodus watch` for continuous incremental generation;
- `dart run nodus check` for a non-persistent stale-output/fingerprint check;
- `dart run nodus explain [Entity] [--json]` for human or machine-readable
  resolved intent and provenance;
- `dart run nodus inventory [--write|--check|--json]` for deterministic,
  metadata-aware classification of replaceable application mechanics with
  source evidence and the generated replacement; and
- `dart run nodus migrate <name>` for Drift history, target schema, and reviewed
  migration artifacts.

No-op generation writes nothing. Ordinary generation MUST NOT create a
migration, advance schema history, synchronize a remote schema, or require an
application-owned tool script.

For every create-capable non-link reference, graph generation also emits a
typed inverse collection whose `create(...)` binds the reference represented by
the receiver. Ordered children additionally expose `createFirst(...)`. Both
delegate to the same generated set signature and durability primitive; the
relationship wrapper cannot duplicate defaults, ownership, validation,
persistence, queueing, or adapter selection.

## 6. Entity mutation API

### 6.1 Creation

For `localOnly`, `replicated`, and `exported` entities,
`Future<Entity> entityGraph.<entities>.create(...)` is generated from
create-capable fields, defaults, ownership, ID policy, constraints, and sync
metadata. Imported entities do not expose ordinary local creation. The entity
graph exposes one generated `<Entity>Set` per entity; its `create(...)` is the
public typed creation API. The generated `<Entity>Set.create(...)` signature is
the single source of creation parameters and defaults. Creation MUST:

- expose typed parameters only once;
- be reachable only through a compatible generated entity graph and never
  accept a concrete sync adapter;
- infer separately stored ownership from the entity graph's nominal authenticated
  account and never expose it as an ordinary create parameter;
- infer relationship-owned ownership from the declared target relationship;
- omit server-generated and immutable runtime metadata;
- infer safe defaults without asking callers to repeat them;
- allocate a nominal ID unless a valid explicit ID is allowed;
- validate the complete candidate;
- create one stable identity;
- infer the entity's sync target from generated metadata;
- atomically persist the local projection and, for a replicated or exported
  entity, its durable target-aware queue intent;
- resolve only after local durability succeeds and roll back the optimistic
  identity if it fails;
- never wait for remote synchronization.

Outside a graph transaction, the returned `Future<Entity>` is the exact local
durability boundary: when it completes, both the Drift projection and any
required durable outbound intent have committed. A following `flushLocal()` is
redundant and MUST NOT be required for correctness. Inside
`entityGraph.transaction(...)`, `await create(...)` returns the registered
optimistic identity so later operations in the same callback can form typed
references without deadlocking. The outer transaction future is then the sole
durability and failure boundary; created identities MUST NOT escape as durable
results until that outer future succeeds.

Generation MUST bind every create path to its exact local commit. It cannot
detach that commit, discard its future, or persist a second fire-and-forget
repair. Ordered placement, related rank repair, relationship-derived ownership,
the projection row, and outbound intent are one local atomic operation.

Creation code outside the generated set API is forbidden unless it is an
irreducible multi-entity business transaction. A generated list insertion such
as `list.prepend(...)` MAY delegate to the same set creation primitive while
deriving owner, relationship, and ordering membership from that list.
An inverse collection follows the same rule: for a typed reference with inverse
`children`, `parent.children(entityGraph).create(...)` omits the already-known
parent ID and delegates to `entityGraph.<children>.create(...)`. Feature code
MUST NOT reintroduce that bound ID through a repository, command, or handwritten
factory.

A `Component` is never created as a standalone durable root. Its generated set
is usable only inside `entityGraph.transaction(...)`; the transaction creates
the component, then its composing root, then component children, and commits
every projection and queue intent atomically. A named aggregate constructor MAY
hide this mechanical sequence when one typed input maps deterministically, but
it MUST delegate to the same generated sets and transaction. A caller MUST NOT
persist an empty placeholder component and repair it later.

### 6.2 Typed create/edit drafts

Ordinary persisted fields are not publicly mutable. Generation emits
`entity.beginEdit()`, `entityGraph.<entities>.beginCreate()`, and one typed
`<Entity>MutationDraft` spanning the create and edit form contract. Creation and
editing MUST NOT require separate handwritten form models, controller objects,
or field-copying adapters.

A draft MUST be:

- typed and initialized either from creation defaults/unset required values or
  from one stable entity identity and the base values of its editable fields;
- scoped to the entity-graph generation and account that created it;
- non-observable and non-persistent until `save()`;
- limited to editable fields;
- incapable of changing identity, ownership, server version, timestamps,
  tombstones, or transition-only fields unless explicitly declared;
- discardable with no side effects;
- free of raw maps and duplicate serialization.

Draft editability is inferred for client-authoritative, non-reference scalar
fields on an update-capable entity. Fields owned by identity, ownership,
timestamps, lifecycle capabilities, transitions, relationships, commands, or
fixed action assignments are excluded. An ordinary scalar MAY also be a
parameter of a semantic compound action without losing draft editability. If
that action touches any excluded field, local and remote validation activate
on the excluded field and require the action's complete atomic shape, including
its ordinary parameters. A creation-time or otherwise action-exclusive scalar
fact uses `@Persisted(editable: false)`; a catch-all `edit(...)` action is
forbidden boilerplate and action method names never affect draft generation.

For a creation draft, `await draft.save()` validates every required field and
delegates to the generated set's canonical `create(...)` operation. For an edit
draft it MUST:

1. reject a consumed, disposed, detached, or account-switched draft with a typed
   error;
2. calculate the fields actually changed by the draft;
3. merge those fields over the latest entity state when intervening mutations
   changed only non-overlapping fields;
4. reject overlapping changes with a typed stale-field error unless an explicit
   deterministic field merge policy resolves them;
5. form and validate one complete merged candidate, including cross-field
   invariants against the latest state;
6. no-op when the merged candidate is unchanged;
7. apply all observable field changes in one MobX action;
8. atomically persist the Drift projection and, for replicated or exported
   entities, durable target-aware outbound intent;
9. resolve only after local durability succeeds;
10. roll back or rebase the optimistic projection if local persistence fails.

`save()` never waits for the network. Remote convergence is observable through
generated synchronization state.

`beginEdit()` is required only when an edit lives across time, such as a form.
An immediate fully specified mutation MAY invoke its generated atomic action
directly. Persisted entity fields MUST NOT expose ordinary public setters plus a
later `entity.save()`: doing so would publish unsaved or temporarily invalid
state through the shared identity, require permanent dirty tracking, make
cancel/rollback ambiguous, and allow concurrent editors to overwrite one
another silently. A draft instead owns one private candidate and field-level
base snapshot; discard has no side effects, unrelated changes merge safely,
overlapping changes fail or merge by declared policy, and successful save
publishes exactly one coherent mutation.

When one form changes an ordinary edit field and an ordering-scope field, the
same generated mutation draft invokes the entity's declared action methods in
one generated transaction. The UI MUST NOT create a feature transaction file
to combine `entity.edit(...)` with `entity.moveTo...(...)`. This transaction is
a draft implementation detail; outside the form, callers continue to invoke
the entity actions directly.

Flutter bindings own only ephemeral controller/busy/error state. Generated
`EntityDraftField<T>` values remain the form candidate, `useEntityMutationDraft`
discards an abandoned draft, text/value bindings write directly to its typed
fields, and `useEntityAction` owns action feedback. These hooks MUST NOT create
a second persisted or query-state authority. When aggregate acquisition is
asynchronous, `useAsyncEntityMutationDraft` owns the future, stale acquisition,
and unconsumed-tree disposal; feature widgets MUST NOT repeat mounted checks or
draft cleanup around generated aggregate loaders.

When one bounded domain form owns more than one entity, generation emits a
typed `<Root>AggregateDraft` in addition to the ordinary entity drafts. The
aggregate boundary is inferred only from declared non-null compositions,
references marked as bounded `aggregateMember`s, and bounded active
relationship collections. A unique link from an aggregate member to one
bounded target proves the same bounded inverse and MUST NOT require the
consumer to repeat `aggregateMember`. Feature code MUST NOT restate that topology in a
repository, form model, transaction helper, or ID bundle.

An aggregate creation draft allocates stable identities for its complete tree
before persistence and derives composition IDs, aggregate-member owner
references, defaults, and relationship source IDs. An edit draft retains the
component, child-collection, and membership query leases needed to keep every
loaded identity stable for exactly the draft lifetime. Nested aggregate members
expose their own aggregate drafts recursively. Archival, removal, restoration,
canonical order, and active relationship replacement remain staged until the
aggregate save.

`await aggregate.save()` validates and commits one durability boundary in
causal order: component roots first, the aggregate root, an optional typed
post-root business callback, then membership and child trees. It runs in one
generated graph transaction, consumes the complete draft tree on success or
failure, and releases every retained lease. It MUST NOT perform external I/O or
wait for remote synchronization. An ordinary `<Entity>MutationDraft` continues
to own only one entity; aggregate topology MUST NOT be added to it ad hoc.

### 6.3 Generated and semantic actions

A declarative action is fully described by typed target fields, values,
optional named pure value methods, and an optional named pure guard. Generation
owns its awaited implementation. A semantic action adds irreducible handwritten
decision logic through those referenced pure entity methods, or through a named
transaction on the owning aggregate when other entities or several mutations
participate.

The two responsibilities MUST NOT be conflated: generation never infers
business meaning, and handwritten code never repeats persistence,
serialization, queueing, rollback, or adapter selection. A generated action invokes
the explicitly referenced handwritten guard/value methods and owns every
mutation mechanic. Semantic operations preserve ordering and MUST NOT be
coalesced when doing so changes meaning.

Every persisted semantic or lifecycle action MUST return `Future<void>` and
MUST expose its exact local commit; every generated action obeys the same
contract. The optimistic MobX
projection is applied synchronously; awaiting the action resolves only after the
Drift projection and, for replicated or exported entities, target-aware durable
outbound intent commit atomically, or rethrows the persistence failure after
rollback or rebase.
Public `void` mutation methods and separate `flush()` calls are forbidden.
One generated create, action, draft save, or lifecycle operation MUST be awaited
directly; wrapping that sole operation in `entityGraph.transaction(...)` adds no
atomicity and is forbidden. A graph transaction exists only when two or more
generated mutations must share one irreducible business commit.
Generated multi-entity code MUST still `await` generated mutation APIs inside
an asynchronous graph transaction. Those inner futures register and bind their
real local commit but do not wait for a batch that cannot be scheduled until
the transaction body returns. The outer transaction future is the sole
durability and failure boundary: it schedules the buffered batch, awaits its
atomic Drift commit, and then resolves. Outside a graph transaction, every
mutation future awaits its own local commit. Public callers never observe or
configure this distinction.

Public mutation vocabulary is entity vocabulary: `entity.archive()`,
`entity.complete()`, `entity.setCollaborator(...)`, or another domain verb.
A public `EntityCommands`, command handler, command bus, or one-method wrapper
adds indirection without owning state or a decision and is forbidden. Generated
runtime code MAY encode the same call as an `EntitySemanticCommand` so it can be
persisted, retried, ordered, authorized, and synchronized. That command is an
internal immutable protocol value, not an application-layer object that UI or
feature code constructs, injects, or calls.

Each affected identity has an ordered local mutation sequence. Concurrent local
mutations may update the optimistic overlay, but their durable commits are
serialized. Failure removes the failed mutation and deterministically reapplies
later valid mutations over the last durable projection; it MUST NOT restore an
obsolete snapshot over later user intent.

### 6.4 Multi-entity transactions

One aggregate or named collection owns an invariant spanning several entities.
Its generated `entityGraph.transaction(...)` MUST:

- validate before exposing partial state;
- publish at most one coherent observable commit;
- persist every projection and queue operation atomically;
- order creates and deletes by declared relationships;
- roll back observable identities in reverse order on failure;
- join an existing transaction only when the generated root and coordinator are
  identical; reject cross-root, cross-graph, or otherwise ambiguous nesting.

The callback accepts `FutureOr<R>` so synchronous invariants remain concise and
asynchronous generated preparation can be composed safely. Ordered boundary
planning inside the callback merges only that transaction's optimistic
identities with indexed durable rows. It MUST NOT ignore buffered creates or
moves, allocate duplicate positions from a stale database boundary, flush the
batch early, or load an unbounded scope to compensate.

A generic application service or `...Commands` class is not a substitute for
choosing an aggregate owner. If an operation changes one existing root and
related entities, the root exposes the named operation and generated code owns
the graph transaction. If no existing aggregate can truthfully own the
invariant, a narrowly named domain transaction is allowed; it MUST describe the
business outcome, not become a miscellaneous command namespace.

`Ordered` declares that an entity or relationship participates in one canonical
ordered scope. It introduces a generated internal ordering key, default ordered
list behavior, required indexes, and collection-level mutation. It MUST NOT
expose a raw public `sortOrder`, `moveTo(sortOrder: ...)` action, writable rank,
or storage-key API.

An ordering scope is a typed tuple, not an assumed single field. It may be the
empty tuple for one complete root, one owner or relationship-source identity,
or a composite such as `(ownerId, parentId)` for hierarchical siblings. Nullable
tuple components retain null as a real value; adapters MUST NOT flatten them to
a sentinel, drop them, or merge root members with another lane.

Generation infers the minimal canonical tuple from, in order: the source of an
ordered relationship, one unambiguous declared sibling/hierarchy relationship,
the entity owner, or a complete bounded root collection. An account-owned entity
with no scope-forming relationship therefore needs no configuration. A parent
relationship and a flat owner collection are competing candidates unless the
declared list/relationship contract proves which one is canonical; generation
fails and requests the smallest explicit tuple override rather than guessing.
If one entity participates in several independently ordered collections, the
relationship entity implements `Ordered`; the target entity does not.

The explicit ambiguity form names existing persisted fields once:

```dart
@Entity(orderScope: [#parentId])
abstract class HierarchicalItem
    implements OwnedBy<HierarchicalItem, Account>, Ordered {
  abstract final LocalId<HierarchicalItem>? parentId;
}
```

The override names only the ambiguous discriminator fields. For a separately
owned entity generation prepends its inferred owner; repeating `#ownerId` is
redundant and fails generation. An empty override therefore selects the flat
inferred-owner lane, while it selects the one complete root for an
identity-owned entity. Every component MUST be an immutable scalar persisted
field; duplicated, missing, collection, JSON, generated-infrastructure, or
ordinary mutable fields fail generation. A scope field can change only through
a generated transfer that locks the old and new tuple lanes, validates both
memberships, allocates the new position, and advances both versions atomically.
An ordinary edit or transition MUST NOT mutate it.

The entity declares transfer intent once as a semantic action. Its required
parameters MUST name exactly every changeable non-owner scope discriminator;
the owner remains inferred, and partial, extra, fixed-value, or ordinary-edit
scope mutation fails generation. The method name supplies domain vocabulary but
never hidden mechanics:

```dart
@Action()
Future<void> reparent({required LocalId<HierarchicalItem>? parentId});
```

Generation recognizes the parameter-to-field relationship, not the word
`reparent`. It emits target-scope validation, self-hierarchy cycle rejection,
optimistic rank allocation, rollback, one durable `transferInOrder` command,
and matching adapter protocol. The default placement is append in the target
scope; another placement requires explicit semantic intent supported by the
generated API. Feature code MUST NOT declare a rank, a second reorder action,
or hand-write remove-plus-add mechanics. One self-referential discriminator
generates cycle validation; multiple recursive ancestry axes are ambiguous and
fail generation instead of producing a partial runtime check.

Ordered transfer is an optional runtime capability, not part of every mutation
sink. Reusable runtimes expose it through a narrow capability such as
`OrderedTransferMutationSink`; ordinary sinks, fixtures, entities, and adapters
MUST NOT implement transfer methods they cannot use. Graph composition and
generation validate that every transfer-capable entity is attached to a
compatible sink before production mutation.

That inferred scope is emitted once as typed descriptor metadata and reused by
every local and remote adapter. Scope versions, serialization locks, rank
allocation, membership validation, and acknowledgements MUST be keyed by the
derived scope identity, never by entity type alone and never by independently
guessing a conventional `ownerId` field. Two relationship scopes owned by the
same account remain independent ordering lanes.

The generated PostgreSQL ordering index starts with every stored component of
that same scope tuple, followed by every equality field in the generated
membership predicate, rank, and stable identity. Ordinary ordered entities use
`deletedAt == null`; an inferred active relationship additionally uses
`active == true`. Local indexed planning, in-memory conformance adapters,
generated list filters, and every remote order query consume the same descriptor
conditions and MUST NOT guess membership independently. Owner-scoped and
relationship-scoped remote queries MUST NOT receive a
scope-free rank index; that shape degenerates into cross-tenant scans. An
account-scoped local database omits only its invariant authenticated-owner
component, but retains parent and relationship-source components because one
local graph may contain many such scopes. A complete identity-owned root omits
the prefix because no stored scope component exists. These adapter-specific
physical shapes are derived from the same tuple descriptor; they are not
separately configured.

Create, remove, and restore change canonical membership, so they MUST acquire
the same target-side scope lock as move and reorder and advance the same scope
version in the transaction that changes the row. Acknowledgements return a
typed list of `{scope, version}` receipts, never one ambiguous scalar. A normal
single-scope operation returns one receipt; transfer returns both source and
target receipts in the same acknowledgement. Duplicate receipts are invalid,
and clients retain the greatest observed value per scope rather than allowing
out-of-order receipts to regress it. The inferred scope fields are immutable to
ordinary patches; changing scope is an explicit remove/create or generated
transfer operation. This makes exact membership validation serializable against
concurrent collaboration without a second handwritten coordination path.

A transfer commits the discriminator change, destination rank, optional bounded
destination rebalance, local projection, and one queue item atomically. The
local planner and remote adapter both reserve source and target lanes in
deterministic key order. The local reservation covers indexed preparation
through registration of the durable mutation; inside one graph transaction its
optimistic overlay is the input to the next ordered operation. For a
recursive hierarchy it first acquires one generated hierarchy-partition lock,
normally derived from the immutable owner component, so concurrent transfers
between otherwise disjoint sibling lanes cannot both pass cycle validation. It
then revalidates source membership after locking, validates target access and
cycle freedom, applies the move, advances both scope versions, and returns both
typed receipts. A same-scope transfer is invalid; ordinary movement within a
scope uses the generated move operations instead.

The scope includes an exact generated membership predicate, including lifecycle
visibility and inferred active-link state. Every field that can cross this
predicate is a scope-versioned membership mutation: it acquires the same scope
lane, changes the row, advances the scope version, and returns a scope receipt
atomically. An arbitrary filtered view MUST NOT expose ordering mutation when
excluded members share the same scope. Ordering across a filter, page boundary,
or incomplete result is rejected unless the operation names explicit canonical
neighbors.

The generated canonical collection always owns neighbor-based
`moveBefore(id, neighborId)`, `moveAfter(id, neighborId)`, `prepend`, and
`append`. The default persistent representation is a scalable rank key so a
move normally changes one member rather than shifting every sibling. Rank
allocation is internal. An unbounded scope uses generated keyset boundary and
neighbor queries against the scope/rank/identity index. Exhaustion expands a
bounded window geometrically, rebalances only the smallest sufficient canonical
window, and records the repair plus create or move as one local transaction and
one semantic outcome. The planner merges transaction-local optimistic members
without turning the identity map into a second query engine. It never counts,
loads, or rewrites the complete unbounded scope. A complete-scope fallback is
permitted only when generation has proved bounded cardinality; its rare O(n)
cost is explicit in benchmarks.

Exact `reorder(ids)` and `move(id, toIndex:)` are generated only for a complete
bounded canonical collection. They reject duplicates and require the identities
to match the complete membership. The local projection and its one durable
semantic command commit atomically. The adapter serializes the scope, validates
the same membership, assigns ranks set-wise, and returns every changed canonical
member in one acknowledgement. Exact reorder is absent from the generated set,
descriptor decoder, and remote protocol for an unbounded entity; a UI drag over
a filtered or paged view emits one named-neighbor move instead. A dense integer
strategy is permitted only
through an explicit bounded single-writer or server-serialized override; it is
never inferred for an unbounded or independently writable scope.

For replicated ordered collections, push work records one semantic scope
operation with a scope base version, member identities, and one named anchor or
exact membership. It does not synchronize independent raw rank patches as
unrelated field edits. The generated default serializes operations per scope and
rebases `moveBefore` or `moveAfter` against the anchor's current position. A
missing anchor or scope mismatch is a typed conflict. Configuration is required
only to replace this deterministic default with another target-supported policy.

The generated set's ordinary `create(...)` appends by convention.
`createFirst(...)` exposes the same entity-derived parameters and inserts at the
canonical start. Both allocate the internal rank before the generated create,
so ordinary creation produces one local transaction and one durable create
intent rather than a create followed by a move. If boundary repair is required,
the repaired local members are durable bookkeeping on that same create outcome
and are not exposed to the remote adapter as caller-authored rank patches. The
generated implementation
shares one private creation primitive; repeated public parameter lists are
derived output, never repeated authored configuration. The created entity must
satisfy canonical membership or the transaction rolls back. Handwritten callers
MUST NOT repeat ordered lookup, duplicate checks, rank assignment, membership
validation, rebalance, conflict handling, or rollback.

### 6.5 Lifecycle and relationships

Declared lifecycle capabilities generate typed `remove`, `restore`, `archive`,
or equivalent methods. Generated relationship handles provide typed link,
unlink, movement, exact replacement, and inverse-list behavior only where the
resolved relationship contract makes each operation safe.

An entity action declared with `@Action(bulk: true)` generates a domain-named
query-owned action on every compatible generated `<Entity>List`. Standard
lifecycle capabilities generate the corresponding query-owned lifecycle
actions without another declaration. The query, not feature code, owns
canonical paging, identity retention, page transactions, cleanup, and the
`EntityBulkMutationResult(matched, changed)` result; `skipped` is derived from
those counts. An unbounded operation is atomic per generated page, not across
an unlimited result set. A business rule requiring global all-or-nothing
semantics MUST use a proved-bounded aggregate transaction; work requiring
restart recovery, external I/O, progress, or cancellation MUST use a durable
process. A caller MUST NOT call `useAll` merely to run one mutation per item.

A nullable self-reference may declare `hierarchy: true` only with cascade
deletion. Generation then exposes `removeHierarchy`, `restoreHierarchy`, and,
for `Archivable`, `setHierarchyArchived` on the entity set. Nodus validates the
root and hierarchy descriptor, rejects cycles, traverses the durable local
projection recursively in bounded pages, keeps identities only for the active
page, and orders parent/child lifecycle safely. Removal and archive are
children-first where required; restoration is parent-first and rejects a root
whose external parent is still deleted. For separately owned entities,
foreign-owned descendants count as skipped rather than receiving unauthorized
mutations. Feature code MUST NOT reconstruct descendants from a bounded
identity map or issue its own recursive lifecycle loop.

Relationship mutation MUST enforce source and target existence, ownership or
access, active-link reuse, dependency ordering, and atomic persistence without
N+1 reads. Handwritten link repositories and duplicated ID collections are
forbidden.

Composition is a first-class aggregate relationship, not a specially named
ordinary reference. For:

```dart
@Entity()
abstract class Document
    implements OwnedBy<Document, Account>, Component {}

@Entity()
abstract class Note implements OwnedBy<Note, Account> {
  @Composition()
  abstract final LocalId<Document> contentId;
}
```

generation MUST provide all of the following from those two declarations:

- a native non-null `content_id` UUID and typed `content` accessor;
- a restrictive foreign key so the component cannot disappear beneath the
  aggregate;
- a unique local and remote index plus graph-wide enforcement that one
  component identity belongs to only one aggregate instance, even when several
  aggregate types compose the same component type;
- same nominal owner, resolved sync mode, and sync-target validation;
- aggregate-derived relationship select/update authorization, finite audience
  publication, revocation, reference-child propagation, and dependency order;
- transaction-only component creation;
- physical orphan cleanup when the aggregate row is physically removed.

The aggregate's soft deletion does not destroy its component. Ordinary queries
hide the root, relationship access is revoked, and restoration re-exposes the
same component identity and child history. Physical retention cleanup removes
the component only after no generated composition reference remains, and the
component's ordinary cascading children then clean up through their declared
references. Feature services, adapters, and handwritten triggers MUST NOT
repeat this lifecycle.

A relationship entity with one ownership reference, one target reference, an
unconditional unique pair, and `Activatable` generates one inverse relationship
handle. Ambiguous ownership, extra required payload, a conditional unique pair,
or more than one candidate target fails inference and requires an explicit
relationship contract rather than a guessed handle.

Root-entity cardinality and relationship-collection cardinality are different
resolved facts. A normalized unique relationship can be proved bounded when
the complete link entity set or complete target entity set is bounded; a future
explicit relationship bound is valid only when storage and validation enforce
that limit. Current row count, page size, a UI convention, or a bounded owning
endpoint does not prove that an inverse collection is complete. The default is
unbounded. Exact `replace` is generated only for a proved-bounded relationship,
ordered or not; otherwise callers express incremental `link` and `unlink`
intent. Boundedness permits exact replacement but does not enable it by itself:
the API is absent unless local projection, one durable graph-scope command,
every configured writable adapter, acknowledgement, rollback, and conflict
handling implement the operation atomically. The compiler MUST NOT use the link
entity's root cardinality as a substitute for a separately resolved
relationship fact without recording the actual proof.

The recorded relationship-cardinality resolution is exactly one of:

- `boundedByLinkEntity` when the complete link entity set is bounded;
- `boundedByTargetEntity` when link uniqueness and a complete bounded target
  set prove the inverse collection bounded;
- `unboundedByDefault` otherwise.

The ordering of these proofs is deterministic: link-entity proof wins when both
bounded proofs apply. A bounded source endpoint is never a completeness proof
for its outgoing relationship collection.

The generated handle owns the lifecycle semantics:

- `link(targetId)` is idempotent for an active pair;
- an absent pair creates one active row and, when ordered, appends it;
- an inactive pair reuses the same identity. Its previous opaque rank is
  preserved by default, so reactivation is one membership mutation and does
  not invent an unrequested move;
- `unlink(targetId)` deactivates the row, preserves its identity and opaque rank
  for deterministic reactivation, and never compacts siblings;
- source and target existence, access, uniqueness, persistence, queue intent,
  rollback, and precise query invalidation remain generated mechanics.

Callers that want a different position after reactivation issue one explicit
neighbor move. The API does not hide two remotely non-atomic operations behind
a misleading `link` call.

When that relationship also implements `Ordered`, the handle infers one ordered
scope per source. Its list view defaults to active, non-deleted rows in rank
order; `moveFirst`, `moveLast`, `moveBefore`, and `moveAfter` identify semantic
positions without exposing a rank. Neighbor moves remain available at every
cardinality. Exact `reorder` and exact ordered `replace` exist only when the
resolved relationship collection is bounded and the generated operation proves
it owns the complete active target set. One exact relationship operation MUST
commit its local membership/order projection and one durable semantic command
atomically; it is not an N-item loop disguised as an atomic API. Exact
operations are absent for an unbounded relationship; callers stream explicit
`link`/`unlink` intent and use canonical neighbors rather than loading an
unlimited scope. Feature code MUST NOT repeat link lookup, reactivation, rank
allocation, membership repair, or rollback.

### 6.6 Named source creation and entity-owned processes

A process is exposed through the domain object that owns its outcome, not a
public generic workflow registry. The generated receiver follows the result:

- a source producing one entity is a named constructor on its generated set,
  such as `await entityGraph.<entities>.fromFile(source)`;
- a source inserted into one canonical relationship or ordered scope is a named
  operation on that generated collection, which derives ownership,
  relationship, and order membership from the receiver;
- a process changing an existing entity is an awaited semantic entity action;
- a process enforcing a multi-entity invariant is rooted at the owning
  aggregate transaction;
- a process is modeled as its own ordinary entity only when its identity,
  progress, cancellation, retry, audit history, failure, or zero/many-result
  lifecycle is domain-visible independently of the produced entities.

The conceptual named-constructor vocabulary belongs to the entity. Until stable
Dart augmentation can add static members without duplicate declarations, the
canonical generated syntax remains the graph-compatible set receiver:

```dart
final document = await entityGraph.documents.fromFile(file);
await document.replaceFromFile(replacement);
```

The named creation intent is declared adjacent to the entity through a typed
generator-recognized declaration. Generation derives its public name from the
typed source and declared semantic intent when unambiguous, and requires a name
override only for a collision or genuine vocabulary choice. A direct field-wise
source mapping is inferred from the semantic codec and field names. An unusual
mapping or decision names one handwritten pure typed mapper/guard; it does not
repeat IDs, ownership, defaults, persistence, queueing, progress plumbing,
adapter selection, retry, or serialization.

If source interpretation is deterministic and local, the named constructor
parses, validates, and commits the produced entity or entities plus any sync
intent in one local transaction. Its future returns the locally durable entity
result. If work continues remotely, the returned entity MUST already satisfy a
declared valid lifecycle state such as queued, uploading, processing, ready, or
failed. The local commit atomically stores that state and its durable idempotent
process intent; completion, progress, retry, cancellation, and typed failure
update the same stable identity through Drift. The initial future still means
local durability, never remote completion.

When a produced entity cannot truthfully exist before completion, or one source
may yield zero or many entities, generation MUST NOT manufacture a partially
valid result. A real process entity owns the observable lifecycle and exposes
generated relationships to its eventual results. Purely mechanical process
records remain private runtime state and MUST NOT leak as a second application
state model.

External I/O never runs while a local database transaction is open. The local
transaction records validated intent; an internal durable process lane invokes
the typed external capability afterward, records idempotent outcomes, and
publishes them through Drift and the same identities. Immediate irreversible
confirmation uses the narrow online capability rule from section 17. None of
these mechanics justify an import repository, command handler, workflow
service, provider, or feature-selected adapter.

Purely mechanical entity-triggered work is declared adjacent to its source:

```dart
@EntityProcess(
  name: 'applyOutcomes',
  source: WorkSource(Decision, fields: [#status, #respondedAt]),
)
abstract final class ApplyOutcomesProcessDeclaration {}
```

`WorkSource` names one graph entity and, optionally, the persisted fields that
can trigger the work; an empty field list means every projection change. The
compiler validates the source, field symbols, and unique lower-camel name.
Generation exposes one typed graph installer whose handler receives the stable
source identity and a `GeneratedDurableWorkContext` containing the operation ID
and attempt. Nodus owns coalescing, durable registration, leases, restart
recovery, retry/backoff, scheduling, and page cleanup. The handler owns only
the irreducible domain decision and applies outcomes through generated entity,
relationship, aggregate, or query-owned actions. A successful checkpoint MUST
be committed with its outcome when replay could otherwise duplicate behavior.

## 7. Collections, queries, and identity

One persisted entity ID maps to exactly one live object instance per account
entity graph. Materialization, local writes, pull merges, query membership
changes, and acknowledgements update that same identity.

Two identity-owned entity types MAY declare `coIdentityWith: [Other]` only when
their distinct domain identities deliberately use the same external authority
UUID. The compiler requires both types to be graph entities with
`Ownership.identity` and the same synchronization mode and target, then emits
named nominal `LocalId` conversions in both directions. Co-identity does not
merge tables, entities, lifecycle, fields, or permissions. Raw `.value`
round-trips, a generic ID cast, or an undeclared conversion remain forbidden.

Generated sets provide:

- synchronous `byId`, tombstone-filtered `byPresentId`, and throwing
  `requirePresent` for safely bounded complete sets;
- lease-scoped `loadById` for advanced unbounded-set lifetime control and
  canonical `useById(id, action)` for recovery/inspection; ordinary domain work
  uses tombstone-filtered `loadPresentById` or `usePresentById`;
- an unbounded set's generated `lookup(id)` returns an `EntityLookup<E>`
  whose lease is owned by `useObservedEntityLookup` for the widget lifetime;
- synchronous generated `by...` lookup for a bounded complete set and a
  generated `<Entity>Lookup.by...` lease for an unbounded set, only when an
  unconditional unique index with non-null key fields proves singularity;
- generated `createOrGetBy...` on a bounded complete set for the same safe
  unconditional unique indexes, including owner-scoped and compound keys;
- typed query acquisition, predicates, ordering, paging, and refresh;
- stable observation of identity and relevant fields.

`useById` retains one demand-loaded identity for exactly the callback duration
and throws the typed runtime `EntityNotFoundException` when it is absent.
Its callback uses the public `LeaseAction<E, R>` alias so generated entity
libraries support synchronous and asynchronous work without requiring a
redundant `dart:async` import in every domain declaration.
Feature code MUST NOT repeat lookup-lease plumbing, return the entity beyond
that callback, or translate absence inside a repository/access façade. Bounded
sets continue to expose synchronous `byId` and `require` because declaration
guarantees that their complete identity map is already retained.

`createOrGetBy...` checks the complete bounded identity map and otherwise
delegates to the one generated durable `create` path. Optimistic registration
happens before that create first yields, so concurrent callers in one entity
graph converge on the registered identity. Finding an existing identity never
overwrites its non-key fields. Generation MUST NOT expose this convenience for
unbounded sets, conditional indexes, nullable unique keys, or indexes whose
fields cannot be supplied through the canonical create contract.

A generated `<Entity>Lookup` represents exactly zero or one retained stable
identity. Its constructor name and typed parameters derive from the unique key,
for example `DailyPlanLookup.byOwnerAndPlanDate(entityGraph, ownerId, date)`.
It requests one indexed row and exposes no caller-supplied predicate, ordering,
or page size: adding any of those would weaken or duplicate the exact declared
selection. Imperative code uses `lookup.use((entity) async { ... })`, which
releases the lease on success, absence, and failure. Flutter uses
`useEntityLookup`, which owns the lease for exactly the widget lifetime and
observes the returned stable MobX identity directly. Returning a detached
snapshot, retaining the entity after disposal, or hiding this lifetime in a
provider is forbidden.

An exact unique key MUST NOT also generate a one-item `<Entity>List`
constructor. `List` means zero-to-many and would duplicate the same predicate
while inviting `first`, page-size, and disposal boilerplate. Nullable unique
keys, conditional/partial indexes, unordered keys without one exact symmetric
predicate, and any other ambiguous uniqueness do not generate a singular
lookup until their semantics are declared safely. If durable storage ever
returns more than one row for a generated lookup, the runtime fails as a schema
or descriptor inconsistency rather than choosing one arbitrarily.

A partial unique index generates a singular API only when the declaration opts
into an exact lookup and its complete predicate is representable in Dart,
Drift, and PostgreSQL. `activeOnly` is the canonical soft-deletion predicate;
an enum-backed `IndexCondition.oneOf` is the canonical finite condition. The
same predicate MUST constrain the in-memory computed index, acquired lookup,
local unique validation, schema index, remote validation, and synchronization.
Unsupported predicate combinations fail compilation rather than weakening a
selection or silently choosing the first row. A conditional lookup exposes no
caller predicate because the safe condition is part of its generated contract.

Existence and ordered-first intent are not uniqueness claims. `EntityExistence`
loads at most one row and returns a Boolean; `EntityFirst` requires explicit
ordering and returns the deterministic first identity. Neither walks an
unbounded set or exposes `pageSize: 1` spelling to feature code.

Generated immutable `<Entity>Query` values describe selections for ownership,
references, participants, unique indexes, safe compound indexes, and inverse
relationships. Equivalent values have structural equality and share cached work.
Callers MAY add typed `where` and `orderBy` clauses but MUST NOT repeat a
generated base predicate in a manual query function.

A generated `<Entity>List` is the live acquired result of one query. Named
constructors such as `<Entity>List.forOwner(entityGraph, ownerId)` combine the
generated query with acquisition for concise domain use. Every list owns a
precise lease and exposes deterministic `dispose()`; application scopes, generated
Flutter hooks, or explicit `try/finally` own that lifetime. Constructors MUST
NOT hide a permanent subscription or make callers guess whether disposal is
required.

For a separately owned entity, `<Entity>List.owned(entityGraph)` derives the
authenticated owner from the graph and MUST NOT ask the caller to repeat its
ID. `forOwner(entityGraph, ownerId)` is generated only when authorization and
the declared participant relationships permit selecting another owner; its ID
then represents real query intent rather than duplicated context.

Cardinality is explicit:

- a bounded set may preload its complete readable projection and evaluate
  bounded queries in memory;
- an unbounded set is Drift-backed, paginated, and never exposes an unrestricted
  synchronous `all` collection;
- imperative unbounded reads use leases so identities cannot be evicted during
  work;
- equivalent query specifications share cached work while each list consumer
  owns a precise lease;
- every stream, reaction, query, and identity lease has deterministic cleanup.

`useAll` is an explicit exhaustive, paged, lease-scoped read. It is allowed
only when the returned business value genuinely depends on the complete typed
selection—for example an ID-bounded relationship join, a date-bounded
calculation, or a one-shot projection snapshot. It MUST remain read-only and
MUST NOT create a retained cache, provider mirror, or mutation loop. A broad
whole-account exhaustive read is a performance review signal: keep it only
when the product result is intentionally complete and measured scale permits
it; otherwise move the calculation to paging, a secondary projection, or a
durable process. Conformance inventory reports these sites for review even when
their lease and paging behavior is architecturally valid.

When several exhaustive reads form one result, record `.useAll` runs two to
six `EntityList` or `LocalEntityQuery` values concurrently and disposes every
lease on all exits. Heterogeneous non-query futures use record `.waitAll`,
which preserves each static result type without `Future.wait<Object?>`, list
positions, or casts. These helpers own mechanics only; they do not make an
otherwise unbounded business read acceptable.

Collections owned by the runtime are read-only outside it. Mutable backing
collections never escape.

## 8. State management and Flutter

MobX is the exclusive state and observation system for generated entity and
query state. It owns:

- generated observable entity fields;
- stable collection membership and ordering;
- typed loading, error, empty, stale, and synchronization states;
- small observable runtime status surfaces.

Flutter Hooks or local widget state owns only widget-lifetime resources and
ephemeral interaction state, including controllers, focus nodes, animations,
hover, expansion, temporary form presentation, debounce, and scroll lifecycle.

An entity value change automatically updates the stable identity and rebuilds
only observers that read the changed fields; membership or rank changes update
only lists that contain that entity and consumers that observe their membership
or ordering. An entity declaration change regenerates typed fields, validation,
queries, and optional form bindings. It does not invent product layout, choose
which screen shows a new field, or replace handwritten presentation decisions.

Application composition mechanisms MAY inject dependencies and coordinate
account/session lifecycle, platform or external-service state, and workflows
whose state is not derived from an entity or query. They MUST NOT own, cache,
republish, aggregate, or synchronize generated entity identities, persisted
fields, query membership or ordering, or generated
loading/error/empty/stale/sync state. A provider, notifier, view model, stream
projection, or other container that mirrors any of that state is migration debt
and MUST be removed. MobX entities and queries are observed directly with the
narrowest `Observer` scope. Widgets must not copy persisted fields into
`useState`, a hook, or another controller.

Typed inherited scopes and constructor injection are the preferred dependency
composition surfaces. An `AccountEntityGraphScope` publishes account
entity-graph lifecycle, not individual entity changes. Entity mutation MUST NOT
rebuild the application scope or router. External capabilities are injected by
interface; service locators and global mutable registries are forbidden.

For a managed Flutter graph, generation MUST also emit the application-named
`<Application>EntityGraphScope` and `BuildContext` accessors for strict state,
optional readiness, and session access. Application code uses those typed
names; it MUST NOT repeat the graph and account type arguments at every widget.
The wrapper adds no state authority and delegates to the generic account scope.

Scope access is explicit: strict state/session accessors fail when composition
is missing, while an optional readiness accessor returns null when the scope is
absent or not ready and subscribes only to lifecycle transitions. An API named
as optional MUST NOT throw merely because no scope exists.

Reactions and subscriptions MUST observe only state used by their consumer.
Global invalidation and feature-wide refresh registries are forbidden. One
database query, stream, or remote subscription per rendered row is forbidden;
one narrow MobX reaction per visible row is permitted and normally preferred to
rebuilding an entire list. Virtualization bounds active row reactions, the list
reaction observes membership and order, and each row reaction observes only the
fields it renders.

Generated query hooks own their acquired list, lookup, existence, or first-row
lease for exactly the widget lifetime. Observed wrappers fold the sealed query
state once: initial loading, empty, ready data, stale/refreshing data, failure
with or without retained data, pagination, and disposal. UI code MUST use that
typed fold instead of repeating state switches or converting it into provider
state. A bounded synchronous exact lookup uses a narrow MobX observation hook
over the generated computed index and retains no query lease.

When one widget consumes several independent observed queries,
`ObservedEntityQueryGroup` folds only their shared lifecycle: initial loading,
refreshing, blocking failure, stale-data refresh failure, and refresh-all. Each
concrete query remains the typed source of its own items. A failure is blocking
only when that query has no retained items; a refresh failure with stale items
is exposed separately. Widgets MUST NOT replace this fold with local helper
switches, a detached view model, or an untyped combined entity collection.

## 9. Local persistence

Drift is the mandatory durable source observed by the application. Every
ordinary entity create, edit, transition/action, lifecycle change, and
relationship mutation, named source constructor, and durable entity-owned
process transition writes locally first. Feature and domain code MUST NOT choose
between local and remote persistence, call a sync or process adapter directly,
or bypass Drift for an ordinary entity mutation.

Every entity derives or overrides exactly one synchronization mode:

- `localOnly`: Drift is the only durable authority and no sync work exists;
- `replicated`: local mutations are allowed, the remote target supplies a
  canonical version, and ordered push plus pull converge both sides;
- `imported`: the remote target is authoritative, ordered pull updates Drift,
  and ordinary local mutation APIs are not generated;
- `exported`: Drift is authoritative and a durable idempotent outbox projects
  local changes outward without remote base, pull, or rebase semantics.

A graph default target implies `replicated` for ordinary entities. Without a
graph default or entity target, the safe inferred mode is `localOnly`. Selecting
an entity target without an explicit mode implies `replicated`. `imported` and
`exported` are never inferred because they change mutation and authority
semantics.

A replicated entity stores conceptually:

```text
accepted remote base
    + ordered pending local operations
    = visible optimistic projection
```

The replicated accepted base is stored explicitly and is not reconstructed from
dirty flags. Pending operations remain durable and ordered across restart, lost
responses, rebases, rejection, and account switching. Imported entities store
the latest accepted remote projection and cursor state but no local push overlay.
Exported entities store accepted local state and pending outbox receipts but no
remote base.

For a replicated or exported entity, the entity mutation and its target-aware
queue intent commit in one database transaction. There is no interval in which
visible durable state exists without recoverable outbound work, or queued work
exists without its visible projection. A local-only mutation commits the
projection through the same transaction coordinator without manufacturing sync
work. Imported entities reject ordinary local mutation before any optimistic
projection is exposed.

One account entity graph owns one Drift database connection/coordinator.
Background work uses the same owner or an explicit supported bridge.
Independent writers to the same file are forbidden because they break
observation and transaction ordering.

The generated `EntityGraphDefinition` is the source of truth for entity-owned
local schema objects. Mappings, indexes, constraints, and ordinary migration
proposals are generated by diffing the previous reviewed definition. Local
schema version, each target protocol version, descriptor fingerprint, and live
session epoch are distinct typed values and MUST NOT share one ambiguous
`schemaVersion`.

The previous reviewed descriptor manifest is checked in. Generation proposes
deterministic monotonic local and per-target protocol version changes from that
manifest; entity annotations and package setup do not repeat those numbers. A reviewer
accepts the generated migration and new manifest together. Runtime session
epochs are allocated at open time and never enter schema or protocol metadata.

Migration output is reviewed before application, especially for destructive or
semantic changes. Data backfills and external-resource changes remain explicit
reviewed migrations because they cannot be inferred safely.

Constraint-only Drift changes generate `TableMigration` rebuilds. When existing
rows are already known to satisfy the new semantic constraint, the application
uses `NodusMigrationPlan.acknowledgeGenerated()` as the explicit reviewed
decision. It MUST NOT add an empty manual callback merely to satisfy the
semantic-change guard; a real backfill or transformation uses the manual or
augmented plan instead.

A coordinated rewrite MAY reset generated local migration history only when
the deployment owner has declared every existing local store disposable and a
new physical store generation prevents old binaries from opening the new file.
The reset is an explicit generator operation: it deletes only generated local
schema snapshots, steps, and migration-test artifacts, then records the current
schema as baseline version one. It MUST NOT delete or rewrite remote migration
history, authoritative business data, or a compatible local store. Ordinary
compatible evolution always appends a generated migration.

Every rollout selects one reviewed evolution policy in the generated deployment
manifest:

- **compatible** keeps already released clients and durable work valid. A
  storage or protocol migration is incomplete if it converts only canonical
  rows: it also converts accepted bases, optimistic projections, tombstones,
  pending operations, idempotency receipts, and unread change-log records;
- **coordinated rewrite** rejects the previous descriptor/protocol generation,
  migrates authoritative business data with an explicit deterministic script,
  and recreates derived local stores, caches, cursors, receipts, and generated
  clients. It MUST NOT accumulate compatibility aliases or upcasters. Before
  cutover, old pending business intent is drained, exported into the data
  migration, or explicitly declared disposable by the deployment owner.

Compatibility is therefore a rollout decision, not permanent complexity hidden
inside an entity capability. Generated infrastructure fields never assume a
historical application field name. Under compatible evolution, an explicit
reviewed field or semantic-operation mapping preserves legacy intent. Under a
coordinated rewrite, unsupported generations fail clearly instead of being
guessed. Local and remote migrations use the same deterministic ordering,
tie-break, and scope rules so imported data cannot silently reorder.

An operation whose correctness requires immediate remote confirmation, such as
a payment or irreversible third-party side effect, is not ordinary entity
persistence. Its public API still belongs to the entity, generated set, owning
aggregate, or explicit process entity, but its implementation uses a narrow
typed online capability or a durable intent/outcome process. It MUST distinguish
"intent durably accepted locally" from "remote outcome confirmed" in its return
type and observable state and MUST NOT weaken the local-first entity contract.

## 10. Synchronization

One account entity graph owns one physical durable work store and scheduler for
synchronization, entity-owned external processes, and secondary projections.
Work is logically partitioned by typed work kind, target, and direction into
independent lanes with separate leases, concurrency limits, backoff, and
fairness. A failing or rate-limited sync target, process capability, or
projection destination MUST NOT block another lane. Feature code does not
select adapters, enqueue, serialize, retry, debounce, pull, project, or
invalidate manually. This section defines the synchronization lanes; sections
6.6 and 10.1 define the additional process and projection contracts using the
same durable scheduler mechanics.

### 10.1 Sync targets and adapter composition

The package setup owns stable sync-target identifiers and one default. The
compiler generates the application target enum and typed adapter registry;
authors do not declare either. Target names SHOULD identify the actual service
or protocol when that identity is intentionally part of the durable routing
contract, for example `supabase`, `convex`, or a precise external API name.
Ambiguous names such as `primary` or `externalApi` SHOULD be avoided unless that
abstraction is itself deliberate and stable.

An entity inherits the graph default target and therefore `replicated` mode. In
a graph without a default, an entity without a target is `localOnly`; selecting
an entity target implies `replicated` unless `imported` or `exported` is
explicit. If Supabase is the default, ordinary replicated entities MUST NOT
repeat `supabase` individually. A non-local entity in a graph without a default
must select a target explicitly or generation fails.

The ordinary single-target setup accepts any stable lower-snake-case target
name. A built-in target looks like:

```sh
dart run nodus init --target supabase
```

```dart
@Entity()
abstract class DefaultEntity {} // Inherits replicated + supabase.

@Entity(sync: SyncMode.localOnly)
abstract class DeviceOnlyEntity {}
```

Multiple targets and per-entity non-default routing are irreducible package
configuration in `nodus.yaml`. Generation validates those names and emits the
typed enum; domain declarations retain only synchronization semantics such as
`imported`, `exported`, or `localOnly`. Renaming a target after it has durable
work requires an explicit stable wire-name override and reviewed routing
migration.

The canonical graph freezes one `SyncBindingDefinition` per entity and
one erased `SyncTargetId` per used generated enum value. The erased target
records the exact generated package-enum type identity plus its stable wire
name; authors never write either string. Graph construction rejects
missing/duplicate bindings, local-only bindings with a target, non-local
bindings without one, and malformed wire identities before a session can open.
This metadata is the sole input to generated adapter groups and durable lane
routing.

An entity declaration records only its generated target identifier; it MUST NOT
import or instantiate `SupabaseSyncAdapter`, `ConvexSyncAdapter`, or another
transport implementation. A built-in target factory accepts its client:

```dart
final entityGraph = await ApplicationEntityGraph.openSupabase(
  accountId: accountId,
  client: supabaseClient,
);
```

Generation MUST derive the target-to-entity descriptor groups and the typed
registry slots. A custom single target uses the same managed opening path:

```dart
final class RestApiAdapter implements PushPullSyncAdapter {
  RestApiAdapter({required this.client, required this.definition});

  final RestApiClient client;
  @override
  final EntityGraphDefinition definition;

  @override
  Future<PushResult> push(PushSyncWorkItem item) => client.push(item);

  @override
  Future<PullResult> pull({required ServerSequence afterSequence}) =>
      client.pull(afterSequence: afterSequence);
}

final entityGraph = await ApplicationEntityGraph.openRestApi(
  accountId: accountId,
  connector: (context) => RestApiAdapter(
    client: restApiClient,
    definition: context.definition,
  ),
);
```

The adapter translates only the generic Nodus synchronization protocol; it does
not declare application entities, routes, tables, or target routing. A reusable
connector package MAY expose the callback already bound to its client. Adding a
target MUST NOT require editing the Nodus runtime or generator. Multi-target
applications pass one capability-typed connector per generated target to
`openWithConnectors(...)`; they do not construct the generated registry or an
entity-to-adapter map. Opening an entity graph MUST fail before local storage is
opened when a target is missing, duplicated, built for a stale descriptor
group, or lacks a capability required by its entities.

When the resolved graph uses no synchronization target, generation emits a
constant empty adapter registry and graph opening defaults to it. Application
code MUST NOT pass an empty bundle merely to satisfy a signature. The first
resolved non-local binding makes adapter composition explicit and required.

The generated slot type is the smallest directional capability proved by its
bindings: `PushSyncAdapter`, `PullSyncAdapter`, or `PushPullSyncAdapter`.
Push-only and pull-only contracts expose only their own operation; they are not
markers layered over an interface that secretly requires both methods. Every
`SyncAdapter` carries the exact generated target descriptor subgraph, and
registry binding rejects an over-broad full graph, stale schema, different
definition, or missing directional capability before the local database is
published. No raw erased backend bypass exists.

A `SyncAdapter` declares compile-time capabilities. A replicated binding
requires idempotent version-checked push, canonical acknowledgement,
authoritative entity or scope versions, ordered cursor recovery, and typed
conflict/rejection results. An imported binding requires ordered cursor recovery
and canonical snapshots. Ordered recovery includes deletions as tombstones. If
change history has finite retention, the adapter must expose typed cursor
expiration plus a bounded canonical snapshot recovery path. An exported binding
requires an idempotent operation receipt; a destination that cannot deduplicate
stable operation IDs is not a safe entity-sync target and instead uses an
explicitly at-least-once external integration contract.

Remote-change signals and demand snapshot fetches MAY improve latency, but
signals never replace ordered recovery. Snapshot recovery is mandatory when the
ordered log is not retained indefinitely. `SnapshotSyncAdapter` extends
`SyncAdapter`, so even this optional read path carries and validates the exact
generated target subgraph. No adapter may silently emulate an unsupported
capability with an unbounded fetch, polling fan-out, timestamp ordering, or loss
of conflict semantics. Generated adapter conformance suites verify every
capability claimed by a binding.

Each replicated or imported entity has one authoritative remote target. Each
exported entity has one primary projection destination. Secondary analytics,
search indexing, webhook, or additional export destinations consume generated
outbox events or projections; they MUST NOT become additional writable entity
authorities.

Authority and projection roles are distinct generated contracts:

```text
replica authority
    owns canonical versions, access decisions, conflict/rejection results,
    ordered recovery, and collaborative convergence

import source
    owns canonical imported state and ordered recovery; local ordinary writes
    are absent

export destination
    receives the authoritative local entity projection with idempotent receipts

secondary projection
    receives a derived search, analytics, calendar, notification, webhook, or
    materialized-view representation and can never mutate the source entity
```

One entity MAY have several secondary projections. Their typed declarations
name real destination intent once; generation infers source fields, semantic
codecs, operation IDs, dependency order, routing, and ordinary full-record
mapping. An explicit typed mapper or field selection is required only when the
projection intentionally changes or narrows semantics. Projection outbox work
commits atomically with the authoritative local mutation, has independent
destination lanes and receipts, and may be rebuilt deterministically from its
declared source when the destination contract permits it. Projection failure
never rolls back authoritative entity state.

A mechanical multi-source projection is declared once beside its domain
contract:

```dart
@SecondaryProjection(
  name: 'searchIndex',
  sources: [
    WorkSource(Document, fields: [#title, #updatedAt]),
    WorkSource(Tag),
  ],
)
abstract final class SearchIndexProjectionDeclaration {}
```

Generation emits one typed installer and a domain-named `run...Now` trigger.
All declared sources coalesce into an independent durable projection lane with
stable operation IDs, leases, restart recovery, and retry/backoff. The supplied
handler maps canonical state to the external destination and MUST rethrow a
retryable destination failure; it does not subscribe, debounce, checkpoint,
schedule, invalidate, or maintain its own outbox. Manual execution enters the
same lane and semantics rather than bypassing durability.

Application code MUST NOT represent a secondary destination by cloning the
entity, adding another writable sync target, or maintaining a handwritten
fan-out service. A search index, warehouse, calendar, notification service, or
webhook becomes an authority only if the domain explicitly declares its data
imported from that system; it cannot be both a projection sink and a competing
authority accidentally.

Generic fan-out to two independently writable remote authorities is forbidden.
If a CRDT or other genuine multi-master system supplies deterministic merge,
causal recovery, authorization, and canonical acknowledgement, one specialized
`SyncAdapter` encapsulates that complete protocol and presents it to the
entity graph as one authority contract. The entity graph never attempts to
merge unrelated Supabase, Convex, or external-service answers by timestamp or
best effort.

The stable target identifier is persisted with queued work and diagnostics so a
restart cannot change its destination accidentally. Renaming or reassigning a
target with pending work is a reviewed protocol/data migration, never a runtime
configuration accident.

Every durable queue row has a non-null generated `sync_target` routing column.
Ready and state-patch coalescing indexes begin with that column, and a worker
may claim only rows for its own generated target identity. The cursor store is
keyed by `sync_target`, not by a singleton row ID. Graph creation inserts one
cursor for every pull-capable target; `localOnly` and export-only targets do not
receive meaningless pull cursors. Migrating an older implicit single-target
store requires one explicit legacy-target choice, preserves queued operations
and its cursor, and rebuilds the generated routing indexes. Falling back to a
default adapter for missing or unknown durable routing is forbidden.

The scheduler indexes work by kind, target, direction, eligibility time, and
dependency. It claims bounded batches fairly across ready lanes. Dependencies
inside one target use generated entity/relationship ordering; cross-target
dependencies require the explicit saga contract from section 10.4.

### 10.2 Outbound flow

```text
generated create/draft/transition/action/transaction
    -> optimistic IdentityMap projection
    -> atomic Drift projection + durable target-aware push work
    -> target lane claims a bounded batch with a lease
    -> generated sync router selects the declared target adapter
    -> idempotent version-checked remote operation
    -> canonical acknowledgement of every record changed by the operation
    -> accepted-base replacement and pending-overlay rebase
```

The final two steps apply to replicated entities. An exported entity records an
idempotent destination receipt and removes acknowledged outbox work without
creating an accepted remote base. Imported and local-only entities do not
produce ordinary outbound entity work.

State patches MAY coalesce only when the final visible state and conflict
semantics are unchanged. Semantic actions, creates required by dependants, and
ordered lifecycle events do not coalesce across meaning boundaries.

Every outbound operation has a stable operation ID, nominal entity identity,
target protocol version, sync-target identifier, and typed payload. Replicated
operations additionally carry an authoritative base entity or scope version;
exported operations carry a stable projection version or receipt key. Retry is
idempotent. Device clocks never determine cross-device ordering.

A semantic operation MAY change several records, but still owns one operation
ID and one queue item. Its local-only optimistic state patches are durable for
rollback/rebase and MUST NOT leak into the adapter payload. Its acknowledgement
contains one primary record plus a duplicate-free ordered set of related
canonical records carrying the same receipt. Drift merges all acknowledged
records in one transaction and only then publishes precise identity/query
changes. Returning only the command target after a server-side sibling
rebalance is a protocol violation.

### 10.3 Inbound flow

```text
target adapter signal, foreground, reconnect, or periodic recovery
    -> coalesced durable pull request for that target
    -> ordered remote change-log read after that target's local cursor
    -> descriptor validation and policy-allowed upcast
    -> atomic Drift base/projection/target-cursor update
    -> same IdentityMap objects and exact queries react
```

This flow applies only to replicated and imported entities. Realtime is a
latency hint, not the correctness mechanism. Signals may be
duplicated, delayed, or lost. An ordered durable change log and cursor provide
recovery. Every pull-capable target lane owns an independent durable cursor,
retry state, signal subscription, and diagnostics. Resources are shared per
target, not allocated per entity.

Cursor expiration triggers the adapter's canonical snapshot recovery in bounded
pages. The runtime atomically replaces accepted bases and the cursor, preserves
local-only state, and rebases replicated pending operations before publishing
the resulting IdentityMap changes. It never clears the local database and hopes
realtime events reconstruct correctness.

Remote changes are written to Drift before the IdentityMap publishes them.
No feature stream writes directly into entities, and no global invalidation is
needed.

### 10.4 Cross-target constraints

The local entity graph may commit a transaction containing entities routed to
different targets, but it MUST NOT claim remote atomicity across independent
services. Remote foreign keys, ownership/access propagation, collaboration
joins, and server-atomic invariants normally require all participating entities
to share one target.

A cross-target relationship requires an explicit loose-reference, saga, or
integration-event contract that defines ordering, compensation, unavailable
targets, and partial acceptance. Generation MUST reject an ordinary remotely
constrained relationship that cannot be implemented by the selected adapters.

### 10.5 Conflicts and rejection

Replicated conflict detection uses authoritative server or ordered-scope
versions and accepted base, not timestamps. The runtime rebases remaining
pending operations over a new canonical base according to generated field,
transition, action, and ordering policies.

Conflict policies MUST be deterministic, typed, and declared once. Automatic
resolution is allowed only where field semantics make it safe. Rejection must
restore or rebase the visible projection without losing the accepted base and
must expose typed diagnostic state.

Imported entities replace their accepted projection from ordered remote input
and have no local-write conflict policy. Export rejection preserves the
authoritative local state, retains or dead-letters the outbox operation by typed
policy, and exposes diagnostics; it never rolls local entity state back merely
because a projection destination rejected it.

## 11. Remote schema, protocol, and security

For a schema-capable SQL target such as Supabase, the target-specific descriptor
group deterministically emits entity-owned remote schema:

- tables, columns, SQL types, defaults, checks, indexes, and foreign keys;
- synchronization metadata and ordered change capture;
- mode-required idempotent push and ordered pull functions;
- payload validation and compatible-policy protocol upcasting;
- RLS policies, grants, and required helper predicates when authorization is
  derivable without ambiguity;
- publication metadata for collaboration-related changes.

A built-in target emitter consumes only its exact generated target subgraph; it
MUST NOT receive the full local graph and filter it ad hoc. Exact conventional
target identities select built-in emitters when unambiguous—for example,
`supabase` selects the Supabase emitter. A custom or ambiguous target supplies
one explicit target-level emitter binding, never per-entity schema config.
Tables and outbound functions include replicated, imported, or exported
entities owned by that target as their modes require, while an ordered pull
contract includes only replicated and imported entity types. Export-only and
local-only entities MUST NOT appear as inbound pull cases.

A non-SQL adapter consumes the same generated entity descriptors, semantic codec
definitions, operation IDs, target protocol version, conflict policies, and
target definition. It MAY supply a target-specific schema or provisioning
emitter, but application code MUST NOT duplicate entity DTOs or serialization
to accommodate it.

Generated remote schema is a reviewed source artifact for entity-owned objects,
not SQL executed implicitly during application startup. The target emitter diffs
the previous reviewed descriptor manifest and proposes migrations. Destructive
changes, data backfills, external resources, and authorization that cannot be
derived safely require an explicit reviewed extension. Ambiguous authorization
fails generation rather than producing permissive RLS.

Authenticated identity is inferred by the database wherever possible; clients
do not repeat trusted owner identity in writable payloads. Generated functions
use explicit search paths, qualified objects, least privilege, and no default
`PUBLIC` execution.

Every generated table in an exposed SQL schema enables row-level security,
including internal change logs, receipts, and ordering metadata. Revoking API
role privileges remains required but is not a substitute for RLS defense in
depth.

Migration acceptance verifies effective privileges with ordinary database
roles after replay; reviewing declarative `GRANT`/`REVOKE` text alone is not
sufficient. If a target diff engine omits function or table ACL changes, the
reviewed migration MUST add an explicit least-privilege finalization step before
deployment. Anonymous execution of generated mutation, trigger, capture,
publication, composition, or upcast helpers is a release blocker. Only the
declared authenticated adapter entry points and predicates required by RLS may
remain executable by application roles.

Ownership, collaboration, and access propagation are declared as typed graph
relationships. The generator validates access cycles and operation-specific
capabilities within each target. A relationship must not grant broader access
than its declared source and target policies and must not assume RLS or foreign
keys can span independent services.

Direct table writes that bypass optimistic concurrency, idempotency, capture,
or authorization are forbidden for ordinary clients.

## 12. Serialization and API boundaries

One semantic codec definition is generated per declared type. From it, target
emitters derive type-safe local storage, wire protocol, diagnostics, and
external-input codecs where semantics match. The actual local and remote
representations MAY differ; changing a wire representation MUST NOT silently
change Drift storage or force an unrelated local migration.

Wire maps are confined to generated codecs and external adapters. Domain,
application, synchronization orchestration, state, and UI APIs remain typed.
Unknown fields, unsupported protocol versions, malformed IDs, invalid enum
values, and incomplete snapshots fail with typed boundary errors.

Nominal IDs are never converted to arbitrary strings inside domain code. Raw
strings are parsed exactly once at untrusted boundaries.

## 13. Routing

Navigation intent is declared by the feature filesystem page contract and
generated into one typed router graph.

Conventions MUST derive:

- static and dynamic path segments from folders;
- typed path values from dynamic segment names;
- typed query values and defaults from page entry parameters;
- layouts, guards, redirects, and the external-input error boundary;
- route dependency reads by exact declared type;
- typed locations and navigation values.

A page file contains exactly one typed public entry: either the real public
widget and its constructor contract, or a top-level `Widget ...Page(...)`
function that composes reusable presentation without introducing a forwarding
widget class. A second route declaration, manual path constant, forwarding
widget, central mirror tree, string concatenation, or untyped `$extra` payload
is forbidden.

Routing owns URL and navigation composition, not entity state. Guards read
typed entity-graph/session state without creating a parallel store.

## 14. Performance rules

The architecture MUST make common costs explicit and bounded:

- generation occurs at build time; runtime reflection and graph scanning are
  forbidden;
- inference and normalization occur once in the canonical compiler pipeline;
  emitters do not reparse declarations or repeat graph analysis;
- no-op generation writes no files, and an incremental entity change
  invalidates only its transitive semantic dependants and genuinely changed
  graph-wide artifacts;
- indexed lookups use generated maps or indexed SQL, not linear scans;
- unbounded queries are parameterized, paginated, and index-compatible;
- relationship loading is batched and avoids N+1 queries;
- equivalent queries share work by structural typed keys;
- persistence batches related mutations in one transaction;
- synchronization coalesces safe state patches and pull wake-ups;
- sync, process, and projection lanes are scheduled fairly and one target's
  backoff cannot cause head-of-line blocking for another;
- ordinary rank movement is O(log n) lookup plus O(1) member writes, excluding
  an explicit bounded rank-window rebalance;
- remote decoding occurs once before stable identities update;
- UI observation is field-precise and does not rebuild global scopes;
- leases, reactions, streams, timers, and database listeners are disposed
  deterministically;
- code generation creates one local database/coordinator and one durable work
  scheduler per account entity graph and shares workers, cursors, and
  remote-signal channels at the narrowest correct work-kind/target scope; it
  never creates them per entity.

Benchmarks MUST cover clean and incremental generation, no-op output, affected
artifact fan-out, analyzer cost, generated source size, mutation intent,
identity lookup, bounded filtering, unbounded paging, rank
allocation/rebalance, concurrent ordering, batched relationship work, large
pull application, multi-target fairness, projection-lane isolation, durable
process recovery, and UI reaction fan-out. A convenience API is rejected if it
hides an unbounded scan, subscription, rebuild, serialization pass, sibling
rewrite, compiler-wide invalidation, or network round trip.

## 15. Errors, diagnostics, and observability

Errors crossing a layer boundary are typed. At minimum, the system distinguishes
validation, not found, duplicate, authorization, authentication, consumed or
detached draft, overlapping draft fields, conflict, rejected operation,
retryable transport, incompatible protocol or adapter capability, local
persistence, target-lane exhaustion, and disposed lifecycle failures.

Diagnostics include entity type and nominal ID, operation ID, sync-target and
mode, queue lane/direction and attempt, descriptor fingerprint, target protocol
and authoritative versions, account/session epoch, and the failing phase.
Sensitive field values and credentials are never logged.

Build diagnostics include the complete declaration path, failed inference or
validation pass, competing candidates, derivation provenance, affected
generated API, and the smallest valid override. The generated `explain` report
uses the same provenance as diagnostics and MUST never show a different reason
from the compiler. A generic "invalid entity" or template-emission exception is
not an acceptable user-facing failure when a typed declaration caused it.

Logs are emitted at generic runtime boundaries. Features do not duplicate queue
or persistence logs.

## 16. Package and dependency rules

All reusable annotations, values, compiler stages, builders, generators,
runtime contracts, codecs, Drift storage, MobX observation, Flutter
hooks/scopes, route generation, synchronization, supported target adapters,
testing utilities, and conformance tooling live in one cohesively versioned
`nodus` package. Applications have one dependency, one public setup
surface, one generator/runtime protocol version, and one supported upgrade
path. Independently versioning these internal features and exposing their
compatibility matrix is forbidden unless an irreducible platform or licensing
constraint makes one artifact impossible to distribute together.

One package does not mean one implementation unit. The package has private,
acyclic internal modules for its domain-facing surface, compiler front end,
canonical intermediate representation, inference passes, validation passes,
emitters, runtime roles, target adapters, and tests. Only the stable umbrella
library and explicitly documented extension contracts are public; applications
MUST NOT import `src/`, instantiate internal runtimes, or assemble an alternate
subset manually.

The domain-facing annotation/value API exported by the package does not expose
Flutter, MobX, Drift, or remote-client types. Runtime coordination does not
depend on Flutter. MobX, Drift, Flutter, routing, durable processes, projections,
and each target remain typed internal capability modules selected by resolved
entity intent. The package may contain all features while generation emits and
initializes only those required by the entity graph.

The package MUST NOT import an application or depend on a sample entity.
Application-generated implementations are centralized below
`lib/src/generated/` and reached only through `lib/nodus.g.dart`; they MAY import
the package plus their own domain declarations. Domain declarations remain in
their feature folders and import only the package's domain-facing annotations,
capabilities, and nominal value types; they MUST NOT mention presentation,
MobX, Drift, remote-client, adapter, or application-composition types.

Dependency direction is:

```text
nodus domain-facing public surface
    <- application domain declarations
    <- generated domain implementation and metadata
    <- generated entity-graph/runtime composition
    <- application composition and UI

nodus canonical compiler/runtime contracts
    <- nodus internal integrations and emitters
    <- generated application artifacts
```

Internal dependencies point toward the canonical semantic and runtime contracts,
never toward an emitter, adapter, sample entity, or application. Routing and UI
are internal consumers of the shared type catalog, not dependencies of the
domain compiler. An external dependency is added only when it materially
reduces code or complexity and does not create a second source of truth.

## 17. Extension points and permanent exceptions

Configuration remains possible for advanced behavior, but defaults and
inference come first. An extension point MUST be typed, narrow, testable, and
incapable of bypassing the entity graph accidentally.

Valid extension categories include:

- a custom value codec;
- a typed source codec or pure named-creation mapper when fields cannot be
  inferred safely;
- a typed `SyncAdapter` constructed through `SyncConnector` from one exact
  generated sync-target definition;
- a typed external-process capability invoked behind an entity-owned API;
- a typed secondary-projection destination or semantic mapper;
- an explicit conflict policy;
- an unusual authorization rule;
- a reviewed data migration or backfill;
- an external file, device, payment, messaging, or computation system;
- a revocable online-only authorization projection;
- a platform lifecycle capability.

A reusable sync adapter is part of the declared synchronization architecture;
its connector consumes `SyncConnectorContext`, its adapter consumes generated
descriptors, and neither contains feature-specific schema or entity routing.
The generated target factory owns local storage and registry assembly, so a
connector package stays transport-only and can be tested against an in-memory
target definition. A reusable process or projection adapter likewise consumes
a generated typed contract and cannot expose a feature-level workflow registry
or become another writable authority. A reusable immediate external-capability
adapter MAY consume a transport-neutral typed request/response contract and
normalize transport failures, but it remains stateless and transport-only. It
MUST NOT select feature workflows, persist or cache results, enqueue hidden
retries, or replace an entity-owned durable process when the outcome has a
domain-visible lifecycle. Every other retained non-generated
boundary is labeled **Permanent exception** in the implementation inventory
with its concrete external-system, security, or platform reason. Such an
exception MUST NOT own entity lookup, persistence, caching, serialization,
synchronization, or invalidation and MUST NOT become an alternate entity data
path.

A narrow request/response implementation for an irreducible online system is
named for its protocol role, such as `Client` or `Gateway`, and recorded as a
permanent external integration boundary. It MUST NOT be named `Repository`,
because it neither owns nor abstracts entity persistence. Renaming a mechanical
entity wrapper to `Client` or `Gateway` remains forbidden by the artifact
decision rules.

When an authorized online read intentionally returns data that cannot belong to
the current account's local entity graph, its boundary value is minimal,
immutable, read-only, and named for that external projection or snapshot. It
contains only fields consumed at the boundary and MUST NOT reuse the local
entity name, pretend to be a stable entity identity, expose mutation, or become
a general presentation view model. If that data later needs offline identity,
observation, or synchronization, it becomes a declared imported entity or
projection instead of growing a cache behind the snapshot.

## 18. Testing and quality gates

Tests exist to catch a production regression, not to preserve scaffolding. At
the reusable compiler boundary, deterministic goldens and compile-failure
fixtures are appropriate. At the application boundary, conformance tests MUST
exercise public typed APIs, generated metadata, runtime behavior, or a real
schema reset/query. They MUST NOT assert exact architecture prose, scan source
or generated files for expected strings, require a retired filename to stay
deleted, or pin a one-off migration after its supported upgrade window has
closed.

A widget test MUST pump the production widget or flow whose behavior it claims
to verify. An integration test MUST cross the production boundary that makes it
an integration test. A scenario that only mutates a test-local state bag,
prints step names, settles an empty harness, checks that a generic `Scaffold`
exists, or asserts a constant is not coverage and MUST be deleted. Mocks and
fakes are permitted only around an actual production unit and MUST NOT
reimplement the behavior being asserted.

Every generated application graph provides one generated test harness below
`test/`. The harness opens the real generated graph with an in-memory Drift
database, deterministic clock support, generated adapter registry, and
descriptor-compatible in-memory backends. Tests may inject a backend, clock,
ID generator, or diagnostics policy, but MUST NOT repeat graph descriptors,
database construction, sync-adapter wiring, or account defaults in each file.
The harness changes setup only; assertions still exercise production entities,
queries, widgets, persistence, and synchronization behavior.

Migration guards are temporary. They are removed when the migration debt is
retired or the supported upgrade window closes; durable behavior remains
covered by the current compiler, runtime, database, security, and UI contracts.

### 18.1 Generator contracts

Golden and compile-failure tests cover inference, overrides, determinism,
unsupported ambiguity, defaults, codecs, constraints, indexes, relationships,
transitions, drafts, set-based and named-source creation, entity-owned process
APIs, routes, sync-mode and target inference, authority/projection separation,
typed adapter registries, target descriptor groups, SQL, RLS, and protocol
output. Every emitter is tested from frozen resolved definitions so no emitter
can perform independent inference.

A clean-generation fixture deletes every generated output before running the
builders. It MUST compile multiple mutually related entities, nominal IDs,
computed getters, pure business methods, capabilities, and one graph without
requiring a generated public replacement entity. Compile-failure fixtures prove
that an entity set cannot be used through an incompatible graph and that raw
strings, symbols, undeclared targets, or capability-incompatible modes fail.
Golden `explain` reports prove derivation provenance and actionable ambiguity
diagnostics. Clean, no-op, single-entity incremental, relationship-dependent,
and graph-wide changes prove precise invalidation and deterministic output.

### 18.2 Runtime contracts

Tests cover stable identity, precise observation, field-level draft merge and
overlap rejection, optimistic rollback/rebase, transaction atomicity, query and
list leases, paging, eviction, queue durability, coalescing, retry, idempotency,
dependency ordering, pull recovery, per-target cursors and signals, fair lane
scheduling, failure isolation between targets, adapter routing,
missing/capability-incompatible adapters, replicated conflict rebase, imported
write rejection, exported receipts, independent secondary projections,
projection failure isolation, entity-owned durable-process recovery,
idempotent external outcomes, account switching, and restart recovery.

Ordering tests include concurrent clients, incomplete pages, lifecycle
membership, rank exhaustion/rebalance, exact bounded reorder, and deterministic
scope conflict policy. Every adapter capability profile runs a reusable
conformance suite against lost responses, duplicate delivery, out-of-order
signals, cursor recovery, and canonical acknowledgement.

### 18.3 Database and security contracts

Tests execute generated Drift migrations and remote schema from a clean reset,
verify declarative convergence for every schema-capable target, exercise
effective grants and RLS with ordinary roles, and prove malformed, cross-target,
or bypass operations fail.

### 18.4 UI contracts

Widget tests verify direct stable-identity reactions, loading/error/empty states,
precise rebuild counters for list membership and visible rows, route decoding,
lease cleanup, observed-query and generated list-hook disposal, draft bindings,
and action feedback.
Persistence behavior is tested at the entity-graph boundary rather than mocked
through a repository that does not exist in the target.

### 18.5 Required gate

Every architectural change runs:

1. code generation;
2. formatting;
3. static analysis with zero infos, warnings, or errors;
4. relevant generator, compile-failure, and public conformance tests;
5. relevant entity-graph, database, sync-adapter, and UI tests;
6. affected runtime and compiler-budget benchmarks;
7. generated-output, explanation-provenance, and migration-inventory drift
   checks.

No generated file is hand-edited, no dead compatibility wrapper is retained,
and no new unresolved TODO is accepted.

## 19. Migration conformance

Application rollout information lives outside this architecture document. Its
inventory uses exactly these labels:

- **Target**: code and behavior that conform and remain;
- **Temporary debt**: a concrete current violation plus its deletion condition;
- **Permanent exception**: a retained boundary plus its irreducible reason.

A feature or slice is complete only when:

1. it has no **Temporary debt** entries;
2. generated inventory finds no replaceable repository, access interface,
   provider, CRUD command, serializer, route wrapper, or feature state adapter;
3. UI observes generated MobX identities and queries directly;
4. writes and processes use generated set create/named constructors, drafts,
   entity or aggregate actions, transactions, relationship APIs, and explicit
   process entities only where their lifecycle is real domain state;
5. local persistence and target-aware queue intent are atomic;
6. tests and quality gates pass;
7. obsolete code and configuration are deleted.

Migration may proceed vertically feature by feature only while shared generator
capabilities are still missing. Once missing generic capabilities are known,
they SHOULD be implemented and validated in the reusable architecture first,
then consumers SHOULD be converted mechanically in broad passes. Handwriting
the same temporary pattern in more features is forbidden.

A coordinated rewrite SHOULD be preferred while replacing a nonconforming
architecture when preserving its application protocols would slow the rewrite
or retain obsolete seams. Build the reusable capability set first, migrate
declarations and consumers in mechanical batches, then run one reviewed remote
business-data migration at cutover. Do not build per-feature compatibility
bridges that the completed rewrite will delete.

The architecture document itself MUST remain free of application names,
feature status, exact application file paths, schema-version narratives, and
product-specific migration history.

## 20. Final conformance checklist

An implementation conforms only when all statements are true:

1. Intent is declared once in an abstract public entity declaration and graph
   declaration; concrete records, sets, and the entity graph are generated.
2. Safe, unambiguous mechanics are inferred and generated.
3. Explicit configuration exists only for overrides or real ambiguity.
4. Domain APIs use nominal IDs and typed values end to end.
5. Entities contain properties, invariants, relationships, and business methods,
   not infrastructure.
6. Single-entity set creation, named source constructors, create/edit mutation drafts,
   lifecycle, collaboration, relationship, and selection mechanics are generated
   and reachable through an explicit compatible `entityGraph`; existing-entity
   operations are invoked directly on that entity.
7. Persisted fields change only through an awaited typed draft save, generated
   transition, awaited semantic/lifecycle action, or generated awaited
   transaction.
8. `save()` means atomic local durability plus durable queue intent, never
   remote completion, for replicated or exported entities; local-only entities
   do not manufacture queue work and imported entities reject local writes.
9. One loaded ID maps to one stable object in the `IdentityMap`.
10. Remote changes update Drift and then the same identities.
11. UI observes only the identities, query state, and fields it renders.
12. MobX exclusively owns generated entity/query state; provider, controller,
    view-model, and other mirrors of that state are absent.
13. Repositories, access adapters, and feature-facing `...Commands` objects do
    not wrap generated entity persistence or behavior.
14. Query/list APIs are inferred from ownership, relationships, and indexes.
15. Root-entity and relationship-collection cardinality are independent
    resolved facts; exact replacement/reordering exists only with a recorded
    completeness proof, while unbounded work is paginated, indexed, leased, and
    explicit.
16. Relationship and synchronization work avoids N+1 behavior.
17. Drift stores the mode-appropriate accepted state, optimistic projection,
    pending operations, conflicts, outbox receipts, queue work, and cursors
    durably.
18. One physical scheduler provides fair, independently leased
    work-kind/target/direction lanes for sync, entity-owned processes, and
    projections; each pull-capable target has independent cursor, retry, signal,
    and diagnostic state.
19. Realtime is a wake-up hint; ordered pull history provides correctness.
20. Each target's remote schema or protocol contract, authorization metadata,
    codecs, and descriptor group are generated from the same entity graph.
21. Filesystem pages generate the one typed route graph.
22. Runtime reflection, global invalidation, duplicate serialization, and
    unnecessary rebuilds are absent.
23. Sync adapters implement one generated target contract; other external
    integrations are narrow documented permanent exceptions.
24. The one reusable `nodus` package has no application or sample-entity
    dependency, and applications do not import its private internals.
25. Generation is deterministic and failures are compile-time and actionable.
26. Tests, schema validation, static analysis, and relevant benchmarks pass.
27. The separate implementation inventory has no temporary debt for anything
    claimed complete.
28. Public runtime types and variables use `EntityGraph` and `entityGraph`, not
    the ambiguous `Model` and `model` vocabulary.
29. Every non-local entity has one typed target, inherits the default without
    repeated configuration, declares `replicated`, `imported`, or `exported`
    semantics, and never imports a concrete sync adapter.
30. Cross-target relationships and entity-owned processes never claim remote
    atomicity without an explicit saga, loose-reference, or integration-event
    contract.
31. Optional standard features compose through concise capability interfaces
    such as `Ordered`, `Archivable`, `SoftDeletable`, and
    `Collaborative<Principal>` plus paired `ActivityTracked`/`ActivityOf`;
    redundant names such as `OrderedEntity`, opt-in annotations, and partial
    handwritten implementations are absent.
32. `Ordered` exposes semantic collection operations, not a raw position field;
    collaborative movement is scope-versioned and rank-based.
33. Drafts merge unrelated changes and reject or explicitly resolve overlapping
    changes at field granularity.
34. Static metadata, live `EntityGraph`, `IdentityMap`, local schema version,
    target protocol versions, descriptor fingerprints, and session epochs are
    distinct concepts and types.
35. `@Entity` is the sole graph-membership declaration annotation; package-wide
    graph identity, targets, schema version, and fingerprint are tool-owned and
    no handwritten graph root exists.
36. Ordered membership changes and ordering operations share one inferred
    scope identity, serialization lock, and monotonic scope-version lane.
37. Ordered indexes derive from one scope: PostgreSQL prefixes every stored
    scope; account-scoped local stores omit only their invariant owner, then
    both use the exact generated membership equality fields, rank, and identity.
38. Ordered `create` appends and `createFirst` prepends through one durable
    placement-aware create intent; the local rank is optimistic and the remote
    rank is resolved under the canonical scope lock.
39. Compatible semantic migrations preserve accepted state, optimistic state,
    tombstones, and pending durable intent; coordinated rewrites instead reject
    old generations and migrate authoritative business data explicitly.
40. The public `EntityGraph` is a generated domain facade over narrow private
    identity, mutation, query, transaction, local-store, process, and sync
    runtimes; none are application-visible service-locator entries.
41. One compiler pipeline resolves inference once into a canonical
    `EntityGraphDefinition`; deterministic emitters consume resolved facts and
    never reinterpret declarations.
42. Every inferred result has derivation provenance and an actionable generated
    explanation; ambiguity diagnostics identify competing candidates and the
    smallest valid override.
43. Routing and Flutter integration are internal passes in the same package but
    consume narrow typed catalogs and cannot influence persistence or sync
    inference.
44. A process that produces or changes entities is exposed through its generated
    set, canonical collection, entity, or owning aggregate. It becomes a process
    entity only when its independent lifecycle is genuine domain state.
45. One entity has one authority contract; additional destinations are
    independent generated projections whose failure cannot roll back canonical
    state. Genuine multi-master semantics are encapsulated by one explicit
    adapter contract.
46. Clean, no-op, and incremental compiler costs, affected-artifact fan-out,
    analyzer time, generated size, runtime costs, and recovery paths have
    explicit measured regression budgets.
47. A declared scope transition is inferred from its exact non-owner scope
    parameters, not from its method name, and generates one atomic cross-scope
    command with append as the default target placement.
48. Cross-scope acknowledgements carry typed source and target scope-version
    receipts; no scalar receipt can silently identify the wrong lane.
49. Ordered transfer is an optional sink/adapter capability; unrelated entities
    and mutation sinks do not acquire unused transfer APIs.
50. Recursive scope transfers serialize cycle validation by one inferred
    hierarchy partition in addition to their deterministic source/target lane
    locks; disjoint sibling lanes cannot race a cycle into existence.
51. Capability interfaces are recognized by exact type identity and supply
    their complete vertical feature; entities never repeat inherited fields or
    methods, and collaboration is exposed directly as
    `entity.setCollaborator(...)`.
52. A generated active-relationship handle reuses one unique link identity,
    preserves rank on reactivation unless an explicit move follows, omits exact
    operations for unbounded collections, and never claims an N-item mutation
    loop is one atomic semantic operation.
53. Drift and remote SQL store the best native scalar types; persisted entity
    fields contain no generic JSON, collection blobs, object trees, or EAV
    escape hatches. Repeated and structured data is normalized into generated
    typed columns and relationships.
54. A create-capable inverse relationship binds its known reference in a
    generated collection `create`/`createFirst` API backed by the one set
    creation contract.
55. A nominal atomic domain value uses `PersistedScalarValue<Wire>` to derive
    one native scalar representation end to end; it never hides structured data
    inside that scalar.
56. A sealed domain value declares one `@PersistedVariant`; generation derives
    its mutually exclusive native values or typed references, and persists a
    discriminator only when variant identity cannot be derived safely from
    presence. Derived tags are forbidden duplicated state.
57. Nullable dependencies, ordered numeric relationships, and exclusive
    variant membership are declared once and generated across Dart candidates,
    SQLite, PostgreSQL, merge, and synchronization boundaries.
58. Runtime-defined structured input uses first-class definition and typed
    response entities, a closed native value variant, one parent-definition
    identity, aggregate type validation, and references rather than copied
    choice labels; it never becomes an arbitrary attribute bag.
59. `LocalId<E>` always preserves nominal native identity, while `@Reference`
    alone opts into a live graph relationship. Historical identity that may
    outlive target visibility uses the typed ID without a foreign key and never
    degrades to raw strings or generic payloads.
60. `ActivityTracked` mutations append one immutable `ActivityOf` entry in the
    same generated batch, no-op or failed mutations append none, remote replay
    does not duplicate history, and callers use the source entity directly.
