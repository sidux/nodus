import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';

import '../configuration.dart';

typedef CommandRunner =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

typedef TimestampFactory = DateTime Function();

const nodusGenerationUsage = '''Usage: dart run nodus <command> [options]

Fast application generation and deterministic schema migrations.

Options:
  --supabase-migration NAME            Generate a declarative Supabase diff.
  --bootstrap-supabase-migration NAME  Create the initial Supabase migration.
  --overwrite-bootstrap                Replace that undeployed bootstrap file.
  --defer-supabase-composition         Keep the canonical schema unchanged.
  --reset-drift-baseline               Replace local Drift history after store invalidation.
  -h, --help                           Show this help.

Commands:
  init --target NAME                   Create inferred package graph setup.
  generate                             Regenerate application APIs quickly.
  watch                                Regenerate while entity sources change.
  check                                Fail if generated APIs are stale.
  explain [ENTITY] [--json]            Explain the resolved graph or entity.
  migrate NAME                         Generate a named schema migration.
''';

const _fastBuildFilters = <String>[
  '--build-filter=lib/nodus.g.dart',
  '--build-filter=lib/src/generated/entities/**',
  '--build-filter=lib/src/generated/nodus.runtime.g.dart',
  '--build-filter=lib/src/generated/nodus.runtime.g.drift.dart',
  '--build-filter=lib/src/generated/nodus.explain.g.json',
  '--build-filter=lib/src/generated/routes/**',
  '--build-filter=test/nodus_test_harness.g.dart',
  '--build-filter=supabase/nodus/schema.sql',
];

final class NodusGenerationOptions {
  const NodusGenerationOptions({
    this.migration,
    this.supabaseMigration,
    this.bootstrapSupabaseMigration,
    this.overwriteBootstrap = false,
    this.deferSupabaseComposition = false,
    this.resetDriftBaseline = false,
    this.showHelp = false,
  });

  final String? migration;
  final String? supabaseMigration;
  final String? bootstrapSupabaseMigration;
  final bool overwriteBootstrap;
  final bool deferSupabaseComposition;
  final bool resetDriftBaseline;
  final bool showHelp;
}

final class NodusToolUsageException implements Exception {
  const NodusToolUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

NodusGenerationOptions parseGenerationOptions(List<String> arguments) {
  if (arguments.length == 1 &&
      (arguments.single == '--help' || arguments.single == '-h')) {
    return const NodusGenerationOptions(showHelp: true);
  }
  if (arguments.contains('--help') || arguments.contains('-h')) {
    throw const NodusToolUsageException(
      '--help must be used without other options.',
    );
  }
  String? migration;
  String? supabaseMigration;
  String? bootstrapSupabaseMigration;
  var overwriteBootstrap = false;
  var deferSupabaseComposition = false;
  var resetDriftBaseline = false;

  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--migration':
        if (migration != null) {
          throw const NodusToolUsageException(
            '--migration may be provided only once.',
          );
        }
        migration = _readMigrationName(arguments, ++index, argument);
      case '--supabase-migration':
        if (supabaseMigration != null) {
          throw const NodusToolUsageException(
            '--supabase-migration may be provided only once.',
          );
        }
        supabaseMigration = _readMigrationName(arguments, ++index, argument);
      case '--bootstrap-supabase-migration':
        if (bootstrapSupabaseMigration != null) {
          throw const NodusToolUsageException(
            '--bootstrap-supabase-migration may be provided only once.',
          );
        }
        bootstrapSupabaseMigration = _readMigrationName(
          arguments,
          ++index,
          argument,
        );
      case '--overwrite-bootstrap':
        overwriteBootstrap = true;
      case '--defer-supabase-composition':
        deferSupabaseComposition = true;
      case '--reset-drift-baseline':
        resetDriftBaseline = true;
      default:
        throw NodusToolUsageException('Unknown argument: $argument');
    }
  }

  final migrationModes = [
    migration,
    supabaseMigration,
    bootstrapSupabaseMigration,
  ].whereType<String>();
  if (migrationModes.length > 1) {
    throw const NodusToolUsageException(
      'Choose one generic, Supabase, or bootstrap migration mode.',
    );
  }
  if (overwriteBootstrap && bootstrapSupabaseMigration == null) {
    throw const NodusToolUsageException(
      '--overwrite-bootstrap requires --bootstrap-supabase-migration.',
    );
  }
  if (deferSupabaseComposition &&
      (migration != null ||
          supabaseMigration != null ||
          bootstrapSupabaseMigration != null)) {
    throw const NodusToolUsageException(
      '--defer-supabase-composition cannot be combined with a named migration.',
    );
  }
  return NodusGenerationOptions(
    migration: migration,
    supabaseMigration: supabaseMigration,
    bootstrapSupabaseMigration: bootstrapSupabaseMigration,
    overwriteBootstrap: overwriteBootstrap,
    deferSupabaseComposition: deferSupabaseComposition,
    resetDriftBaseline: resetDriftBaseline,
  );
}

String _readMigrationName(List<String> arguments, int index, String option) {
  if (index >= arguments.length) {
    throw NodusToolUsageException('$option requires a migration name.');
  }
  final name = arguments[index];
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    throw NodusToolUsageException(
      'Migration name "$name" must use lower_snake_case.',
    );
  }
  return name;
}

final class NodusGenerator {
  NodusGenerator({
    required Directory root,
    CommandRunner? runCommand,
    TimestampFactory? nowUtc,
    void Function(String message)? report,
    void Function(String warning)? warn,
  }) : root = root.absolute,
       _runCommand = runCommand ?? _runInherited,
       _usesDefaultRunner = runCommand == null,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _report = report ?? stdout.writeln,
       _warn = warn ?? stderr.writeln;

  final Directory root;
  final CommandRunner _runCommand;
  final bool _usesDefaultRunner;
  final TimestampFactory _nowUtc;
  final void Function(String message) _report;
  final void Function(String warning) _warn;

  Future<void> generate(NodusGenerationOptions options) async {
    if (options.showHelp) return;
    _requireConsumerPackage();
    await _run('dart', ['run', 'build_runner', 'build']);
    await _verifySchemaLock(options);
    if (!options.deferSupabaseComposition) synchronizeSupabaseSchema();
    if (options.resetDriftBaseline) resetDriftBaseline();
    await _run('dart', ['run', 'drift_dev', 'make-migrations']);
    normalizeDriftStepsAccessors();
    normalizeDriftTestSchemaAccessors();
    normalizeDriftMigrationTests();
    emitDriftMigrations();
    await _formatGeneratedDart();

    final bootstrap = options.bootstrapSupabaseMigration;
    if (bootstrap != null) {
      bootstrapSupabaseMigration(
        bootstrap,
        overwrite: options.overwriteBootstrap,
      );
      return;
    }
    final migration = options.supabaseMigration;
    if (migration != null) await generateSupabaseMigration(migration);
    final genericMigration = options.migration;
    if (genericMigration != null && _usesTarget('supabase')) {
      await generateSupabaseMigration(genericMigration);
    }
  }

  /// Runs only the compiler builders and schema-fingerprint gate.
  ///
  /// Drift history and remote migrations are deliberately reserved for
  /// [generate] with a named migration so ordinary edit/generate cycles stay
  /// fast.
  Future<void> generateFast() async {
    _requireConsumerPackage();
    await _run('dart', ['run', 'build_runner', 'build', ..._fastBuildFilters]);
    await _verifySchemaLock(const NodusGenerationOptions());
  }

  Future<void> watch() async {
    _requireConsumerPackage();
    await generateFast();
    _report(
      'Watching Nodus entity sources. Run `dart run nodus check` before committing.',
    );
    await _run('dart', ['run', 'build_runner', 'watch', ..._fastBuildFilters]);
  }

  Future<void> check() async {
    _requireConsumerPackage();
    final before = _generatedSources();
    Object? failure;
    StackTrace? failureStack;
    List<String> changed = const [];
    try {
      await _run('dart', ['run', 'build_runner', 'build']);
      await _verifySchemaLock(const NodusGenerationOptions(), checkOnly: true);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      final after = _generatedSources();
      changed =
          {...before.keys, ...after.keys}
              .where((path) => before[path] != after[path])
              .toList(growable: false)
            ..sort();
      _restoreGeneratedSources(before, after);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
    if (changed.isNotEmpty) {
      throw NodusToolUsageException(
        'Generated Nodus output is stale:\n  ${changed.join('\n  ')}\n'
        'Run `dart run nodus generate`.',
      );
    }
    _report('Nodus generated output is current.');
  }

  Future<String> explain({String? entity, bool json = false}) async {
    _requireConsumerPackage();
    if (json && _usesDefaultRunner) {
      await _runQuietly('dart', [
        'run',
        'build_runner',
        'build',
        ..._fastBuildFilters,
      ]);
    } else {
      await _run('dart', [
        'run',
        'build_runner',
        'build',
        ..._fastBuildFilters,
      ]);
    }
    final file = File(_path('lib/src/generated/nodus.explain.g.json'));
    if (!file.existsSync()) {
      throw const NodusToolUsageException(
        'No resolved Nodus explanation was generated.',
      );
    }
    final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final entities = (root['entities']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final selected = entity == null
        ? null
        : entities.where((item) => item['name'] == entity).firstOrNull;
    if (entity != null && selected == null) {
      throw NodusToolUsageException(
        'Unknown entity `$entity`. Available: '
        '${entities.map((item) => item['name']).join(', ')}.',
      );
    }
    if (json) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(selected ?? root);
    }
    if (selected != null) return _formatEntityExplanation(selected);
    final lines = <String>[
      '${root['graph']} (schema ${root['schemaVersion']})',
      'Targets: ${(root['targets'] as List<Object?>).join(', ')}',
      'Entities:',
      for (final item in entities)
        '  ${item['name']} -> ${item['table']} '
            '[${(item['sync'] as Map<String, Object?>)['mode']}]',
    ];
    return lines.join('\n');
  }

  Map<String, String> _generatedSources() {
    final result = <String, String>{};
    final lib = Directory(_path('lib'));
    if (lib.existsSync()) {
      for (final entry in lib.listSync(recursive: true)) {
        if (entry is! File) continue;
        final relative = _relative(entry.path);
        final privateGeneratedDart =
            relative.startsWith('lib/src/generated/') &&
            relative.endsWith('.dart');
        if (!privateGeneratedDart &&
            !relative.endsWith('.g.dart') &&
            !relative.endsWith('.g.json')) {
          continue;
        }
        result[relative] = entry.readAsStringSync();
      }
    }
    final schema = File(_path('supabase/nodus/schema.sql'));
    if (schema.existsSync()) {
      result['supabase/nodus/schema.sql'] = schema.readAsStringSync();
    }
    return result;
  }

  void _restoreGeneratedSources(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    for (final path in after.keys.where((path) => !before.containsKey(path))) {
      File(_path(path)).deleteSync();
    }
    for (final entry in before.entries) {
      final file = File(_path(entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  String _relative(String absolutePath) {
    final prefix = '${root.path}${Platform.pathSeparator}';
    return absolutePath.startsWith(prefix)
        ? absolutePath.substring(prefix.length)
        : absolutePath;
  }

  String _formatEntityExplanation(Map<String, Object?> entity) {
    final sync = entity['sync']! as Map<String, Object?>;
    final capabilities = entity['capabilities']! as Map<String, Object?>;
    final fields = (entity['fields']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final enabledCapabilities = capabilities.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .join(', ');
    return [
      '${entity['name']} -> ${entity['table']}',
      'Source: ${entity['source']}',
      'Ownership: ${entity['ownership']}; cardinality: ${entity['cardinality']}',
      'Sync: ${sync['mode']} via ${sync['target'] ?? 'local storage'}',
      'Capabilities: ${enabledCapabilities.isEmpty ? 'none' : enabledCapabilities}',
      'Fields:',
      for (final field in fields)
        '  ${field['name']}: ${field['type']} -> ${field['column']} '
            '(${field['source']})',
    ].join('\n');
  }

  Future<void> _verifySchemaLock(
    NodusGenerationOptions options, {
    bool checkOnly = false,
  }) async {
    final lockFile = File(_path('nodus.lock'));
    if (!lockFile.existsSync()) return;
    final previousSource = lockFile.readAsStringSync();
    final lock = NodusLock.decode(previousSource);
    final generated = File(_path('lib/nodus.g.dart'));
    if (!generated.existsSync()) {
      throw const NodusToolUsageException(
        'Nodus did not generate lib/nodus.g.dart. Ensure build.yaml includes '
        'the tool-owned Nodus Drift configuration.',
      );
    }
    final match = RegExp(
      r'^// Schema fingerprint: ([a-f0-9]{64})$',
      multiLine: true,
    ).firstMatch(generated.readAsStringSync());
    if (match == null) {
      throw const NodusToolUsageException(
        'Generated lib/nodus.g.dart has no schema fingerprint.',
      );
    }
    final fingerprint = match.group(1)!;
    if (lock.schemaFingerprint == fingerprint) return;

    if (lock.schemaFingerprint == null) {
      if (checkOnly) {
        throw const NodusToolUsageException(
          'nodus.lock has no schema fingerprint. Run `dart run nodus generate`.',
        );
      }
      writeIfChanged(
        lockFile,
        lock.copyWith(schemaFingerprint: fingerprint).encode(),
      );
      _report('Recorded initial Nodus schema fingerprint.');
      return;
    }

    final migrationName =
        options.migration ??
        options.supabaseMigration ??
        options.bootstrapSupabaseMigration;
    if (migrationName == null) {
      throw const NodusToolUsageException(
        'The resolved entity schema changed without a named migration. Run '
        '`dart run nodus migrate <lower_snake_case_name>`.',
      );
    }

    final next = lock.copyWith(
      schemaVersion: lock.schemaVersion + 1,
      schemaFingerprint: fingerprint,
    );
    writeIfChanged(lockFile, next.encode());
    try {
      await _run('dart', ['run', 'build_runner', 'build']);
    } catch (_) {
      writeIfChanged(lockFile, previousSource);
      rethrow;
    }
    _report(
      'Advanced Nodus schema ${lock.schemaVersion}->${next.schemaVersion} '
      'for $migrationName.',
    );
  }

  bool _usesTarget(String target) {
    final lockFile = File(_path('nodus.lock'));
    if (!lockFile.existsSync()) return target == 'supabase';
    return NodusLock.decode(
      lockFile.readAsStringSync(),
    ).targets.contains(target);
  }

  void _requireConsumerPackage() {
    if (!File(_path('pubspec.yaml')).existsSync() ||
        !Directory(_path('lib')).existsSync()) {
      throw const NodusToolUsageException(
        'Run nodus from the root of a Dart or Flutter application.',
      );
    }
  }

  Future<void> _run(String executable, List<String> arguments) =>
      _runCommand(executable, arguments, workingDirectory: root.path);

  Future<void> _runQuietly(String executable, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: root.path,
    );
    if (result.exitCode == 0) return;
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }

  Future<void> _formatGeneratedDart() {
    final targets = <String>['lib'];
    if (Directory(_path('test/features/bdd')).existsSync()) {
      targets.add('test/features/bdd');
    }
    return _run('dart', ['format', ...targets]);
  }

  /// Materializes the canonical declarative schema from optional ordered base
  /// sources, generated entity SQL, and reviewed project-specific extensions.
  void synchronizeSupabaseSchema() {
    final generated = File(_path('supabase/nodus/schema.sql'));
    if (!generated.existsSync()) {
      throw const NodusToolUsageException(
        'No generated Nodus Supabase schema fragment was found.',
      );
    }

    final sections = <String>[];
    final sourcesDirectory = Directory(_path('supabase/schema_sources'));
    if (sourcesDirectory.existsSync()) {
      final sources = _orderedSqlFiles(sourcesDirectory);
      for (final source in sources) {
        sections.add(
          '-- Schema source: ${source.uri.pathSegments.last}\n'
          '${source.readAsStringSync().trim()}',
        );
      }
    }
    sections.add(generated.readAsStringSync().trim());
    final extensionsDirectory = Directory(_path('supabase/schema_extensions'));
    if (extensionsDirectory.existsSync()) {
      for (final extension in _orderedSqlFiles(extensionsDirectory)) {
        sections.add(
          '-- Schema extension: ${extension.uri.pathSegments.last}\n'
          '${extension.readAsStringSync().trim()}',
        );
      }
    }

    final output = File(_path('supabase/schemas/public.sql'));
    final changed = writeIfChanged(output, '${sections.join('\n\n')}\n');
    if (changed) _report('Updated ${_relativePath(output.path)}');
  }

  /// Deletes only generated Drift history after the application has moved to
  /// a new physical local-store generation.
  ///
  /// The current schema becomes version 1 again on the next make-migrations
  /// run. Remote schemas and Supabase migrations are deliberately untouched.
  void resetDriftBaseline() {
    final schemaDirectory = inferDriftSchemaDirectory();
    final generated = <File>[
      ...schemaDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => _schemaVersion(file) != null),
      ...Directory(_path('lib'))
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.g.steps.dart')),
      if (Directory(_path('test')).existsSync())
        ...Directory(_path('test'))
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) {
              final name = file.uri.pathSegments.last;
              if (!RegExp(r'^schema(?:_v\d+)?\.dart$').hasMatch(name)) {
                return false;
              }
              return file.readAsStringSync().contains('GENERATED BY drift_dev');
            }),
    ];
    for (final file in generated) {
      file.deleteSync();
    }
    _report('Reset ${generated.length} generated Drift baseline artifacts.');
  }

  List<File> _orderedSqlFiles(Directory directory) =>
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  void emitDriftMigrations() {
    final schemaDirectory = inferDriftSchemaDirectory();
    final snapshots = _schemaSnapshots(schemaDirectory);
    if (snapshots.isEmpty) {
      throw const NodusToolUsageException(
        'No Drift schema snapshots were generated.',
      );
    }

    final callbacks = <String>[];
    for (final (oldSnapshot, newSnapshot) in _adjacent(snapshots)) {
      if (newSnapshot.version != oldSnapshot.version + 1) {
        throw NodusToolUsageException(
          'Drift schema versions must be contiguous: '
          '${oldSnapshot.version} -> ${newSnapshot.version}.',
        );
      }
      final proposal = migrationStatements(oldSnapshot.file, newSnapshot.file);
      callbacks.add(
        _emitTransition(oldSnapshot.version, newSnapshot.version, proposal),
      );
      if (proposal.requiresManualChanges) {
        _warn(
          'WARNING: Drift schema ${oldSnapshot.version}->'
          '${newSnapshot.version} contains destructive or semantic changes. '
          'Return an augmenting or replacement NodusMigrationPlan.',
        );
      }
    }

    final output = File(_path('lib/src/generated/nodus.migrations.g.dart'));
    output.parent.createSync(recursive: true);
    final steps = snapshots.length > 1 ? inferDriftStepsFile() : null;
    final source = _emitMigrationLibrary(
      callbacks: callbacks,
      stepsImport: steps == null ? null : _relativeImport(output.parent, steps),
    );
    final formatted = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(source);
    final changed = writeIfChanged(output, formatted);
    _report(
      '${changed ? 'Generated' : 'Unchanged'} '
      '${_relativePath(output.path)}',
    );
  }

  Directory inferDriftSchemaDirectory() {
    final schemaRoot = Directory(_path('drift_schemas'));
    if (!schemaRoot.existsSync()) {
      throw const NodusToolUsageException(
        'No drift_schemas directory was generated.',
      );
    }
    final candidates = schemaRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => _schemaVersion(file) != null)
        .map((file) => file.parent.path)
        .toSet()
        .map(Directory.new)
        .toList();
    if (candidates.length != 1) {
      throw NodusToolUsageException(
        'Expected exactly one generated Drift database under drift_schemas, '
        'found ${candidates.length}.',
      );
    }
    return candidates.single;
  }

  File inferDriftStepsFile() {
    final candidates = Directory(_path('lib'))
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.g.steps.dart'))
        .toList();
    if (candidates.length != 1) {
      throw NodusToolUsageException(
        'Expected exactly one generated Drift steps library under lib, '
        'found ${candidates.length}.',
      );
    }
    return candidates.single;
  }

  /// Restores the declared Dart getter names in Drift's versioned schema.
  ///
  /// `drift_dev make-migrations` currently derives `Shape*` accessors from SQL
  /// column names. That loses an explicitly generated getter name such as
  /// `textColumn` and can recreate a member that conflicts with `Table.text`.
  /// The serialized schema remains the source of truth for these Dart names.
  void normalizeDriftStepsAccessors() {
    final snapshots = _schemaSnapshots(inferDriftSchemaDirectory());
    if (snapshots.length < 2) return;
    final steps = inferDriftStepsFile();
    final source = steps.readAsStringSync();
    final tables = <String, Map<String, String>>{};
    for (final entry in _entities(snapshots.last.file).entries) {
      if (entry.key.type != 'table') continue;
      tables[entry.key.name] = {
        for (final column in _columns(entry.value).entries)
          column.key: _requiredString(column.value, 'getter_name'),
      };
    }
    final shapeTables = <String, String>{};
    final declarations = RegExp(
      r"late final (Shape\d+)\s+\w+\s*=\s*\1\(\s*"
      r"source:\s*i0\.VersionedTable\(\s*entityName:\s*'([^']+)'",
      multiLine: true,
    );
    for (final match in declarations.allMatches(source)) {
      shapeTables[match.group(1)!] = match.group(2)!;
    }
    final shapes = RegExp(
      r'class (Shape\d+) extends i0\.VersionedTable \{[\s\S]*?\n\}',
      multiLine: true,
    );
    final accessors = RegExp(
      r"(get )([A-Za-z_]\w*)(\s*=>\s*columnsByName\['([^']+)'\])",
      multiLine: true,
    );
    final normalized = source.replaceAllMapped(shapes, (shapeMatch) {
      final shapeName = shapeMatch.group(1)!;
      final columns = tables[shapeTables[shapeName]];
      if (columns == null) return shapeMatch.group(0)!;
      return shapeMatch.group(0)!.replaceAllMapped(accessors, (match) {
        final getter = columns[match.group(4)];
        if (getter == null || getter == match.group(2)) return match.group(0)!;
        return '${match.group(1)}$getter${match.group(3)}';
      });
    });
    writeIfChanged(steps, normalized);
  }

  /// Removes Drift's placeholder data-integrity template from generated tests.
  ///
  /// The exhaustive empty-schema migration matrix remains. The trailing
  /// template contains unresolved TODOs and empty expectations, so it does not
  /// exercise production behavior until an application authors a real data
  /// migration test of its own.
  void normalizeDriftMigrationTests() {
    final testDirectory = Directory(_path('test'));
    if (!testDirectory.existsSync()) return;
    const marker = '  // The following template shows how to write tests';
    final versionImport = RegExp(
      r"^import 'generated/schema_v\d+\.dart' as v\d+;\n",
      multiLine: true,
    );
    for (final file
        in testDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (file) => file.uri.pathSegments.last == 'migration_test.dart',
            )) {
      final source = file.readAsStringSync();
      final templateStart = source.indexOf(marker);
      var normalized = templateStart < 0
          ? source
          : '${source.substring(0, templateStart).replaceAll(versionImport, '').trimRight()}\n}\n';
      final runtimeImport = RegExp(
        r"import 'package:([^/]+)/src/generated/nodus\.runtime\.g\.dart';",
      ).firstMatch(normalized);
      final databaseConstructor = RegExp(
        r'final db = (\w+Database)\(schema\.newConnection\(\)\);',
      ).firstMatch(normalized);
      if (runtimeImport != null && databaseConstructor != null) {
        final packageName = runtimeImport.group(1)!;
        final databaseName = databaseConstructor.group(1)!;
        final metadataName = databaseName.replaceFirst(
          RegExp(r'Database$'),
          'Metadata',
        );
        final migrationsImport =
            "import 'package:$packageName/src/generated/nodus.migrations.g.dart';";
        if (!normalized.contains(migrationsImport)) {
          normalized = normalized.replaceFirst(
            runtimeImport.group(0)!,
            '${runtimeImport.group(0)!}\n$migrationsImport',
          );
        }
        normalized = normalized.replaceFirst(
          databaseConstructor.group(0)!,
          '''final db = $databaseName(
              schema.newConnection(),
              migrationOverride: nodusMigrationStrategy<$databaseName>(
                initialPullTargets: $metadataName.definition.syncTargets,
              ),
            );''',
        );
      }
      if (normalized == source) continue;
      final formatted = DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(normalized);
      file.writeAsStringSync(formatted);
    }
  }

  /// Restores declared getters in Drift's generated migration-test libraries.
  ///
  /// Drift's test emitter currently recreates the SQL name as the Dart field,
  /// even when the serialized schema records a collision-free getter such as
  /// `textColumn`. SQL names and data-class properties remain unchanged; only
  /// the generated table member and its metadata references are normalized.
  void normalizeDriftTestSchemaAccessors() {
    final snapshots = _schemaSnapshots(inferDriftSchemaDirectory());
    if (snapshots.isEmpty) return;
    final testRoot = Directory(_path('test'));
    if (!testRoot.existsSync()) return;
    final generatedSchemas = testRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList(growable: false);
    for (final snapshot in snapshots) {
      final renamedByTable = <String, Map<String, String>>{};
      for (final entry in _entities(snapshot.file).entries) {
        if (entry.key.type != 'table') continue;
        final renamed = <String, String>{};
        for (final column in _columns(entry.value).entries) {
          final getter = _requiredString(column.value, 'getter_name');
          if (getter != column.key) renamed[column.key] = getter;
        }
        if (renamed.isNotEmpty) renamedByTable[entry.key.name] = renamed;
      }
      if (renamedByTable.isEmpty) continue;
      for (final file in generatedSchemas.where(
        (file) => file.path.endsWith('schema_v${snapshot.version}.dart'),
      )) {
        final source = file.readAsStringSync();
        final tableClasses = RegExp(
          r'class \w+ extends Table\s+with TableInfo<[\s\S]*?(?=\nclass \w+Data extends DataClass)',
          multiLine: true,
        );
        final normalized = source.replaceAllMapped(tableClasses, (match) {
          var tableSource = match.group(0)!;
          final tableName = RegExp(
            r"static const String \$name = '([^']+)';",
          ).firstMatch(tableSource)?.group(1);
          final renamed = renamedByTable[tableName];
          if (renamed == null) return tableSource;
          for (final entry in renamed.entries) {
            final oldGetter = RegExp.escape(entry.key);
            tableSource = tableSource.replaceFirstMapped(
              RegExp(
                '(late final GeneratedColumn<[^>]+> )$oldGetter( = '
                'GeneratedColumn<[^>]+>\\()',
              ),
              (declaration) =>
                  '${declaration.group(1)}${entry.value}${declaration.group(2)}',
            );
            tableSource = _replaceAccessorMetadata(
              tableSource,
              oldGetter: entry.key,
              newGetter: entry.value,
            );
          }
          return tableSource;
        });
        if (normalized != source) writeIfChanged(file, normalized);
      }
    }
  }

  static String _replaceAccessorMetadata(
    String source, {
    required String oldGetter,
    required String newGetter,
  }) {
    final metadata = RegExp(
      r'(List<GeneratedColumn> get \$columns => \[[\s\S]*?\];|'
      r'Set<GeneratedColumn> get \$primaryKey => \{[\s\S]*?\};|'
      r'List<Set<GeneratedColumn>> get uniqueKeys => \[[\s\S]*?\];)',
      multiLine: true,
    );
    final identifier = RegExp('\\b${RegExp.escape(oldGetter)}\\b');
    return source.replaceAllMapped(
      metadata,
      (match) => match.group(0)!.replaceAll(identifier, newGetter),
    );
  }

  MigrationProposal migrationStatements(File oldFile, File newFile) {
    final oldEntities = _entities(oldFile);
    final newEntities = _entities(newFile);
    final statements = <String>[];
    var requiresManualChanges = false;

    for (final entry in newEntities.entries) {
      final key = entry.key;
      final data = entry.value;
      final previous = oldEntities[key];
      if (previous == null) {
        statements.add(
          'await migrator.create(schema.${_camelCase(key.name)});',
        );
        continue;
      }
      if (key.type != 'table') {
        final changed = !_jsonEquivalent(
          _withoutKey(previous, 'on'),
          _withoutKey(data, 'on'),
        );
        if (changed && key.type == 'index') {
          final index = _camelCase(key.name);
          statements
            ..add('await migrator.drop(schema.$index);')
            ..add('await migrator.create(schema.$index);');
        } else if (changed) {
          requiresManualChanges = true;
        }
        continue;
      }

      final oldColumns = _columns(previous);
      final newColumns = _columns(data);
      final removed = oldColumns.keys.toSet().difference(
        newColumns.keys.toSet(),
      );
      final changed = oldColumns.keys
          .toSet()
          .intersection(newColumns.keys.toSet())
          .where(
            (name) => !_jsonEquivalent(oldColumns[name], newColumns[name]),
          );
      if (removed.isNotEmpty ||
          changed.isNotEmpty ||
          !_jsonEquivalent(previous['constraints'], data['constraints'])) {
        requiresManualChanges = true;
      }
      for (final name in newColumns.keys.toSet().difference(
        oldColumns.keys.toSet(),
      )) {
        final column = newColumns[name]!;
        final nullable = column['nullable'] == true;
        if (!nullable && column['default_dart'] == null) {
          requiresManualChanges = true;
          continue;
        }
        final getter = _requiredString(column, 'getter_name');
        final table = _camelCase(key.name);
        statements.addAll([
          'await migrator.addColumn(',
          '  schema.$table,',
          '  schema.$table.$getter,',
          ');',
        ]);
      }
    }

    if (oldEntities.keys
        .toSet()
        .difference(newEntities.keys.toSet())
        .isNotEmpty) {
      requiresManualChanges = true;
    }
    return MigrationProposal(
      statements: statements,
      requiresManualChanges: requiresManualChanges,
    );
  }

  Future<void> generateSupabaseMigration(String name) async {
    _validateMigrationName(name);
    final migrations = Directory(_path('supabase/migrations'));
    migrations.createSync(recursive: true);
    final manual = Directory(_path('supabase/manual_migrations'));
    final replacement = File(
      '${manual.path}${Platform.pathSeparator}$name.replace.sql',
    );
    final fragment = File('${manual.path}${Platform.pathSeparator}$name.sql');
    _rejectExistingMigration(migrations, name);

    if (replacement.existsSync()) {
      final output = _timestampedMigration(migrations, name);
      output.writeAsStringSync(
        '-- Reviewed manual replacement for the generated declarative diff.\n\n'
        '${replacement.readAsStringSync().trim()}\n',
      );
      _report('Created ${_relativePath(output.path)}');
      return;
    }

    await _run('supabase', ['db', 'diff', '-f', name]);
    final candidates = _namedMigrations(migrations, name);
    if (candidates.isEmpty) {
      if (!fragment.existsSync()) {
        _report('No Supabase schema changes found for $name.');
        return;
      }
      final output = _timestampedMigration(migrations, name);
      output.writeAsStringSync(
        '-- Reviewed manual migration without a declarative schema diff.\n\n'
        '${fragment.readAsStringSync().trim()}\n',
      );
      _report('Created ${_relativePath(output.path)}');
      return;
    }
    if (candidates.length != 1) {
      throw NodusToolUsageException(
        'Supabase generated ${candidates.length} migrations named $name.',
      );
    }
    if (!fragment.existsSync()) return;
    final output = candidates.single;
    output.writeAsStringSync(
      '${output.readAsStringSync().trimRight()}\n\n'
      '-- Reviewed manual migration extension.\n'
      '${fragment.readAsStringSync().trim()}\n',
    );
  }

  void bootstrapSupabaseMigration(String name, {required bool overwrite}) {
    _validateMigrationName(name);
    final migrations = Directory(_path('supabase/migrations'));
    migrations.createSync(recursive: true);
    final existing = _namedMigrations(migrations, name);
    if (existing.length > 1) {
      throw NodusToolUsageException(
        'Found multiple Supabase migrations named $name.',
      );
    }
    if (existing.isNotEmpty && !overwrite) {
      throw NodusToolUsageException(
        'A Supabase migration named $name already exists.',
      );
    }
    final schema = File(_path('supabase/schemas/public.sql'));
    if (!schema.existsSync()) {
      throw const NodusToolUsageException(
        'No generated Supabase public schema was found.',
      );
    }
    final output = existing.isEmpty
        ? _timestampedMigration(migrations, name)
        : existing.single;
    output.writeAsStringSync(
      '-- Initial migration generated from the reviewed declarative entity schema.\n\n'
      '${schema.readAsStringSync().trim()}\n',
    );
    _report('Created ${_relativePath(output.path)}');
  }

  String _emitTransition(int from, int to, MigrationProposal proposal) {
    final buffer = StringBuffer()
      ..writeln('from${from}To$to: (migrator, schema) async {')
      ..writeln('  final transition = NodusSchemaTransition(')
      ..writeln('    from: $from,')
      ..writeln('    to: $to,')
      ..writeln('  );')
      ..writeln('  final plan = configuredHooks.plan(transition);');
    if (proposal.requiresManualChanges) {
      buffer
        ..writeln('  if (!plan.handlesManualChanges) {')
        ..writeln('    throw StateError(')
        ..writeln(
          "      'Schema transition $from->$to requires an explicit manual migration plan.',",
        )
        ..writeln('    );')
        ..writeln('  }');
    }
    buffer.writeln('  if (plan.runsGeneratedSteps) {');
    for (final statement in proposal.statements) {
      buffer.writeln('    $statement');
    }
    buffer
      ..writeln('  }')
      ..writeln('  await applyNodusMigrationPlan<D>(')
      ..writeln('    plan: plan,')
      ..writeln('    migrator: migrator,')
      ..writeln('    transition: transition,')
      ..writeln('  );')
      ..writeln('  final violations = await migrator.database')
      ..writeln("      .customSelect('pragma foreign_key_check')")
      ..writeln('      .get();')
      ..writeln('  if (violations.isNotEmpty) {')
      ..writeln('    throw StateError(')
      ..writeln("      'Drift migration introduced foreign-key violations.',")
      ..writeln('    );')
      ..writeln('  }')
      ..writeln('},');
    return buffer.toString();
  }

  String _emitMigrationLibrary({
    required List<String> callbacks,
    required String? stepsImport,
  }) {
    final steps = stepsImport == null
        ? ''
        : "import '$stepsImport' as steps;\n\n";
    final hooks = callbacks.isEmpty
        ? '  final _ = hooks;\n'
        : '  final configuredHooks = hooks ?? NodusMigrationHooks<D>();\n';
    final upgrade = callbacks.isEmpty
        ? '''  Future<void> generatedUpgrade(
    Migrator migrator,
    int from,
    int to,
  ) async => throw StateError(
    'No generated Drift migration for \$from -> \$to.',
  );'''
        : '''  final stepUpgrade = steps.stepByStep(
${callbacks.map((value) => _indent(value, 4)).join()}  );
  Future<void> generatedUpgrade(
    Migrator migrator,
    int from,
    int to,
  ) => stepUpgrade(migrator, from, to);''';
    return '''// GENERATED FILE. DO NOT EDIT.
// Exceptional transitions are configured with NodusMigrationHooks.

import 'package:nodus/nodus_migrations.dart';

${steps}MigrationStrategy nodusMigrationStrategy<D extends GeneratedDatabase>({
  required Iterable<SyncTargetId> initialPullTargets,
  NodusMigrationHooks<D>? hooks,
}) {
$hooks  final cursorTargets = initialPullTargets.toSet();
$upgrade

  return MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      for (final target in cursorTargets) {
        await migrator.database.customStatement(
          'insert or ignore into local_entity_sync_cursor '
          '(sync_target, cursor) values (?, 0)',
          [target.wireName],
        );
      }
    },
    onUpgrade: generatedUpgrade,
  );
}
''';
  }

  Map<_EntityKey, Map<String, Object?>> _entities(File file) {
    final document = _requiredMap(
      jsonDecode(file.readAsStringSync()),
      'schema',
    );
    final entities = _requiredList(document['entities'], 'entities');
    return {
      for (final raw in entities)
        _entityKey(raw): _requiredMap(
          _requiredMap(raw, 'entity')['data'],
          'entity.data',
        ),
    };
  }

  _EntityKey _entityKey(Object? raw) {
    final entity = _requiredMap(raw, 'entity');
    final data = _requiredMap(entity['data'], 'entity.data');
    return _EntityKey(
      _requiredString(entity, 'type'),
      _requiredString(data, 'name'),
    );
  }

  Map<String, Map<String, Object?>> _columns(Map<String, Object?> table) {
    final columns = _requiredList(table['columns'], 'table.columns');
    return {
      for (final raw in columns)
        _requiredString(_requiredMap(raw, 'column'), 'name'): _requiredMap(
          raw,
          'column',
        ),
    };
  }

  List<_SchemaSnapshot> _schemaSnapshots(Directory directory) {
    final snapshots =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .map((file) => (file: file, version: _schemaVersion(file)))
            .where((entry) => entry.version != null)
            .map((entry) => _SchemaSnapshot(entry.version!, entry.file))
            .toList()
          ..sort((left, right) => left.version.compareTo(right.version));
    return snapshots;
  }

  Iterable<(_SchemaSnapshot, _SchemaSnapshot)> _adjacent(
    List<_SchemaSnapshot> snapshots,
  ) sync* {
    for (var index = 1; index < snapshots.length; index++) {
      yield (snapshots[index - 1], snapshots[index]);
    }
  }

  int? _schemaVersion(File file) {
    final match = RegExp(r'drift_schema_v(\d+)\.json$').firstMatch(file.path);
    return match == null ? null : int.parse(match.group(1)!);
  }

  File _timestampedMigration(Directory directory, String name) {
    final timestamp = _nowUtc().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final prefix =
        '${timestamp.year.toString().padLeft(4, '0')}'
        '${two(timestamp.month)}${two(timestamp.day)}'
        '${two(timestamp.hour)}${two(timestamp.minute)}${two(timestamp.second)}';
    return File(
      '${directory.path}${Platform.pathSeparator}${prefix}_$name.sql',
    );
  }

  List<File> _namedMigrations(Directory directory, String name) {
    if (!directory.existsSync()) return const [];
    final suffix = '_$name.sql';
    final files =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith(suffix))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  void _rejectExistingMigration(Directory directory, String name) {
    if (_namedMigrations(directory, name).isNotEmpty) {
      throw NodusToolUsageException(
        'A Supabase migration named $name already exists.',
      );
    }
  }

  void _validateMigrationName(String name) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw NodusToolUsageException(
        'Migration name "$name" must use lower_snake_case.',
      );
    }
  }

  String _path(String relative) =>
      '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

  String _relativePath(String absolute) => absolute
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
}

final class MigrationProposal {
  const MigrationProposal({
    required this.statements,
    required this.requiresManualChanges,
  });

  final List<String> statements;
  final bool requiresManualChanges;
}

final class _SchemaSnapshot {
  const _SchemaSnapshot(this.version, this.file);

  final int version;
  final File file;
}

final class _EntityKey {
  const _EntityKey(this.type, this.name);

  final String type;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _EntityKey && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);
}

Future<void> _runInherited(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command exited with code $result.',
      result,
    );
  }
}

bool writeIfChanged(File file, String content) {
  if (file.existsSync() && file.readAsStringSync() == content) return false;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return true;
}

Map<String, Object?> _requiredMap(Object? value, String context) {
  if (value is! Map) {
    throw FormatException('Expected an object for $context.', value);
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _requiredList(Object? value, String context) {
  if (value is! List) {
    throw FormatException('Expected a list for $context.', value);
  }
  return value.cast<Object?>();
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected a non-empty string for $key.', value);
  }
  return value;
}

Map<String, Object?> _withoutKey(Map<String, Object?> source, String key) => {
  for (final entry in source.entries)
    if (entry.key != key) entry.key: entry.value,
};

bool _jsonEquivalent(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length ||
        !left.keys.toSet().containsAll(right.keys)) {
      return false;
    }
    return left.keys.every((key) => _jsonEquivalent(left[key], right[key]));
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquivalent(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

String _camelCase(String source) {
  final parts = source.split('_');
  return parts.first +
      parts.skip(1).map((part) {
        if (part.isEmpty) return '';
        return '${part[0].toUpperCase()}${part.substring(1)}';
      }).join();
}

String _relativeImport(Directory from, File to) {
  final fromParts = from.absolute.path
      .split(Platform.pathSeparator)
      .where((part) => part.isNotEmpty)
      .toList();
  final toParts = to.absolute.path
      .split(Platform.pathSeparator)
      .where((part) => part.isNotEmpty)
      .toList();
  var shared = 0;
  while (shared < fromParts.length &&
      shared < toParts.length &&
      fromParts[shared] == toParts[shared]) {
    shared++;
  }
  final parts = <String>[
    for (var index = shared; index < fromParts.length; index++) '..',
    ...toParts.skip(shared),
  ];
  final relative = parts.join('/');
  return relative.startsWith('.') ? relative : './$relative';
}

String _indent(String source, int spaces) {
  final prefix = ' ' * spaces;
  return source
      .split('\n')
      .where((line) => line.isNotEmpty)
      .map((line) => '$prefix$line\n')
      .join();
}
