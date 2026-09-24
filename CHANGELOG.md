# Changelog

## Unreleased

- Generated `open` initializes entity engines concurrently and drops a
  per-engine probe query, so opening a graph pipelines its reads (about 35%
  faster in a 43-entity app).
- `LocalDate.addDays` and `LocalDate.daysUntil` do calendar arithmetic that is
  independent of daylight-saving transitions.
- Exhaustive reads (`loadAll`, `useAll`, `loadAllPages` hooks) fetch the rows
  after the first page in chunks of 500, instead of one page per round trip.
- Exact-ID loads (generated lookups and `id.equals` pages) that start in the
  same microtask share one `id in (...)` query, so rows that each look up one
  entity, such as avatars, cost one database read per list.
- Query invalidation is per entity: a settled database query no longer
  reloads when the changed, loaded entities are neither listed by it nor match
  its predicate, so editing one row stops reloading every sibling selection.
  `loadRawId(refresh: true)` updates a loaded identity before notifying.
- `useObservedEntityValue` no longer takes `keys`.
- Adds column subquery filters: generated sets expose `column(field, where:)`
  and fields expose `isInColumn(...)`, so "tasks with this tag" is one SQL
  query that refreshes when the link rows change, instead of a link list whose
  IDs feed a second `isIn` query. Bounded sets serve these predicates from the
  database through `LocalEntityQueryCache.bounded`.
- Adds `@Action(guard: #decision)`: a concrete `bool` getter or method gates
  the action with a typed `ActionGuardException` before any optimistic change,
  and generated `<action>All` operations skip rejected entities.
- Adds `@Entity(conflict: ...)` so an entity declares its field merge policy
  once; field overrides still apply, and server-authoritative fields and
  conventional timestamps keep `serverWins`.
- Generates `isRemoved` on every entity and `isArchived` on `Archivable`
  entities; declarations can no longer repeat them.
- Exports `Enum.wireName`, `values.byWireName(...)`, and
  `values.asWireNameMap()`, sharing the generator's persisted enum spelling.
- Fixes push ordering: a target lane is strictly first-in-first-out, so work
  no longer overtakes an operation that is backing off or leased elsewhere.
- Fixes patch coalescing that could move an edit ahead of a later command on
  the same entity or the creation of an entity it references.
- Stops earlier save failures from failing unrelated `transaction()` and
  `close()` calls, joins repeated `switchAccount` requests for the account
  being opened, and completes `dispose()` when closing the graph fails.
- Fixes draft form hooks: text controllers follow their draft, write only user
  edits, and value bindings expose an unset field as `null`; `useEntityAction`
  no longer updates state after its widget unmounts.
- Generator: escapes `\`, `$`, and line breaks in generated string literals;
  rejects non-literal initializer defaults, non-finite defaults, index names
  that collide, and enum values sharing one stored spelling.
- `EntityBulkMutationResult<E>` reports typed `changedIds`, and generated
  `removeHierarchy`, `restoreHierarchy`, and `setHierarchyArchived` accept
  `only:`, so undo reverses exactly one operation instead of restoring
  descendants that were deleted or archived earlier.
- Selection hooks (`useEntityList`, `useObservedEntityList`, lookups,
  existence, first, and query hooks) key their lease by the structural
  selection when `keys` is omitted, so call sites no longer mirror their
  inputs as hook keys; `LocalEntityQuery.sharesSelectionWith` exposes the test.
  `useObservedEntityValue` re-tracks its latest read after every build.
- Generates `WorkflowMembership.end()` (the owner revokes, the member
  declines), `targetId`, `ownerId`, `isPending`, and `isAccepted`; membership
  sets implement `WorkflowMembershipSet` (`forTarget`, `visibleTo`, `invite`)
  so shared collaboration code needs no per-target glue.
- `withReadyEntityGraph` leases now run concurrently instead of queueing
  behind each other; account transitions still wait for leases already running.
- Quarantines a queued sync operation that can no longer be decoded (rejected
  with a diagnostic) instead of wedging its lane or failing graph open, and
  upgrades queued graph-level commands with the graph definition.
- Generator: rejects reserved SQL words as table or column names, names the
  field and points at it for unsupported types and column collisions, and
  warns when an `@Entity` lives outside a `domain/` directory.
- `nodus generate` formats only tool-written Dart instead of the whole `lib`.
- A failed graph open reports the original error even if cleanup fails.
- Entity processes run only for the sources whose triggering changes are
  pending (removed and archived ones included) instead of rescanning every
  source; projection changes carry the changed entity IDs.
- Adds `InMemorySyncBackend.pushFault` and `pullFault` for exercising retry
  behavior in tests; a new pull now supersedes a rejected one.
- Removes unused `MutationOrigin`, `migrateImplicitSyncTarget`, and the
  unbatched `MutationCoordinator` constructor.

## 0.1.0

- Introduces the entity-first compiler and generated account-scoped entity
  graph runtime.
- Generates typed entities, mutation drafts, queries, Drift persistence,
  Supabase synchronization and security, file-based routes, and test harnesses
  from annotated domain declarations.
- Adds `nodus init`, `generate`, `watch`, `check`, `explain`, `inventory`, and
  `migrate` commands. The deterministic semantic inventory combines resolved
  graph metadata with analyzer ASTs and supports write/check CI drift gates.
- Allows source-boundary policies to forbid directories, package prefixes, or
  both without requiring an unused restriction kind.
- Includes direct collaboration, ordering, archiving, soft deletion, activity
  tracking, and deterministic in-memory synchronization support.
- Enforces immutable persisted declarations and routes durable changes through
  typed actions or mutation drafts; JSON/object and collection persistence are
  rejected in favor of native scalar fields and normalized relationships.
- Infers ordinary edit-draft fields without a catch-all action, merges
  non-overlapping concurrent drafts over current state, reports overlapping
  fields through a typed conflict, and treats unchanged saves as durable no-ops.
- Keeps ordinary scalar action parameters draft-editable while enforcing the
  complete atomic action shape whenever a transition, fixed assignment,
  relationship, or explicitly action-exclusive field activates it.
- Enables row-level security on the generated internal remote change log in
  addition to revoking direct API-role privileges.
- Removes the legacy handwritten `@EntityGraph` setup path. Package discovery
  plus tool-owned `nodus.lock` is the sole graph declaration contract.
- Allows same-coordinator nested transactions to join safely while rejecting
  unrelated asynchronous work, and generates executable Drift migration tests
  wired to the reviewed migration strategy.
- Adds transport-neutral typed external capability contracts and a shared
  Supabase RPC/Edge Function adapter with normalized failure categories and a
  transport-free testing seam.
- Preserves collision-free Dart getters from Drift schema snapshots in both
  migration steps and generated verification schemas, including current
  schema emitters that do not generate a companion `DataClass`.
- Adds `WorkflowMembership` generation for conventional participant/status
  fields, transitions, self-membership constraints, and invite-or-reuse APIs.
- Infers bounded aggregate inverses from unique links and generates typed
  `beginUpsertBy...` drafts for live unique identities.
- Adds present-only bounded and unbounded identity APIs, lifecycle-default
  inactive relationship queries with identity-preserving relationship
  reactivation, mixed exhaustive-read record leases, and typed heterogeneous
  record futures through arity fourteen.
- Adds asynchronous generated-draft Flutter lifecycle ownership and JSON
  object/list/void external-capability contract factories.
- Generates Drift table rebuilds for constraint-only changes and adds an
  explicit `NodusMigrationPlan.acknowledgeGenerated()` review decision.
