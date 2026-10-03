@Tags(['flutter'])
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_flutter.dart';
import 'package:mobx/mobx.dart';

void main() {
  test('observed query groups fold lifecycle without copying typed items', () {
    final source = ObservableList<int>.of([1]);
    final cache = LocalEntityQueryCache<int>(
      source: ReadOnlyObservableList(source),
    );
    addTearDown(cache.dispose);
    final first = cache.acquire(EntityQuerySpec<int>());
    final second = cache.acquire(EntityQuerySpec<int>());
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final loading = ObservedEntityQueryGroup([
      ObservedEntityQuery(first, const EntityQueryInitialLoading<int>()),
      ObservedEntityQuery(
        second,
        const EntityQueryData<int>(items: [1], hasMore: false),
      ),
    ]);
    expect(loading.isInitialLoading, isTrue);
    expect(loading.failure, isNull);

    final error = StateError('query failed');
    final failed = ObservedEntityQueryGroup([
      ObservedEntityQuery(
        first,
        EntityQueryFailure<int>(error: error, items: const [], hasMore: false),
      ),
      ObservedEntityQuery(
        second,
        const EntityQueryData<int>(items: [1], hasMore: false),
      ),
    ]);
    expect(failed.failure, same(error));
  });

  testWidgets(
    'Given a generated list hook, When its widget unmounts, Then its lease is disposed',
    (tester) async {
      final source = ObservableList<int>.of([1]);
      final cache = LocalEntityQueryCache<int>(
        source: ReadOnlyObservableList(source),
      );
      addTearDown(cache.dispose);
      _IntList? captured;

      await tester.pumpWidget(
        HookBuilder(
          builder: (_) {
            captured = useEntityList(
              () => _IntList(cache.acquire(EntityQuerySpec<int>())),
            );
            return const SizedBox();
          },
        ),
      );

      expect(captured!.items, [1]);

      await tester.pumpWidget(const SizedBox());

      expect(captured!.state.value, isA<EntityQueryDisposed<int>>());
    },
  );

  testWidgets(
    'Given a query hook, When its widget unmounts, Then its lease is disposed',
    (tester) async {
      final source = ObservableList<int>.of([1]);
      final cache = LocalEntityQueryCache<int>(
        source: ReadOnlyObservableList(source),
      );
      addTearDown(cache.dispose);
      LocalEntityQuery<int>? captured;

      await tester.pumpWidget(
        HookBuilder(
          builder: (_) {
            captured = useEntityQuery(
              () => cache.acquire(EntityQuerySpec<int>()),
            );
            return const SizedBox();
          },
        ),
      );

      expect(captured!.items, [1]);

      await tester.pumpWidget(const SizedBox());

      expect(captured!.state.value, isA<EntityQueryDisposed<int>>());
    },
  );

  testWidgets(
    'Given an exact lookup hook, When its widget unmounts, Then its lease is disposed',
    (tester) async {
      final source = ObservableList<int>.of([1]);
      final cache = LocalEntityQueryCache<int>(
        source: ReadOnlyObservableList(source),
      );
      addTearDown(cache.dispose);
      _IntLookup? captured;

      await tester.pumpWidget(
        HookBuilder(
          builder: (_) {
            captured = useEntityLookup(
              () =>
                  _IntLookup(cache.acquire(EntityQuerySpec<int>(pageSize: 1))),
            );
            return const SizedBox();
          },
        ),
      );

      expect(captured!.value, 1);

      await tester.pumpWidget(const SizedBox());

      expect(captured!.state.value, isA<EntityQueryDisposed<int>>());
    },
  );

  testWidgets('observed lookup exposes one entity without list mechanics', (
    tester,
  ) async {
    final source = ObservableList<int>.of([1]);
    final cache = LocalEntityQueryCache<int>(
      source: ReadOnlyObservableList(source),
    );
    addTearDown(cache.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HookBuilder(
          builder: (_) {
            final observed = useObservedEntityLookup(
              () =>
                  _IntLookup(cache.acquire(EntityQuerySpec<int>(pageSize: 1))),
            );
            return observed.when(
              loading: () => const Text('loading'),
              empty: () => const Text('empty'),
              failure: (error, retry) => Text('failure: $error'),
              data: (value, {required refreshing, refreshError}) =>
                  Text('value: $value'),
            );
          },
        ),
      ),
    );

    expect(find.text('value: 1'), findsOneWidget);

    runInAction(source.clear);
    await tester.pump();

    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets(
    'Given a bounded exact index, When membership changes, Then the value hook rebuilds and disposes its reaction',
    (tester) async {
      final selected = Observable<int?>(1);
      var reads = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HookBuilder(
            builder: (_) {
              final value = useObservedEntityValue<int>(() {
                reads++;
                return selected.value;
              });
              return Text('value: $value');
            },
          ),
        ),
      );

      expect(find.text('value: 1'), findsOneWidget);

      runInAction(() => selected.value = 2);
      await tester.pump();
      expect(find.text('value: 2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final readsAtDispose = reads;
      runInAction(() => selected.value = 3);
      await tester.pump();
      expect(reads, readsAtDispose);
    },
  );

  testWidgets('observed existence exposes a boolean without list mechanics', (
    tester,
  ) async {
    final source = ObservableList<int>();
    final cache = LocalEntityQueryCache<int>(
      source: ReadOnlyObservableList(source),
    );
    addTearDown(cache.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HookBuilder(
          builder: (_) {
            final observed = useObservedEntityExistence(
              () => EntityExistence(
                cache.acquire(EntityQuerySpec<int>(pageSize: 1)),
              ),
            );
            return Text('exists: ${observed.value}');
          },
        ),
      ),
    );

    expect(find.text('exists: false'), findsOneWidget);

    runInAction(() => source.add(1));
    await tester.pump();
    expect(find.text('exists: true'), findsOneWidget);
  });

  testWidgets('entity action reports and clears errors generically', (
    tester,
  ) async {
    EntityActionBinding? captured;
    Object? reported;

    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          captured = useEntityAction(onError: (error) => reported = error);
          return const SizedBox();
        },
      ),
    );

    await captured!.run(() async => throw StateError('failed'));
    await tester.pump();

    expect(captured!.error, isA<StateError>());
    expect(reported, same(captured!.error));

    captured!.clearError();
    await tester.pump();

    expect(captured!.error, isNull);
  });

  testWidgets('async draft hooks expose readiness and discard on unmount', (
    tester,
  ) async {
    final completer = Completer<_TestDraft>();
    AsyncSnapshot<_TestDraft>? captured;

    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          captured = useAsyncEntityMutationDraft<int, _TestDraft>(
            () => completer.future,
          );
          return const SizedBox();
        },
      ),
    );
    expect(captured!.connectionState, ConnectionState.waiting);

    final draft = _TestDraft();
    completer.complete(draft);
    await tester.pumpAndSettle();
    expect(captured!.data, same(draft));

    await tester.pumpWidget(const SizedBox());
    expect(draft.isConsumed, isTrue);
  });

  testWidgets('a list hook whose selection changes keeps showing the previous '
      'results as refreshing until the new ones load, then releases them', (
    tester,
  ) async {
    final invalidations =
        StreamController<EntityProjectionChange<int>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    final evens = Completer<void>();
    final cache = LocalEntityQueryCache<int>.database(
      loader: (spec, {required after, required limit}) async {
        // The page size stands in for a filter: 10 selects odd values and 20
        // even ones, which load only once released.
        if (spec.pageSize == 20) await evens.future;
        return EntityQueryPage(
          items: spec.pageSize == 20 ? const [2, 4] : const [1, 3],
          hasMore: false,
          nextCursor: null,
        );
      },
      invalidations: invalidations.stream,
    );
    addTearDown(cache.dispose);
    final filter = ValueNotifier(10);
    addTearDown(filter.dispose);
    final lists = <_IntList>[];
    late ObservedEntityQuery<int> observed;

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: filter,
        builder: (_, pageSize, _) => HookBuilder(
          builder: (_) {
            observed = useObservedEntityList(() {
              final list = _IntList(
                cache.acquire(EntityQuerySpec<int>(pageSize: pageSize)),
              );
              lists.add(list);
              return list;
            }, keys: [pageSize]);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(observed.state.items, [1, 3]);

    filter.value = 20;
    await tester.pump();
    await tester.pump();

    expect(observed.state, isA<EntityQueryStaleData<int>>());
    expect(observed.state.items, [1, 3]);
    expect(lists.first.state.value, isNot(isA<EntityQueryDisposed<int>>()));

    evens.complete();
    await tester.pumpAndSettle();

    expect(observed.state, isA<EntityQueryData<int>>());
    expect(observed.state.items, [2, 4]);
    expect(lists.first.state.value, isA<EntityQueryDisposed<int>>());

    await tester.pumpWidget(const SizedBox());
    expect(lists.last.state.value, isA<EntityQueryDisposed<int>>());
  });

  testWidgets('complete query hooks exhaust every cached page', (tester) async {
    final invalidations =
        StreamController<EntityProjectionChange<int>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    var values = [1, 2, 3];
    final cache = LocalEntityQueryCache<int>.database(
      loader: (spec, {required after, required limit}) async {
        final offset = (after as _OffsetCursor?)?.offset ?? 0;
        final items = values.skip(offset).take(limit).toList(growable: false);
        final nextOffset = offset + items.length;
        return EntityQueryPage(
          items: items,
          hasMore: nextOffset < values.length,
          nextCursor: _OffsetCursor(nextOffset),
        );
      },
      invalidations: invalidations.stream,
    );
    addTearDown(cache.dispose);
    LocalEntityQuery<int>? captured;

    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          captured = useEntityQuery(
            () => cache.acquire(EntityQuerySpec<int>(pageSize: 1)),
            loadAllPages: true,
          );
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(captured!.items, [1, 2, 3]);
    expect(captured!.hasMore, isFalse);

    values = [4, 5, 6, 7];
    invalidations.add(const EntityProjectionChange<int>.unknown());
    await tester.pumpAndSettle();

    expect(captured!.items, [4, 5, 6, 7]);
    expect(captured!.hasMore, isFalse);
  });

  testWidgets('complete query hooks do not hot-retry a failed page', (
    tester,
  ) async {
    final invalidations =
        StreamController<EntityProjectionChange<int>>.broadcast(sync: true);
    addTearDown(invalidations.close);
    var loadCount = 0;
    final cache = LocalEntityQueryCache<int>.database(
      loader: (spec, {required after, required limit}) async {
        loadCount++;
        if (after == null) {
          return const EntityQueryPage(
            items: [1],
            hasMore: true,
            nextCursor: _OffsetCursor(1),
          );
        }
        throw StateError('second page failed');
      },
      invalidations: invalidations.stream,
    );
    addTearDown(cache.dispose);
    LocalEntityQuery<int>? captured;

    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          captured = useEntityQuery(
            () => cache.acquire(EntityQuerySpec<int>(pageSize: 1)),
            loadAllPages: true,
          );
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(captured!.state.value, isA<EntityQueryFailure<int>>());
    expect(loadCount, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(loadCount, 2);

    invalidations.add(const EntityProjectionChange<int>.unknown());
    await tester.pumpAndSettle();
    expect(loadCount, 4);
  });

  testWidgets(
    'observed query rendering automatically loads the next visible page',
    (tester) async {
      final values = List<int>.generate(40, (index) => index);
      var loadCount = 0;
      LocalEntityQuery<int>? captured;
      final cache = LocalEntityQueryCache<int>.database(
        invalidations: const Stream.empty(),
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          final offset = (after as _OffsetCursor?)?.offset ?? 0;
          final items = values.skip(offset).take(limit).toList(growable: false);
          final nextOffset = offset + items.length;
          return EntityQueryPage(
            items: items,
            hasMore: nextOffset < values.length,
            nextCursor: _OffsetCursor(nextOffset),
          );
        },
      );
      addTearDown(cache.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 200,
            child: HookBuilder(
              builder: (_) {
                final observed = useObservedEntityQuery(
                  () => cache.acquire(EntityQuerySpec<int>(pageSize: 4)),
                );
                captured = observed.query;
                return observed.when(
                  pagingPreloadExtent: 0,
                  loading: SizedBox.shrink,
                  empty: SizedBox.shrink,
                  failure: (error, retry) => Text('$error'),
                  data:
                      (
                        items, {
                        required hasMore,
                        required refreshing,
                        refreshError,
                      }) => ListView.builder(
                        itemExtent: 100,
                        itemCount: items.length,
                        itemBuilder: (_, index) => Text('${items[index]}'),
                      ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The first layout notification may prefetch one page while the scroll
      // extent is still zero; it must not exhaust an actually scrollable list.
      expect(loadCount, 2);
      expect(find.text('3'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(loadCount, greaterThan(2));
      expect(loadCount, lessThan(10));
      expect(captured!.items.length, greaterThan(8));
    },
  );

  testWidgets(
    'automatic paging fills a viewport without hot-retrying a failed page',
    (tester) async {
      var loadCount = 0;
      final cache = LocalEntityQueryCache<int>.database(
        invalidations: const Stream.empty(),
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          if (after == null) {
            return const EntityQueryPage(
              items: [1],
              hasMore: true,
              nextCursor: _OffsetCursor(1),
            );
          }
          throw StateError('next page failed');
        },
      );
      addTearDown(cache.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 300,
            child: HookBuilder(
              builder: (_) {
                final observed = useObservedEntityQuery(
                  () => cache.acquire(EntityQuerySpec<int>(pageSize: 1)),
                );
                return observed.when(
                  loading: SizedBox.shrink,
                  empty: SizedBox.shrink,
                  failure: (error, retry) => Text('$error'),
                  data:
                      (
                        items, {
                        required hasMore,
                        required refreshing,
                        refreshError,
                      }) => ListView.builder(
                        itemExtent: 100,
                        itemCount: items.length,
                        itemBuilder: (_, index) => Text('${items[index]}'),
                      ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(loadCount, 2);
    },
  );

  testWidgets(
    'automatic paging follows a vertical list through a horizontal pager',
    (tester) async {
      final values = List<int>.generate(6, (index) => index);
      var loadCount = 0;
      var verticalNotificationDepth = 0;
      final cache = LocalEntityQueryCache<int>.database(
        invalidations: const Stream.empty(),
        loader: (spec, {required after, required limit}) async {
          loadCount++;
          final offset = (after as _OffsetCursor?)?.offset ?? 0;
          final items = values.skip(offset).take(limit).toList(growable: false);
          final nextOffset = offset + items.length;
          return EntityQueryPage(
            items: items,
            hasMore: nextOffset < values.length,
            nextCursor: _OffsetCursor(nextOffset),
          );
        },
      );
      addTearDown(cache.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 200,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical) {
                  verticalNotificationDepth = notification.depth;
                }
                return false;
              },
              child: HookBuilder(
                builder: (_) {
                  final observed = useObservedEntityQuery(
                    () => cache.acquire(EntityQuerySpec<int>(pageSize: 1)),
                  );
                  return observed.when(
                    pagingPreloadExtent: 0,
                    loading: SizedBox.shrink,
                    empty: SizedBox.shrink,
                    failure: (error, retry) => Text('$error'),
                    data:
                        (
                          items, {
                          required hasMore,
                          required refreshing,
                          refreshError,
                        }) => PageView(
                          children: [
                            ListView.builder(
                              itemExtent: 100,
                              itemCount: items.length,
                              itemBuilder: (_, index) =>
                                  Text('${items[index]}'),
                            ),
                          ],
                        ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(verticalNotificationDepth, greaterThan(0));
      expect(loadCount, 2);
      expect(find.text('1'), findsOneWidget);
    },
  );
}

final class _OffsetCursor implements EntityQueryCursor {
  const _OffsetCursor(this.offset);

  final int offset;
}

final class _IntList extends EntityList<int> {
  _IntList(super.query);
}

final class _IntLookup extends EntityLookup<int> {
  _IntLookup(super.query);
}

final class _TestDraft implements EntityMutationDraft<int> {
  var _consumed = false;

  @override
  int? get entity => null;

  @override
  LocalId<int> get id => LocalId('00000000-0000-7000-8000-000000000001');

  @override
  bool get isConsumed => _consumed;

  @override
  bool get isCreating => true;

  @override
  void discard() => _consumed = true;

  @override
  Future<int> save() async {
    _consumed = true;
    return 1;
  }
}
