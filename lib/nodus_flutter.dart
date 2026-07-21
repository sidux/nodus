/// Flutter lifecycle, Hook bindings, local storage, and typed file routing for
/// generated Nodus entity graphs.
library;

export 'nodus.dart';

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:nodus/nodus.dart';
import 'package:mobx/mobx.dart' hide Listenable;

import 'src/flutter_local_store_stub.dart'
    if (dart.library.io) 'src/flutter_local_store_io.dart'
    as local_store;

part 'src/file_routes.dart';

/// Opens the durable local database used by a generated account graph.
abstract interface class NodusLocalStore {
  Future<QueryExecutor> open({
    required String packageName,
    required String accountId,
  });
}

/// Default Flutter storage: one background SQLite database per account.
final class ApplicationSupportNodusLocalStore implements NodusLocalStore {
  const ApplicationSupportNodusLocalStore();

  @override
  Future<QueryExecutor> open({
    required String packageName,
    required String accountId,
  }) => local_store.openApplicationSupportNodusStore(
    packageName: packageName,
    accountId: accountId,
  );
}

/// Platform-selected ephemeral executor used by generated demos and tests.
QueryExecutor openNodusInMemoryExecutor() =>
    local_store.openNodusInMemoryExecutor();

/// Publishes only account-entity-graph lifecycle transitions to a subtree.
///
/// Entity and query changes remain direct MobX observations and never rebuild
/// this scope. Applications place one scope above their router, then pages read
/// the ready generated entity graph without a provider or service locator.
final class AccountEntityGraphScope<G, A> extends StatefulWidget {
  const AccountEntityGraphScope({
    required this.session,
    required this.child,
    super.key,
  });

  final AccountEntityGraphSession<G, A> session;
  final Widget child;

  static AccountEntityGraphSessionState<G, A> stateOf<G, A>(
    BuildContext context,
  ) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<
          _AccountEntityGraphInherited<G, A>
        >();
    if (scope == null) {
      throw StateError(
        'No AccountEntityGraphScope<$G, $A> exists above this context.',
      );
    }
    return scope.state;
  }

  /// Reads the account session for an imperative callback without subscribing
  /// the caller to lifecycle transitions.
  ///
  /// Use [stateOf] while rendering lifecycle UI. Commands use this accessor and
  /// [AccountEntityGraphSession.withReadyEntityGraph] so an account switch
  /// cannot close the generated entity graph during the command.
  static AccountEntityGraphSession<G, A> sessionOf<G, A>(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<_AccountEntityGraphInherited<G, A>>();
    if (scope == null) {
      throw StateError(
        'No AccountEntityGraphScope<$G, $A> exists above this context.',
      );
    }
    return scope.session;
  }

  static AccountEntityGraphReady<G, A>? maybeReadyOf<G, A>(
    BuildContext context,
  ) {
    final state = context
        .dependOnInheritedWidgetOfExactType<
          _AccountEntityGraphInherited<G, A>
        >()
        ?.state;
    return state is AccountEntityGraphReady<G, A> ? state : null;
  }

  @override
  State<AccountEntityGraphScope<G, A>> createState() =>
      _AccountEntityGraphScopeState<G, A>();
}

final class _AccountEntityGraphScopeState<G, A>
    extends State<AccountEntityGraphScope<G, A>> {
  late AccountEntityGraphSessionState<G, A> _state;
  StreamSubscription<AccountEntityGraphSessionState<G, A>>? _subscription;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(AccountEntityGraphScope<G, A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _bind();
  }

  void _bind() {
    _subscription?.cancel();
    _state = widget.session.state;
    _subscription = widget.session.changes.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AccountEntityGraphInherited<G, A>(
    session: widget.session,
    state: _state,
    child: widget.child,
  );
}

final class _AccountEntityGraphInherited<G, A> extends InheritedWidget {
  const _AccountEntityGraphInherited({
    required this.session,
    required this.state,
    required super.child,
  });

  final AccountEntityGraphSession<G, A> session;
  final AccountEntityGraphSessionState<G, A> state;

  @override
  bool updateShouldNotify(_AccountEntityGraphInherited<G, A> oldWidget) =>
      !identical(session, oldWidget.session) ||
      !identical(state, oldWidget.state);
}

/// Acquires one value-cached query lease and releases it with the widget.
///
/// Put every value that changes the query specification in [keys]. Entity
/// fields and predicates are generated/value-based, so feature widgets only
/// declare business selection criteria. Set [loadAllPages] only for a bounded
/// selector or other UI that requires the complete result; failures remain in
/// typed query state until a refresh or invalidation.
LocalEntityQuery<E> useEntityQuery<E>(
  LocalEntityQuery<E> Function() acquire, {
  List<Object?> keys = const [],
  bool loadAllPages = false,
}) {
  final query = useMemoized(acquire, keys);
  useEffect(() => query.dispose, [query]);
  _useCompleteEntityQuery(query, loadAllPages: loadAllPages);
  return query;
}

/// Acquires one generated domain-named list and releases it with the widget.
///
/// Use this with generated constructors such as `TaskList.forOwner(...)` or
/// inverse accessors such as `goal.tasks(entityGraph)`. It has the same paging
/// and exhaustive-loading semantics as [useEntityQuery] without exposing generic
/// predicate construction at ordinary feature call sites.
L useEntityList<E, L extends EntityList<E>>(
  L Function() acquire, {
  List<Object?> keys = const [],
  bool loadAllPages = false,
}) {
  final list = useMemoized(acquire, keys);
  useEffect(() => list.dispose, [list]);
  _useCompleteEntityQuery(list.query, loadAllPages: loadAllPages);
  return list;
}

/// Acquires one generated exact unique-index lookup and releases it with the
/// widget. The selected entity remains one stable MobX identity for the whole
/// widget lifetime; no provider or detached view-model copy is introduced.
L useEntityLookup<E, L extends EntityLookup<E>>(
  L Function() acquire, {
  List<Object?> keys = const [],
}) {
  final lookup = useMemoized(acquire, keys);
  useEffect(() => lookup.dispose, [lookup]);
  _useCompleteEntityQuery(lookup.query, loadAllPages: false);
  return lookup;
}

/// Acquires one generated existence selection and releases it with the widget.
EntityExistence<E> useEntityExistence<E>(
  EntityExistence<E> Function() acquire, {
  List<Object?> keys = const [],
}) {
  final existence = useMemoized(acquire, keys);
  useEffect(() => existence.dispose, [existence]);
  _useCompleteEntityQuery(existence.query, loadAllPages: false);
  return existence;
}

/// Acquires one generated ordered-first selection and releases it with the
/// widget.
EntityFirst<E> useEntityFirst<E>(
  EntityFirst<E> Function() acquire, {
  List<Object?> keys = const [],
}) {
  final first = useMemoized(acquire, keys);
  useEffect(() => first.dispose, [first]);
  _useCompleteEntityQuery(first.query, loadAllPages: false);
  return first;
}

/// A query lease and its current state observed by a Flutter Hook.
///
/// This removes the otherwise repetitive `Observer` wrapper while preserving
/// the query's MobX state as the only source of truth.
final class ObservedEntityQuery<E> {
  const ObservedEntityQuery(this.query, this.state);

  final LocalEntityQuery<E> query;
  final EntityQueryState<E> state;

  Future<void> refresh() => query.refresh();

  Future<void> loadNextPage() => query.loadNextPage();

  Widget when({
    required Widget Function() loading,
    required Widget Function() empty,
    required Widget Function(
      List<E> items, {
      required bool hasMore,
      required bool refreshing,
      Object? refreshError,
    })
    data,
    required Widget Function(Object error, Future<void> Function() retry)
    failure,
    Widget Function()? disposed,
  }) => switch (state) {
    EntityQueryInitialLoading<E>() => loading(),
    EntityQueryEmpty<E>() => empty(),
    EntityQueryData<E>(:final items, :final hasMore) => data(
      items,
      hasMore: hasMore,
      refreshing: false,
    ),
    EntityQueryStaleData<E>(:final items, :final hasMore) => data(
      items,
      hasMore: hasMore,
      refreshing: true,
    ),
    EntityQueryFailure<E>(:final error, :final items, :final hasMore) =>
      items.isEmpty
          ? failure(error, query.refresh)
          : data(
              items,
              hasMore: hasMore,
              refreshing: false,
              refreshError: error,
            ),
    EntityQueryDisposed<E>() => disposed?.call() ?? const SizedBox.shrink(),
  };
}

ObservedEntityQuery<E> useObservedEntityQuery<E>(
  LocalEntityQuery<E> Function() acquire, {
  List<Object?> keys = const [],
  bool loadAllPages = false,
}) {
  final query = useEntityQuery(acquire, keys: keys, loadAllPages: loadAllPages);
  return _useObservedEntityQuery(query);
}

ObservedEntityQuery<E> useObservedEntityList<E>(
  EntityList<E> Function() acquire, {
  List<Object?> keys = const [],
  bool loadAllPages = false,
}) {
  final list = useEntityList<E, EntityList<E>>(
    acquire,
    keys: keys,
    loadAllPages: loadAllPages,
  );
  return _useObservedEntityQuery(list.query);
}

/// A lease-owning exact lookup and its current state observed by a Flutter Hook.
///
/// Unlike [ObservedEntityQuery], the data branch exposes exactly one entity and
/// does not leak list or pagination mechanics into a zero-or-one selection.
final class ObservedEntityLookup<E extends Object> {
  const ObservedEntityLookup(this.lookup, this.state);

  final EntityLookup<E> lookup;
  final EntityQueryState<E> state;

  E? get value => lookup.value;

  Future<void> refresh() => lookup.query.refresh();

  Widget when({
    required Widget Function() loading,
    required Widget Function() empty,
    required Widget Function(
      E entity, {
      required bool refreshing,
      Object? refreshError,
    })
    data,
    required Widget Function(Object error, Future<void> Function() retry)
    failure,
    Widget Function()? disposed,
  }) => switch (state) {
    EntityQueryInitialLoading<E>() => loading(),
    EntityQueryEmpty<E>() => empty(),
    EntityQueryData<E>() => data(value!, refreshing: false),
    EntityQueryStaleData<E>() => data(value!, refreshing: true),
    EntityQueryFailure<E>(:final error, :final items) =>
      items.isEmpty
          ? failure(error, lookup.query.refresh)
          : data(value!, refreshing: false, refreshError: error),
    EntityQueryDisposed<E>() => disposed?.call() ?? const SizedBox.shrink(),
  };
}

/// An observed yes/no existence selection without leaking list mechanics.
final class ObservedEntityExistence<E> {
  const ObservedEntityExistence(this.existence, this.state);

  final EntityExistence<E> existence;
  final EntityQueryState<E> state;

  bool get value => existence.value;
  bool get loading => state is EntityQueryInitialLoading<E>;
  Object? get error => switch (state) {
    EntityQueryFailure<E>(:final error) => error,
    _ => null,
  };

  Future<void> refresh() => existence.query.refresh();
}

/// Acquires and observes an existence query for the widget lifetime.
ObservedEntityExistence<E> useObservedEntityExistence<E>(
  EntityExistence<E> Function() acquire, {
  List<Object?> keys = const [],
}) {
  final existence = useEntityExistence(acquire, keys: keys);
  final observed = _useObservedEntityQuery(existence.query);
  return ObservedEntityExistence(existence, observed.state);
}

/// An observed deterministic first entity without a uniqueness claim.
final class ObservedEntityFirst<E> {
  const ObservedEntityFirst(this.first, this.state);

  final EntityFirst<E> first;
  final EntityQueryState<E> state;

  E? get value => first.value;
  bool get loading => state is EntityQueryInitialLoading<E>;
  Object? get error => switch (state) {
    EntityQueryFailure<E>(:final error) => error,
    _ => null,
  };

  Future<void> refresh() => first.query.refresh();
}

/// Acquires and observes an explicitly ordered first-row query.
ObservedEntityFirst<E> useObservedEntityFirst<E>(
  EntityFirst<E> Function() acquire, {
  List<Object?> keys = const [],
}) {
  final first = useEntityFirst(acquire, keys: keys);
  final observed = _useObservedEntityQuery(first.query);
  return ObservedEntityFirst(first, observed.state);
}

/// Acquires and observes one exact zero-or-one lookup for the widget lifetime.
ObservedEntityLookup<E> useObservedEntityLookup<E extends Object>(
  EntityLookup<E> Function() acquire, {
  List<Object?> keys = const [],
}) {
  final lookup = useEntityLookup<E, EntityLookup<E>>(acquire, keys: keys);
  final observed = _useObservedEntityQuery(lookup.query);
  return ObservedEntityLookup(lookup, observed.state);
}

/// Observes one synchronous generated bounded-set lookup.
///
/// The generated computed index remains the only state owner. This hook owns
/// only the MobX reaction that rebuilds its widget when exact membership or the
/// selected stable identity changes.
E? useObservedEntityValue<E extends Object>(
  E? Function() read, {
  List<Object?> keys = const [],
}) {
  final currentRead = useMemoized(() => read, keys);
  final rebuild = useState(0);
  useEffect(() {
    var initial = true;
    final disposeReaction = autorun((_) {
      currentRead();
      if (initial) {
        initial = false;
      } else {
        rebuild.value++;
      }
    });
    return disposeReaction.call;
  }, [currentRead]);
  rebuild.value;
  return currentRead();
}

ObservedEntityQuery<E> _useObservedEntityQuery<E>(LocalEntityQuery<E> query) {
  final rebuild = useState(0);
  useEffect(() {
    var initial = true;
    final disposeReaction = autorun((_) {
      query.state.value;
      if (initial) {
        initial = false;
      } else {
        rebuild.value++;
      }
    });
    return disposeReaction.call;
  }, [query]);
  rebuild.value;
  return ObservedEntityQuery(query, query.state.value);
}

/// Owns one generated draft for exactly the lifetime of the Hook widget.
D useEntityMutationDraft<E, D extends EntityMutationDraft<E>>(
  D Function() create, {
  List<Object?> keys = const [],
}) {
  final draft = useMemoized(create, keys);
  useEffect(
    () => () {
      if (!draft.isConsumed) draft.discard();
    },
    [draft],
  );
  return draft;
}

/// A text controller that writes directly into one generated draft field.
TextEditingController useEntityDraftTextField(
  EntityDraftField<String> field, {
  String Function(String value)? normalize,
}) {
  final controller = useTextEditingController(text: field.valueOrNull ?? '');
  useEffect(() {
    void updateDraft() {
      field.value = normalize?.call(controller.text) ?? controller.text;
    }

    controller.addListener(updateDraft);
    updateDraft();
    return () => controller.removeListener(updateDraft);
  }, [controller, field, normalize]);
  return controller;
}

TextEditingController useEntityDraftNullableTextField(
  EntityDraftField<String?> field, {
  String? Function(String value)? normalize,
}) {
  final controller = useTextEditingController(text: field.valueOrNull ?? '');
  useEffect(() {
    void updateDraft() {
      field.value = normalize?.call(controller.text) ?? controller.text;
    }

    controller.addListener(updateDraft);
    updateDraft();
    return () => controller.removeListener(updateDraft);
  }, [controller, field, normalize]);
  return controller;
}

/// Hook-owned binding for non-text draft values such as enums and dates.
final class EntityDraftValueBinding<T> {
  const EntityDraftValueBinding({required this.value, required this.set});

  final T value;
  final ValueChanged<T> set;
}

EntityDraftValueBinding<T> useEntityDraftValue<T>(EntityDraftField<T> field) {
  final state = useState(field.value);
  return EntityDraftValueBinding(
    value: state.value,
    set: (value) {
      field.value = value;
      state.value = value;
    },
  );
}

/// Hook-owned busy/error state for entity actions.
final class EntityActionBinding {
  const EntityActionBinding._({
    required this.isRunning,
    required this.error,
    required Future<void> Function(Future<void> Function()) run,
    required VoidCallback clearError,
  }) : _run = run,
       _clearError = clearError;

  final bool isRunning;
  final Object? error;
  final Future<void> Function(Future<void> Function()) _run;
  final VoidCallback _clearError;

  Future<void> run(Future<void> Function() action) => _run(action);

  void clearError() => _clearError();
}

EntityActionBinding useEntityAction({ValueChanged<Object>? onError}) {
  final running = useState(false);
  final error = useState<Object?>(null);
  final errorHandler = useRef(onError)..value = onError;

  Future<void> run(Future<void> Function() action) async {
    if (running.value) return;
    running.value = true;
    error.value = null;
    try {
      await action();
    } on Object catch (caught) {
      error.value = caught;
      errorHandler.value?.call(caught);
    } finally {
      running.value = false;
    }
  }

  return EntityActionBinding._(
    isRunning: running.value,
    error: error.value,
    run: run,
    clearError: () => error.value = null,
  );
}

void _useCompleteEntityQuery<E>(
  LocalEntityQuery<E> query, {
  required bool loadAllPages,
}) {
  useEffect(() {
    if (!loadAllPages) return null;
    var disposed = false;
    var loading = false;

    Future<void> loadRemainingPages() async {
      if (disposed || loading || !query.hasMore) return;
      loading = true;
      try {
        await query.loadAll();
      } on Object {
        // The query publishes its typed failure state for the widget.
      } finally {
        loading = false;
      }
    }

    final disposeReaction = autorun((_) {
      final state = query.state.value;
      if (state.hasMore) {
        // Let the controller finish publishing and tracking its active page
        // before exhaustive loading observes it.
        unawaited(Future<void>.microtask(loadRemainingPages));
      }
    });
    return () {
      disposed = true;
      disposeReaction();
    };
  }, [query, loadAllPages]);
}

/// Loads the next query page shortly before a scroll view reaches its end.
ScrollController useEntityQueryScrollController<E>(
  LocalEntityQuery<E> query, {
  double preloadExtent = 320,
}) {
  final controller = useScrollController();
  useEffect(() {
    void loadNextPage() {
      if (!controller.hasClients || !query.hasMore) return;
      if (controller.position.extentAfter <= preloadExtent) {
        unawaited(query.loadNextPage());
      }
    }

    controller.addListener(loadNextPage);
    return () => controller.removeListener(loadNextPage);
  }, [controller, query, preloadExtent]);
  return controller;
}

/// Loads the next page of a generated domain-named list near the scroll end.
ScrollController useEntityListScrollController<E>(
  EntityList<E> list, {
  double preloadExtent = 320,
}) => useEntityQueryScrollController(list.query, preloadExtent: preloadExtent);
