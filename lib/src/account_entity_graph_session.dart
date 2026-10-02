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

/// The account's local store is owned by another live entity graph, such as
/// the same application open in another browser tab.
///
/// No graph is open. The session opens one automatically as soon as the
/// other owner releases the store, unless a later account transition has
/// superseded this request.
final class AccountEntityGraphStoreInUse<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphStoreInUse(this.accountId);

  @override
  final LocalId<A> accountId;
}

/// Thrown by a local-store opener when another live entity graph already owns
/// the account's store.
///
/// Every runtime that can reach one store grants it to exactly one entity
/// graph at a time. [available] completes when the current owner releases the
/// store; a new claim then has to be made, because another opener may win it.
final class LocalStoreInUseException implements Exception {
  const LocalStoreInUseException(this.storeName, {required this.available});

  final String storeName;
  final Future<void> available;

  @override
  String toString() =>
      'LocalStoreInUseException: $storeName is owned by another live '
      'entity graph.';
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
    } on LocalStoreInUseException catch (inUse) {
      if (generation != _requestGeneration) return;
      _emit(AccountEntityGraphStoreInUse(accountId));
      unawaited(_reopenWhenAvailable(inUse.available, accountId, generation));
      return;
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

  /// Retries a store-in-use open once the other owner releases the store.
  ///
  /// The retry is dropped when a later transition superseded the request, and
  /// a retry failure is published as [AccountEntityGraphFailure] like any other
  /// open failure.
  Future<void> _reopenWhenAvailable(
    Future<void> available,
    LocalId<A> accountId,
    int generation,
  ) async {
    try {
      await available;
    } catch (_) {
      // The claim is attempted again either way; a failed wait cannot strand
      // the session in the store-in-use state.
    }
    if (generation != _requestGeneration || _disposing) return;
    try {
      await _enqueue(() => _transition(accountId, generation));
    } catch (_) {
      // Already published as AccountEntityGraphFailure by _transition.
    }
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
