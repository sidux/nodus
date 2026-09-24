part of '../nodus.dart';

typedef OpenAccountEntityGraph<G, A> = Future<G> Function(LocalId<A> accountId);
typedef CloseAccountEntityGraph<G> = Future<void> Function(G entityGraph);

/// Projects the latest values from two independently changing streams.
///
/// The result starts after both sources have emitted, keeps exactly one
/// subscription to each source, forwards errors, and releases both
/// subscriptions when its consumer cancels. This is the small composition
/// primitive needed when one domain projection depends on two generated
/// query snapshots; it does not introduce another state owner.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A first, B second) project,
) => Stream.multi((controller) {
  A? firstValue;
  B? secondValue;
  var hasFirst = false;
  var hasSecond = false;
  var completedSources = 0;

  void emit() {
    if (!hasFirst || !hasSecond) return;
    try {
      controller.addSync(project(firstValue as A, secondValue as B));
    } on Object catch (error, stackTrace) {
      controller.addErrorSync(error, stackTrace);
    }
  }

  void completeSource() {
    completedSources++;
    if (completedSources == 2) controller.closeSync();
  }

  final firstSubscription = first.listen(
    (value) {
      firstValue = value;
      hasFirst = true;
      emit();
    },
    onError: controller.addErrorSync,
    onDone: completeSource,
  );
  final secondSubscription = second.listen(
    (value) {
      secondValue = value;
      hasSecond = true;
      emit();
    },
    onError: controller.addErrorSync,
    onDone: completeSource,
  );
  controller.onCancel = () async {
    await firstSubscription.cancel();
    await secondSubscription.cancel();
  };
});

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
  int _activeLeases = 0;
  Completer<void>? _leasesReleased;
  G? _currentEntityGraph;
  LocalId<A>? _currentAccountId;
  int _requestGeneration = 0;
  ({LocalId<A>? accountId, Future<void> transition})? _pendingSwitch;
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
    // Identity providers repeat the current account (initial session, token
    // refresh); joining the pending request avoids reopening the same graph.
    final pending = _pendingSwitch;
    if (pending != null && pending.accountId == accountId) {
      return pending.transition;
    }
    final generation = ++_requestGeneration;
    final transition = _enqueue(() => _transition(accountId, generation));
    final request = (accountId: accountId, transition: transition);
    _pendingSwitch = request;
    transition.then<void>((_) {}, onError: (_, _) {}).whenComplete(() {
      if (identical(_pendingSwitch, request)) _pendingSwitch = null;
    });
    return transition;
  }

  /// Runs account-scoped work against the ready entity graph.
  ///
  /// Leases run concurrently with each other. A lease requested after an
  /// account switch or sign-out runs after that transition, and a transition
  /// closes the previous graph only once every lease on it has completed, so
  /// [action] never receives a stale or partially opened graph.
  Future<R> withReadyEntityGraph<R>(
    FutureOr<R> Function(LocalId<A> accountId, G entityGraph) action,
  ) async {
    final inherited = Zone.current[_readyZoneKey];
    if (inherited is _ReadyEntityGraphLease<G, A> && inherited.active) {
      return action(inherited.accountId, inherited.entityGraph);
    }
    if (_disposing || _disposed) {
      throw StateError('The account entity-graph session is disposed.');
    }
    await _tail;
    final current = state;
    if (current is! AccountEntityGraphReady<G, A>) {
      throw StateError('The account entity-graph session is not ready.');
    }
    final lease = _ReadyEntityGraphLease<G, A>(
      accountId: current.accountId,
      entityGraph: current.entityGraph,
    );
    _activeLeases++;
    try {
      return await runZoned(
        () => Future.sync(() => action(current.accountId, current.entityGraph)),
        zoneValues: {_readyZoneKey: lease},
      );
    } finally {
      lease.active = false;
      if (--_activeLeases == 0) {
        _leasesReleased?.complete();
        _leasesReleased = null;
      }
    }
  }

  /// Runs account-scoped work when only the ready entity graph is needed.
  ///
  /// This is the graph-only spelling of [withReadyEntityGraph]. It preserves
  /// the same serialized lease, reentrancy, and account-switch guarantees
  /// without forcing callers to declare an unused account identifier.
  Future<R> withReadyGraph<R>(FutureOr<R> Function(G entityGraph) action) =>
      withReadyEntityGraph((_, entityGraph) => action(entityGraph));

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
    if (_activeLeases > 0) {
      await (_leasesReleased ??= Completer<void>()).future;
    }
    final entityGraph = _currentEntityGraph;
    _currentEntityGraph = null;
    _currentAccountId = null;
    if (entityGraph != null) await _close(entityGraph);
  }

  Future<void> _enqueue(Future<void> Function() transition) {
    final task = _tail.then((_) => transition());
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
    _pendingSwitch = null;
    try {
      await _enqueue(_closeCurrent);
    } finally {
      _emit(const AccountEntityGraphSignedOut());
      _disposed = true;
      await _changes.close();
    }
  }
}
