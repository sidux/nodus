import 'package:flutter/material.dart';

import 'app_bootstrap.dart';
import 'package:tasks_example/features/app_shell/presentation/components/tasks_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final entityGraph = await TasksBootstrap.open();
    runApp(TasksExample(entityGraph: entityGraph));
  } catch (error) {
    runApp(_BootstrapFailureApp(message: error.toString()));
  }
}

final class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Tasks could not start.\n\n$message'),
          ),
        ),
      ),
    );
  }
}
