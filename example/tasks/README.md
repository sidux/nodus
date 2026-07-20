# Tasks architecture example

This standalone Flutter app is the executable reference for
[`doc/Architecture.md`](../../doc/Architecture.md). It stays deliberately
focused on tasks: creating and editing work, project ordering, completion,
archiving, collaboration, activity, deletion, and synchronization.

Application code depends on one reusable architecture package:
[`nodus`](../..). Domain declarations and
file-owned pages express intent; the package generates persistence, reactive
identity, typed queries, routes, synchronization, collaboration security, and
Supabase schema.

## What the example demonstrates

- `Task` is an unbounded, project-scoped ordered entity with generated create,
  edit, start, complete, reopen, archive, unarchive, move, delete, restore, and
  collaboration behavior.
- `TaskProject` is a bounded ordered entity used for complete selectors and
  project navigation.
- `Task` implements `ActivityTracked`, while `TaskActivity` implements
  `ActivityOf<Task, Account>`. Nodus generates the immutable activity fields
  and appends each entry in the same mutation batch as the task change.
  Callers use `task.complete()`, `task.archive()`, and the other entity methods
  directly; there is no activity transaction wrapper.
- Generated typed predicates drive open, completed, and archived views.
- Generated entity lookup leases keep unbounded task identities stable for the
  lifetime of detail, edit, and collaboration pages.
- `TaskMutationDraft` is the one create/edit form model. Its typed fields bind
  directly to Flutter and it atomically combines `task.edit(...)` with
  `task.moveToProject(...)` when both change.
- Observed list/lookup and action Hooks remove repeated query-state and action
  feedback scaffolding without copying generated entity state.
- Project task lists use generated canonical rank ordering and neighbor moves;
  widgets never author storage ranks.
- Direct `task.setCollaborator(...)` calls use the generated semantic operation,
  so they remain correctly ordered with offline writes without a feature-facing
  command object.
- Soft deletion produces synchronized tombstones. Ordinary queries exclude
  them; repair flows opt in explicitly.
- The sync center renders the graph-owned durable push/pull queue.
- File-owned page classes and lightweight top-level page entries generate typed
  deep links for `/tasks`, `/projects`, `/activity`, and `/sync` without
  forwarding widget classes.
- The UI uses a bottom navigation bar below 600 logical pixels, a compact rail
  from 600 through 839, and an extended rail plus task list/detail split at 840
  and above.

There is no handwritten graph declaration. Nodus discovers the three domain
declarations under [`lib/features/tasks/domain`](lib/features/tasks/domain),
derives `TasksExampleEntityGraph` from the package name, and exposes the whole
generated application surface through [`lib/nodus.g.dart`](lib/nodus.g.dart).
Implementation artifacts live privately under `lib/src/generated`; production
code imports only that facade. Tests open the real graph through the generated
`test/nodus_test_harness.g.dart` harness.
The committed [`nodus.lock`](nodus.lock) owns the generated target, schema
version, and physical-schema fingerprint.

The canonical generated Supabase schema is
[`supabase/schemas/public.sql`](supabase/schemas/public.sql), with one clean
bootstrap migration in [`supabase/migrations`](supabase/migrations). Obsolete
schema-history stages from the previous example are intentionally not carried
into this app.

## Run and verify

Run the explicit in-memory demo:

```sh
cd example/tasks
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

The ephemeral demo starts with a small seeded workspace created entirely
through production generated APIs. Its Sync badge and Sync center intentionally
show pending durable work, making the offline-first boundary visible without
requiring Supabase credentials.

Without that flag, the app requires `SUPABASE_URL` and `SUPABASE_ANON_KEY` and
fails visibly if they are absent. Never place a service-role key in a Flutter
client.

Quality gate:

```sh
dart run nodus generate
dart run nodus check
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

The tests invoke production entity APIs and widgets through the generated
in-memory graph harness. They cover
task lifecycle, automatic activity tracking, collaboration queue intent,
project-scoped ordering, tombstone visibility, deterministic synchronization,
typed deep links, and compact, medium, and expanded layouts.

## Change the schema

Update the handwritten entity declarations, then run one named migration:

```sh
dart run nodus migrate describe_the_change
```

Nodus detects the resolved schema change, advances `nodus.lock`, and regenerates
the Dart graph, Drift snapshot and migration, canonical Supabase schema, and SQL
migration. Review them together. A plain `dart run nodus` rejects changed schema
without a migration name. The initial migration is a fresh Tasks bootstrap and
must not be overwritten after deployment.
