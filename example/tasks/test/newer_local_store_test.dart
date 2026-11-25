import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/nodus.g.dart';

void main() {
  test('Given a store a newer build migrated, When this build opens it, '
      'Then it refuses and leaves the newer schema version in place', () async {
    final directory = await Directory.systemTemp.createTemp('newer_store');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tasks.sqlite');
    const newerVersion = 99;

    await expectLater(
      TasksExampleEntityGraph.openWithConnectors(
        accountId: LocalId<Account>('00000000-0000-0000-0000-000000000001'),
        supabase: (context) =>
            InMemorySyncBackend.graph(definition: context.definition),
        localStore: _FileStore(
          file,
          setup: (database) => database.userVersion = newerVersion,
        ),
        autoSync: false,
      ),
      throwsA(
        isA<LocalStoreNewerThanAppException>()
            .having((e) => e.storeVersion, 'storeVersion', newerVersion)
            .having(
              (e) => e.appVersion,
              'appVersion',
              TasksExampleMetadata.definition.schemaVersion,
            ),
      ),
    );

    int? recorded;
    final reader = NativeDatabase(
      file,
      setup: (database) => recorded = database.userVersion,
    );
    await reader.ensureOpen(_Reader());
    await reader.close();
    expect(recorded, newerVersion);
  });
}

final class _FileStore implements NodusLocalStore {
  _FileStore(this.file, {required this.setup});

  final File file;
  final DatabaseSetup setup;

  @override
  Future<QueryExecutor> open({
    required String packageName,
    required String accountId,
  }) async => NativeDatabase(file, setup: setup);

  @override
  Future<void> delete({
    required String packageName,
    required String accountId,
  }) async {}
}

final class _Reader implements QueryExecutorUser {
  @override
  int get schemaVersion => 99;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
