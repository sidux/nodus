# Nodus contributor instructions

## Architecture authority

- [`doc/Architecture.md`](doc/Architecture.md) is the sole normative
  architecture contract. Read the relevant sections before changing domain
  models, compiler inference, generated APIs, persistence, synchronization,
  security, routing, or architectural boundaries.
- Existing code, tests, examples, and generated artifacts do not override the
  architecture. Treat conflicts as migration debt.

## Working conventions

- Preserve unrelated and in-progress work.
- Prefer simple, typed, reusable code and established naming conventions.
- Never edit generated files directly. Regenerate them with the owning Nodus,
  Build Runner, Drift, or schema tool.
- Add a dependency only when it materially reduces complexity.
- Tests must execute production behavior; do not add source-text guards or
  no-op smoke tests.

## Verification

Run the smallest relevant tests while iterating, then the affected portion of:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
dart test --exclude-tags flutter
flutter test --tags flutter
dart doc --validate-links
dart pub publish --dry-run

cd example/tasks
dart run nodus check
flutter analyze
flutter test
```
