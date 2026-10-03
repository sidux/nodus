import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../nodus_sqlite.dart';

Future<QueryExecutor> openApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final file = await _storeFile(packageName, accountId);
  await file.parent.create(recursive: true);
  return NativeDatabase.createInBackground(
    file,
    setup: installNodusSqlFunctions,
  );
}

Future<void> deleteApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final file = await _storeFile(packageName, accountId);
  // SQLite keeps uncheckpointed writes beside the database file.
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final part = File('${file.path}$suffix');
    if (await part.exists()) await part.delete();
  }
}

Future<File> _storeFile(String packageName, String accountId) async {
  final directory = await getApplicationSupportDirectory();
  final safeAccountId = accountId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return File(
    path.join(directory.path, packageName, 'nodus', '$safeAccountId.sqlite'),
  );
}

QueryExecutor openNodusInMemoryExecutor() =>
    NativeDatabase.memory(setup: installNodusSqlFunctions);
