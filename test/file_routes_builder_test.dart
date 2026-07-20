import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:nodus/builder.dart';
import 'package:test/test.dart';

import 'support/test_package_config.dart';

void main() {
  initializeBuildTestEnvironment();

  test('derives typed paths, queries, dependencies, shell, and errors', () async {
    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/features/shell/presentation/pages/redirect.dart': '''
import 'package:example/features/rules/presentation/pages/(authenticated)/rules/page.dart';

final class FileRouteRedirect {
  const FileRouteRedirect.to(this.target);
  final Function target;
}

FileRouteRedirect rootRedirect() => FileRouteRedirect.to(RulesPage.new);
''',
        'example|lib/features/shell/presentation/pages/layout.dart': '''
final class BuildContext {}
final class Widget {}

Widget appLayout(BuildContext context, Widget child) => child;
''',
        'example|lib/features/auth/presentation/pages/(authenticated)/guard.dart':
            '''
final class Dependencies {}
final class FileRouteRedirect {}
final class FileRouteMatch {
  bool isPage(Function page) => false;
}

FileRouteRedirect? authenticatedGuard(
  Dependencies dependencies,
  FileRouteMatch match,
) => null;
''',
        'example|lib/features/rules/presentation/pages/(authenticated)/rules/layout.dart':
            '''
final class Widget {}

Widget rulesLayout(Widget child) => child;
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class BuildContext {}
final class GoRouterState {}
final class Widget {}
typedef VoidCallback = void Function();

Widget notFoundPage(
  BuildContext context,
  GoRouterState state,
  Object error,
  VoidCallback recover,
) => const SizedBox();
''',
        'example|lib/features/rules/presentation/pages/(authenticated)/rules/page.dart':
            '''
final class Dependencies {}
class Widget { const Widget(); }

final class RulesPage extends Widget {
  const RulesPage(this.dependencies);
  final Dependencies dependencies;
}
''',
        'example|lib/features/rules/presentation/pages/(authenticated)/rules/[ruleId]/page.dart':
            '''
enum Filter { all, active }
final class Dependencies {}
class Widget { const Widget(); }

final class RuleDetailsPage extends Widget {
  const RuleDetailsPage(
    this.dependencies,
    this.ruleId, {
    this.filter = Filter.all,
    this.includeArchived = false,
  });
  final Dependencies dependencies;
  final int ruleId;
  final Filter filter;
  final bool includeArchived;
}
''',
      },
      rootPackage: 'example',
      outputs: {
        'example|lib/features/shell/presentation/pages/not_found.routes.g.dart':
            decodedMatches(
              allOf([
                contains('// ignore_for_file: type=lint'),
                contains('final class RuleDetailsRoute'),
                contains("path: '/rules/:ruleId'"),
                contains('final int ruleId;'),
                contains('this.filter = Filter.all'),
                contains('this.includeArchived = false'),
                contains("query['include-archived']"),
                contains("state.uri.queryParameters['include-archived']"),
                contains('FileRouteScope.read<Dependencies>(context)'),
                contains('_buildFileRouteLayout0'),
                contains('_buildFileRouteLayout1'),
                contains('_buildFileRouteGuard0'),
                contains('_matchFileRoute(state)'),
                contains(
                  "'/rules/:ruleId' => FileRouteMatch.page(route1.RuleDetailsPage.new)",
                ),
                contains('identical(redirect.target'),
                contains('_resolveFileRouteRedirect('),
                contains('() => context.go(const RootRoute().location)'),
              ]),
            ),
      },
    );
  });

  test('derives page-owned presentation and root router configuration', () async {
    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/features/home/presentation/pages/page.dart': '''
class BuildContext {}
class GoRouterState {}
class Widget { const Widget(); }
abstract interface class FileRoutePagePresentation {
  Object buildRoutePage(BuildContext context, GoRouterState state);
}

final class HomePage extends Widget implements FileRoutePagePresentation {
  const HomePage();

  @override
  Object buildRoutePage(BuildContext context, GoRouterState state) => Object();
}
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class GoRouterState {}
final class Widget {}
typedef VoidCallback = void Function();

Widget notFoundPage(
  GoRouterState state,
  Object error,
  VoidCallback recover,
) => Widget();
''',
      },
      outputs: {
        'example|lib/features/shell/presentation/pages/not_found.routes.g.dart':
            decodedMatches(
              allOf([
                contains('Page<void> _buildFileRoute0('),
                contains('return page.buildRoutePage(context, state);'),
                contains('pageBuilder: _buildFileRoute0'),
                contains('FileRouterConfiguration configuration ='),
                contains('navigatorKey: configuration.navigatorKey'),
                contains('refreshListenable: configuration.refreshListenable'),
                contains('redirect: configuration.redirect'),
                isNot(contains('package:go_router/src/')),
              ]),
            ),
      },
    );
  });

  test('omits type imports already re-exported by a route dependency', () async {
    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/work_filter.dart': 'enum WorkFilter { all, active }',
        'example|lib/entity_graph.runtime.g.dart': '''
export 'work_filter.dart';

final class ExampleEntityGraph {}
''',
        'example|lib/features/work/presentation/pages/work/page.dart': '''
import 'package:example/entity_graph.runtime.g.dart';
import 'package:example/work_filter.dart';

class Widget { const Widget(); }

final class WorkPage extends Widget {
  const WorkPage(this.entityGraph, {this.filter = WorkFilter.all});

  final ExampleEntityGraph entityGraph;
  final WorkFilter filter;
}
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class Widget {}

Widget notFoundPage(Object error) => Widget();
''',
      },
      rootPackage: 'example',
      outputs: {
        'example|lib/features/shell/presentation/pages/not_found.routes.g.dart':
            decodedMatches(
              allOf([
                contains(
                  "import 'package:example/entity_graph.runtime.g.dart';",
                ),
                isNot(contains("import 'package:example/work_filter.dart';")),
                contains('FileRouteScope.read<ExampleEntityGraph>(context)'),
                contains('final WorkFilter filter;'),
              ]),
            ),
      },
    );
  });

  test('rejects a dynamic folder without its typed parameter', () async {
    final messages = <String>[];

    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/features/home/presentation/pages/page.dart': '''
class Widget { const Widget(); }

final class HomePage extends Widget {
  const HomePage();
}
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class BuildContext {}
final class GoRouterState {}
final class Widget {}
typedef VoidCallback = void Function();

Widget notFoundPage(
  BuildContext context,
  GoRouterState state,
  Object error,
  VoidCallback recover,
) => const SizedBox();
''',
        'example|lib/features/rules/presentation/pages/rules/[ruleId]/page.dart':
            '''
class Widget { const Widget(); }

final class RuleDetailsPage extends Widget {
  const RuleDetailsPage();
}
''',
      },
      onLog: (record) => messages.add(record.message),
    );

    expect(
      messages,
      contains(
        contains(
          'Folder `[ruleId]` requires a page entry parameter named `ruleId`.',
        ),
      ),
    );
  });

  test(
    'accepts a typed top-level Widget page entry without a wrapper class',
    () async {
      await testBuilder(
        fileRoutesBuilder(BuilderOptions.empty),
        {
          'example|lib/features/home/presentation/pages/page.dart': '''
class Widget { const Widget(); }
class Key {}

Widget homePage({Key? key}) => const Widget();
''',
          'example|lib/features/home/presentation/pages/guard.dart': '''
final class FileRouteRedirect {}
final class FileRouteMatch {}

FileRouteRedirect? homeGuard(FileRouteMatch match) => null;
''',
          'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class Widget {}

Widget notFoundPage(Object error) => Widget();
''',
        },
        rootPackage: 'example',
        outputs: {
          'example|lib/features/shell/presentation/pages/not_found.routes.g.dart':
              decodedMatches(
                allOf([
                  contains('return route1.homePage(key: state.pageKey);'),
                  contains('FileRouteMatch.page(route1.homePage)'),
                  contains('identical(redirect.target, route1.homePage)'),
                  isNot(contains('route1.homePage.new')),
                ]),
              ),
        },
      );
    },
  );

  test('rejects the same route path claimed by separate features', () async {
    final messages = <String>[];

    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/features/first/presentation/pages/rules/page.dart': '''
class Widget { const Widget(); }

final class FirstRulesPage extends Widget {
  const FirstRulesPage();
}
''',
        'example|lib/features/second/presentation/pages/rules/page.dart': '''
class Widget { const Widget(); }

final class SecondRulesPage extends Widget {
  const SecondRulesPage();
}
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class GoRouterState {}
final class Widget {}
typedef VoidCallback = void Function();

Widget notFoundPage(
  GoRouterState state,
  Object error,
  VoidCallback recover,
) => Widget();
''',
      },
      onLog: (record) => messages.add(record.message),
    );

    expect(messages.join('\n'), contains('Duplicate file route `/rules`.'));
  });

  test('rejects loose feature presentation files', () async {
    final messages = <String>[];

    await testBuilder(
      fileRoutesBuilder(BuilderOptions.empty),
      {
        'example|lib/features/rules/presentation/rules_view.dart': '''
final class RulesView {}
''',
        'example|lib/features/rules/presentation/pages/rules/page.dart': '''
class Widget { const Widget(); }

final class RulesPage extends Widget {
  const RulesPage();
}
''',
        'example|lib/features/shell/presentation/pages/not_found.dart': '''
final class GoRouterState {}
final class Widget {}
typedef VoidCallback = void Function();

Widget notFoundPage(
  GoRouterState state,
  Object error,
  VoidCallback recover,
) => Widget();
''',
      },
      onLog: (record) => messages.add(record.message),
    );

    expect(
      messages.join('\n'),
      contains('must live under `pages/` or `components/`'),
    );
  });
}
