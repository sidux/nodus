import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:tasks_example/features/app_shell/presentation/components/route_not_found_view.dart';

Widget notFoundPage(GoRouterState state, Object error, VoidCallback recover) =>
    RouteNotFoundView(
      message: switch (error) {
        FormatException(:final message) => message,
        _ => 'No example route matches ${state.uri.path}.',
      },
      onRecover: recover,
    );
