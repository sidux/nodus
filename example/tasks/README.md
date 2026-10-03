# Tasks reference app

A complete Flutter app built with Nodus. It is deliberately focused on tasks
— creating and editing work, projects and ordering, completion, archiving,
collaboration, activity history, deletion, and synchronization — so every
line of handwritten code shows one Nodus feature in context.

The app depends on Nodus through a local path ([`nodus`](../..)). Its domain
declarations and page files express intent; everything else is generated.

## Run it

Without any backend, using an in-memory database and sync backend:

```sh
cd example/tasks
flutter pub get
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

The demo seeds a small workspace through the same generated APIs the UI uses.
Its **Sync** badge and Sync center show pending durable work on purpose: this
is the offline-first queue, made visible.

The repository only contains the `macos/` platform folder. For another
platform, run `flutter create .` in this directory first.

### With a local Supabase

1. Start the bundled stack with the Supabase CLI: `supabase start`. It applies
   the migrations in `supabase/migrations/` and enables anonymous sign-in,
   which the app uses.
2. Copy `.env.example` to `.env` and set `SUPABASE_ANON_KEY` from the
   `supabase start` output.
3. Run `flutter run --dart-define-from-file=.env`.

Without `ALLOW_IN_MEMORY_DEMO`, the app requires `SUPABASE_URL` and
`SUPABASE_ANON_KEY` and shows an error if they are missing. Never put a
service-role key in a Flutter client.

## Where to look

| Feature | Source |
| --- | --- |
| Entity declarations | [`lib/features/tasks/domain/`](lib/features/tasks/domain) — `Task`, `TaskProject`, `TaskActivity` |
| Graph bootstrap (Supabase or in-memory) | [`lib/app_bootstrap.dart`](lib/app_bootstrap.dart) |
| Create/edit form bound to one draft | [`task_editor.dart`](lib/features/tasks/presentation/components/task_editor.dart) |
| Filtered, paged, observed list | [`task_list.dart`](lib/features/tasks/presentation/components/task_list.dart) |
| Typed routes | [`lib/features/*/presentation/pages/`](lib/features/tasks/presentation/pages) |
| Tests on the real graph | [`test/`](test) |

## What it demonstrates

**Entities.** `Task` is an unbounded (paged) entity, ordered within its
project. It implements `SoftDeletable`, `Archivable`, `Ordered`,
`ActivityTracked`, and `Collaborative<Account>`, and declares the actions
`start`, `complete`, `reopen`, and `moveToProject`. From that declaration Nodus
generates creation, edit drafts, `remove()`/`restore()`,
`archive()`/`unarchive()`, ordering moves, and `setCollaborator(...)`.
`TaskProject` is a bounded entity, so its complete list is always in memory.

**Activity history.** `TaskActivity` implements `ActivityOf<Task, Account>`.
Every task change appends one immutable activity entry in the same local
transaction. Callers just call `task.complete()` or `task.archive()`; there is
no activity code to write.

**One form model.** `TaskMutationDraft` backs both the create and edit forms.
Its typed fields bind directly to Flutter widgets. When one save changes both
ordinary fields and the project, the draft applies the edit and the
`moveToProject` action in one transaction.

**Queries and observation.** Typed predicates drive the open, completed, and
archived views. Observed list and lookup hooks replace hand-written
loading/empty/error plumbing, and lookups keep a task's identity loaded for
the lifetime of its detail, edit, and access pages.

**Ordering.** Project task lists use generated rank ordering with neighbor
moves; widgets never see or write a rank.

**Collaboration and deletion.** `task.setCollaborator(...)` is a generated
operation that queues correctly alongside other offline writes. Soft deletion
produces synchronized tombstones that ordinary queries hide.

**Sync center.** Renders the graph-owned durable push/pull queue.

**Routing.** Page files generate typed deep links, including `/tasks`,
`/tasks/new`, `/tasks/:taskId`, `/tasks/:taskId/edit`,
`/tasks/:taskId/access`, `/projects`, `/projects/new`,
`/projects/:projectId`, `/activity`, and `/sync`, plus a shared layout, a root
redirect, and a not-found page.

**Adaptive layout.** A bottom navigation bar below 600 logical pixels, a
compact rail from 600 to 839, and an extended rail with a list/detail split at
840 and above.

## How the generated code is organized

There is no handwritten graph setup. Nodus discovers the entity declarations,
derives `TasksExampleEntityGraph` from the package name `tasks_example`, and
exposes every generated API through [`lib/nodus.g.dart`](lib/nodus.g.dart).
Implementation files live under `lib/src/generated/` and are never imported
directly. Tests use the generated `test/nodus_test_harness.g.dart`.

[`nodus.lock`](nodus.lock) records the graph name, the `supabase` target, the
schema version, and the schema fingerprints.

On the backend side, Nodus generates the fragment `supabase/nodus/schema.sql`
and composes it into the canonical schema
[`supabase/schemas/public.sql`](supabase/schemas/public.sql). The reviewed,
deployable history is in [`supabase/migrations/`](supabase/migrations).

## Verify

```sh
dart run nodus check
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

The tests drive production entity APIs and widgets through the generated
in-memory harness. They cover the task lifecycle, activity tracking,
transactions, collaboration queue intent, project ordering, tombstone
visibility, synchronization, local-store ownership, typed deep links, the
generated Drift migrations, and compact, medium, and expanded layouts.

## Change the schema

Edit an entity declaration, then record the change under a name:

```sh
dart run nodus migrate describe_the_change
```

`dart run nodus generate` refuses a schema change without a migration name.
`migrate` updates `nodus.lock`, regenerates the code, and writes the Drift
migration (when the local schema changed), the canonical Supabase schema, and
a Supabase SQL migration produced by `supabase db diff`, which needs the
Supabase CLI and a running Docker daemon. Review them together. Never rewrite a migration that
has already been deployed.
