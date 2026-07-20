@Tags(['flutter'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_flutter.dart';

final class _Dependency {
  const _Dependency(this.value);

  final int value;
}

abstract interface class _DependencyContract {
  int get value;
}

final class _DependencyImplementation implements _DependencyContract {
  const _DependencyImplementation(this.value);

  @override
  final int value;
}

void main() {
  test('redirect target preserves the page function identity', () {
    Widget page() => const SizedBox();

    final redirect = FileRouteRedirect.to(page);

    expect(redirect.target, same(page));
  });

  testWidgets('resolves an immutable dependency by its exact type', (
    tester,
  ) async {
    const dependency = _Dependency(42);
    late _Dependency resolved;

    await tester.pumpWidget(
      FileRouteScope(
        dependencies: const [FileRouteDependency(dependency)],
        child: Builder(
          builder: (context) {
            resolved = FileRouteScope.read<_Dependency>(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, same(dependency));
  });

  testWidgets('binds an implementation by its declared interface type', (
    tester,
  ) async {
    const _DependencyContract dependency = _DependencyImplementation(7);
    late _DependencyContract resolved;

    await tester.pumpWidget(
      FileRouteScope(
        dependencies: const [FileRouteDependency(dependency)],
        child: Builder(
          builder: (context) {
            resolved = FileRouteScope.read<_DependencyContract>(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, same(dependency));
  });

  testWidgets('reports a missing dependency at the route boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      FileRouteScope(
        dependencies: const [],
        child: Builder(
          builder: (context) {
            FileRouteScope.read<_Dependency>(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      tester.takeException(),
      isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('_Dependency'),
      ),
    );
  });

  test('rejects duplicate dependency types', () {
    expect(
      () => FileRouteScope(
        dependencies: const [
          FileRouteDependency(_Dependency(1)),
          FileRouteDependency(_Dependency(2)),
        ],
        child: const SizedBox(),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('registered twice'),
        ),
      ),
    );
  });
}
