# OpenAI Build Week record

This file records how Nodus was created during OpenAI Build Week while
disclosing the pre-event Pacely experiments that informed it. It exists so
judges can distinguish Nodus itself from that earlier exploratory work.

## Pre-event lineage (not Nodus)

Before July 13, 2026 at 09:00 Pacific, Pacely contained an experimental package
named `model_first`. It had explored the entity-first direction and some
generated persistence, synchronization, and tombstone behavior, but it was not
Nodus. The last pre-window Pacely baseline commit used for this record is:

```text
2ac77eca02f59ee03a7542430e3988b5e2bae4ea
feat(model-first): generate reversible tombstones
2026-07-13T17:21:23+02:00
```

Nodus began during the Build Week submission period, when those experiments
were reworked into the standalone framework, public API, repository,
documentation, CI project, and runnable submission presented here.

## Nodus creation during Build Week

From the event start through Nodus's standalone launch, 79 Pacely commits
touched the transition from `packages/model_first` experiments to the new
`packages/nodus` boundary. The core pre-launch diff from `2ac77eca` to
`e7c7cb5e` changed 37 package files with 22,787 insertions and 2,060 deletions.
Those numbers include tests and generated/compiler work and are provided as
provenance, not as a quality metric.

The event work included:

- one validated, frozen `EntityGraphDefinition` consumed by independent
  deterministic emitters;
- generated durable edit drafts, relationship mutations, actions, account
  sessions, bounded and unbounded queries, and stable reactive identity;
- relationship cardinality, aggregate access, collaboration visibility, exact
  unique lookup, and ordered-scope inference;
- typed sync targets, target-partitioned durable work, directional adapter
  capabilities, and managed factories for custom connectors;
- native scalar and nominal-ID persistence inference across Dart, Drift,
  protocol codecs, and SQL;
- generated file routes, guards, migrations, Supabase RLS/protocol artifacts,
  and real in-memory graph harnesses;
- creation of the standalone `sidux/nodus` package with a CLI, reviewed schema
  lock, BSD license, security policy, contribution guide, CI, architecture
  atlas, and Tasks reference application;
- post-launch fixes found by running the complete package and example gates.

The standalone Nodus history begins with `bc949a2`, its deliberate launch
commit. The fine-grained Build Week development history remains in the Pacely
repository; it was not rewritten into misleading backdated Nodus commits.

## How Codex and GPT-5.6 were used

Codex with GPT-5.6 worked inside the real repositories rather than generating a
detached proof of concept. Its role included:

1. reading the normative architecture and repository instructions before
   changing compiler or runtime boundaries;
2. tracing domain declarations through the canonical graph, emitters, generated
   application API, Drift state, sync queues, Supabase protocol, and tests;
3. implementing narrowly scoped changes and reviewing the resulting diffs;
4. repeatedly running generation, formatting, static analysis, package tests,
   documentation validation, publish validation, and the reference app tests;
5. auditing the final package against the hackathon requirements and producing
   the evidence, demo, and submission materials.

Human-authored architectural intent remained normative in
`doc/Architecture.md`. Codex was most useful because Nodus supplied a stable
contract and fast executable feedback; failed inference and tests were treated
as information, not patched around.

## Reproduce the submitted verification

From the repository root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
dart test --exclude-tags flutter
flutter test --tags flutter
dart doc --validate-links
dart pub publish --dry-run

cd example/tasks
dart run nodus check
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

Final pre-submission result on macOS:

- 316 package Dart tests passed;
- 14 package Flutter tests passed;
- 12 Tasks application tests passed;
- static analysis passed for the package and example;
- generated output and `nodus.lock` were current;
- dartdoc validation completed with zero warnings and errors;
- the pub.dev dry run completed with zero warnings;
- the release Tasks app built as a universal macOS binary.

The CI workflow runs the package and example gates on Linux. The in-memory demo
is deliberate: it invokes generated production entities, Drift persistence,
queries, actions, and durable sync scheduling without requiring judges to
configure a Supabase project.
