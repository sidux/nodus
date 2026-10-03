# Capability reference

This page lists what you can declare and what Nodus generates from it,
organized by task. It assumes you know the vocabulary from
[Core concepts](concepts.md); for a first walk-through, start with
[Getting started](getting-started.md).

The [architecture contract](Architecture.md) is normative wherever this page
leaves out a detail.

Examples use the [Tasks reference app](../example/tasks/README.md): package
`tasks_example`, graph `TasksExampleEntityGraph`, entities `Task` and
`TaskProject`.

**Contents**

- [At a glance](#at-a-glance)
- [Declaring entities](#declaring-entities)
- [Creating and changing entities](#creating-and-changing-entities)
- [Standard capabilities](#standard-capabilities)
- [Reading: queries, lookups, and identity](#reading-queries-lookups-and-identity)
- [Relationships and authorization](#relationships-and-authorization)
- [Ordered collections](#ordered-collections)
- [Synchronization and remote targets](#synchronization-and-remote-targets)
- [Online-only operations](#online-only-operations)
- [Flutter integration](#flutter-integration)
- [Typed route generation](#typed-route-generation)
- [Migrations](#migrations)
- [Testing](#testing)
- [Package entrypoints](#package-entrypoints)

## At a glance

| Concern | You declare | Nodus generates |
| --- | --- | --- |
| Entity model | Fields, defaults, constraints, relationships, capabilities | Typed entities, nominal IDs, codecs, descriptors, sets |
| Mutation | Editable fields and named `@Action` methods | Create/edit drafts, validation, rollback, lifecycle operations, durable sync intent |
| Local data | Cardinality and indexes | Drift tables, migrations, paging, identity retention, query caches |
| Synchronization | Sync mode or target only when the default does not fit | Typed payloads, queues, retry, cursors, conflict handling, recovery |
| Supabase | Nothing extra | PostgreSQL schema, checks, indexes, grants, RLS, push functions, pull history |
| Queries | Relationships, participants, uniqueness, predicates, ordering | Named lists, inverse lists, exact lookups, keyset paging, reactive state |
| Flutter | An account session and optional page files | Lifecycle scope, Hooks bindings, typed GoRouter routes |
| Testing | Nothing extra | A harness running the real graph in memory |

## Declaring entities

Nodus discovers `@Entity()` classes in `domain/` directories under `lib/`
(`lib/**/domain/**.dart`). Put each entity in its own file as one public
abstract class. An `@Entity` outside a `domain/` directory does not get an
implementation and breaks the build.

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

`@Entity()` is the only annotation that adds a class to the graph. There is no
graph class, registry, or schema version to write.

### Fields

Every `abstract final` instance field is persisted. `final` means the entity
has no public setter: you change a field through a draft, an action, or a
generated lifecycle method, never by assignment. Getters and pure methods are
ordinary handwritten code on the same object.

| Declaration | Meaning |
| --- | --- |
| `abstract final T name;` | Persisted field. Non-null fields without a default are required at creation. Editable through drafts unless something below says otherwise. |
| `@Persisted(...)` | Constraints, default, editability, normalization, conflict policy, transitions, or authority (see below). |
| `@Reference(onDelete: ...) LocalId<T>? fooId` | A live relationship to entity `T`; see [Relationships](#relationships-and-authorization). |
| `LocalId<T>` without `@Reference` | A typed ID that may outlive its target (history, audit). No foreign key or inverse list. |
| `@Transient()` | Keep a declared field out of persistence. |
| `@PersistedVariant()` | Store a sealed class as mutually exclusive native columns. |
| `PersistedScalarValue<Wire>` | A value type stored as one native `String`, `bool`, `int`, or `double` (it provides `toScalar()` and `fromScalar(...)`). |
| `LocalDate` | A timezone-free calendar date (Drift text, PostgreSQL `date`). |

Supported scalars — `String`, `int`, `double`, `bool`, `DateTime`, enums,
`LocalDate`, and IDs — map to native Drift, PostgreSQL, and wire types.
Collections, maps, and JSON blobs are rejected: model repeated or structured
state as a child entity with a relationship.

### `@Persisted` options

| Option | Effect |
| --- | --- |
| `defaultValue` | Value used when creation omits the field. |
| `minLength`, `maxLength`, `allowWhitespace` | String bounds. |
| `minValue`, `maxValue` | Numeric bounds. |
| `allowedValues` | Restrict a field to listed values. |
| `greaterThan: #other`, `greaterThanOrEqual: #other` | Ordering between two numeric fields. |
| `notEqualTo: #other` | Two fields may not hold the same value. |
| `requires: #other` | This nullable field may be set only when `other` is set. |
| `normalization` | `FieldNormalization.trim` or `.trimToNull`, applied everywhere before validation. |
| `editable: false` | Settable at creation or by actions only, not by edit drafts. |
| `transitions` | Allowed `AllowedTransition(from, to)` edges for an enum field. |
| `conflict` | `ConflictStrategy.serverWins` (default) or `.localWins` for this field. |
| `authority: FieldAuthority.server` | Only the server writes this field. |
| `updateBy` | Restrict which principals may update the field. |
| `column`, `renamedFrom`, `sinceProtocolVersion` | Storage and protocol evolution overrides. |

Every constraint is enforced from the same declaration in Dart, Drift,
transport decoding, the in-memory test backend, and PostgreSQL.

Use `ExclusiveFieldGroup` on the entity for "at most one" or "exactly one" of
several nullable fields:

```dart
@Entity(exclusiveFieldGroups: [
  ExclusiveFieldGroup([#taskId, #projectId], allowNone: false),
])
```

### `@Entity` options

All options are optional; use one only when the default does not fit.

| Option | Use |
| --- | --- |
| `cardinality` | `Cardinality.unbounded` (default, paged from Drift) or `.bounded` (complete set kept in memory). See [Cardinality](#cardinality-and-paging). |
| `ownership` | `Ownership.separate` (default) or `.identity` for an account-root entity whose ID *is* the account ID. |
| `sync`, `syncTarget` | Override the [sync mode](#synchronization-and-remote-targets) or target. |
| `indexes` | `CompoundIndex(...)`, `CompoundIndex.query(...)`, `CompoundIndex.unorderedWithOwner(...)`. |
| `exclusiveFieldGroups` | See above. |
| `orderScope` | The fields that scope an `Ordered` entity, when they cannot be inferred. |
| `collaboration` | `CollaborationAccess(...)` policy; see [authorization](#relationships-and-authorization). |
| `authenticatedReadSync` | Whether broadly readable data is synchronized eagerly or on demand. |
| `grants`, `referenceAccessGuards` | Exceptional row-level-security rules. |
| `table`, `setAccessor` | Rename the table or the `entityGraph.<set>` accessor to resolve a collision. |
| `coIdentityWith` | Identity-owned entity types that deliberately share the same UUID. |

`@Indexed()` on a field adds a single-field index. `@Indexed(unique: true)` on
a non-null field also generates an exact lookup: `bySlug(...)` and
`createOrGetBySlug(...)` on a bounded set, or `<Entity>Lookup.bySlug(...)` for
an unbounded one (for a field named `slug`).

### Ownership

`OwnedBy<Self, Owner>` says that each row belongs to one authenticated
account. The graph opens for one `LocalId<Account>`, and generated `create`
methods fill in the owner automatically; callers never pass an owner ID. Row
level security uses the same rule on the server.

Nodus also owns the conventional fields `id`, `deletedAt`, and
`serverVersion`. Declaring `createdAt` or `updatedAt` gives them automatic
clock values.

### Server-authoritative fields

`@Persisted(authority: FieldAuthority.server)` marks state that only trusted
server workflows change. The field must have a default when non-null. It is
left out of client create and edit payloads and changes only when the
server's version arrives.

### Validation and diagnostics

Generation fails, with a message naming the smallest fix, for duplicate names,
unsupported types, invalid defaults, unresolved or cyclic relationships,
ambiguous ownership, unsafe uniqueness, invalid transitions, and schema
changes without a migration. `dart run nodus explain Task` shows every
inferred value and where it came from.

## Creating and changing entities

```dart
final task = await entityGraph.tasks.create(title: 'Ship Nodus');

final draft = task.beginEdit()..title = 'Publish Nodus';
await draft.save();

await task.complete();
await task.archive();
await task.remove();
```

Every awaited mutation:

1. validates the complete new state;
2. updates the stable in-memory entity immediately;
3. commits the local row and, for synchronized entities, a durable sync work
   item in one Drift transaction;
4. returns when that commit succeeds — never waiting for the network.

If the commit fails, the in-memory change is rolled back and the original
error is rethrown. Failed background persistence is also listed in
`entityGraph.persistenceFailures`.

### Creating

`entityGraph.<entities>.create(...)` takes typed parameters for the creatable
fields, with defaults already applied. For ordered entities, `createFirst`
inserts at the start and `createAt(placement: ...)` chooses explicitly.
Relationship collections also create with the parent filled in:

```dart
final task = await project.tasks(entityGraph).create(title: 'Write docs');
```

`allocateId()` reserves an ID before creation when you need it up front.

### Edit and create drafts

`entityGraph.tasks.beginCreate()` and `task.beginEdit()` return the same typed
`TaskMutationDraft`, with one setter per editable field. A draft is private:
nothing is visible or persisted until `save()`.

- `save()` validates once and commits once; `discard()` drops the draft.
- Changes made elsewhere to *other* fields are merged in.
- A different concurrent value for the *same* field throws
  `EntityDraftFieldConflictException` listing the fields.
- Saving an unchanged draft does nothing.
- Reference fields can be set on a create draft. On an edit draft they are
  read-only, with one exception: the scope field of an `Ordered` entity (for
  example `@Entity(orderScope: [#projectId])`) that a declared action changes,
  such as `moveToProject({required LocalId<TaskProject>? projectId})`. Then
  `save()` applies the edit and that action in one transaction.

Identity, ownership, timestamps, lifecycle fields, and fixed action values are
never on a draft. In Flutter, use the [form hooks](#forms).

When one form owns several entities (a root plus its composed or
aggregate-member children), Nodus also generates a `<Root>AggregateDraft`
that saves the whole tree in one transaction.

### Actions and transitions

An abstract `Future<void>` method annotated with `@Action` is one atomic,
named business transition. Its implementation is generated:

```dart
@Action()
Future<void> moveToProject({required LocalId<TaskProject>? projectId});

@Action(values: [
  ActionValue(#status, TaskStatus.done),
  ActionValue.clockNow(#completedAt),
])
Future<void> complete();

@Action(values: [
  ActionValue(#status, TaskStatus.todo),
  ActionValue.clear(#completedAt),
])
Future<void> reopen();
```

- Each required parameter sets the field with the same name.
- `ActionValue(field, value)` sets a fixed value, `ActionValue.clockNow` the
  current time, and `ActionValue.clear` null.
- `@Action(bulk: true)` also generates `<Entity>List.<action>All(...)` to apply
  the action to a whole selection.
- Nodus never infers meaning from a method name. A generic `edit` action is
  rejected, because ordinary editing is what drafts are for.

`@Persisted(transitions: [AllowedTransition(TaskStatus.todo, TaskStatus.done)])`
lists the allowed edges of an enum field, optionally restricted by principal
with `by:`. The same rule is enforced locally, in the test backend, and in the
generated PostgreSQL push function.

### Transactions

Group several mutations into one atomic local commit:

```dart
await entityGraph.transaction(() async {
  final project = await entityGraph.taskProjects.create(title: 'Launch');
  final task = await entityGraph.tasks.create(
    title: 'Announce',
    projectId: project.id,
  );
  await task.complete();
});
```

Inside the callback, `await create(...)` returns the new entity right away so
later steps can reference it; the outer future is the single durability and
failure boundary. Nested transactions join the outer one. Never perform
network calls inside a transaction.

### Bulk lifecycle operations

Lists of entities with lifecycle capabilities expose `removeAll()`,
`restoreAll()`, `archiveAll()`, and `unarchiveAll()`, which page through the
selection in transactions instead of loading it into memory.

## Standard capabilities

Implement a capability interface to switch on a complete feature: fields,
storage, validation, indexes, sync, security, and methods. Do not redeclare
the members a capability supplies.

| Capability | What you get |
| --- | --- |
| `SoftDeletable` | `remove()` and `restore()` backed by synchronized tombstones; tombstones are hidden from ordinary queries. |
| `Archivable` | `archive()`, `unarchive()`, `archivedAt`, and `.active` / `.archived` list selectors. |
| `Ordered` | A hidden rank, scoped ordering, `createFirst`, and neighbor moves. See [Ordered collections](#ordered-collections). |
| `Collaborative<Principal>` | `setCollaborator(principalId, active: ...)`, membership storage, and authorization. |
| `ActivityTracked` + `ActivityOf<Subject, Actor>` | An immutable activity entry appended with every change. See below. |
| `Activatable` | An `active` flag with `activate()` / `deactivate()` for relationship rows; inactive rows are hidden by default. |
| `WorkflowMembership<Target, Principal, Status>` | Invitation-style membership with `accept()`, `decline()`, `revoke()`, `reinvite()`, and invite-or-reuse creation. `Status` must define `pending`, `accepted`, `declined`, and `revoked`. |
| `Component` + `@Composition` | A child owned by exactly one aggregate, created in the same transaction as its root. |

### Activity tracking

The tracked entity implements `ActivityTracked` and returns a label; one
separate entity implements `ActivityOf<Subject, Actor>`:

```dart
@Entity()
abstract class Task implements OwnedBy<Task, Account>, ActivityTracked {
  abstract final String title;

  @override
  String get activityLabel => title;
}

@Entity()
abstract class TaskActivity
    implements OwnedBy<TaskActivity, Account>, ActivityOf<Task, Account> {}
```

Every real create, edit, action, lifecycle change, collaboration change, or
move on a `Task` appends one `TaskActivity` in the same transaction. Failed or
no-op mutations record nothing, and synchronized changes are not recorded
twice. Entries store structured facts (operation, label, actor, time); format
them in the UI.

## Reading: queries, lookups, and identity

One loaded ID maps to one stable, MobX-observable object. Local edits and
remote changes update that same object, so there is no second cache or
provider copy.

```dart
final openTasks = TaskList.all(
  entityGraph,
  where: TaskFields.status.equals(TaskStatus.todo) |
      TaskFields.status.equals(TaskStatus.inProgress),
  orderBy: TaskFields.dueAt.ascending(),
);
```

`<Entity>Fields` provides typed equality, membership, range, null checks,
text containment, and ordering, combined with `&` and `|`. The same predicate
runs in memory and compiles to Drift SQL, so filtering happens before paging.

### Cardinality and paging

| Cardinality | Behavior |
| --- | --- |
| `Cardinality.unbounded` (default) | Queries page through Drift with keyset pagination and keep only the entities currently in use. |
| `Cardinality.bounded` | The complete collection stays in memory; `entityGraph.<set>.all`, `byId`, and `require` are synchronous. |

Declare `bounded` only when the collection is guaranteed to stay small. The
list, predicate, and query-state APIs are the same either way.

### Lists

Each entity gets a domain-named `<Entity>List` with the selectors the graph
can prove, for example:

| Selector | Generated when |
| --- | --- |
| `TaskList.all(entityGraph)` | Always. |
| `TaskList.owned(entityGraph)` | The entity is owned separately; the owner is the signed-in account. |
| `TaskList.forOwner(entityGraph, ownerId)` | Selecting another owner is authorized. |
| `TaskList.forProject(entityGraph, projectId)` | Per `@Reference` and participant field. |
| `TaskList.active(...)` / `.archived(...)` | The entity is `Archivable`. |
| Inverse lists such as `project.tasks(entityGraph)` | Per `@Reference`. |

Every list accepts `where:` and `orderBy:`. Lists hide tombstones, archived
rows, and inactive relationships by default; recovery or audit screens opt in
with `tombstones: TombstoneVisibility.include` (or `.only`), `archives:
ArchiveVisibility...`, or `inactive: InactiveVisibility...`. A `where`
predicate can only narrow that default, never bypass it.

A list holds resources: call `dispose()` when done, or let a Flutter hook own
it.

### Lookups and single reads

| API | Use |
| --- | --- |
| `entityGraph.tasks.lookup(id)` | An `EntityLookup` (zero or one) for an unbounded set, usually owned by `useObservedEntityLookup`. |
| `<Entity>Lookup.by<Key>(entityGraph, ...)` | Exact lookup by a non-null unique key on an unbounded set. |
| `by<Key>(...)` | The same, synchronously, on a bounded set. |
| `entityGraph.tasks.usePresentById(id, (task) async { ... })` | Load, use, and release one entity; throws if absent or deleted. |
| `loadPresentById(id)` / `loadById(id, refresh:)` | Manual lease control for advanced code. |
| `byId`, `require`, `byPresentId`, `requirePresent` | Synchronous reads on bounded sets. |
| `createOrGetBy<Key>(...)` | Bounded sets with a unique key: return the live match or create it. |
| `exists(where: ...)`, `first(where:, orderBy:)` | Existence check and first match without loading a page. |

### Leases and exhaustive reads

Unbounded entities stay loaded only while something holds a **lease**. Hooks
and `use...` callbacks manage leases for you. `list.useAll((items) { ... })`
pages through a complete selection for one calculation and releases
everything afterwards; reserve it for results that genuinely need every row.
A record of lists, `(listA, listB).useAll(...)`, reads several concurrently,
and `await (futureA, futureB).waitAll` (a getter) awaits differently typed
futures into a typed record.

### Streams

`entityGraph.tasks.watchById(id)`, the set's `watchQuery(...)` and
`watchCompleteQuery(...)`, and a list's `watchCompleteStates()` emit changes;
cancelling the subscription releases its lease.

## Relationships and authorization

```dart
@Reference(onDelete: ReferenceDeleteAction.setNull)
abstract final LocalId<TaskProject>? projectId;
```

A `@Reference` field must end in `Id`. It generates a forward accessor, an
inverse list on the target, the foreign key, and authorization metadata.
`onDelete` (`restrict`, `cascade`, or `setNull`) is required because delete
behavior is a domain decision.

| `@Reference` option | Use |
| --- | --- |
| `inverse` | Name of the generated inverse list on the target. |
| `inverseCardinality` | `Cardinality.bounded` when each target's children form a small complete set. |
| `aggregateMember` | The child is edited as part of its parent's aggregate draft. |
| `hierarchy` | A self-reference forming a tree, with generated subtree remove/restore/archive. |

PostgreSQL keeps the authoritative foreign keys. Locally, a child may
reference a target the user cannot see; the generated accessor then returns
`null`.

### Access rules

| Declaration | Use |
| --- | --- |
| `OwnedBy<Self, Owner>` | The owner can read and write the row. |
| `@OwnerReference()` | Derive a row's owner from a referenced entity. |
| `@AccessParticipant()` | A `LocalId<Account>` field whose account may access the row. |
| `@AccessReference()` | Access the row whenever you can access the referenced entity. |
| `@AccessTarget()` | A relationship row grants its audience access to the target it points to. |
| `Collaborative<Principal>` with `CollaborationAccess()` | Owner-managed collaborators. |
| `CollaborationAccess.workflow()` | Invitation and acceptance through a `WorkflowMembership` entity. |
| `CollaborationAccess.workflow(editPermissionField: ...)` | Same, where a membership bool separates editors from read-only members. |

From these, Nodus derives indexes, RLS policies, push authorization, pull
visibility, and the snapshots and revocations sent when access changes.
Ambiguous or unsafe access paths fail generation rather than producing
permissive policies.

Generated SQL revokes broad privileges and grants only the reads the graph
needs. Clients write only through generated, locked push functions.

## Ordered collections

Implement `Ordered` to give an entity a canonical order within a scope (its
owner, or a parent such as `projectId`). Nodus stores a hidden `OrderRank` and
generates the operations; your code never reads or writes a rank.

| API | Effect |
| --- | --- |
| `create(...)` / `createFirst(...)` | Append / insert at the start. |
| `entityGraph.tasks.moveBefore(id, neighborId)` / `moveAfter(...)` | Move next to a neighbor without loading the whole collection. |
| `prepend(id)` / `append(id)` | Move to the start / end. |
| `reorder(...)` | Exact reordering, only for complete bounded collections. |

Archiving keeps an item's position; removing it leaves the order. Ranks sort
identically in Dart, SQLite, and PostgreSQL, and are rebalanced automatically
when needed.

## Synchronization and remote targets

Every entity has one sync mode:

| Mode | Behavior |
| --- | --- |
| `localOnly` | Stays on the device; no sync work. |
| `replicated` | Local changes are pushed; remote changes are pulled. |
| `imported` | The remote system is authoritative; local mutation APIs are not generated. |
| `exported` | Local state is authoritative and delivered outward. |

With a default target (the usual setup from `nodus init --target ...`),
entities are `replicated`. Override per entity:

```dart
@Entity(sync: SyncMode.localOnly)
abstract class DraftNote implements OwnedBy<DraftNote, Account> {
  abstract final String body;
}
```

A background worker handles retry with backoff, idempotency, dependency
ordering, cursors, and restart recovery, per target. Call
`entityGraph.sync()` to synchronize now, and observe pending work through
`entityGraph.syncQueue`.

### Supabase

Supabase is the built-in target. Open the graph with the generated factory:

```dart
final entityGraph = await TasksExampleEntityGraph.openSupabase(
  accountId: parseLocalId<Account>(user.id),
  client: Supabase.instance.client,
);
```

Nodus generates native PostgreSQL tables and constraints, narrow grants, RLS,
locked push functions, operation receipts, and ordered change history.
Realtime messages only wake the worker; correctness comes from the ordered
history and a durable cursor. Sync work waits while the account is not signed
in instead of failing.

### Custom connectors

A custom connector translates Nodus's push/pull protocol to another backend.
Initialize with your own target name, for example
`dart run nodus init --target rest_api`, and Nodus generates
`openRestApi(...)`:

```dart
final entityGraph = await TasksExampleEntityGraph.openRestApi(
  accountId: accountId,
  connector: (context) => RestApiAdapter(
    client: client,
    definition: context.definition,
  ),
);
```

`RestApiAdapter` is your class. It implements `PushSyncAdapter`,
`PullSyncAdapter`, or `PushPullSyncAdapter` — whichever the target's entities
require:

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
```

`SyncConnectorContext` provides the account, the target, and the
target-specific `EntityGraphDefinition`. Nodus keeps owning entity selection,
codecs, the durable queue, cursors, conflict handling, and local storage; the
adapter only moves data. Every graph also has `openWithConnectors(...)`, which
takes one connector per target.

### Protocol safety and recovery

- Durable operations carry typed entity and operation IDs; retries are
  idempotent.
- `PushResult.validateFor` rejects wrong identities, missing or mismatched
  receipts, and duplicate changes.
- Related acknowledgements merge in one transaction before the UI sees them.
- When a newer remote version arrives, remaining local changes are rebased on
  top of it.
- Closing the graph waits for in-flight local work before Drift closes.

Broadly readable data is not downloaded wholesale by default: bounded
readable entities are pulled, while unbounded ones load on demand unless
`authenticatedReadSync` says otherwise.

### Durable processes and projections

For work that must survive restarts — sending entity changes to a search
index, or reacting to an entity change with an external call —
`@EntityProcess` and `@SecondaryProjection` declare durable, retried
background lanes driven by `WorkSource` triggers. See
[Architecture §10.1](Architecture.md#101-sync-targets-and-adapter-composition)
and [§6.6](Architecture.md#66-named-source-creation-and-entity-owned-processes).

## Online-only operations

Some calls cannot work offline, such as a payment or an AI request. Give them
a typed contract and keep them outside entity persistence:

```dart
final summarize = ExternalCapabilityContract<String, String>.jsonObject(
  name: 'summarize-task',
  encodeRequest: (text) => {'text': text},
  decodeResponse: (json) => json['summary']! as String,
);

final summary = await SupabaseExternalCapabilityAdapter(client)
    .invokeFunction(summarize, task.description!);
```

`SupabaseExternalCapabilityAdapter` calls an Edge Function
(`invokeFunction`) or RPC (`callRpc`) and maps failures to a typed
`ExternalCapabilityException` with an `ExternalCapabilityFailureKind`. It is
not a cache or retry queue. Commit any resulting entity change through the
generated API. [Writing custom code](custom-code.md#isolate-an-irreducible-external-operation)
shows where this code belongs.

## Flutter integration

### Account lifecycle

`AccountEntityGraphSession<G, Account>` opens, switches, and closes graphs as
the signed-in account changes, one at a time. The generated
`<App>EntityGraphScope` publishes its state to the widget tree:

```dart
final session = AccountEntityGraphSession<TasksExampleEntityGraph, Account>(
  open: (accountId) => TasksExampleEntityGraph.openSupabase(
    accountId: accountId,
    client: client,
  ),
  close: (entityGraph) => entityGraph.close(),
);
await session.switchAccount(accountId); // null signs out

TasksExampleEntityGraphScope(session: session, child: app);
```

`context.tasksExampleEntityGraphState` is one of:

| State | Meaning |
| --- | --- |
| `AccountEntityGraphSignedOut` | No account. |
| `AccountEntityGraphOpening` | Opening the account's graph. |
| `AccountEntityGraphReady` | Ready; carries `accountId` and `entityGraph`. |
| `AccountEntityGraphStoreInUse` | Another live graph (for example another browser tab) owns this account's database. The session reopens automatically when it is released. |
| `AccountEntityGraphFailure` | Opening failed. |

The scope rebuilds only on these transitions, never on entity changes. Also
generated: `context.tasksExampleEntityGraphReady` (nullable),
`context.tasksExampleEntityGraphSession`, and
`context.withReadyTasksExampleEntityGraph((entityGraph) async { ... })`, which
keeps the graph open for the duration of an operation.

A database belongs to one live graph at a time, across processes and browser
tabs. A second opener gets `LocalStoreInUseException`. After deleting an
account, close its graph and call
`TasksExampleEntityGraph.eraseLocalStore(accountId: ...)`.

The graph's injected clock is available as `entityGraph.nowUtc()`, so
application code and tests share one time source.

### Web

On the web the local store uses Drift's WebAssembly build. Serve Drift's
`sqlite3.wasm` and compiled `drift_worker.js` from the app's `web/` root (see
the [Drift web setup](https://drift.simonbinder.eu/platforms/web/)).

### Observing entities and queries

Read entity fields inside a MobX `Observer` (from `flutter_mobx`); only the
fields read are tracked. Nodus provides these hooks, built on
`flutter_hooks`, for queries and actions:

| Hook | Purpose |
| --- | --- |
| `useObservedEntityList(() => list, keys: [...])` | Own a list for the widget's lifetime and fold it with `when(loading:, empty:, data:, failure:)`. It pages automatically as descendant scroll views scroll. When `keys` change, the previous results stay on screen (marked refreshing) until the new ones load. |
| `useObservedEntityQuery` | The same for a raw `LocalEntityQuery`. |
| `useObservedEntityLookup` | Zero-or-one lookup state. |
| `useObservedEntityValue` | A synchronous lookup on a bounded set. |
| `useObservedEntityExistence`, `useObservedEntityFirst` | Existence and first-match state. |
| `ObservedEntityQueryGroup` | Fold several observed queries' shared loading/failure/refresh state. |
| `EntityQueryPagingBoundary` / `observed.pagingBoundary(...)` | Automatic paging when rendering observed state manually. |
| `useEntityQueryScrollController`, `useEntityListScrollController` | A scroll controller that loads pages, for custom scroll setups. |
| `useEntityAction()` | Busy/error state for an awaited operation: `action.run(() async { ... })`, `action.error`. |
| `useEntityList`, `useEntityLookup`, `useEntityQuery`, ... | Lower-level hooks that own the lease without folding state. |

### Forms

```dart
final draft = useEntityMutationDraft(
  () => task == null ? entityGraph.tasks.beginCreate() : task.beginEdit(),
  keys: [entityGraph, task],
);
final title = useEntityDraftTextField(draft.titleField);
final priority = useEntityDraftValue(draft.priorityField);
final save = useEntityAction();

// TextField(controller: title)
// DropdownButton(value: priority.value, onChanged: priority.set)
// onPressed: () => save.run(() => draft.save())
```

`useEntityMutationDraft` discards an abandoned draft, the text and value
bindings write straight into its typed fields, and field constraints are
available for widgets, for example `TaskFields.title.constraints.maxLength`.
Use `useEntityDraftNullableTextField` for nullable text and
`useAsyncEntityMutationDraft` when the draft is loaded asynchronously.

## Typed route generation

Routing is optional and independent of persistence. Pages live under:

```text
lib/features/<feature>/presentation/pages/**/page.dart
```

- Folders below `pages/` form the URL; the feature folder does not.
- `[taskId]` folders are dynamic segments, typed from the page parameter
  (for example `LocalId<Task>`).
- `(group)` folders organize files without adding a URL segment.
- Static folders use lowercase kebab-case.
- Each `page.dart` contains one public widget class ending in `Page`, or one
  top-level function ending in `Page` that returns a widget.

```dart
// lib/features/tasks/presentation/pages/tasks/[taskId]/page.dart
Widget taskDetailsPage(
  TasksExampleEntityGraph entityGraph,
  LocalId<Task> taskId, {
  TaskListFilter filter = TaskListFilter.open,
}) => TasksView(entityGraph: entityGraph, selectedTaskId: taskId, filter: filter);
```

Nodus generates a typed location per page:

```dart
TaskDetailsRoute(task.id, filter: TaskListFilter.completed).go(context);
```

- Named optional parameters become query parameters; Dart defaults stay the
  source of truth and are omitted from the URL.
- Parameters that are not path or query values (here `entityGraph`) are
  dependencies, supplied by type through
  `FileRouteScope(dependencies: [FileRouteDependency(entityGraph)], ...)`.
- `layout.dart` (`Widget appLayout(Widget child)`) wraps the pages below it.
- `guard.dart` returns a `FileRouteRedirect?`, and `redirect.dart` returns a
  `FileRouteRedirect`, for example `FileRouteRedirect.to(tasksPage)`. Targets
  are page functions, not path strings.
- Exactly one root `not_found.dart` is required; route generation runs only
  when it exists.
- Ambiguous paths and duplicate generated names fail at build time.

Build the router with the generated `createFileRouter(...)`, optionally passing
a `FileRouterConfiguration` (navigator key, global redirect, refresh
listenable, observers, and a `defaultPageBuilder` for transitions). A page
widget that needs its own presentation (an adaptive detail, a sheet, no
transition) implements `FileRoutePagePresentation`: its
`buildRoutePage(context, state)` returns a custom `Page`, or `null` to fall
back to `defaultPageBuilder`. Put reusable widgets under
`presentation/components/`.

## Migrations

`nodus.lock` stores fingerprints of the resolved schema. A physical schema
change stops `dart run nodus generate` until you run
`dart run nodus migrate <name>`, which writes the Drift migration, the
canonical Supabase schema, and the Supabase SQL migration together. See the
[command line reference](cli.md#migrate-name) for the details and for
bootstrap, schema composition, and manual SQL files.

Some transitions cannot be applied blindly: adding a constraint, for example,
makes the generated migration (and its generated test) fail with "requires an
explicit manual migration plan" until you decide how existing rows migrate.
Constraint-only local changes generate Drift table rebuilds. When existing
rows already satisfy the new constraint, record that decision in the
migration strategy with `NodusMigrationPlan.acknowledgeGenerated()`. Real data
changes use `NodusMigrationPlan.augment(...)` (your callback runs alongside the
generated steps) or `NodusMigrationPlan.replace(...)` (your callback replaces
them); `NodusMigrationPlan.generated()` is the default. The generated strategy lives in
`lib/src/generated/nodus.migrations.g.dart` — the one generated file an
application imports directly, only at the place that opens the graph:

```dart
import 'package:tasks_example/src/generated/nodus.migrations.g.dart';

final strategy = nodusMigrationStrategy<TasksExampleDatabase>(
  initialPullTargets: TasksExampleMetadata.definition.pullSyncTargets,
  hooks: NodusMigrationHooks<TasksExampleDatabase>(
    planner: (transition) => switch ((transition.from, transition.to)) {
      (1, 2) =>
        const NodusMigrationPlan<TasksExampleDatabase>.acknowledgeGenerated(),
      _ => const NodusMigrationPlan<TasksExampleDatabase>.generated(),
    },
  ),
);

await TasksExampleEntityGraph.openSupabase(
  accountId: accountId,
  client: client,
  migrationOverride: strategy,
);
```

Pass the same strategy as `migrationOverride` in
`test/drift/<database>/migration_test.dart` so the migration tests exercise
the plans the app ships.

## Testing

Nodus generates `test/nodus_test_harness.g.dart`, which opens the real graph
with an in-memory Drift database, a deterministic `NodusTestClock`, and an
in-memory sync backend built from the graph's own descriptors:

```dart
final harness = await TasksExampleTestHarness.open();
addTearDown(harness.close);

final task = await harness.entityGraph.tasks.create(title: 'Test me');
await task.complete();
expect(task.status, TaskStatus.done);
```

`open` accepts `accountId`, `clock`, `idGenerator`, `diagnostics`, a shared
backend (named after the target, for example `supabase:`), and `autoSync`.
Pass your own `InMemorySyncBackend` to control or inspect the remote side, and
keep the harness's `idGenerator` default unless a test needs fixed IDs (the
default generates UUIDv7s). Tests exercise production entities, queries,
persistence, and sync — no mock repositories.

Each `migrate` also generates Drift migration tests under `test/drift/`.

## Package entrypoints

| Library | Contents |
| --- | --- |
| `nodus.dart` | Annotations, capabilities, typed IDs, queries, the local runtime, sync contracts, the account session, and the in-memory sync backend. |
| `nodus_flutter.dart` | Flutter scope, hooks, the on-device local store, and the typed route runtime. |
| `nodus_supabase.dart` | The Supabase sync backend and external-capability adapter. |
| `nodus_testing.dart` | `NodusTestClock`. |
| `nodus_migrations.dart` | The Drift types generated migrations need (`GeneratedDatabase`, `MigrationStrategy`, `Migrator`, `TableMigration`). |

Every entrypoint re-exports `nodus.dart`. Domain files import
`package:nodus/nodus.dart`; everything else imports the generated
`package:<app>/nodus.g.dart`, which re-exports `nodus_flutter.dart`. Imports from `package:nodus/src/...`
are unsupported.

## Related documentation

- [Core concepts](concepts.md) — the mental model and glossary.
- [Getting started](getting-started.md) — a first entity end to end.
- [Writing custom application code](custom-code.md) — where your own logic
  belongs.
- [Command line and project files](cli.md) — commands, options, and files.
- [Architecture](Architecture.md) — normative rules.
- [Tasks example](../example/tasks/README.md) — executable end-to-end usage.
