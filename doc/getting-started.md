# Getting started

This guide takes a Flutter app from zero to a working, offline-first entity
that synchronizes with Supabase. It takes about fifteen minutes.

You will:

1. add the dependencies;
2. declare one entity;
3. initialize Nodus and generate code;
4. create, edit, and query entities;
5. show them in Flutter;
6. connect a real Supabase backend;
7. write a test;
8. change the schema with a migration.

New to the vocabulary? [Core concepts](concepts.md) explains entities, the
entity graph, and sync targets in a few minutes.

## Prerequisites

- Flutter stable with Dart `3.10` or newer.
- An existing Flutter application package (`flutter create my_app`).
- For steps 6 and 8 only: the
  [Supabase CLI](https://supabase.com/docs/guides/local-development), Docker,
  and a Supabase project (local or hosted). Steps 1–5 and 7 need no backend.

## 1. Add the dependencies

Nodus is not yet published on pub.dev, so depend on the Git repository. The
generated code also imports Drift, and widgets observe entities through MobX:

```yaml
dependencies:
  flutter:
    sdk: flutter
  nodus:
    git:
      url: https://github.com/sidux/nodus.git
      ref: main
  drift: ^2.34.2
  flutter_hooks: ^0.21.3+1
  flutter_mobx: ^2.3.0
  mobx: ^2.6.0
  supabase_flutter: ^2.16.0 # only when the target is Supabase

dev_dependencies:
  drift_dev: ^2.34.4
```

Then run `flutter pub get`. The [Tasks example `pubspec.yaml`](../example/tasks/pubspec.yaml)
is a known-good reference.

## 2. Declare an entity

Nodus discovers entities in any `domain/` directory under `lib/`. Create
`lib/features/tasks/domain/task.dart`:

```dart
import 'package:nodus/nodus.dart';

import '../../accounts/domain/account.dart';

enum TaskStatus { todo, done }

@Entity()
abstract class Task implements OwnedBy<Task, Account>, Archivable {
  @Persisted(minLength: 1, maxLength: 160)
  abstract final String title;

  @Persisted(defaultValue: TaskStatus.todo)
  abstract final TaskStatus status;

  @Persisted(maxLength: 1000)
  abstract final String? description;

  bool get isCompleted => status == TaskStatus.done;

  @Action(values: [ActionValue(#status, TaskStatus.done)])
  Future<void> complete();
}
```

And the account type that owns every task,
`lib/features/accounts/domain/account.dart`:

```dart
/// Nominal identity tag for authenticated accounts.
final class Account {}
```

What each line means:

| Code | Meaning |
| --- | --- |
| `@Entity()` | Make this class part of the generated graph. |
| `OwnedBy<Task, Account>` | Every task belongs to one signed-in `Account`; ownership is filled in automatically and enforced by row-level security. |
| `Archivable` | Generate `archive()`, `unarchive()`, and archive-aware lists. |
| `abstract final String title` | A persisted, non-null field. |
| `@Persisted(minLength:, maxLength:)` | A constraint checked in Dart, SQLite, and PostgreSQL. |
| `@Persisted(defaultValue:)` | The value used when creation omits the field. |
| `bool get isCompleted` | Ordinary handwritten logic, available on every task. |
| `@Action(...)` | A named transition; Nodus generates `complete()`. |

## 3. Initialize and generate

From the application root:

```sh
dart run nodus init --target supabase
```

This one-time command:

- discovers every `@Entity` under `lib/`;
- derives the graph name from your package name (`my_app` →
  `MyAppEntityGraph`);
- writes the committed, tool-owned `nodus.lock` and the Drift builder settings
  in `build.yaml`;
- generates the code, including the single import `lib/nodus.g.dart`.

`--target` names the default remote system. Use `supabase` for the built-in
backend, or any `lower_snake_case` name for a [custom connector](capabilities.md#custom-connectors).

Afterwards, regenerate whenever declarations change:

```sh
dart run nodus generate   # once
dart run nodus watch      # continuously while you edit
```

Commit `nodus.lock` and the generated files. Never edit generated files; change
the declaration and regenerate.

## 4. Create, edit, and query

Open an in-memory graph to try the API without a backend:

```dart
import 'package:my_app/nodus.g.dart';

final entityGraph = await MyAppEntityGraph.openInMemory(
  accountId: LocalId<Account>('00000000-0000-0000-0000-000000000001'),
);

// Create through the generated set.
final task = await entityGraph.tasks.create(title: 'Ship Nodus');

// Edit through a typed draft, then save once.
final draft = task.beginEdit()..title = 'Publish Nodus';
await draft.save();

// Call a declared action or a capability method.
await task.complete();
await task.archive();

// Query with typed predicates.
final openTasks = TaskList.all(
  entityGraph,
  where: TaskFields.status.equals(TaskStatus.todo),
);
// ... use openTasks, then release it:
openTasks.dispose();

await entityGraph.close();
```

Every awaited mutation updates the `task` object immediately and commits the
change — plus durable sync work for synchronized entities — in one local
transaction. It never waits for the network. If the local commit fails, the
change is rolled back and the error is rethrown.

## 5. Show entities in Flutter

Widgets read generated lists and entities directly. `useObservedEntityList`,
a Nodus hook built on `flutter_hooks`, owns the query for the widget's
lifetime and folds its loading, empty, data, and failure states; the list
pages itself as the user scrolls.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:my_app/nodus.g.dart';

final class OpenTasks extends HookWidget {
  const OpenTasks({required this.entityGraph, super.key});

  final MyAppEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) {
    final tasks = useObservedEntityList(
      () => TaskList.all(
        entityGraph,
        where: TaskFields.status.equals(TaskStatus.todo),
      ),
      keys: [entityGraph],
    );
    return tasks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      empty: () => const Center(child: Text('Nothing to do')),
      failure: (error, retry) =>
          TextButton(onPressed: retry, child: Text('Retry: $error')),
      data: (items, {required hasMore, required refreshing, refreshError}) =>
          ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final task = items[index];
              // Observer rebuilds only when the fields it reads change.
              return Observer(
                builder: (_) => CheckboxListTile(
                  value: task.isCompleted,
                  title: Text(task.title),
                  onChanged: task.isCompleted ? null : (_) => task.complete(),
                ),
              );
            },
          ),
    );
  }
}
```

There is no provider, repository, or view model in between: the `task` object
in the list *is* the entity, and any change to it — local or synchronized —
rebuilds only the observers that read the changed fields.

## 6. Connect Supabase

Replace the in-memory graph with the generated Supabase factory. The graph
belongs to one account, so open it after the user has signed in with Supabase
Auth:

```dart
await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
final client = Supabase.instance.client;
final user = client.auth.currentUser!;

final entityGraph = await MyAppEntityGraph.openSupabase(
  accountId: parseLocalId<Account>(user.id),
  client: client,
);
```

The local database lives on the device and keeps working offline; a background
worker pushes queued changes and pulls remote ones.

The backend schema is already generated: `supabase/schemas/public.sql`
contains the tables, constraints, indexes, grants, row-level security, and the
push and pull functions for your entities. To deploy it:

1. If the app has no Supabase project folder yet, run `supabase init`. The
   CLI reads declarative schemas from `supabase/schemas/` by default; if your
   `supabase/config.toml` sets `schema_paths`, keep `./schemas/public.sql` in
   it.

2. Create the first migration from the generated schema:

   ```sh
   dart run nodus --bootstrap-supabase-migration initial_schema
   ```

3. Apply it with the Supabase CLI as usual, for example `supabase db reset`
   locally or `supabase db push` for a linked project.

Later schema changes produce their migrations through `nodus migrate`
(step 8). Never put a service-role key in a Flutter client.

### Signing in, switching, and signing out

Real apps open and close graphs as the user signs in and out. Let one
`AccountEntityGraphSession` do that and publish its state to widgets with the
generated scope:

```dart
final session = AccountEntityGraphSession<MyAppEntityGraph, Account>(
  open: (accountId) =>
      MyAppEntityGraph.openSupabase(accountId: accountId, client: client),
  close: (entityGraph) => entityGraph.close(),
);

client.auth.onAuthStateChange.listen((event) {
  final userId = event.session?.user.id;
  session.switchAccount(
    userId == null ? null : parseLocalId<Account>(userId),
  );
});

runApp(MyAppEntityGraphScope(session: session, child: const MyApp()));
```

Inside the tree, `context.myAppEntityGraphState` is one of
`AccountEntityGraphSignedOut`, `AccountEntityGraphOpening`,
`AccountEntityGraphReady` (which carries the `entityGraph`),
`AccountEntityGraphStoreInUse` (the account is already open in another tab),
or `AccountEntityGraphFailure`. The scope rebuilds only on these lifecycle
changes, never on entity changes.

When a user deletes their account, close its graph and call
`MyAppEntityGraph.eraseLocalStore(accountId: ...)` so the device keeps nothing.

## 7. Write a test

Nodus generates `test/nodus_test_harness.g.dart`. It opens the **real**
generated graph with an in-memory database, a deterministic clock, and an
in-memory sync backend, so tests exercise production code instead of mocks:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'nodus_test_harness.g.dart';

void main() {
  test('completing a task marks it done', () async {
    final harness = await MyAppTestHarness.open();
    addTearDown(harness.close);
    final entityGraph = harness.entityGraph;

    final task = await entityGraph.tasks.create(title: 'Write a test');
    await task.complete();

    expect(task.isCompleted, isTrue);
  });
}
```

## 8. Change the schema

Add a field to `Task`, for example `abstract final DateTime? dueAt;`, then:

```sh
dart run nodus migrate add_task_due_date
```

`dart run nodus generate` refuses a physical schema change without a migration
name, so the version can never be forgotten. `migrate` advances `nodus.lock`
and writes, for review, the Drift migration, the updated canonical Supabase
schema, and the Supabase SQL migration. The SQL diff comes from
`supabase db diff`, which needs the Supabase CLI and a running Docker daemon.
It also writes migration tests under `test/drift/`; run them with
`flutter test`.

Before committing, `dart run nodus check` confirms that nothing generated is
stale. Add it to CI.

## Common problems

| Symptom | Fix |
| --- | --- |
| `init` says `build.yaml` contains handwritten configuration | Nodus owns `build.yaml`. Move or remove the custom settings, then rerun `init`. |
| `init` finds no entities | Entities must be `@Entity()` classes inside a `domain/` directory under `lib/`. |
| `generate` says the schema changed without a named migration | Run `dart run nodus migrate <name>`. |
| `migrate` fails while running `supabase db diff` | Install the Supabase CLI and start Docker. |
| A migration test fails with "requires an explicit manual migration plan" | The schema change adds a constraint or needs data changes. Decide how existing rows migrate with a [migration plan](capabilities.md#migrations), and pass the same strategy in `test/drift/<database>/migration_test.dart`. |
| Typed routes are not generated | Add the root `not_found.dart` page; see [typed routes](capabilities.md#typed-route-generation). |
| The web build cannot open the database | Serve Drift's `sqlite3.wasm` and `drift_worker.js` from `web/`; see [Web](capabilities.md#web). |
| A second browser tab shows "store in use" | Expected: one account's database belongs to one tab at a time. Handle `AccountEntityGraphStoreInUse`. |

## Where to go next

- [Core concepts](concepts.md) — the mental model in one page.
- [Capability reference](capabilities.md) — relationships, ordering,
  collaboration, activity, routing, sync, and every generated API.
- [Writing custom application code](custom-code.md) — where your own logic and
  integrations belong.
- [Command line](cli.md) — every command and option.
- [Tasks reference app](../example/tasks/README.md) — a complete application
  with routing, adaptive UI, collaboration, and the sync queue.
