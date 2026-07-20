part of '../nodus.dart';

typedef OpenAccountEntityGraph<G, A> = Future<G> Function(LocalId<A> accountId);
typedef CloseAccountEntityGraph<G> = Future<void> Function(G entityGraph);

sealed class AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphSessionState();

  LocalId<A>? get accountId;
}

final class AccountEntityGraphSignedOut<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphSignedOut();

  @override
  LocalId<A>? get accountId => null;
}

final class AccountEntityGraphOpening<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphOpening(this.accountId);

  @override
  final LocalId<A> accountId;
}

final class AccountEntityGraphReady<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphReady({
    required this.accountId,
    required this.entityGraph,
  });

  @override
  final LocalId<A> accountId;
  final G entityGraph;
}

final class AccountEntityGraphFailure<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphFailure({
    required this.accountId,
    required this.error,
    required this.stackTrace,
  });

  @override
  final LocalId<A> accountId;
  final Object error;
  final StackTrace stackTrace;
}

final class _ReadyEntityGraphLease<G, A> {
  _ReadyEntityGraphLease({required this.accountId, required this.entityGraph});

  final LocalId<A> accountId;
  final G entityGraph;
  bool active = true;
}

/// Serializes account-scoped entity-graph ownership across auth transitions.
///
/// An entity graph opened for a superseded account is closed before a newer
/// request is processed and is never published as [AccountEntityGraphReady].
/// Callers therefore have one visible graph, one owner, and one close path.
final class AccountEntityGraphSession<G, A> {
  AccountEntityGraphSession({
    required OpenAccountEntityGraph<G, A> open,
    required CloseAccountEntityGraph<G> close,
  }) : _open = open,
       _close = close;

  final OpenAccountEntityGraph<G, A> _open;
  final CloseAccountEntityGraph<G> _close;
  final Object _readyZoneKey = Object();
  final StreamController<AccountEntityGraphSessionState<G, A>> _changes =
      StreamController.broadcast(sync: true);

  AccountEntityGraphSessionState<G, A> _state =
      const AccountEntityGraphSignedOut();
  Future<void> _tail = Future.value();
  G? _currentEntityGraph;
  LocalId<A>? _currentAccountId;
  int _requestGeneration = 0;
  bool _disposing = false;
  bool _disposed = false;

  AccountEntityGraphSessionState<G, A> get state => _state;

  Stream<AccountEntityGraphSessionState<G, A>> get changes => _changes.stream;

  /// Emits the current state and then every transition without a subscription
  /// gap between the snapshot and live changes.
  Stream<AccountEntityGraphSessionState<G, A>> get states =>
      Stream.multi((controller) {
        final subscription = changes.listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        );
        controller.addSync(state);
        controller.onCancel = subscription.cancel;
      });

  /// Replaces the active derived stream whenever the account-graph state
  /// changes and cancels the previous stream before binding the next one.
  ///
  /// This is the account-scoped equivalent of `switchMap`: feature adapters
  /// describe how each exhaustive session state maps to a stream while the
  /// session owns auth-race cancellation and stale-emission suppression.
  Stream<R> switchMapState<R>(
    Stream<R> Function(AccountEntityGraphSessionState<G, A> state) connect,
  ) => Stream.multi((controller) {
    StreamSubscription<R>? activeSubscription;
    var generation = 0;
    var listening = true;

    Future<void> bind(AccountEntityGraphSessionState<G, A> next) async {
      final request = ++generation;
      final previous = activeSubscription;
      activeSubscription = null;
      await previous?.cancel();
      if (!listening || request != generation) return;

      try {
        final subscription = connect(next).listen(
          (value) {
            if (listening && request == generation) {
              controller.addSync(value);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (listening && request == generation) {
              controller.addErrorSync(error, stackTrace);
            }
          },
        );
        if (!listening || request != generation) {
          await subscription.cancel();
          return;
        }
        activeSubscription = subscription;
      } catch (error, stackTrace) {
        if (listening && request == generation) {
          controller.addErrorSync(error, stackTrace);
        }
      }
    }

    final stateSubscription = states.listen(
      (next) => unawaited(bind(next)),
      onError: controller.addErrorSync,
      onDone: () {
        listening = false;
        generation++;
        final close = activeSubscription?.cancel() ?? Future<void>.value();
        unawaited(close.whenComplete(controller.closeSync));
      },
    );
    controller.onCancel = () async {
      listening = false;
      generation++;
      await stateSubscription.cancel();
      await activeSubscription?.cancel();
    };
  });

  Future<void> switchAccount(LocalId<A>? accountId) {
    if (_disposing || _disposed) {
      throw StateError('The account entity-graph session is disposed.');
    }
    final generation = ++_requestGeneration;
    return _enqueue(() => _transition(accountId, generation));
  }

  /// Runs account-scoped work in the same serial queue as auth transitions.
  ///
  /// A later sign-out or account switch cannot close `entityGraph` until [action]
  /// completes. The action never receives a stale or partially opened graph.
  Future<R> withReadyEntityGraph<R>(
    FutureOr<R> Function(LocalId<A> accountId, G entityGraph) action,
  ) {
    final inherited = Zone.current[_readyZoneKey];
    if (inherited is _ReadyEntityGraphLease<G, A> && inherited.active) {
      return Future.sync(
        () => action(inherited.accountId, inherited.entityGraph),
      );
    }
    if (_disposing || _disposed) {
      throw StateError('The account entity-graph session is disposed.');
    }
    return _enqueueValue(() async {
      final current = state;
      if (current is! AccountEntityGraphReady<G, A>) {
        throw StateError('The account entity-graph session is not ready.');
      }
      final lease = _ReadyEntityGraphLease<G, A>(
        accountId: current.accountId,
        entityGraph: current.entityGraph,
      );
      try {
        return await runZoned(
          () =>
              Future.sync(() => action(current.accountId, current.entityGraph)),
          zoneValues: {_readyZoneKey: lease},
        );
      } finally {
        lease.active = false;
      }
    });
  }

  Future<void> _transition(LocalId<A>? accountId, int generation) async {
    if (generation != _requestGeneration) return;
    if (_currentEntityGraph != null && _currentAccountId == accountId) return;

    if (accountId == null) {
      _emit(const AccountEntityGraphSignedOut());
      await _closeCurrent();
      return;
    }

    _emit(AccountEntityGraphOpening(accountId));
    try {
      await _closeCurrent();
    } catch (error, stackTrace) {
      if (generation == _requestGeneration) {
        _emit(
          AccountEntityGraphFailure(
            accountId: accountId,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      rethrow;
    }
    if (generation != _requestGeneration) return;
    late final G opened;
    try {
      opened = await _open(accountId);
    } catch (error, stackTrace) {
      if (generation == _requestGeneration) {
        _emit(
          AccountEntityGraphFailure(
            accountId: accountId,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      rethrow;
    }

    if (generation != _requestGeneration || _disposing) {
      await _close(opened);
      return;
    }
    _currentEntityGraph = opened;
    _currentAccountId = accountId;
    _emit(AccountEntityGraphReady(accountId: accountId, entityGraph: opened));
  }

  Future<void> _closeCurrent() async {
    final entityGraph = _currentEntityGraph;
    _currentEntityGraph = null;
    _currentAccountId = null;
    if (entityGraph != null) await _close(entityGraph);
  }

  Future<void> _enqueue(Future<void> Function() transition) {
    return _enqueueValue(transition);
  }

  Future<R> _enqueueValue<R>(FutureOr<R> Function() operation) {
    final task = _tail.then((_) => operation());
    _tail = task.then<void>((_) {}, onError: (_, _) {});
    return task;
  }

  void _emit(AccountEntityGraphSessionState<G, A> next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (_disposing) {
      await _tail;
      return;
    }
    _disposing = true;
    _requestGeneration++;
    await _enqueue(_closeCurrent);
    _emit(const AccountEntityGraphSignedOut());
    _disposed = true;
    await _changes.close();
  }
}
