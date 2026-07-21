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
