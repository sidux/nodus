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
/// No graph is open. [AccountEntityGraphSession.takeOverStore] asks the other
/// owner to let the store go. Unless [handedOver], the session also opens one
/// automatically as soon as the other owner releases the store, unless a
/// later account transition has superseded this request.
final class AccountEntityGraphStoreInUse<G, A>
    extends AccountEntityGraphSessionState<G, A> {
  const AccountEntityGraphStoreInUse(
    this.accountId, {
    this.handedOver = false,
    this.releaseRequested = false,
  });

  @override
  final LocalId<A> accountId;

  /// Whether this session asked the other owner to let the store go. An
  /// owner that never answers, such as one running an older build, leaves
  /// it set, so an application can tell the user after a while.
  final bool releaseRequested;

  /// Whether this session closed its own graph because another owner took
  /// the store over. It then reopens only through
  /// [AccountEntityGraphSession.takeOverStore] or a new account transition,
  /// so two owners never hand the store back and forth on their own.
  final bool handedOver;
}

/// Thrown by a local-store opener when another live entity graph already owns
/// the account's store.
///
/// Every runtime that can reach one store grants it to exactly one entity
/// graph at a time. [available] completes when the current owner releases the
/// store; a new claim then has to be made, because another opener may win it.
/// [requestRelease] asks the current owner to close its graph, which it does
/// through the handler its opener read from [LocalStoreReleaseRequests].
final class LocalStoreInUseException implements Exception {
  const LocalStoreInUseException(
    this.storeName, {
    required this.available,
    required this.requestRelease,
  });

  final String storeName;
  final Future<void> available;
  final void Function() requestRelease;

  @override
  String toString() =>
      'LocalStoreInUseException: $storeName is owned by another live '
      'entity graph.';
}

/// Connects a local-store opener to the session that is opening its graph,
/// so another runtime's [LocalStoreInUseException.requestRelease] reaches the
/// store's owner.
///
/// [AccountEntityGraphSession] opens every graph inside [runWith]. An opener
/// that claims a store reads [current] once while claiming and calls it when
/// another runtime asks for the store; the session then closes that graph
/// and publishes [AccountEntityGraphStoreInUse.handedOver].
abstract final class LocalStoreReleaseRequests {
  static final Object _zoneKey = Object();

  /// The handler of the graph being opened in this zone, if any.
  static void Function()? get current =>
      Zone.current[_zoneKey] as void Function()?;

  static Future<R> runWith<R>(
    void Function() onReleaseRequested,
    Future<R> Function() open,
  ) => runZoned(open, zoneValues: {_zoneKey: onReleaseRequested});
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

  /// Identifies the open that produced the current graph, so a release
  /// request from an earlier claim never closes a later graph.
  Object? _currentClaim;
  LocalStoreInUseException? _storeInUse;
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

  /// Opens [accountId]'s entity graph, closing the current one, or signs out
  /// when it is null.
  ///
  /// An account opening from signed out is reported as
  /// [AccountEntityGraphOpening] before this returns, so a caller may show
  /// its app without awaiting the open, which can include local migrations:
  /// readers see the account coming rather than nobody signed in.
  Future<void> switchAccount(LocalId<A>? accountId) {
    if (_disposing || _disposed) {
      throw StateError('The account entity-graph session is disposed.');
    }
    final generation = ++_requestGeneration;
    if (accountId != null && _state is AccountEntityGraphSignedOut<G, A>) {
      _emit(AccountEntityGraphOpening(accountId));
    }
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

  /// Asks the other owner of the current account's store to close its graph,
  /// so this session opens it instead.
  ///
  /// Does nothing unless the state is [AccountEntityGraphStoreInUse], which
  /// it reports with [AccountEntityGraphStoreInUse.releaseRequested] at once.
  /// A session that [AccountEntityGraphStoreInUse.handedOver] its store
  /// claims it again first, which finds the new owner to ask.
  Future<void> takeOverStore() {
    if (_disposing || _disposed) {
      throw StateError('The account entity-graph session is disposed.');
    }
    final current = _state;
    if (current is! AccountEntityGraphStoreInUse<G, A>) return Future.value();
    _emit(
      AccountEntityGraphStoreInUse(current.accountId, releaseRequested: true),
    );
    if (!current.handedOver) {
      _storeInUse?.requestRelease();
      return Future.value();
    }
    final generation = ++_requestGeneration;
    return _enqueue(
      () => _transition(current.accountId, generation, takeOver: true),
    );
  }

  /// Closes the graph another owner asked for, unless a later transition has
  /// already replaced it.
  void _releaseRequested(LocalId<A> accountId, Object claim) {
    if (_disposing || _disposed) return;
    unawaited(
      _enqueue(() async {
        if (_currentClaim != claim) return;
        _emit(AccountEntityGraphStoreInUse(accountId, handedOver: true));
        try {
          await _closeCurrent();
        } catch (error, stackTrace) {
          _emit(
            AccountEntityGraphFailure(
              accountId: accountId,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      }),
    );
  }

  Future<void> _transition(
    LocalId<A>? accountId,
    int generation, {
    bool takeOver = false,
  }) async {
    if (generation != _requestGeneration) return;
    if (_currentEntityGraph != null && _currentAccountId == accountId) return;
    _storeInUse = null;

    if (accountId == null) {
      _emit(const AccountEntityGraphSignedOut());
      await _closeCurrent();
      return;
    }

    // switchAccount may already have reported this open, and a takeover
    // stays reported as a pending request until the store is free.
    if (!takeOver &&
        (_state is! AccountEntityGraphOpening<G, A> ||
            _state.accountId != accountId)) {
      _emit(AccountEntityGraphOpening(accountId));
    }
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
    final claim = Object();
    try {
      opened = await LocalStoreReleaseRequests.runWith(
        () => _releaseRequested(accountId, claim),
        () => _open(accountId),
      );
    } on LocalStoreInUseException catch (inUse) {
      if (generation != _requestGeneration) return;
      _storeInUse = inUse;
      _emit(
        AccountEntityGraphStoreInUse(accountId, releaseRequested: takeOver),
      );
      unawaited(_reopenWhenAvailable(inUse.available, accountId, generation));
      if (takeOver) inUse.requestRelease();
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
    _currentClaim = claim;
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
    _currentClaim = null;
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
