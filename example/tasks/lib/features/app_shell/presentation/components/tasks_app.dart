import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tasks_example/nodus.g.dart';

final class TasksExample extends HookWidget {
  const TasksExample({
    required this.entityGraph,
    this.initialLocation,
    this.closeEntityGraphOnDispose = true,
    super.key,
  });

  final TasksExampleEntityGraph entityGraph;
  final String? initialLocation;
  final bool closeEntityGraphOnDispose;

  @override
  Widget build(BuildContext context) {
    final router = useMemoized(
      () => createFileRouter(initialLocation: initialLocation),
    );
    final currentGraph = useRef(entityGraph)..value = entityGraph;
    final shouldCloseGraph = useRef(closeEntityGraphOnDispose)
      ..value = closeEntityGraphOnDispose;
    useEffect(() => router.dispose, [router]);
    useEffect(
      () => () {
        if (shouldCloseGraph.value) {
          unawaited(currentGraph.value.close());
        }
      },
      const [],
    );

    return FileRouteScope(
      dependencies: [FileRouteDependency(entityGraph)],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        routerConfig: router,
      ),
    );
  }
}
