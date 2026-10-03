# Command line and project files

Nodus ships one executable. Run every command from the root of the
application package (the directory containing `pubspec.yaml` and `lib/`):

```sh
dart run nodus <command>
```

`dart run nodus` (or `dart run nodus --help`) prints the usage summary.
`init`, `explain`, and `inventory` also accept `--help`.

## Everyday workflow

| When | Run |
| --- | --- |
| Once, when adding Nodus to an app | `dart run nodus init --target supabase` |
| After editing entity declarations or route pages | `dart run nodus generate`, or keep `dart run nodus watch` running |
| When the generator says the schema changed | `dart run nodus migrate describe_the_change` |
| Before committing and in CI | `dart run nodus check` |
| When you want to know what Nodus inferred | `dart run nodus explain Task` |

## Commands

### `init --target NAME`

Creates the graph configuration for the package and runs a first generation.

- Discovers every `@Entity` under `lib/`.
- Derives the graph name from the pubspec package name (`tasks_example` →
  `TasksExampleEntityGraph`).
- Writes `nodus.lock` with schema version `1` and `NAME` as the single default
  sync target.
- Writes the Drift builder configuration to `build.yaml`.

`--target` is required and must be a `lower_snake_case` name. `supabase`
selects the built-in Supabase target; any other name (for example `rest_api`)
generates a managed `open<Target>(connector: ...)` factory for a
[custom connector](capabilities.md#custom-connectors).

`init` is safe to repeat with the same target: it keeps the existing lock and
refreshes `build.yaml`. It refuses to run when `build.yaml` contains
handwritten configuration, because Nodus owns that file.

### `generate`

Regenerates the Dart API quickly: the entity implementations, the graph,
`lib/nodus.g.dart`, routes, the test harness, and the generated Supabase
fragment. It then checks the schema fingerprint in `nodus.lock`.

If the resolved physical schema changed, `generate` stops and asks for
`migrate`. Ordinary generation never creates a migration or advances the
schema version. Generation is deterministic and writes nothing when nothing
changed.

### `watch`

Runs `generate` once, then regenerates whenever entity or route sources change.
Run `check` before committing.

### `migrate NAME`

Records a schema change under a `lower_snake_case` name. In one step it:

1. advances the schema version in `nodus.lock` (only when the local schema
   changed — a change confined to the remote schema keeps the device database
   version);
2. regenerates the code;
3. writes the Drift schema snapshot, migration steps, and migration tests;
4. rewrites the canonical Supabase schema `supabase/schemas/public.sql`;
5. for a Supabase target, runs `supabase db diff -f NAME` to write the SQL
   migration into `supabase/migrations/`.

Step 5 needs the [Supabase CLI](https://supabase.com/docs/guides/local-development)
and a running Docker daemon: the CLI diffs the migration history against the
canonical schema in a temporary shadow database. The local Supabase stack
itself does not need to be running. Review all generated migrations together
before committing; the CLI's diff can include unrelated drift.

`migrate` also runs `dart format`, like every full generation (`init` and the
[advanced options](#advanced-generation-options)), but only on generated
outputs: `lib/nodus.g.dart`, `lib/src/generated/`,
`test/nodus_test_harness.g.dart`, and the Drift steps library and versioned
migration-test schemas. Handwritten files, including the Drift
`migration_test.dart` you extend, are never reformatted.

### `check`

Verifies, without changing any file, that:

- every generated file is current;
- `nodus.lock` matches the resolved schema;
- the committed conformance inventory, when one exists, is current.

It exits non-zero with the list of stale files. Use it in CI.

### `explain [ENTITY] [--json]`

Prints what the compiler resolved for the whole graph or one entity — table,
sync mode and target, capabilities, generated set, list, and draft names,
indexes, and the declaration or convention behind each value. `--json` emits
the same information for tools.

### `inventory [--write|--check|--json]`

Scans application source for code that duplicates generated behavior (for
example a repository that forwards a generated query) and for violations of
the optional source boundaries below. Each finding names its evidence and the
generated replacement.

- No option prints the report.
- `--write` saves it to `doc/nodus_conformance_inventory.md`.
- `--check` fails when the saved report is out of date.
- `--json` prints machine-readable output.

Once the inventory file exists, `check` also verifies it.

## Advanced generation options

These options run a full generation (like `migrate`) without a command name:

```sh
dart run nodus --bootstrap-supabase-migration initial_schema
```

| Option | Use |
| --- | --- |
| `--bootstrap-supabase-migration NAME` | Write the first Supabase migration directly from the generated schema, for a project that has none yet. |
| `--overwrite-bootstrap` | With the option above, replace that bootstrap migration while it is still undeployed. |
| `--supabase-migration NAME` | For a Supabase target, the same as `migrate NAME`: record the schema change and write the Supabase SQL diff. |
| `--defer-supabase-composition` | Regenerate Dart and Drift during a coordinated rewrite while leaving `supabase/schemas/public.sql` unchanged. Cannot be combined with a named migration. |
| `--reset-drift-baseline` | Delete generated local migration history and restart at version 1. Only for a deliberate new local-store generation where every existing device database is disposable. Remote migrations are untouched. |

Only one of `--bootstrap-supabase-migration`, `--supabase-migration`, and
`migrate` may be used at a time.

## Project files

### What you write

| Path | Purpose |
| --- | --- |
| `lib/**/domain/**.dart` | Entity declarations (`@Entity()` classes). |
| `lib/features/<feature>/presentation/pages/**/page.dart` | Optional route pages; see [typed routes](capabilities.md#typed-route-generation). |
| `supabase/schema_sources/*.sql` | Optional SQL composed **before** the generated schema, in file-name order. |
| `supabase/schema_extensions/*.sql` | Optional reviewed SQL composed **after** the generated schema, in file-name order. |
| `supabase/manual_migrations/NAME.sql` | Optional SQL appended to the generated Supabase migration `NAME`, or used alone when the diff is empty. |
| `supabase/manual_migrations/NAME.replace.sql` | Optional reviewed SQL that replaces the generated diff for migration `NAME`. |
| `test/drift/<database>/migration_test.dart` | Created once by Drift, then yours. It replays every schema version through the migration strategy; point it at the same strategy the app passes as `migrationOverride` when you add [migration plans](capabilities.md#migrations). |

### What Nodus owns

Commit these files, but never edit them by hand:

| Path | Contents |
| --- | --- |
| `nodus.lock` | Package and graph name, sync targets, schema version, and schema fingerprints. |
| `build.yaml` | Drift builder configuration. |
| `lib/nodus.g.dart` | The single public import for all generated APIs. |
| `lib/src/generated/` | Implementation: entities, graph runtime, Drift database, migrations, routes, and `nodus.explain.g.json`. Never import these paths, except `nodus.migrations.g.dart` where you configure [migration plans](capabilities.md#migrations). |
| `test/nodus_test_harness.g.dart` | The in-memory test harness. |
| `drift_schemas/` and `test/drift/<database>/generated/` | Local schema snapshots for each version, used by migrations and their tests. |
| `supabase/nodus/schema.sql` | The generated Supabase fragment for the target. |
| `supabase/schemas/public.sql` | The canonical composed schema: sources, generated fragment, extensions. Keep it listed in `schema_paths` in `supabase/config.toml`. |
| `supabase/migrations/*.sql` | Generated migrations (reviewed, then deployed). |

### `nodus.lock`

```json
{
  "formatVersion": 1,
  "packageName": "tasks_example",
  "graphName": "TasksExample",
  "schemaVersion": 3,
  "schemaFingerprint": "e0c585eb…",
  "localSchemaFingerprint": "bf4a06de…",
  "targets": ["supabase"],
  "defaultTarget": "supabase"
}
```

The tools maintain every field above. The one optional, hand-maintained
section is `sourceBoundaries`, which declares import rules reported by
`inventory`:

```json
"sourceBoundaries": [
  {
    "name": "domain",
    "sourceDirectories": ["domain"],
    "forbiddenDirectories": ["application", "infrastructure", "presentation"],
    "forbiddenPackages": ["flutter", "supabase"]
  }
]
```

A boundary applies to files inside any directory named in
`sourceDirectories` and forbids imports from the listed directory names and
package-name prefixes. Each boundary must forbid at least one directory or
package. Nodus does not assume any particular folder layout.
