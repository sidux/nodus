@Tags(['flutter'])
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting an account store removes its database and journal files, '
      'and leaves other accounts alone', () async {
    final support = Directory.systemTemp.createTempSync('nodus_store_');
    addTearDown(() => support.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => support.path,
        );
    const store = ApplicationSupportNodusLocalStore();
    Future<void> write(String accountId) async {
      final executor = await store.open(
        packageName: 'fixture',
        accountId: accountId,
      );
      await executor.ensureOpen(_NoMigrations());
      await executor.runCustom('create table notes (id text)');
      await executor.close();
    }

    await write('account-1');
    await write('account-2');
    final directory = Directory('${support.path}/fixture/nodus');
    File('${directory.path}/account-1.sqlite-wal').writeAsStringSync('');

    await store.delete(packageName: 'fixture', accountId: 'account-1');

    final remaining = directory
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .toList();
    expect(remaining.where((name) => name.startsWith('account-1')), isEmpty);
    expect(remaining, contains('account-2.sqlite'));
  });
}

final class _NoMigrations extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
