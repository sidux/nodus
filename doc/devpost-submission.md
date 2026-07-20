# Devpost submission copy

This is the canonical copy deck for the OpenAI Build Week form.

## Project name

Nodus

## Elevator pitch

Flutter made multiplatform UI simpler. Nodus takes the next step: one typed
product model generates local data, sync, backend security, routes, and tests.

## Category

Developer Tools

## Built with

Codex, GPT-5.6, Dart, Flutter, code generation, Drift, MobX, Supabase,
PostgreSQL, GoRouter, build_runner

## About the project

### Inspiration

Flutter removed a major source of multiplatform duplication: teams can build
one interface and run much of the same code across platforms. But the product
behind the screen is still repeated across state models, local tables, API
payloads, sync logic, backend constraints and permissions, routes, and test
doubles. The UI may be shared while the application meaning drifts.

AI makes that seam more visible. A coding agent can produce a screen quickly,
but it also inherits every duplicated model and configuration, only faster.

Nodus begins with a different question: what if a product decision were written
once, kept typed and reviewable, and compiled into every mechanical layer?

### What it does

Nodus builds on Flutter's multiplatform foundation with a local-first
application architecture and compiler. A developer declares an abstract entity
with fields, constraints, relationships, capabilities, and actions. Nodus
resolves those declarations once into a canonical entity graph and
deterministically emits:

- reactive, identity-stable Dart entities and typed create/edit/action APIs;
- Drift tables, constraints, migrations, observable queries, and durable work;
- a transport-neutral sync protocol with operations, codecs, cursors, retries,
  idempotency, and conflict rebase;
- Supabase PostgreSQL schema, checks, grants, RLS, push functions, change history,
  and receipts;
- typed file-system routes and a production-runtime in-memory test harness.

The result is more than one UI codebase. It is one product model whose state,
offline behavior, persistence, backend policies, and tests stay coherent as the
application moves between platforms.

The generated Tasks app demonstrates offline creation, editing, transitions,
ordering, collaboration, activity, tombstones, paging, deep links, and durable
sync scheduling. It is evidence of Nodus, not the project being submitted.

### Supabase without Supabase lock-in

Supabase is the first built-in schema-capable target, not the runtime boundary.
Entities resolve to typed target descriptors. Generated graphs construct
connectors through `SyncConnectorContext`; target-partitioned queues, cursors,
workers, operation IDs, codecs, and conflict policies speak a generic Nodus
protocol. A new backend implements a directional adapter and, if it provisions
schema, its own emitter. Feature code and entity declarations do not change.

Supabase is the only production-ready provisioning target in `0.1.0`. The
extension contract is ready; Firebase, REST, and other adapters are not bundled
yet.

### How I built it

Nodus uses a multi-phase compiler: discover declarations, parse and normalize
them, infer safe facts, validate ambiguity and graph invariants, freeze one
`EntityGraphDefinition`, then run independent emitters. Emitters are forbidden
from reinterpreting annotations. If a choice is genuinely domain-specific,
generation stops and asks for the smallest typed override.

Nodus was created during Build Week, informed by earlier experiments in Pacely's
`model_first` package. Codex with GPT-5.6 worked inside the real repository:
reading the architecture contract, tracing changes across
compiler/runtime/generated boundaries, implementing scoped changes, reviewing
diffs, and running generation, formatting, analysis, documentation validation,
publish validation, and 342 package-plus-example tests.

### Why this is good architecture for vibe coding

Nodus narrows what a coding agent must invent. The prompt becomes typed domain
intent; the compiler owns repetitive cross-layer mechanics; and stale output,
invalid inference, schema drift, type errors, and behavioral regressions become
fast executable feedback.

Research supports the ingredients, with important caveats. Test-guided intent
clarification has improved developers' ability to evaluate AI code in a user
study; repository-level code generation benefits from full dependency context
and iterative debugging; and OpenAI's Codex guidance emphasizes durable repo
instructions and executable gates. Other research shows AI tools can slow
experienced maintainers in mature repositories and can generate insecure code.
So the claim is not “AI is automatically faster.” It is that AI-assisted work
needs an architectural boundary that is coherent, inspectable, and falsifiable.
The README links every source and states what Nodus has not yet measured.

### Challenges

The hard part was preserving one meaning across very different systems. A
relationship affects the Dart API, local foreign keys, inverse collections,
remote access, sync patches, delete policy, ordering scopes, and tests. The
tempting solution is to let each generator infer independently; that creates
drift. I instead built one canonical graph, made ambiguity fatal, and kept the
emitters deliberately boring.

Local-first semantics were another challenge. `await save()` cannot honestly
mean “the server accepted this” while offline. In Nodus it means the local
projection and durable sync intent committed atomically. Networking, retry,
acknowledgement, remote changes, and rebase happen independently.

### Accomplishments

- Created Nodus as a standalone documented package, CLI, CI project, and
  executable reference application during Build Week.
- Built a canonical graph that drives Dart, Drift, sync, PostgreSQL/RLS, routes,
  migrations, and tests.
- Kept the core backend-neutral while shipping a complete Supabase target.
- Passed 316 package Dart tests, 14 package Flutter tests, 12 application tests,
  static analysis, dartdoc validation, generated-output checks, and pub dry-run.
- Built the Tasks demo as a universal release-mode macOS application.

### What I learned

The useful boundary between human/AI intent and generated mechanics is not
“model versus boilerplate.” It is “real domain decision versus safely derivable
fact.” Nodus became simpler whenever a product choice stayed explicit and every
mechanical consequence moved into the graph.

I also learned to be careful with the vibe-coding claim. Architecture should
make AI output easier to test and review, but that benefit must be measured. The
submission includes the evidence behind the thesis and a proposed controlled
evaluation rather than presenting inference as a benchmark.

### What's next

- Publish `0.1.0` to pub.dev and stabilize the API from external feedback.
- Ship a second production adapter and provisioning emitter to demonstrate the
  transport contract end to end.
- Add Windows, Linux, web, Android, and iOS reference builds.
- Benchmark equivalent features with and without Nodus: time, human edits,
  cross-layer defects, security-policy defects, and test pass rate.
- Grow explainability tooling so every generated line traces to a declaration,
  inferred rule, or explicit override.

## Try it

Repository: https://github.com/sidux/nodus

Judge launch command:

```sh
cd example/tasks
flutter pub get
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

No Supabase credentials are required for the in-memory demonstration. The Sync
center intentionally exposes durable pending work. Full verification commands
are in `BUILD_WEEK.md`.

## Media captions

1. **One graph, every layer** — A typed Task declaration compiles into reactive
   entities, Drift, sync, Supabase RLS, routes, and real tests.
2. **One resolved meaning** — Independent emitters consume the same frozen graph
   to produce typed Dart, Drift, protocol, SQL/RLS, routes, and test boundaries.
3. **Local-first is a precise contract** — A mutation commits accepted state,
   optimistic projection, and durable sync intent before networking begins.
4. **Supabase is a target, not a lock-in** — Typed connector factories and a
   transport-neutral protocol make additional backends architectural plugins.
5. **Vibe coding needs rails** — Codex and GPT-5.6 work against one architecture
   contract and executable generation, type, schema, and test feedback.

## Submitted links

- Devpost project: https://devpost.com/software/nodus
- Unlisted YouTube demo: https://youtu.be/eI_jyBBLImI
- Public repository: https://github.com/sidux/nodus
- Submitter: individual, France
