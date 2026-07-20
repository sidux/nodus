# Nodus capability reference

> One graph. Every layer.

Flutter made sharing an interface across platforms simpler. Nodus builds on
that foundation by carrying one typed product model through the application
layers behind the interface. It generates the application graph, reactive
entities, mutation drafts, Drift persistence, durable synchronization, backend
schema and security, typed queries, file-based routes, and a real in-memory test
harness.

Nodus is currently `0.1.0`: suitable for evaluation and new projects, with API
evolution expected before `1.0.0`. The built-in durable store supports Android,
iOS, Linux, macOS, and Windows.

## Why Nodus

| You declare | Nodus generates |
| --- | --- |
| Entity fields, constraints, and relationships | Validated domain records, codecs, Drift tables, and PostgreSQL schema |
| Actions and capabilities | Atomic drafts, lifecycle APIs, ordering, collaboration, and activity |
| Ownership and sync mode | Durable offline queue, conflict handling, RLS, grants, pull, and push |
| Typed predicates and indexes | Cached reactive queries, paging, named lists, and lookups |
| Filesystem pages | Typed GoRouter locations, parameters, layouts, guards, and redirects |

There are no handwritten repositories, DTO copies, graph registries, or
feature-level synchronization services. Loaded entities keep one stable MobX
identity, and `await` on a mutation means local durability plus durable sync
intent—not a network round trip.

## Quick start

Add Nodus from your Flutter application root:

```sh
flutter pub add nodus
```

Declare entities below `lib/**/domain/`:

```dart
import 'package:nodus/nodus.dart';

final class Account {}

enum TaskStatus { todo, done }

@Entity()
abstract class Task
    implements OwnedBy<Task, Account>, SoftDeletable, Archivable {
  @Persisted(minLength: 1, maxLength: 160)
  abstract final String title;

  @Persisted(defaultValue: TaskStatus.todo)
  abstract final TaskStatus status;

  @Action()
  Future<void> edit({required String title});

  @Action(values: [ActionValue(#status, TaskStatus.done)])
  Future<void> complete();
}
```

Initialize after the first entity declaration:

```sh
dart run nodus init --target supabase
```

Nodus discovers the package, creates `nodus.lock`, and emits one public
`lib/nodus.g.dart` facade. Use the generated API directly:

```dart
final task = await entityGraph.tasks.create(title: 'Ship Nodus');

final draft = task.beginEdit()..title = 'Publish Nodus';
await draft.save();
await task.complete();

final openTasks = TaskList.all(
  entityGraph,
  where: TaskFields.status.equals(TaskStatus.todo),
);
```

Schema changes are named and reviewable:

```sh
dart run nodus migrate add_task_due_date
dart run nodus explain Task
dart run nodus check
```

`migrate` updates the schema version and generates the Drift migration,
declarative Supabase schema, and SQL diff together. A plain generation fails if
the resolved physical schema changed without a migration name.

## See the complete app

The [Tasks reference app](../example/tasks/)
exercises production entity APIs and generated infrastructure end to end:
offline creation and editing,
project-scoped ordering, lifecycle transitions, collaboration, activity
tracking, tombstones, paging, adaptive Flutter UI, typed deep links, and a
visible durable sync queue.

```sh
cd example/tasks
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

Its tests use the generated in-memory graph harness rather than mock
repositories. See the package-local
[example guide](../example/README.md)
for a compact walkthrough.

## Public libraries

- `nodus.dart` — annotations, typed IDs, queries, synchronization contracts,
  local engine, and deterministic in-memory backend.
- `nodus_flutter.dart` — Flutter account lifecycle, Hooks query/list bindings,
  and typed file-route runtime.
- `nodus_supabase.dart` — descriptor-driven Supabase synchronization.
- `nodus_testing.dart` — deterministic clock and generated-harness support.
- `nodus_migrations.dart` — narrow Drift types used by generated migrations.

Applications import their generated `nodus.g.dart` facade in production. The
other public libraries are primarily generation and extension boundaries;
`package:nodus/src/...` is unsupported.

## Tool commands

| Command | Purpose |
| --- | --- |
| `dart run nodus init --target NAME` | Create `nodus.lock`, standard builder configuration, and the first graph |
| `dart run nodus generate` | Regenerate application APIs quickly |
| `dart run nodus watch` | Regenerate while domain or page sources change |
| `dart run nodus explain [ENTITY] [--json]` | Show resolved schema, sync, capability, and field inference |
| `dart run nodus migrate NAME` | Advance the schema and generate reviewed local/remote migrations |
| `dart run nodus check` | Fail when generated output or the schema lock is stale |

## Advanced capability reference

Each generated entity graph exposes one immutable `EntityGraphDefinition`.
Backends accept that definition directly, so consumers never repeat descriptor
lists, protocol versions, or pull RPC names. Built-in graph-aware backends are
validated before the local database opens; plain `SyncBackend`
implementations remain the extension point for custom transports and focused
tests.

For incremental adoption, ordered `supabase/schema_sources/*.sql` files are
composed before generated entity SQL and reviewed
`supabase/schema_extensions/*.sql` files remain after it. During a coordinated
rewrite, `--defer-supabase-composition` can regenerate Dart and Drift artifacts
without changing the canonical remote schema; it cannot be combined with a
deployment migration.

Entity discovery covers `lib/**/domain/**.dart`. `@Entity()` is the sole entity
annotation and defaults to an unbounded, Drift-paged collection. Package-wide
generation owns the graph facade, private implementations, generated test
harness, and physical schema fingerprint.

## Custom connectors

Target names are open: `dart run nodus init --target rest_api` generates a
managed `openRestApi(...)` factory. Implement the smallest generated adapter
capability and bind it with one callback:

```dart
final graph = await TasksExampleEntityGraph.openRestApi(
  accountId: accountId,
  connector: (context) => RestApiAdapter(
    client: client,
    definition: context.definition,
  ),
);
```

`SyncConnectorContext` supplies the account, stable target, and exact
target-only `EntityGraphDefinition`. The generated factory validates the
adapter, opens the account-specific local store, and constructs the typed
registry. Multi-target graphs use `openWithConnectors(...)` with one
capability-typed callback per target. Custom transport code therefore owns only
`push` and/or `pull` plus optional snapshot and remote-change-signal behavior;
it never duplicates entity declarations, codecs, storage paths, or graph
wiring.

Ordering infrastructure uses the opaque fixed-width `OrderRank` value. Its
decimal text order is identical in Dart, SQLite, and PostgreSQL, and
generated infrastructure can allocate deterministic ranks between neighbors or
detect that a canonical-scope rebalance is required. Feature code does not
author or mutate ranks; bounded declarations opt into `Ordered` and receive
neighbor moves, exact membership-checked `reorder`, and an atomic semantic
full-scope fallback for exhausted intervals. Local rank patches stay queue-local
bookkeeping; adapters receive only semantic intent. Generated create, remove,
restore, move, and reorder operations share one inferred scope lock and
monotonic scope version, so an exact reorder cannot race a membership change.
Generated physical indexes reuse that scope metadata. PostgreSQL prefixes a
stored owner or relationship source before lifecycle, rank, and identity, so
remote ordering never falls back to a cross-scope scan. An account-scoped local
store omits only its invariant owner prefix and retains relationship scopes.
Generated ordered sets append through `create(...)` and insert at the canonical
start through `createFirst(...)`; both signatures come from the same entity
fields and persist one create intent with its internal rank.
Generated route dependencies are registered with inferred
`FileRouteDependency<T>` bindings. Lookup keys use the declared static `T`, not
`runtimeType`, so interface injection remains valid and the heterogeneous scope
cannot be populated with a value of the wrong type.
Flutter applications place one `AccountEntityGraphScope<G, Account>` above their
router. It publishes only signed-out/opening/ready/failure transitions from the
account session. Generated entity fields and collection/query state remain
direct MobX observations, so an entity mutation never globally rebuilds the app
or passes through a provider projection. `useEntityList` owns the generated
named collection lease at the consuming widget; `Observer` narrows rebuilds to
the exact fields rendered there. `stateOf` and `sessionOf` are strict composition
accessors; `maybeReadyOf` returns null when the scope is absent or its session is
not ready and observes lifecycle transitions only.
Declared instance fields are persisted by convention. Computed getters and
setters are inferred as derived domain behavior and are never persisted;
`@Transient()` is only needed to exclude a real declared field.
Generated descriptors and engines bind the declared domain type to its exact
generated record type. Query hydration uses that binding directly, so consumers
cannot request an unrelated result type and generated code contains no domain
cast. The inherited generated-access capability similarly lets relationship and
collaboration extensions reach record services through an exact generic
interface, with no downcast and no per-entity adapter allocation.
Generated entities expose their read-only concurrency value as nominal
`ServerVersion`; only Drift, PostgreSQL, and JSON codecs unwrap it to an integer,
so domain code cannot confuse it with local revisions or pull sequences.
The generated entity graph exposes `nowUtc()` from the same injected `Clock`
used by mutations and synchronization. Multi-field application actions can
therefore sample one deterministic instant without reaching for the device
clock or exposing the clock object as mutable application infrastructure.
Reserved infrastructure field/column names (`id`, `ownerId`, `deletedAt`, and
`serverVersion`) live once in `EntityConventions`; generated descriptors do not
repeat non-overridable strings per entity.
Account-root entities may use `Ownership.identity` with identical `Self`
and `Owner` types. Their primary key is also their authenticated owner identity,
so generation omits the redundant `ownerId`/`owner_id` field and the
client-insert grant/API while still inferring owner select/update capabilities.
Graphs containing separately owned entities infer exactly one nominal account
type. The generated entity graph requires that typed account ID when it opens and
carries the canonical principal through local persistence and synchronization.
Ordinary generated `create()` methods derive their owner from that graph scope,
cache the typed owner once per set, and never expose `ownerId` as a caller
parameter. Only relationship-owned entities derive ownership from their
declared ownership reference. A graph with conflicting separately owned account
types fails generation instead of choosing one implicitly.
The public `LocalId<T>` constructor validates and normalizes UUIDs through the
same path as external parsing. It cannot be `const`, because malformed nominal
IDs are rejected rather than trusted at handwritten call sites. Durable
`SyncOperationId` values use the same invariant, so typed ID generators are not
redundantly reparsed by mutation and pull scheduling.
Persisted Dart enums are likewise inferred without a converter annotation:
their Dart names generate exhaustive codecs to conventional lower-snake-case
wire values, equality queries, validated hydration, database membership
constraints, and initializer defaults. Multiword values therefore stay
idiomatic in Dart without leaking camel case into PostgreSQL or JSON.
Persisted text and integer bounds are retained in generated
`EntityFieldConstraints`. Domain validation, transport decoding, the
deterministic in-memory backend, and UI affordances such as `TextField.maxLength`
can consume the same typed metadata; applications never copy a declared limit
into another configuration object.
Persisted entity fields are native scalars or typed references. Repeated values
and structured state use generated child entities and relationships; generic
JSON, collection blobs, and object trees are not persistence shortcuts. A
nominal atomic value implements `PersistedScalarValue<Wire>` with one
`toScalar()` method and one `fromScalar(Wire)` constructor. The supported
`String`, `bool`, `int`, and `double` wires derive the Drift/PostgreSQL type,
protocol codec, defaults, constraints, equality queries, and change detection
without leaking the primitive into the domain. The contract cannot encode
structured data into a scalar. Raw SQL-type overrides are intentionally absent:
supported Dart types have one safe inferred mapping.
Server-generated storage is inferred for the `createdAt` and `serverVersion`
conventions. Trusted workflow state is the distinct explicit exception:
`@Persisted(authority: FieldAuthority.server)` requires an immutable
field and a local/SQL default when non-null. It initializes optimistically from
that default, is omitted from client create and patch payloads, and changes only
when synchronization applies a canonical server record. A generated trigger
advances `serverVersion` when trusted SQL changes any such field without already
advancing the version, so ordinary capture and pull cannot silently discard a
same-version workflow transition. The generator rejects mutable, local-wins, or
uninitialized non-null server-authoritative fields.
An entity whose persisted fields are all immutable and server-authoritative is
a valid synchronized read projection. Generation emits its table, RLS, change
capture, local set, and pull contract but no unusable upcaster, patch helper, or
push function. Trusted SQL remains its only writer.
An immutable non-null `DateTime updatedAt` is a separate managed convention:
local mutations advance it optimistically and persist it locally, trusted push
patches exclude it, PostgreSQL advances it with a generated trigger, and the
canonical response reconciles the timestamp.
Immutable-after-creation behavior derives only from Dart `final`; persistence
annotations cannot contradict the domain setter contract.
Deletion is tombstone-based by convention and exposed only when an
`OwnedBy<Self, Owner>` entity also implements `SoftDeletable`. Generated
`create`, `remove`, and `restore` APIs follow the declared insert/delete grants.
Both lifecycle transitions are idempotent and remain ordered in the
synchronization queue. Generated setters
and relationship commands reject changes after the tombstone is set, preventing
post-delete patches from surviving behind a queued delete. Server-created or
non-deletable entities are narrower at compile time. There is no unusable
hard-delete flag;
adding that policy requires a complete offline/synchronization design.
Entity protocol versions are inferred as the maximum retained field
`sinceProtocolVersion`; empty manual version jumps are not configurable.
Every generated `PersistedEntityField<E, V>` owns its one constant persistence
descriptor and typed wire encoder/decoder. Entity descriptors, create APIs,
patches, snapshots, hydration, and remote application reuse those same typed
fields, so names, codecs, protocol defaults, conflict rules, and relationships
cannot drift through parallel mappings. Query-only `EntityField` values remain
available for advanced in-memory/cache integrations but do not expose
persistence capabilities at compile time.
Comparable generated fields expose typed `isLessThan`, `isAtMost`,
`isGreaterThan`, `isAtLeast`, and inclusive `isBetween` predicates. The same
predicate object evaluates in memory, derives a stable query-cache key, and
compiles to bound Drift comparison SQL; callers never repeat range semantics as
raw SQL or strings. Equality-only IDs, booleans, and structured values do not
gain ordering methods. Generation selects the query backend from cardinality:
bounded queries synchronously evaluate the already complete observable identity
map, while unbounded queries use keyset-paged Drift SQL. The public predicate,
ordering, state, pagination, and lease API remains identical.
Each graph also generates a domain-named `<Entity>List`. Its `all` constructor,
`forOwner` constructor for separately owned entities, `for<Reference>` and
`for<Participant>` constructors, and the owner-or-participant `visibleTo`
constructor are inferred from the entity graph. Non-null unique compound
indexes also derive `for<Field>And<Field>` selectors, so identity-like lookup
predicates cannot drift from their declared uniqueness. Inverse accessors
return the same list type. Every list delegates to one value-cached
`LocalEntityQuery`, so
the semantic API adds no cache, subscription, serialization, or materialization
layer. `watchCompleteStates` is the explicit exhaustive stream bridge for
non-MobX consumers: it suppresses partial pages, preserves the last complete
snapshot across refresh failure, and releases the list lease on cancellation.
It is single-subscription because one list owns one lease; independent listeners
construct independent generated lists and therefore cannot dispose each other.
`useObservedEntityList` binds its lease, MobX query observation, and typed
loading/data/empty/failure rendering to a Flutter widget;
`useEntityQueryScrollController` adds paging. Generated by-ID and exact-index
lookups return `EntityLookup<E>`, and `useObservedEntityLookup` renders their
zero-or-one state without exposing list or pagination mechanics. Mutation
draft bindings write directly to generated fields, while `useEntityAction`
owns reusable busy/error feedback and an optional generic error callback. Raw
`set.query(...)` remains the advanced escape hatch for genuinely ad hoc typed
predicates, not the ordinary feature API.
Generated sets allocate entity IDs during ordinary `create()` calls. Work that
must name a future entity first, such as an upload object key, calls the typed
`allocateId()` once and passes that nominal value to the optional `create(id:)`
override; no parallel UUID convention or raw-string identity path is needed.
Generated relationships keep authoritative foreign keys and delete behavior in
PostgreSQL, but omit them from Drift because an RLS-filtered local projection
may validly contain a child whose target is not visible. Nominal target IDs are
retained, missing accessors resolve to `null`, and local create/patch batches
still validate referenced targets atomically before persistence.
Owner-scoped rows that directly name another authorized account use an
immutable `@AccessParticipant()` `LocalId<Owner>` field plus explicit
`RlsPrincipal.participant` grants. Generation derives the access index, table
policy, push authorization, authenticated-user foreign key (unless an explicit
entity reference overrides it), reference checks, and graph visibility from
that single nominal field. Multiple participant fields are OR-composed. Mutable,
nullable, wrongly typed, or unused participant declarations are rejected so an
access audience cannot change without explicit revocation semantics.
Reciprocal owner/participant relationships can declare
`CompoundIndex.unorderedWithOwner(#participantId)`. The generator verifies the
other endpoint is the same immutable `LocalId<Owner>` type, then emits one
direction-independent unique expression index in SQLite and PostgreSQL plus the
same swapped-pair check in schema-less transports. Deletable relationships
automatically scope that uniqueness to non-deleted rows, so a later
reconnection does not conflict with its synchronized tombstone. No
canonical-pair column or second uniqueness declaration is stored.
A two-ended relationship with one `@OwnerReference`, one unconditional unique
reference pair, an `active` field defaulting to true, and fixed `activate` /
`deactivate` actions also infers a typed inverse mutation handle. Its `link`,
`unlink`, and `replace` methods reuse inactive identities, retain unbounded
query leases through mutation completion, validate duplicate replacement
targets, and resolve only after the exact local transaction and queue writes
are durable. The handle's list view selects active, non-deleted rows by default.
No feature command repeats relationship lookup or reactivation.

Generated set queries, query watches, named lists, and inverse lists all exclude
tombstones by default. Repair and audit flows opt into
`TombstoneVisibility.include` or `.only`; an additional typed predicate can
only narrow that lifecycle selection. Direct identity lookup remains available
for an explicitly known tombstone so generated restore behavior can address it.

For migration compatibility, an entity with a non-negative `sortOrder` default
and an exact `moveTo` action still gives generated named lists default ascending
order. An explicit order overrides that default. Bounded lists also receive
dense `reorder` and `prepend` methods; exhaustive mutation helpers are never
emitted for unbounded lists. Reordering rejects duplicate IDs and requires an
exact match with the selected list; prepending shifts that complete selection
inside one local transaction. This convention is legacy behavior, not the
target declaration API; `Architecture.md` and the migration inventory define
its replacement by the `Ordered` capability and an internal rank.
Typed relationship rows inherit endpoint authorization with
`@AccessReference()`. Marked references are AND-composed and generation infers
the `RlsPrincipal.reference` grants, indexes, RLS, push checks, and ordered-graph
visibility. A polymorphic relationship may instead place nullable marked
references in one `ExclusiveFieldGroup(..., allowNone: false)`; the generator
reuses that exactly-one fact to OR-compose the alternatives and rejects nullable
access references with any weaker or mixed group. Exactly one reference may
independently use `@OwnerReference()`;
its target owner is then reused locally and verified by PostgreSQL, so the
create API does not ask for a duplicate `ownerId`. Direct and workflow
membership changes publish or revoke every affected relationship row with
set-based indexed SQL, including rows whose other endpoint has not become
readable yet. Reference-authorized
entities deliberately cannot be nested as access endpoints: authorization must
terminate at an owner, participant, collaborator, or authenticated entity so
revocation fan-out stays finite and predictable.
Normalized relationships can deliberately extend that finite audience to an
existing referenced target with `@AccessTarget()`. The relationship's
`@AccessReference()` fields remain the source of truth and are AND-composed;
the target annotation infers the target owner's select/update/delete
capabilities, omits insert, and allows an explicit narrowed operation list.
An access target may also be the relationship's `@OwnerReference` when a
different `@AccessReference` supplies the finite audience. This entity graphs links
whose ownership follows the destination while access is inherited from the
source, without persisting or asking for a duplicate owner ID.
Generation filters conventional `active` and tombstone state, rejects broad-
authenticated sources and cycles, verifies that link creation already has
direct target access, and derives target RLS, push checks, pull visibility,
audience snapshots, and revocations. Relationship-derived targets may feed a
later relationship path, forming a compile-time-validated DAG. Audience
enumeration and publication then cascade only through the affected path and
user; source membership and link activation changes require no application
fan-out queries. Recursive SQL aliases retain a readable prefix plus a
deterministic 64-bit suffix when necessary, keeping every identifier within
PostgreSQL's 63-byte limit without allowing distinct access paths to collapse
through silent truncation.
Generated access predicates are the only callable helper functions: default
execution is revoked from `PUBLIC`, `anon`, and `service_role`, then
`authenticated` receives `EXECUTE` because RLS evaluates those boolean
predicates as the actor. They expose no row or mutation capability. Patch,
upcast, capture, publication, timestamp, and other trigger helpers remain
server-only; authenticated writes still enter exclusively through generated
push functions.
Generated SQL revokes every table privilege from `anon` and `authenticated`
before granting the narrow direct read capability. This intentionally removes
legacy `TRUNCATE`, trigger, and reference privileges as well as writes when an
existing table moves under entity-graph-first ownership; RLS does not mediate all of
those operations.
Every generated unbounded entity set also exposes
`loadById(LocalId<E>, {refresh})` for demand-driven reads. Bounded sets are
already complete and expose synchronous `byId` and `require` instead, making a
redundant asynchronous bounded lookup a compile-time error. An unbounded lookup
checks the retained identity first; an explicit refresh or cache miss uses the
backend's optional snapshot capability. Supabase performs an ordinary
parameterized table select, so existing RLS remains the sole access contract and
no per-feature RPC is required. The complete snapshot is decoded by the
generated descriptor and merged through the same accepted-base and
pending-overlay machinery as ordered graph changes, without moving the graph
cursor. The returned `EntityLookupLease<E>` pins unbounded identity only for the
consumer's lifetime. Imperative consumers use `lease.use(...)`, which retains
the stable entity for the complete synchronous or asynchronous callback and
releases it on every exit path. A missing refreshed row purges accepted cached
data, while pending local work is retained until synchronization resolves it.
Generated `watchById` is available for both cardinalities. Each subscription
owns one identity retain, tracks the generated MobX snapshot, and releases both
the reaction and retain on cancellation. Bounded watches observe the complete
identity map without I/O; unbounded watches automatically materialize a missing
identity. Stream-based composition can therefore observe an unbounded entity
without a parallel provider cache or an implicit permanent identity pin.
Imperative multi-row work similarly uses `query.useAll(...)`; it exhausts the
typed query, retains every materialized identity through the callback, and
disposes the query afterward. Returning an unbounded entity beyond either
callback is intentionally outside the retention contract.
Authenticated SELECT grants remain ordinary RLS for direct reads. Their graph
pull behavior is inferred separately: bounded entities synchronize all readable
rows, while unbounded entities keep broad authenticated visibility on demand and
continue synchronizing owner/collaborator rows. Owner rows always participate
in graph pull even when a broader SELECT policy subsumes owner authorization;
the grant list never has to duplicate that derived sync audience. This prevents
a public directory or feed from becoming an accidental global bootstrap. The exceptional
`authenticatedReadSync` annotation can force `onDemand` or `graph` only when the
dataset's boundedness and offline requirements justify overriding the default.
Numeric `minValue`/`maxValue` and string `minLength`/`maxLength` constraints are
validated from the same declaration in constructors, setters, remote hydration,
Drift, and PostgreSQL. Remote snapshots decode and validate every incoming field
before one MobX action mutates the stable entity, preventing partial application
when any field is malformed.
A numeric field may also declare `greaterThan: #otherField` or
`greaterThanOrEqual: #otherField`. The generator validates same-typed numeric
symbols, emits the same cross-field check in Dart, Drift, and PostgreSQL,
validates both sides from one candidate snapshot, promotes nullable candidates
only after presence checks, and checks setters of either participating field.
Multi-field business transitions use an abstract `@Action` method.
Required parameters map to same-named persisted fields; `ActionValue`
adds explicit literal, injected-clock, or null assignments. Every target is
`abstract final`, so independent setters cannot bypass the method. Generation
performs one candidate-snapshot validation, one MobX action, one local revision,
one rollback, and one typed state patch. Actions return `Future<void>`: the
optimistic projection changes synchronously, while awaiting proves the exact
Drift projection and durable queue intent committed or rethrows its failure
after rollback. The ordinary generic entity push is reused—no action-specific
RPC exists. PostgreSQL requires complete declared
action shapes and their literal/null assignments, rejecting partial or forged
patches; the generated action descriptor applies the same contract in the
deterministic in-memory transport. Fields assigned a constant, clock, or clear
value take their safe initial value during creation rather than becoming
constructor escape hatches. Parameter-only action fields retain their ordinary
typed create arguments, allowing concise atomic edit APIs without losing valid
initial data. A nullable clock target is stamped only while null, which makes
lifecycle actions idempotent until another declared action clears it.
An `@Action()` named `edit` additionally generates `entity.beginEdit()` and the
set generates `beginCreate()`. Both return one typed `<Entity>MutationDraft`.
The draft snapshots the editable fields or holds typed creation defaults and
unset required values; it remains a plain, non-observable value until `save()`.
Saving rejects consumed, stale, detached, or disposed targets, invokes the same
generated action and invariant checks, and resolves only after that exact
mutation has atomically reached Drift and the durable synchronization queue.
When an ordered scope field changes with ordinary edit fields, the draft runs
the declared entity actions in one graph transaction; the feature does not add
a transaction wrapper.
It does not flush unrelated work or wait for the network. An unchanged draft
is consumed as a true no-op; a persistence failure rolls the stable MobX entity
back and rethrows the original error. `discard()` consumes the draft without
changing the entity. The generator reserves `beginEdit`, requires exact field
types (including nullability), and rejects fixed action assignments in `edit`
so form state cannot silently omit or invent persisted values.
Mutable or action-managed enum fields may declare typed `AllowedTransition`
edges. The generator rejects cross-enum, nullable, unreachable, duplicate, and
no-op declarations.
Optional `by` principals must have update grants and are enforced by locked
PostgreSQL patches. The field default is the only create state and is supplied
automatically; generated setters/actions and the in-memory backend enforce the
same value graph. Trusted remote hydration remains outside the
client-transition graph, and equal writes remain no-ops.
Generated local setters, actions, drafts, and semantic commands also evaluate
deterministic owner and participant grants against the graph's authenticated
principal before changing observable state. Participant transition actions use
the pre- and post-transition participant identities, so acceptance and
revocation remain exact offline. Collaborator and reference grants are
revocable graph projections; local state may be stale, so their authoritative
decision remains the generated locked remote policy rather than an unsafe local
rejection.
When an entity is generally editable by multiple roles but one field is not,
`@Persisted(updateBy: [...])` narrows that field to principals already present
in the entity update grants. The locked push rejects a patch containing the
field from any other actor. Empty `updateBy` keeps the inferred entity-wide
audience; server-managed and otherwise non-updatable fields cannot declare it.
For workflow enums this field rule and each edge's `AllowedTransition.by` rule
are both required.
`CollaborationAccess()` keeps the compact direct owner-controlled membership
command. `CollaborationAccess.workflow()` instead resolves a normal
`<target>_members` entity from its typed target reference,
`@AccessParticipant` identity, and transitioned status enum. Generation infers
the unique target/member key, accepted collaborator predicate, owner-only
invitation creation, and targeted grant/revocation change-log events. Workflow
acceptance must be participant-controlled and cannot be selected as an initial
create state; no hidden membership table or parallel serializer is emitted.
If an application invokes a workflow action before the initial create has
synchronized, the durable engine preserves two ordered operations. It never
folds the transition back into a forged initial create state. Ordinary
replaceable edits still coalesce, while the first canonical acknowledgement
rebases the dependent operation onto the returned server version.
Nominal `LocalId<Self>` references are valid recursive relationships; graph
ordering ignores only that self-edge while retaining the generated foreign key,
typed forward/inverse accessors, validation, and delete behavior.
`Entity.exclusiveFieldGroups` expresses at-most-one cardinality for two or
more nullable persisted fields with `ExclusiveFieldGroup([#first, #second])`.
The generator validates every symbol and rejects missing, repeated,
non-nullable, or duplicate groups. Constructors, setters, atomic remote
hydration, Drift checks, and PostgreSQL checks all evaluate the same candidate
field group; consumers do not duplicate polymorphic-target constraints in
handwritten validators or migrations. Set `allowNone: false` when the domain
requires exactly one field rather than zero-or-one.
`LocalDate` is the canonical timezone-free `yyyy-MM-dd` value for calendar
dates. Its generated codec stores canonical text in Drift and JSON while using
PostgreSQL `date`, so consumers never reinterpret a calendar day as an instant.
Drift-backed query specifications also infer their projection dependencies from
typed predicate and ordering fields. Public field changes use sealed typed field
references, never raw names. Field patches reload only affected cached queries;
remote snapshots are value-diffed before invalidation; membership changes reload
all queries; unknown external Drift writes fall back to a full entity-query
refresh. Batched mutations union their fields, and non-persisting semantic
commands do not cause projection SQL. `field.isIn(values)` provides normalized,
duplicate-free typed set membership; empty input matches nothing and nullable
membership preserves null semantics in memory and generated SQL.
Generated sets expose `watchQuery()` for non-widget adapters. Every listener
owns one cached query lease and releases both its MobX reaction and cache lease
on cancellation. `watchCompleteQuery()` is the explicit exhaustive variant: it
loads every keyset page through that same lease, suppresses partial snapshots,
and preserves a previously complete stale snapshot while refreshing. Ordinary
queries remain paged, so exhaustive aggregation never becomes a hidden default
cost. `AccountEntityGraphSession<G, Account>.switchMapState()` composes those
streams across auth transitions while cancelling the previous account binding
and suppressing stale emissions. Its states and `withReadyEntityGraph()` callback
retain the account as `LocalId<Account>`; feature adapters neither implement
their own subscription switching nor reparse an authenticated identity from a
raw string.
Remote signal bursts share one pull-scheduling loop. Signals received during an
active pull force one follow-up pull after its cursor commits, and graph shutdown
joins tracked projection, queue, signal, and synchronization tasks before Drift
closes.
The generated durable change log retains one latest general snapshot per entity
and one latest access transition per entity/audience pair. Superseded history is
compacted transactionally without reusing monotonic sequences, keeping initial
pull cost proportional to visible state while operation receipts preserve retry
idempotency independently. A receipt at or behind the durable pull cursor cannot
overwrite a newer projection; surviving rebased intent rotates to a fresh
operation ID and retries against the newer base.
Every push result is checked against its submitted work by the shared
`PushResult.validateFor` contract. It requires the exact nominal entity identity,
the matching non-null operation receipt, duplicate-free non-revoking canonical
changes, and the submitted identity as the primary result. Multi-record semantic
operations merge every related acknowledgement atomically before reactive
projections publish.
Built-in backends, the generic worker, and direct persistence completion all use
the same validation rather than implementing transport-specific acknowledgement
rules.
Field `@SyncCommand` annotations infer delete/tombstone semantics and do not
repeat an operation. Normal updates use typed patches; collaboration uses its
generated typed command. Typed commands are recorded through one runtime path
that derives their durable patch from `toWire()`. Commands and conventional
`remove`/`restore` methods expose the same awaited local-durability boundary as
entity actions. Field-command method names are local API only and are not
emitted as dead wire/protocol rename metadata.
Feature-owned pages live under:

```text
lib/features/<feature>/presentation/pages/**/page.dart
```

Folders below `pages/` define URL structure. The feature name defines code
ownership and is not a URL segment. Feature trees may also contribute layouts,
guards, and redirects; exactly one root tree owns `not_found.dart`. The route
builder merges all trees and rejects ambiguous paths or generated names.
Each `page.dart` declares one typed entry: either a Widget class ending in
`Page`, or a top-level `Widget ...Page(...)` function when a route only composes
reusable presentation and does not need a forwarding widget class. Named page
entry parameters become typed query values; their URL keys are inferred in
kebab case from the Dart names and their declared defaults remain the single
source of truth. Guards may declare `FileRouteMatch` and compare it with a page
constructor or function tear-off, so generated page identity replaces
handwritten path comparisons.
Reusable, non-routable feature widgets live beside that tree under
`presentation/components/`; presentation Dart files do not sit loose directly
under `presentation/`. The route builder validates this organization and fails
generation for any other presentation subfolder.

Pages use GoRouter's default presentation unless their Widget class implements
`FileRoutePagePresentation`, which keeps an exceptional sheet or transition
beside the page that owns it. `createFileRouter` accepts one optional
`FileRouterConfiguration` for app-level navigator ownership, external guard
refresh, URI canonicalization, diagnostics, and observers; route paths and the
route tree remain exclusively filesystem-generated.

Builder phases are explicitly ordered:

```text
local_entity -> entity_graph -> file_routes
             \-> drift_dev
entity_graph  \-> drift_dev
```

Generated application code imports public `nodus` facades only. Importing
`package:nodus/src/...` from an application is unsupported.

Package quality gate:

```sh
dart format .
flutter analyze
flutter test
```
