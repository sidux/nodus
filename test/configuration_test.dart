import 'dart:io';

import 'package:nodus/src/configuration.dart';
import 'package:nodus/src/tool/initializer.dart';
import 'package:nodus/src/tool/migration_generator.dart';
import 'package:test/test.dart';

void main() {
  test('init rejects target names that cannot become enum values', () {
    expect(
      () => parseInitOptions(['--target', 'switch']),
      throwsA(isA<NodusToolUsageException>()),
    );
    expect(
      () => parseInitOptions(['--target', 'in_memory']),
      throwsA(isA<NodusToolUsageException>()),
    );
    expect(parseInitOptions(['--target', 'rest_api']).target, 'rest_api');
  });

  test('Nodus lock round-trips tool-owned graph state', () {
    const lock = NodusLock(
      packageName: 'tasks_example',
      graphName: 'TasksExample',
      schemaVersion: 3,
      schemaFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      targets: ['supabase'],
      defaultTarget: 'supabase',
    );

    final decoded = NodusLock.decode(lock.encode());

    expect(decoded.packageName, 'tasks_example');
    expect(decoded.graphName, 'TasksExample');
    expect(decoded.schemaVersion, 3);
    expect(decoded.targets, ['supabase']);
    expect(decoded.defaultTarget, 'supabase');
    expect(decoded.schemaFingerprint, lock.schemaFingerprint);
  });

  test('init derives the graph and owns standard Drift setup', () {
    final root = Directory.systemTemp.createTempSync('nodus_init_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: tasks_example
dependencies:
  nodus: any
''');
    Directory('${root.path}/lib').createSync();

    final lock = NodusInitializer(
      root: root,
      report: (_) {},
    ).initialize(parseInitOptions(['--target', 'supabase']));

    expect(lock.graphName, 'TasksExample');
    expect(lock.schemaVersion, 1);
    expect(lock.schemaFingerprint, isNull);
    expect(File('${root.path}/nodus.lock').existsSync(), isTrue);
    final build = File('${root.path}/build.yaml').readAsStringSync();
    expect(build, contains('lib/src/generated/nodus.runtime.g.dart'));
    expect(build, contains('nodus.lock'));
    expect(build, contains('include:\n            - lib/**'));
    expect(build, contains('exclude:\n            - lib/src/generated'));
    expect(build, isNot(contains('enabled: false')));
    expect(
      build,
      contains('tasks_example: lib/src/generated/nodus.runtime.g.dart'),
    );
  });

  test('init rejects a handwritten build configuration', () {
    final root = Directory.systemTemp.createTempSync('nodus_init_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
    Directory('${root.path}/lib').createSync();
    File('${root.path}/build.yaml').writeAsStringSync('targets: {}\n');

    expect(
      () => NodusInitializer(
        root: root,
        report: (_) {},
      ).initialize(const NodusInitOptions(target: 'supabase')),
      throwsA(isA<NodusToolUsageException>()),
    );
    expect(File('${root.path}/nodus.lock').existsSync(), isFalse);
  });
}
