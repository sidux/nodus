import 'dart:async';

import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

void main() {
  test('states replays the snapshot before later transitions', () async {
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) async {},
    );
    addTearDown(session.dispose);

    await session.switchAccount(_accountId);
    final states = session.states.take(2).toList();
    await session.switchAccount(null);

    expect(await states, [
      isA<AccountEntityGraphReady<_TestEntityGraph, _TestAccount>>().having(
        (state) => state.accountId,
        'accountId',
        _accountId,
      ),
      isA<AccountEntityGraphSignedOut<_TestEntityGraph, _TestAccount>>(),
    ]);
  });

  test('a superseded open is closed and never becomes ready', () async {
    final firstOpen = Completer<_TestEntityGraph>();
    final opened = <String>[];
    final closed = <String>[];
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async {
        opened.add(accountId.value);
        if (accountId == _firstId) return firstOpen.future;
        return _TestEntityGraph(accountId);
      },
      close: (entityGraph) async => closed.add(entityGraph.accountId.value),
    );
    addTearDown(session.dispose);

    final first = session.switchAccount(_firstId);
    await Future<void>.delayed(Duration.zero);
    final second = session.switchAccount(_secondId);
    firstOpen.complete(_TestEntityGraph(_firstId));
    await Future.wait([first, second]);

    expect(opened, [_firstId.value, _secondId.value]);
    expect(closed, [_firstId.value]);
    expect(
      session.state,
      isA<AccountEntityGraphReady<_TestEntityGraph, _TestAccount>>().having(
        (state) => state.accountId,
        'accountId',
        _secondId,
      ),
    );
  });

  test('sign out closes the current entity graph exactly once', () async {
    final closed = <String>[];
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (entityGraph) async => closed.add(entityGraph.accountId.value),
    );
    addTearDown(session.dispose);

    await session.switchAccount(_accountId);
    await session.switchAccount(null);
    await session.switchAccount(null);

    expect(closed, [_accountId.value]);
    expect(
      session.state,
      isA<AccountEntityGraphSignedOut<_TestEntityGraph, _TestAccount>>(),
    );
  });

  test('a closing entity graph is no longer exposed as ready', () async {
    final close = Completer<void>();
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) => close.future,
    );
    addTearDown(() async {
      if (!close.isCompleted) close.complete();
      await session.dispose();
    });
    await session.switchAccount(_firstId);

    final switching = session.switchAccount(_secondId);
    await Future<void>.delayed(Duration.zero);

    expect(
      session.state,
      isA<AccountEntityGraphOpening<_TestEntityGraph, _TestAccount>>().having(
        (state) => state.accountId,
        'accountId',
        _secondId,
      ),
    );
    close.complete();
    await switching;
  });

  test('an open failure is observable and returned to the caller', () async {
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (_) async => throw StateError('open failed'),
      close: (_) async {},
    );
    addTearDown(session.dispose);

    await expectLater(session.switchAccount(_accountId), throwsStateError);

    expect(
      session.state,
      isA<AccountEntityGraphFailure<_TestEntityGraph, _TestAccount>>()
          .having((state) => state.accountId, 'accountId', _accountId)
          .having((state) => state.error, 'error', isA<StateError>()),
    );
  });

  test('ready work delays a later account close until it completes', () async {
    final action = Completer<void>();
    final events = <String>[];
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (entityGraph) async =>
          events.add('close:${entityGraph.accountId.value}'),
    );
    addTearDown(session.dispose);
    await session.switchAccount(_firstId);

    final use = session.withReadyEntityGraph((accountId, entityGraph) async {
      events.add('use:${accountId.value}');
      expect(entityGraph.accountId, accountId);
      await action.future;
      events.add('used:${accountId.value}');
    });
    final signOut = session.switchAccount(null);
    await Future<void>.delayed(Duration.zero);

    expect(events, ['use:${_firstId.value}']);
    action.complete();
    await Future.wait([use, signOut]);
    expect(events, [
      'use:${_firstId.value}',
      'used:${_firstId.value}',
      'close:${_firstId.value}',
    ]);
  });

  test('ready work can reenter the same session without deadlocking', () async {
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) async {},
    );
    addTearDown(session.dispose);
    await session.switchAccount(_firstId);

    final nestedAccountId = await session
        .withReadyEntityGraph((outerId, outerGraph) {
          return session.withReadyEntityGraph((innerId, innerGraph) {
            expect(innerId, outerId);
            expect(innerGraph, same(outerGraph));
            return innerId;
          });
        })
        .timeout(const Duration(seconds: 1));

    expect(nestedAccountId, _firstId);
  });

  test('ready work rejects signed-out sessions', () async {
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) async {},
    );
    addTearDown(session.dispose);

    await expectLater(
      session.withReadyEntityGraph((_, _) {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'The account entity-graph session is not ready.',
        ),
      ),
    );
  });

  test('switchMapState cancels stale account streams', () async {
    final cancelled = <String>[];
    final controllers = <String, StreamController<String>>{};
    addTearDown(() async {
      for (final controller in controllers.values) {
        await controller.close();
      }
    });
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) async {},
    );
    addTearDown(session.dispose);

    final values = <String>[];
    final subscription = session
        .switchMapState((state) {
          final accountId = state.accountId?.value ?? 'signed-out';
          final controller = StreamController<String>(
            sync: true,
            onCancel: () => cancelled.add(accountId),
          );
          controllers[accountId] = controller;
          return controller.stream;
        })
        .listen(values.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(Duration.zero);
    controllers['signed-out']!.add('none');
    await session.switchAccount(_firstId);
    await Future<void>.delayed(Duration.zero);
    controllers[_firstId.value]!.add('one');
    await session.switchAccount(_secondId);
    await Future<void>.delayed(Duration.zero);
    controllers[_firstId.value]!.add('stale');
    controllers[_secondId.value]!.add('two');

    expect(values, ['none', 'one', 'two']);
    expect(cancelled, containsAllInOrder(['signed-out', _firstId.value]));
  });

  test('switchMapState forwards a synchronous initial derived value', () async {
    final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
      open: (accountId) async => _TestEntityGraph(accountId),
      close: (_) async {},
    );
    addTearDown(session.dispose);
    await session.switchAccount(_firstId);

    final value = await session
        .switchMapState(
          (state) => Stream<String>.value(state.accountId?.value ?? 'none'),
        )
        .first;

    expect(value, _firstId.value);
  });
}

final _accountId = parseLocalId<_TestAccount>(
  'a0000000-0000-7000-8000-000000000001',
);
final _firstId = parseLocalId<_TestAccount>(
  'a0000000-0000-7000-8000-000000000002',
);
final _secondId = parseLocalId<_TestAccount>(
  'a0000000-0000-7000-8000-000000000003',
);

final class _TestAccount {}

final class _TestEntityGraph {
  const _TestEntityGraph(this.accountId);

  final LocalId<_TestAccount> accountId;
}
