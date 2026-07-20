import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<QueryExecutor> openApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final directory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(
    path.join(directory.path, packageName, 'nodus'),
  );
  await databaseDirectory.create(recursive: true);
  final safeAccountId = accountId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return NativeDatabase.createInBackground(
    File(path.join(databaseDirectory.path, '$safeAccountId.sqlite')),
  );
}

QueryExecutor openNodusInMemoryExecutor() => NativeDatabase.memory();
