import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_example/nodus.g.dart';

void main() {
  final accountId = LocalId<Account>('00000000-0000-0000-0000-000000000001');

  test(
    'Given a store owned by another graph, When the session opens the account, '
    'Then it waits without connecting and opens once the store is released',
    () async {
      final store = _OwnedElsewhereStore();
      var connections = 0;
      final session =
          AccountEntityGraphSession<TasksExampleEntityGraph, Account>(
            open: (accountId) => TasksExampleEntityGraph.openWithConnectors(
              accountId: accountId,
              supabase: (context) {
                connections++;
                return InMemorySyncBackend.graph(
                  definition: context.definition,
                );
              },
              localStore: store,
              autoSync: false,
            ),
            close: (entityGraph) => entityGraph.close(),
          );
      addTearDown(session.dispose);

      await session.switchAccount(accountId);
      expect(
        session.state,
        isA<AccountEntityGraphStoreInUse<TasksExampleEntityGraph, Account>>(),
      );
      expect(connections, 0);

      final ready = session.states
          .where(
            (state) =>
                state
                    is AccountEntityGraphReady<
                      TasksExampleEntityGraph,
                      Account
                    >,
          )
          .cast<AccountEntityGraphReady<TasksExampleEntityGraph, Account>>()
          .first;
      store.release();
      final entityGraph = (await ready.timeout(
        const Duration(seconds: 5),
      )).entityGraph;

      final task = await entityGraph.tasks.create(
        title: 'Opened after release',
      );
      expect(
        await entityGraph.tasks.usePresentById(task.id, (task) => task.title),
        'Opened after release',
      );
      expect(connections, 1);
    },
  );

  test('Given a connector that fails, When the graph opens, Then the claimed '
      'store is closed so another graph can claim it', () async {
    final store = _RecordingStore();

    await expectLater(
      TasksExampleEntityGraph.openWithConnectors(
        accountId: accountId,
        supabase: (_) => throw StateError('connector unavailable'),
        localStore: store,
        autoSync: false,
      ),
      throwsStateError,
    );

    expect(store.closed, isTrue);
  });
}

/// Owned by another graph until [release], then opens an in-memory store.
final class _OwnedElsewhereStore implements NodusLocalStore {
  final _released = Completer<void>();

  void release() => _released.complete();

  @override
  Future<QueryExecutor> open({
    required String packageName,
    required String accountId,
  }) async {
    if (!_released.isCompleted) {
      throw LocalStoreInUseException(
        '${packageName}_$accountId',
        available: _released.future,
      );
    }
    return NativeDatabase.memory();
  }
}

final class _RecordingStore implements NodusLocalStore {
  bool closed = false;

  @override
  Future<QueryExecutor> open({
    required String packageName,
    required String accountId,
  }) async => NativeDatabase.memory().interceptWith(_OnClose(this));
}

final class _OnClose extends QueryInterceptor {
  _OnClose(this._store);

  final _RecordingStore _store;

  @override
  Future<void> close(QueryExecutor inner) async {
    await inner.close();
    _store.closed = true;
  }
}
