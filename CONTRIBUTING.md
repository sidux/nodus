# Contributing to Nodus

Thank you for helping improve Nodus. Changes should preserve the central
property of the project: domain intent is declared once and every mechanical
representation is derived from one resolved entity graph.

## Before changing code

Read the relevant sections of [`doc/Architecture.md`](doc/Architecture.md).
That document is the normative contract for domain declarations, compiler
inference, generated APIs, persistence, synchronization, security, routing, and
quality gates. Existing code and tests do not override it.

## Repository map

| Path | Contents |
| --- | --- |
| `bin/nodus.dart` | The `dart run nodus` command line. |
| `lib/nodus.dart`, `lib/nodus_*.dart` | Public entrypoints: runtime, Flutter bindings, Supabase, testing, migrations. |
| `lib/src/annotations.dart` | `@Entity`, `@Persisted`, `@Reference`, and the other declarations. |
| `lib/src/entity_generator/` | The compiler: parser, resolved model, and the Dart, Drift, SQL, and explain emitters. |
| `lib/src/route_generator/` | The typed route compiler. |
| `lib/src/entity_engine.dart` | The local runtime: identity map, mutations, queries, durable queue, synchronization. |
| `lib/src/tool/` | `init`, generation and migration orchestration, and the conformance inventory. |
| `test/` | Package tests; `@Tags(['flutter'])` marks those needing the Flutter engine. |
| `example/tasks/` | The reference app, which also serves as an end-to-end test of generated output. |
| `doc/` | User documentation and the normative [`Architecture.md`](doc/Architecture.md). |

## Development setup

Install the latest stable Flutter SDK. The repository contains two packages
with separate dependencies: the `nodus` package at the root and the Tasks
reference app in `example/tasks`.

```sh
flutter pub get
dart test --exclude-tags flutter   # pure Dart tests
flutter test --tags flutter        # tests tagged `flutter` (widgets, hooks)

cd example/tasks
flutter pub get
dart run nodus check
flutter test
```

Tests that need the Flutter engine carry `@Tags(['flutter'])` so the pure Dart
suite stays fast. Tag any new test that imports Flutter.

Generating a Supabase migration in the example (`dart run nodus migrate ...`)
runs `supabase db diff`, so it needs the
[Supabase CLI](https://supabase.com/docs/guides/local-development) and a
running Docker daemon.

## Pull requests

- Keep handwritten code focused on domain meaning; generate safely derivable
  mechanics.
- Do not edit generated `*.g.dart`, Drift, schema, route, or entity-graph
  artifacts directly. Change the declaration or emitter and regenerate.
- Preserve nominal types end to end and fail ambiguous inference with an
  actionable diagnostic.
- Add tests that execute production behavior. Compiler output may use goldens
  or compile-failure fixtures; application tests should use generated public
  APIs and the real in-memory graph harness.
- Add no unresolved TODOs, dead compatibility code, or feature-facing wrappers
  around generated persistence and synchronization APIs.
- Document user-visible behavior and update `CHANGELOG.md` when appropriate.

Run the complete gate before opening a pull request. It mirrors
[CI](.github/workflows/ci.yml):

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze lib test bin
dart test --exclude-tags flutter
flutter test --tags flutter
dart doc --validate-links
dart pub publish --dry-run

cd example/tasks
dart run nodus check
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Schema changes in a consumer application must use a named migration:

```sh
dart run nodus migrate describe_the_change
```
