# Changelog

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
- Generates a server-only principal retirement step that hands collaborative
  aggregates to their longest-standing accepted collaborator, preferring an
  editor, and revokes every other audience before an account identity is
  removed.
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
- Grants each account's local store to one live entity graph at a time. The
  web store claims it through an exclusive Web Lock shared by every tab of the
  origin; a second claimant fails with `LocalStoreInUseException` before any
  sync connector starts, and `AccountEntityGraphSession` publishes
  `AccountEntityGraphStoreInUse` and reopens automatically once the store is
  released.
- Splits the local schema fingerprint from the remote one in `nodus.lock`, so a
  change confined to the remote schema no longer bumps the device database
  version.
- Lets tombstones release unconditional unique keys, so a live entity may
  reuse a deleted entity's key.
- Raises synchronization conflicts with a dedicated error code that PostgREST
  does not retry, rebases a conflicting push before retrying it, and bounds
  Supabase sync requests with a retryable timeout.
- Adds `CollaborationAccess.workflow(editPermissionField:)` so workflow
  collaborations can separate editors from read-only members.
- Routes realtime revocations and access changes to their addressed
  recipients and catches up with a pull after realtime reconnects. Existing
  Supabase deployments must apply the generated migration that adds the
  change-recipient table.
- Persists the web local store through Drift's WebAssembly build; web apps
  serve `sqlite3.wasm` and `drift_worker.js` from their web root.
- Generates `eraseLocalStore` so an application can delete a deleted
  account's local database.
- Holds an account's synchronization work while it is not signed in instead
  of failing it.
- Keeps an observed list's previous results on screen while a changed query
  reloads.
