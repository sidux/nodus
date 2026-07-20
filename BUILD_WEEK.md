# OpenAI Build Week record

This file separates Nodus's pre-event lineage from the work completed for OpenAI
Build Week. It exists so judges can evaluate the submitted delta without treating
the project as a one-week greenfield prototype.

## Baseline before the event

Before July 13, 2026 at 09:00 Pacific, Pacely contained an experimental package
named `model_first`. It had already established the entity-first direction and
some generated persistence, synchronization, and tombstone behavior. The last
pre-window baseline commit used for this record is:

```text
2ac77eca02f59ee03a7542430e3988b5e2bae4ea
feat(model-first): generate reversible tombstones
2026-07-13T17:21:23+02:00
```

The package was not yet this standalone Nodus repository, its current public
API, documentation set, CI project, or runnable submission artifact.

## Meaningful extension during Build Week

From the event start through extraction, 79 Pacely commits touched the evolving
`packages/model_first` / `packages/nodus` boundary. The core pre-extraction diff
from `2ac77eca` to `e7c7cb5e` changed 37 package files with 22,787 insertions and
2,060 deletions. Those numbers include tests and generated/compiler work and are
provided as provenance, not as a quality metric.

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
- extraction as the standalone `sidux/nodus` package with a CLI, reviewed schema
  lock, BSD license, security policy, contribution guide, CI, architecture
  atlas, and Tasks reference application;
- post-extraction fixes found by running the complete package and example gates.

The standalone history begins with `bc949a2`, a deliberate extraction commit.
The original fine-grained history remains in the Pacely repository; it was not
rewritten into misleading backdated Nodus commits.

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
