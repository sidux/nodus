import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tasks_example/nodus.g.dart';

enum _ShellDestination {
  tasks(
    label: 'Tasks',
    icon: Icons.task_outlined,
    selectedIcon: Icons.task,
    route: TasksRoute(),
  ),
  projects(
    label: 'Projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    route: TaskProjectsRoute(),
  ),
  activity(
    label: 'Activity',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    route: TaskActivityRoute(),
  ),
  sync(
    label: 'Sync',
    icon: Icons.sync_outlined,
    selectedIcon: Icons.sync,
    route: SyncCenterRoute(),
  );

  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final FileRouteLocation route;
}

final class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.child, super.key});

  static const compactBreakpoint = 600.0;
  static const expandedBreakpoint = 840.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final path = GoRouterState.of(context).uri.path;
    final matchedIndex = _ShellDestination.values.indexWhere(
      (destination) => path.startsWith(destination.route.location),
    );
    final selectedIndex = matchedIndex < 0 ? 0 : matchedIndex;

    void select(int index) => _ShellDestination.values[index].route.go(context);

    if (width < compactBreakpoint) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: select,
          destinations: [
            for (final destination in _ShellDestination.values)
              NavigationDestination(
                key: ValueKey('${destination.name}Destination'),
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: width >= expandedBreakpoint,
              selectedIndex: selectedIndex,
              onDestinationSelected: select,
              destinations: [
                for (final destination in _ShellDestination.values)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
