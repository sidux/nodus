# Nodus demo: 2 minutes 45 seconds

This is the recording script for the OpenAI Build Week submission. Keep the
cursor large, use 125% editor zoom, and show actual declarations, compiler
output, generated boundaries, and verification results.

## 0:00–0:18 — Problem and promise

**Visual:** title card, then the one-graph-to-many-layers architecture.

**Voiceover:**

> Vibe coding can make the first screen fast, then leave five versions of the
> same idea across models, tables, APIs, security, and tests. Nodus is a
> local-first Flutter application compiler: one typed domain graph becomes every
> application layer.

## 0:18–0:47 — One declaration

**Visual:** `example/tasks/lib/features/tasks/domain/task.dart`. Highlight the
entity annotation, persisted fields, capabilities, constraints, and actions.

**Voiceover:**

> This is the handwritten Task entity. It owns product decisions—fields,
> validation, relationships, ordering, collaboration, archiving, deletion, and
> actions. There is no handwritten repository, DTO, table, sync service, route
> registry, or test double.

## 0:47–1:05 — One resolved graph

**Visual:** run `dart run nodus explain Task`, then briefly show
`nodus.explain.g.json`.

**Voiceover:**

> Nodus parses and validates intent once into a frozen graph. Independent
> emitters consume resolved facts; they cannot quietly reinterpret annotations.
> Ambiguity fails generation and asks for the smallest explicit decision.

## 1:05–1:35 — Every layer stays coherent

**Visual:** a four-way view of the generated Dart facade, Drift schema,
`supabase/nodus/schema.sql`, and `test/nodus_test_harness.g.dart`.

**Voiceover:**

> From that graph, Nodus emits identity-stable Dart entities, typed mutations,
> Drift tables and migrations, observable queries, protocol codecs, durable
> queues, PostgreSQL constraints and row-level security, typed routes, and a
> production-runtime test harness. They are deterministic views of one resolved
> meaning, not handwritten copies that can drift apart.

## 1:35–2:02 — Local-first semantics are explicit

**Visual:** the runtime sequence: draft → stable identity → atomic Drift
transaction → durable work queue → target adapter, with the return boundary
highlighted after the transaction.

**Voiceover:**

> A draft first updates the stable MobX identity. One Drift transaction commits
> accepted state, optimistic projection, and a versioned operation into durable
> work. Save returns after that local boundary—not after the network. A target
> adapter retries later, and acknowledgements or remote changes rebase accepted
> state with still-pending intent.

## 2:02–2:25 — Supabase is a target, not a lock-in

**Visual:** show `SyncAdapter`, `SyncConnectorContext`, and the generated
`openWithConnectors` factory.

**Voiceover:**

> Supabase is the first built-in provisioning target. The graph and runtime are
> transport-neutral: typed target descriptors, queues, cursors, operations,
> codecs, and conflicts flow through directional adapters. Another backend adds
> an adapter and optional provisioning emitter—not a second app architecture.

## 2:25–2:45 — Codex and the close

**Visual:** terminal showing `nodus check`, analysis, and passing tests; finish
on “One graph. Every layer.”

**Voiceover:**

> During Build Week, Codex with GPT-5.6 helped create Nodus from early in-app
> experiments, challenge the architecture, implement the compiler and example,
> and run 342 tests. Nodus gives vibe coding rails: people and agents express
> intent once, then the compiler makes every layer reviewable and falsifiable.
> One graph. Every layer.

## Recording checklist

- Keep the final video under three minutes and make it publicly viewable.
- Use voice narration; do not rely on captions alone.
- Present Nodus and its architecture; the Tasks app is only optional proof that
  the generated boundary runs.
- Show actual declarations, resolved graph output, generated boundaries, and
  passing gates.
- Avoid claiming that Nodus is empirically faster; describe the feedback loop.
- End with the repository URL and the exact command to launch the demo.
