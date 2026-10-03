import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:nodus/nodus.dart';
import 'package:web/web.dart' as web;

/// Opens one browser-persisted SQLite database per account.
///
/// The application serves drift's `sqlite3.wasm` and compiled `drift_worker.js`
/// from its web root; drift selects the strongest available storage (OPFS,
/// shared worker, or IndexedDB) for the current browser.
///
/// Every tab and worker of the origin reaches the same database, so the store
/// is claimed through an exclusive Web Lock before it opens and released when
/// the executor closes. A second claimant fails with
/// [LocalStoreInUseException] instead of opening an incoherent second graph.
Future<QueryExecutor> openApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final databaseName = _databaseName(packageName, accountId);
  final release = await _claimStore(databaseName);
  try {
    final result = await WasmDatabase.open(
      databaseName: databaseName,
      sqlite3Uri: _sqlite3Uri,
      driftWorkerUri: _driftWorkerUri,
    );
    return result.resolvedExecutor.interceptWith(_ReleaseOnClose(release));
  } catch (_) {
    release();
    rethrow;
  }
}

/// Deletes the account's database from whichever browser storage holds it.
Future<void> deleteApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) async {
  final databaseName = _databaseName(packageName, accountId);
  final probe = await WasmDatabase.probe(
    sqlite3Uri: _sqlite3Uri,
    driftWorkerUri: _driftWorkerUri,
    databaseName: databaseName,
  );
  for (final existing in probe.existingDatabases) {
    if (existing.$2 == databaseName) await probe.deleteDatabase(existing);
  }
}

final _sqlite3Uri = Uri.parse('sqlite3.wasm');
final _driftWorkerUri = Uri.parse('drift_worker.js');

String _databaseName(String packageName, String accountId) =>
    '${packageName}_nodus_${accountId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';

QueryExecutor openNodusInMemoryExecutor() => throw UnsupportedError(
  'The default in-memory Nodus executor is not available on the web.',
);

/// Holds the exclusive lock for [databaseName] and returns its release.
///
/// Web Locks exist only in secure contexts; elsewhere no other tab can be
/// detected, so the store opens unclaimed.
Future<void Function()> _claimStore(String databaseName) async {
  if (!web.window.navigator.has('locks')) return () {};
  final locks = web.window.navigator.locks;
  final lockName = 'nodus:$databaseName';
  final granted = Completer<bool>();
  final released = Completer<void>();
  locks
      .request(
        lockName,
        web.LockOptions(ifAvailable: true),
        ((web.Lock? lock) {
          granted.complete(lock != null);
          return lock == null ? null : released.future.toJS;
        }).toJS,
      )
      .toDart
      .ignore();
  if (!await granted.future) {
    throw LocalStoreInUseException(
      databaseName,
      available: _whenReleased(locks, lockName),
    );
  }
  return () {
    if (!released.isCompleted) released.complete();
  };
}

/// Completes once the current holder of [lockName] lets it go.
///
/// The queued request is granted the lock and returns it at once. The request
/// settles only after that release, so the claim that follows never races the
/// waiter itself.
Future<void> _whenReleased(web.LockManager locks, String lockName) =>
    locks.request(lockName, ((web.Lock? _) {}).toJS).toDart.then((_) {});

final class _ReleaseOnClose extends QueryInterceptor {
  _ReleaseOnClose(this._release);

  final void Function() _release;

  @override
  Future<void> close(QueryExecutor inner) async {
    try {
      await inner.close();
    } finally {
      _release();
    }
  }
}
