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
- Includes direct collaboration, ordering, archiving, soft deletion, activity
  tracking, and deterministic in-memory synchronization support.
- Enforces immutable persisted declarations and routes durable changes through
  typed actions or mutation drafts; JSON/object and collection persistence are
  rejected in favor of native scalar fields and normalized relationships.
- Infers ordinary edit-draft fields without a catch-all action, merges
  non-overlapping concurrent drafts over current state, reports overlapping
  fields through a typed conflict, and treats unchanged saves as durable no-ops.
- Enables row-level security on the generated internal remote change log in
  addition to revoking direct API-role privileges.
- Removes the legacy handwritten `@EntityGraph` setup path. Package discovery
  plus tool-owned `nodus.lock` is the sole graph declaration contract.
- Allows same-coordinator nested transactions to join safely while rejecting
  unrelated asynchronous work, and generates executable Drift migration tests
  wired to the reviewed migration strategy.
