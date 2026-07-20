// GENERATED FILE. DO NOT EDIT.
// Routes are merged from feature presentation/page trees.
// ignore_for_file: type=lint

import 'package:nodus/nodus_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:tasks_example/features/app_shell/presentation/pages/redirect.dart'
    as route2;
import 'package:tasks_example/features/tasks/presentation/pages/activity/page.dart'
    as route3;
import 'package:tasks_example/features/tasks/presentation/pages/projects/page.dart'
    as route6;
import 'package:tasks_example/features/tasks/presentation/pages/sync/page.dart'
    as route7;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/page.dart'
    as route13;
import 'package:tasks_example/features/tasks/presentation/pages/projects/new/page.dart'
    as route5;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/new/page.dart'
    as route12;
import 'package:tasks_example/features/tasks/presentation/pages/projects/[projectId]/page.dart'
    as route4;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/[taskId]/page.dart'
    as route10;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/[taskId]/access/page.dart'
    as route8;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/[taskId]/edit/page.dart'
    as route9;
import 'package:tasks_example/features/app_shell/presentation/pages/layout.dart'
    as route0;
import 'package:tasks_example/features/tasks/presentation/pages/tasks/layout.dart'
    as route11;
import 'package:tasks_example/features/app_shell/presentation/pages/not_found.dart'
    as route1;
import 'package:tasks_example/features/tasks/domain/task_list_filter.dart';
import 'package:tasks_example/src/generated/nodus.runtime.g.dart';

final class RootRoute implements FileRouteLocation {
  const RootRoute();
  String get location {
    final path = '/';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TaskActivityRoute implements FileRouteLocation {
  const TaskActivityRoute();
  String get location {
    final path = '/activity';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TaskProjectsRoute implements FileRouteLocation {
  const TaskProjectsRoute();
  String get location {
    final path = '/projects';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class SyncCenterRoute implements FileRouteLocation {
  const SyncCenterRoute();
  String get location {
    final path = '/sync';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TasksRoute implements FileRouteLocation {
  const TasksRoute({this.filter = TaskListFilter.open});
  final TaskListFilter filter;
  String get location {
    final path = '/tasks';
    final query = <String, String>{};
    if (filter != TaskListFilter.open) {
      query['filter'] = filter.name;
    }
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class NewTaskProjectRoute implements FileRouteLocation {
  const NewTaskProjectRoute();
  String get location {
    final path = '/projects/new';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class NewTaskRoute implements FileRouteLocation {
  const NewTaskRoute({this.filter = TaskListFilter.open});
  final TaskListFilter filter;
  String get location {
    final path = '/tasks/new';
    final query = <String, String>{};
    if (filter != TaskListFilter.open) {
      query['filter'] = filter.name;
    }
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TaskProjectDetailsRoute implements FileRouteLocation {
  const TaskProjectDetailsRoute(this.projectId);
  final LocalId<TaskProject> projectId;
  String get location {
    final path = '/projects/${Uri.encodeComponent(projectId.value)}';
    final query = <String, String>{};
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TaskDetailsRoute implements FileRouteLocation {
  const TaskDetailsRoute(this.taskId, {this.filter = TaskListFilter.open});
  final LocalId<Task> taskId;
  final TaskListFilter filter;
  String get location {
    final path = '/tasks/${Uri.encodeComponent(taskId.value)}';
    final query = <String, String>{};
    if (filter != TaskListFilter.open) {
      query['filter'] = filter.name;
    }
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class TaskAccessRoute implements FileRouteLocation {
  const TaskAccessRoute(this.taskId, {this.filter = TaskListFilter.open});
  final LocalId<Task> taskId;
  final TaskListFilter filter;
  String get location {
    final path = '/tasks/${Uri.encodeComponent(taskId.value)}/access';
    final query = <String, String>{};
    if (filter != TaskListFilter.open) {
      query['filter'] = filter.name;
    }
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

final class EditTaskRoute implements FileRouteLocation {
  const EditTaskRoute(this.taskId, {this.filter = TaskListFilter.open});
  final LocalId<Task> taskId;
  final TaskListFilter filter;
  String get location {
    final path = '/tasks/${Uri.encodeComponent(taskId.value)}/edit';
    final query = <String, String>{};
    if (filter != TaskListFilter.open) {
      query['filter'] = filter.name;
    }
    if (query.isEmpty) return path;
    return '$path?${Uri(queryParameters: query).query}';
  }

  void go(BuildContext context) => context.go(location);
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);
  void replace(BuildContext context) => context.replace(location);
}

Widget _buildFileRouteNotFound(
  BuildContext context,
  GoRouterState state,
  Object error,
) {
  return route1.notFoundPage(
    state,
    error,
    () => context.go(const RootRoute().location),
  );
}

Widget _buildFileRoute1(BuildContext context, GoRouterState state) {
  return route3.TaskActivityPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    key: state.pageKey,
  );
}

Widget _buildFileRoute2(BuildContext context, GoRouterState state) {
  return route6.TaskProjectsPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    key: state.pageKey,
  );
}

Widget _buildFileRoute3(BuildContext context, GoRouterState state) {
  return route7.SyncCenterPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    key: state.pageKey,
  );
}

Widget _buildFileRoute4(BuildContext context, GoRouterState state) {
  late final TaskListFilter filter;
  try {
    filter = state.uri.queryParameters['filter'] == null
        ? TaskListFilter.open
        : TaskListFilter.values.byName(state.uri.queryParameters['filter']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route13.tasksPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    filter: filter,
    key: state.pageKey,
  );
}

Widget _buildFileRoute5(BuildContext context, GoRouterState state) {
  return route5.NewTaskProjectPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    key: state.pageKey,
  );
}

Widget _buildFileRoute6(BuildContext context, GoRouterState state) {
  late final TaskListFilter filter;
  try {
    filter = state.uri.queryParameters['filter'] == null
        ? TaskListFilter.open
        : TaskListFilter.values.byName(state.uri.queryParameters['filter']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route12.newTaskPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    filter: filter,
    key: state.pageKey,
  );
}

Widget _buildFileRoute7(BuildContext context, GoRouterState state) {
  late final LocalId<TaskProject> projectId;
  try {
    projectId = parseLocalId<TaskProject>(state.pathParameters['projectId']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route4.TaskProjectDetailsPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    projectId,
    key: state.pageKey,
  );
}

Widget _buildFileRoute8(BuildContext context, GoRouterState state) {
  late final LocalId<Task> taskId;
  late final TaskListFilter filter;
  try {
    taskId = parseLocalId<Task>(state.pathParameters['taskId']!);
    filter = state.uri.queryParameters['filter'] == null
        ? TaskListFilter.open
        : TaskListFilter.values.byName(state.uri.queryParameters['filter']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route10.taskDetailsPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    taskId,
    filter: filter,
    key: state.pageKey,
  );
}

Widget _buildFileRoute9(BuildContext context, GoRouterState state) {
  late final LocalId<Task> taskId;
  late final TaskListFilter filter;
  try {
    taskId = parseLocalId<Task>(state.pathParameters['taskId']!);
    filter = state.uri.queryParameters['filter'] == null
        ? TaskListFilter.open
        : TaskListFilter.values.byName(state.uri.queryParameters['filter']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route8.TaskAccessPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    taskId,
    filter: filter,
    key: state.pageKey,
  );
}

Widget _buildFileRoute10(BuildContext context, GoRouterState state) {
  late final LocalId<Task> taskId;
  late final TaskListFilter filter;
  try {
    taskId = parseLocalId<Task>(state.pathParameters['taskId']!);
    filter = state.uri.queryParameters['filter'] == null
        ? TaskListFilter.open
        : TaskListFilter.values.byName(state.uri.queryParameters['filter']!);
  } on FormatException catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  } on ArgumentError catch (error) {
    return _buildFileRouteNotFound(context, state, error);
  }
  return route9.editTaskPage(
    FileRouteScope.read<TasksExampleEntityGraph>(context),
    taskId,
    filter: filter,
    key: state.pageKey,
  );
}

Widget _buildFileRouteLayout0(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => route0.appLayout(child);

Widget _buildFileRouteLayout1(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => route11.tasksLayout(child);

String _resolveFileRouteRedirect(FileRouteRedirect redirect) {
  if (identical(redirect.target, route3.TaskActivityPage.new)) {
    return const TaskActivityRoute().location;
  }
  if (identical(redirect.target, route6.TaskProjectsPage.new)) {
    return const TaskProjectsRoute().location;
  }
  if (identical(redirect.target, route7.SyncCenterPage.new)) {
    return const SyncCenterRoute().location;
  }
  if (identical(redirect.target, route13.tasksPage)) {
    return const TasksRoute().location;
  }
  if (identical(redirect.target, route5.NewTaskProjectPage.new)) {
    return const NewTaskProjectRoute().location;
  }
  if (identical(redirect.target, route12.newTaskPage)) {
    return const NewTaskRoute().location;
  }
  throw StateError(
    'A redirect must target a file page without required URL parameters.',
  );
}

GoRouter createFileRouter({
  String? initialLocation,
  FileRouterConfiguration configuration = const FileRouterConfiguration(),
}) {
  return GoRouter(
    navigatorKey: configuration.navigatorKey,
    initialLocation: initialLocation ?? const RootRoute().location,
    refreshListenable: configuration.refreshListenable,
    redirect: configuration.redirect,
    debugLogDiagnostics: configuration.debugLogDiagnostics,
    observers: configuration.observers,
    errorBuilder: (context, state) => _buildFileRouteNotFound(
      context,
      state,
      state.error ?? StateError('No route matches ${state.uri.path}.'),
    ),
    routes: [
      ShellRoute(
        builder: _buildFileRouteLayout0,
        routes: [
          GoRoute(
            path: '/',
            redirect: (context, state) =>
                _resolveFileRouteRedirect(route2.rootRedirect()),
          ),
          GoRoute(path: '/activity', builder: _buildFileRoute1),
          GoRoute(path: '/projects', builder: _buildFileRoute2),
          GoRoute(path: '/sync', builder: _buildFileRoute3),
          GoRoute(path: '/projects/new', builder: _buildFileRoute5),
          GoRoute(path: '/projects/:projectId', builder: _buildFileRoute7),
          ShellRoute(
            builder: _buildFileRouteLayout1,
            routes: [
              GoRoute(path: '/tasks', builder: _buildFileRoute4),
              GoRoute(path: '/tasks/new', builder: _buildFileRoute6),
              GoRoute(path: '/tasks/:taskId', builder: _buildFileRoute8),
              GoRoute(path: '/tasks/:taskId/access', builder: _buildFileRoute9),
              GoRoute(path: '/tasks/:taskId/edit', builder: _buildFileRoute10),
            ],
          ),
        ],
      ),
    ],
  );
}
