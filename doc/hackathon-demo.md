# Nodus hackathon demo

This script demonstrates Nodus as an application compiler rather than an ORM.
It is designed for a two-to-three-minute live walkthrough.

## 1. Show the declaration

Open `example/tasks/lib/features/tasks/domain/task.dart`. Point out that the
handwritten `Task` owns fields, constraints, transitions, actions, ordering,
archiving, deletion, collaboration, and activity intent without a repository,
DTO, database table, or sync service.

## 2. Explain the graph

```sh
cd example/tasks
dart run nodus explain Task
```

Show the resolved ownership, cardinality, target, sync mode, capabilities,
fields, columns, and derivation sources.

## 3. Run offline

```sh
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

Create or edit a task, complete it, and archive it. The UI updates through the
stable MobX entity immediately. Open the Sync center and show that the local
mutation and its durable synchronization intent already committed even though
no server credentials were supplied.

## 4. Show generated boundaries

- `lib/nodus.g.dart`: the only production generated import.
- `lib/src/generated/nodus.runtime.g.dart`: account-scoped graph and sets.
- `supabase/nodus/schema.sql`: tables, checks, indexes, RLS, push functions,
  change history, and receipts.
- `test/nodus_test_harness.g.dart`: the real in-memory graph harness.

## 5. Close with the invariant

One domain declaration produces the local schema, remote schema, wire protocol,
security policy, query surface, reactive identity, and test boundary. A schema
change without `dart run nodus migrate <name>` fails generation.
