# Contributing to Nodus

Thank you for helping improve Nodus. Changes should preserve the central
property of the project: domain intent is declared once and every mechanical
representation is derived from one resolved entity graph.

## Before changing code

Read the relevant sections of [`doc/Architecture.md`](doc/Architecture.md).
That document is the normative contract for domain declarations, compiler
inference, generated APIs, persistence, synchronization, security, routing, and
quality gates. Existing code and tests do not override it.

## Development setup

Install the latest stable Flutter SDK, then run:

```sh
flutter pub get
dart test --exclude-tags flutter
flutter test --tags flutter

cd example/tasks
flutter pub get
dart run nodus check
dart test --exclude-tags flutter
flutter test --tags flutter
```

## Pull requests

- Keep handwritten code focused on domain meaning; generate safely derivable
  mechanics.
- Do not edit generated `*.g.dart`, `*.freezed.dart`, Drift, schema, route, or
  entity-graph artifacts directly. Change the declaration or emitter and
  regenerate.
- Preserve nominal types end to end and fail ambiguous inference with an
  actionable diagnostic.
- Add tests that execute production behavior. Compiler output may use goldens
  or compile-failure fixtures; application tests should use generated public
  APIs and the real in-memory graph harness.
- Add no unresolved TODOs, dead compatibility code, or feature-facing wrappers
  around generated persistence and synchronization APIs.
- Document user-visible behavior and update `CHANGELOG.md` when appropriate.

Run the complete gate before opening a pull request:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
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
