# Nodus capability reference

Nodus compiles typed Dart domain declarations into a local-first application
graph. This page is the practical reference for what applications declare, what
Nodus generates, and how the generated APIs behave.

For installation and a first working entity, start with the
[README](../README.md). The [architecture contract](Architecture.md) is
normative when this guide omits an implementation detail.

## At a glance

| Concern | You declare | Nodus generates |
| --- | --- | --- |
| Entity model | Fields, defaults, constraints, relationships, and capabilities | Typed entities, nominal IDs, codecs, descriptors, and sets |
| Mutation | Editable fields and semantic `@Action` methods | Create/edit drafts, validation, rollback, lifecycle operations, and durable intent |
| Local data | Entity cardinality and indexes | Drift tables, migrations, paging, identity retention, and query caches |
| Synchronization | Authority mode and remote target when inference is insufficient | Typed patches and commands, queues, retry, cursors, conflict rebase, and recovery |
| Supabase | The same entity graph | PostgreSQL schema, checks, indexes, grants, RLS, push functions, and pull history |
| Queries | Relationships, participants, uniqueness, predicates, and ordering | Named lists, inverse lists, exact lookups, keyset paging, and reactive state |
| Flutter | An account-scoped graph and optional route files | Lifecycle scope, Hooks bindings, and typed GoRouter locations |
| Testing | A generated graph | Real in-memory persistence and synchronization using production descriptors |

## Entity declarations

Nodus discovers `@Entity()` declarations under `lib/**/domain/`. Each entity
file contains one public abstract domain type:

```dart
import 'package:nodus/nodus.dart';

final class Account {}

enum TaskStatus { todo, done }

@Entity()
abstract class Task
    implements OwnedBy<Task, Account>, Archivable, SoftDeletable {
  @Persisted(minLength: 1, maxLength: 160)
  abstract final String title;

  @Persisted(defaultValue: TaskStatus.todo)
  abstract final TaskStatus status;

  abstract final DateTime? dueAt;

  bool get isCompleted => status == TaskStatus.done;

  @Action(values: [ActionValue(#status, TaskStatus.done)])
  Future<void> complete();
}
```

`@Entity()` is the only graph-membership annotation. Nodus owns graph
discovery, the generated implementation, the public `nodus.g.dart` facade, the
test harness, the schema version, and the physical schema fingerprint.

### Fields and persisted types

Declared instance fields are persisted by convention. Computed getters and
pure methods remain handwritten domain behavior on the generated entity
identity.

| Declaration | Meaning |
| --- | --- |
| `abstract final T value` | Immutable persisted field; available at creation when caller-supplied |
| `@Persisted(...)` | Default, bounds, conflict policy, editability, transitions, or authority override |
| `@Reference(...) LocalId<T>` | Typed relationship with generated accessors and remote referential behavior |
| `@Transient()` | Explicitly exclude a real declared field from persistence |
| `ExclusiveFieldGroup(...)` | Enforce zero-or-one or exactly-one membership across nullable fields |
| `PersistedScalarValue<Wire>` | Store a nominal domain value as one native `String`, `bool`, `int`, or `double` scalar |
| `LocalDate` | Store a timezone-free calendar date as Drift text and PostgreSQL `date` |

Nodus derives native Drift, PostgreSQL, and wire representations for supported
Dart scalars, enums, nominal IDs, dates, and references. Structured or repeated
state is represented by typed child entities and relationships rather than JSON
blobs or object trees.

String and numeric bounds, enum membership, defaults, exclusive groups, and
cross-field comparisons are validated from the same declaration in Dart,
Drift, transport decoding, the in-memory backend, and PostgreSQL.

### Ownership and generated conventions

`OwnedBy<Self, Owner>` keeps both the entity and authenticated owner IDs
nominal. Ordinary entities use a generated owner field. An account-root entity
may use `Ownership.identity`, where its primary key is also the authenticated
account ID and the redundant owner column is omitted.

The graph infers one account type and requires its `LocalId<Account>` when it
opens. Generated create methods derive ownership from that graph; callers do
not pass an arbitrary owner ID.

The generated conventions also own `id`, `createdAt`, `updatedAt` when used,
`deletedAt`, and `serverVersion`. `ServerVersion` is nominal so domain code
cannot confuse remote concurrency with local revisions or pull sequences.

### Server-authoritative fields

`@Persisted(authority: FieldAuthority.server)` declares trusted remote workflow
state. The field must be immutable and have a local/SQL default when non-null.
It is omitted from client create and patch payloads and changes only when a
canonical remote record is applied.

An entity made entirely from immutable server-authoritative fields becomes a
read-only synchronized projection: it receives storage, RLS, change capture,
local queries, and pull behavior without unusable client mutation APIs.

## Generated entity API

Applications create through the generated set and mutate the returned entity
directly:

```dart
final task = await entityGraph.tasks.create(title: 'Ship Nodus');

final draft = task.beginEdit()..title = 'Publish Nodus';
await draft.save();

await task.complete();
await task.archive();
await task.remove();
```

The entity updates optimistically. Awaiting a mutation proves that the local
projection and, for a synchronized entity, its durable remote intent committed
atomically. It does not wait for the network.

### Creation and edit drafts

The set exposes `beginCreate()` and editable entities expose `beginEdit()`.
Both return one typed `<Entity>MutationDraft`.

- Required values, defaults, and editable fields are derived from the entity.
- `save()` validates one complete candidate before changing persistence.
- Concurrent changes to unrelated fields merge over the latest entity.
- A different concurrent value for the same field raises
  `EntityDraftFieldConflictException` with the overlapping field names.
- An unchanged draft is a true no-op; `discard()` consumes it without mutation.
- A failed persistence commit rolls the optimistic entity back and rethrows the
  original error.

Identity, ownership, timestamps, lifecycle fields, relationships, and fixed
action assignments remain behind their specific generated APIs.

### Actions and transitions

An abstract `@Action` declares one atomic business transition. Required method
parameters map to same-named fields; `ActionValue` supplies fixed, cleared, or
clock-derived values.

`AllowedTransition` defines the valid edges for an enum field and may restrict
an edge to particular principals. Nodus applies the same transition contract in
the local runtime, deterministic backend, and locked PostgreSQL push function.

Action names describe domain meaning. Generic `edit` actions are rejected
because ordinary editing belongs to the generated draft.

### Standard capabilities

| Capability | Generated behavior |
| --- | --- |
| `SoftDeletable` | Tombstone-backed `remove()` and `restore()` |
| `Archivable` | `archive()`, `unarchive()`, archive-aware indexes, and list visibility |
| `Ordered` | Hidden rank storage, scoped indexes, placement-aware creation, and semantic movement |
| `Collaborative<Principal>` | Durable `setCollaborator(...)`, membership storage, and authorization |
| `ActivityTracked` + `ActivityOf<Subject, Actor>` | Immutable activity entries appended in the same mutation batch |
| `Component` | Aggregate-owned identity and creation through a generated composition relationship |
| `Activatable` | Generated active/inactive relationship membership and filtering |

Capabilities are complete vertical features. Do not repeat their generated
fields, methods, storage, or synchronization plumbing in the entity.

## Queries and reactive identity

One loaded ID maps to one stable MobX-observable object. Local mutations and
remote changes update that same identity, so application state does not need a
second entity cache or provider projection.

```dart
final openTasks = TaskList.all(
  entityGraph,
  where: TaskFields.status.equals(TaskStatus.todo),
  orderBy: TaskFields.dueAt.ascending(),
);
```

Generated field objects provide typed equality, set-membership, range, and
ordering operations. The same predicate evaluates in memory, forms a stable
cache key, and compiles to Drift SQL.

### Cardinality and paging

| Cardinality | Runtime behavior |
| --- | --- |
| `Cardinality.bounded` | The complete collection stays in the observable identity map and queries evaluate synchronously. |
| `Cardinality.unbounded` | Queries use keyset-paged Drift SQL and retain only leased identities. |

The public predicate, ordering, query state, and list APIs remain the same.
Exhaustive operations are generated only when collection completeness is known.

### Generated lists and lookups

Each entity receives a domain-named `<Entity>List`. Nodus infers the selectors
that the graph can prove, including:

- `all`;
- `forOwner` for separately owned entities;
- `for<Reference>` and `for<Participant>`;
- `visibleTo` for owner-or-participant visibility;
- exact selectors from non-null unique compound indexes;
- inverse relationship lists.

By-ID and exact-index reads use `EntityLookup<E>`. Unbounded sets also expose
`loadById(..., refresh:)`; bounded sets use synchronous `byId` and `require`
because they are already complete.

Ordinary lists exclude tombstones and archives as appropriate. Repair and audit
flows opt into `TombstoneVisibility` or `ArchiveVisibility` explicitly.

### Leases, streams, and Flutter bindings

Unbounded identities and cached queries are retained only while a consumer owns
a lease. Imperative code uses lookup `use(...)` or query `useAll(...)`; stream
subscriptions release their reaction and lease when cancelled.

| API | Purpose |
| --- | --- |
| `watchById` | Observe one stable identity without a provider cache |
| `watchQuery` | Observe a paged cached query |
| `watchCompleteQuery` / `watchCompleteStates` | Load and emit only exhaustive snapshots |
| `useObservedEntityList` | Bind list lease and loading/data/empty/failure rendering to a widget |
| `useObservedEntityLookup` | Render typed zero-or-one lookup state |
| `useEntityQueryScrollController` | Trigger keyset paging from scroll position |
| `useEntityAction` | Own reusable busy/error feedback for awaited operations |

## Relationships and authorization

Relationships keep nominal target IDs end to end. PostgreSQL retains the
authoritative foreign keys and delete behavior. Drift intentionally permits a
visible child whose RLS-hidden target is absent from the local projection;
generated accessors resolve that missing target to `null`.

| Declaration | Use |
| --- | --- |
| `@Reference()` | Typed forward and inverse relationship |
| `@OwnerReference()` | Derive a relationship entity's owner from one referenced target |
| `@AccessParticipant()` | Grant a directly named account access to an owner-scoped row |
| `@AccessReference()` | Inherit access from a referenced endpoint |
| `@AccessTarget()` | Extend a finite relationship audience to an existing target |
| `CollaborationAccess()` | Direct owner-controlled collaborator membership |
| `CollaborationAccess.workflow()` | Invitation/acceptance workflow modeled as a normal membership entity |

Nodus derives the supporting indexes, RLS predicates, push authorization, pull
visibility, audience snapshots, and revocations. Invalid nullable access paths,
cycles, conflicting ownership, and unbounded authorization fan-out fail at
generation time.

Generated SQL revokes broad table privileges before granting the narrow reads
required by the graph. Authenticated writes enter through locked generated push
functions; patch, capture, publication, and trigger helpers remain server-only.

Recursive `LocalId<Self>` references are supported. Polymorphic relationships
use `ExclusiveFieldGroup` so the same exactly-one rule is enforced across Dart,
Drift, PostgreSQL, and synchronization.

## Ordered collections

An entity or relationship implements `Ordered` to join one canonical order.
Nodus infers its order scope, opaque `OrderRank`, physical indexes, serialization
lane, and semantic collection operations. Feature code never reads or writes a
rank.

- `create(...)` appends and `createFirst(...)` inserts at the canonical start.
- Neighbor moves operate without loading an entire unbounded collection.
- Exact `reorder` is generated only for a complete bounded collection.
- Create, remove, restore, move, transfer, and reorder share the same inferred
  scope lock and monotonic scope version.
- Adapters receive semantic movement intent rather than local rank patches.

Ranks have identical ordering in Dart, SQLite, and PostgreSQL. When no value
fits between neighbors, generated infrastructure performs the canonical scoped
rebalance without exposing that maintenance to feature code.

> Legacy entities with a non-negative `sortOrder` and exact `moveTo` action may
> retain compatibility APIs during migration. New declarations use `Ordered`.

## Synchronization and remote targets

Every non-local entity has one target and one authority mode:

| Mode | Behavior |
| --- | --- |
| `localOnly` | State remains on the device and creates no remote work. |
| `replicated` | Local changes are pushed and remote changes are pulled. |
| `imported` | The remote system is authoritative; local mutation is rejected. |
| `exported` | Local state is authoritative and is delivered outward. |

Replicated or exported mutations write the local projection and durable queue
intent in one Drift transaction. A target-partitioned worker handles retry,
idempotency, dependency ordering, remote signals, cursors, and restart recovery.

### Supabase

Supabase is the built-in production target in `0.1.0`. Nodus generates native
PostgreSQL tables and constraints, narrow grants, RLS, locked push functions,
operation receipts, ordered change history, and pull behavior from the same
entity graph.

Realtime signals are wake-up hints. Correctness comes from ordered pull history
and a durable per-target cursor.

### Custom connectors

A custom connector synchronizes the entities assigned to one named target with
a specific remote system. For example,
`dart run nodus init --target rest_api` generates a managed
`openRestApi(...)` factory:

```dart
final entityGraph = await TasksExampleEntityGraph.openRestApi(
  accountId: accountId,
  connector: (context) => RestApiAdapter(
    client: client,
    definition: context.definition,
  ),
);
```

`SyncConnectorContext` supplies the authenticated account, stable target, and
the target-only `EntityGraphDefinition`. The adapter implements the required
push and/or pull capability against that remote API. Nodus continues to own the
entity selection, codecs, durable queue, cursors, conflict handling, and local
storage.

Multi-target graphs use `openWithConnectors(...)` with one capability-typed
callback per target. A connector translates transport; it does not redefine
entities or choose their destination.

### Protocol safety and recovery

- Durable operations carry nominal entity and operation IDs.
- `PushResult.validateFor` rejects the wrong identity, missing or mismatched
  receipts, duplicate canonical changes, and invalid primary results.
- Related acknowledgements merge atomically before reactive projections
  publish.
- A newer remote base rebases surviving local intent and assigns a fresh
  operation ID.
- Signals received during a pull schedule exactly one follow-up pull after the
  cursor commits.
- Graph shutdown joins projection, queue, signal, and synchronization work
  before Drift closes.

Broad authenticated reads do not automatically become global offline data.
Bounded readable entities participate in graph pull; unbounded broad datasets
remain on-demand unless `authenticatedReadSync` explicitly changes that policy.

## Flutter integration and navigation

`AccountEntityGraphSession<G, Account>` serializes account opening, switching,
and closing. `AccountEntityGraphScope<G, Account>` publishes only the
signed-out, opening, ready, and failure lifecycle to the widget tree. Entity and
query state remain direct MobX observations, so an entity mutation does not
rebuild the entire application scope.

The graph exposes `nowUtc()` from its injected clock. Application operations and
tests can sample the same deterministic time source without exposing mutable
clock infrastructure.

### Typed route generation

Route generation is optional and separate from entity persistence. Route files
are ordinary typed Flutter page entries stored under:

```text
lib/features/<feature>/presentation/pages/**/page.dart
```

Directories below `pages/` define the URL structure. The feature directory
expresses code ownership and does not become a URL segment. Each `page.dart`
contains either one Widget class ending in `Page` or one top-level
`Widget ...Page(...)` function.

Nodus generates typed GoRouter locations from those entries:

- page parameters become typed path or query values;
- Dart defaults remain the source of truth;
- feature trees may contribute layouts, guards, and redirects;
- one root tree owns `not_found.dart`;
- ambiguous paths and generated names fail at build time.

`FileRouteDependency<T>` provides statically typed route dependencies.
`FileRoutePagePresentation` keeps an exceptional sheet or transition beside the
page that owns it. Reusable non-route widgets live under
`presentation/components/`.

## Generation, migrations, and testing

The compiler resolves entity meaning once into an immutable
`EntityGraphDefinition`. Dart, Drift, PostgreSQL, protocol, query, and test
emitters consume resolved facts rather than repeating inference.

### Tool commands

| Command | Purpose |
| --- | --- |
| `dart run nodus init --target NAME` | Discover entities and create `nodus.lock` plus standard builder configuration |
| `dart run nodus generate` | Regenerate Dart artifacts without advancing the schema |
| `dart run nodus watch` | Regenerate while entity or route sources change |
| `dart run nodus migrate NAME` | Advance the schema and generate local and remote migrations |
| `dart run nodus explain [ENTITY] [--json]` | Show resolved inference and its provenance |
| `dart run nodus inventory [--write\|--check\|--json]` | Classify semantic migration debt |
| `dart run nodus check` | Fail on stale output, schema lock, or opted-in inventory |

`migrate` updates the schema version and generates the Drift migration,
canonical Supabase schema, and reviewed SQL diff together. A physical schema
change without a migration name fails generation.

For incremental adoption, ordered `supabase/schema_sources/*.sql` files are
composed before generated entity SQL and reviewed
`supabase/schema_extensions/*.sql` files after it.
`--defer-supabase-composition` may regenerate Dart and Drift during a
coordinated rewrite without changing the canonical remote schema; it cannot be
combined with a deployment migration.

### Generated test harness

Every graph provides an in-memory harness with the real generated graph,
production descriptors, Drift database, deterministic clock and IDs, and
descriptor-compatible synchronization backend. Tests exercise production
entities, queries, persistence, and synchronization without repeating graph
wiring or introducing mock repositories.

The [Tasks reference app](../example/tasks/) demonstrates offline mutation,
ordering, collaboration, activity, paging, typed routes, adaptive Flutter UI,
and the durable sync queue end to end.

### Package entrypoints

| Library | Purpose |
| --- | --- |
| `nodus.dart` | Entity declarations, typed IDs, queries, synchronization contracts, and local runtime |
| `nodus_flutter.dart` | Account lifecycle, Hooks bindings, and typed route runtime |
| `nodus_supabase.dart` | Descriptor-driven Supabase synchronization |
| `nodus_testing.dart` | Deterministic clock and generated-harness support |
| `nodus_migrations.dart` | Narrow Drift types used by generated migrations |

Applications import their generated `nodus.g.dart` facade. Imports from
`package:nodus/src/...` are unsupported.

## Related documentation

- [README](../README.md) — package overview and quick start.
- [Writing custom application code](custom-code.md) — where business and
  external integration code belongs.
- [Architecture](Architecture.md) — normative ownership, persistence,
  synchronization, routing, and conformance rules.
- [Architecture atlas](Architecture.puml) — detailed compiler and runtime
  views.
- [Tasks example](../example/tasks/README.md) — executable end-to-end usage.
- [Contributing](../CONTRIBUTING.md) — development workflow and quality gates.
