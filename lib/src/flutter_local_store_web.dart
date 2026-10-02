import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Opens one browser-persisted SQLite database per account.
///
/// The application serves drift's `sqlite3.wasm` and compiled `drift_worker.js`
/// from its web root; drift selects the strongest available storage (OPFS,
/// shared worker, or IndexedDB) for the current browser.
Future<QueryExecutor> openApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final safeAccountId = accountId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final result = await WasmDatabase.open(
    databaseName: '${packageName}_nodus_$safeAccountId',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}

QueryExecutor openNodusInMemoryExecutor() => throw UnsupportedError(
  'The default in-memory Nodus executor is not available on the web.',
);
