part of '../nodus_flutter.dart';

abstract interface class FileRouteLocation {
  String get location;

  void go(BuildContext context);

  Future<T?> push<T>(BuildContext context);

  void replace(BuildContext context);
}

/// Optional page-owned presentation for generated file routes.
///
/// Ordinary pages use GoRouter's platform-default page. A page implements this
/// only when navigation presentation is real UI intent, such as a transparent
/// sheet launcher or a no-transition adaptive shell destination. Keeping the
/// override on the page prevents a second central route registry.
abstract interface class FileRoutePagePresentation {
  Page<void> buildRoutePage(BuildContext context, GoRouterState state);
}

/// The generated page identity for the current match.
///
/// Guards compare constructor tear-offs rather than duplicating paths. Unknown
/// external locations deliberately match no page and flow to the generated
/// not-found boundary.
final class FileRouteMatch {
  const FileRouteMatch._(this._page);

  const FileRouteMatch.page(Function page) : this._(page);

  const FileRouteMatch.unknown() : this._(null);

  final Function? _page;

  bool isPage(Function page) => identical(_page, page);
}

typedef FileRouterRedirect =
    FutureOr<String?> Function(BuildContext context, GoRouterState state);

/// App-level lifecycle options that cannot be inferred from feature files.
///
/// Route paths, hierarchy, parameters, guards, layouts, and page presentation
/// remain generated from the filesystem. This object is reserved for the root
/// navigator and external state that must ask GoRouter to reevaluate guards.
final class FileRouterConfiguration {
  const FileRouterConfiguration({
    this.navigatorKey,
    this.refreshListenable,
    this.redirect,
    this.debugLogDiagnostics = false,
    this.observers = const [],
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final Listenable? refreshListenable;
  final FileRouterRedirect? redirect;
  final bool debugLogDiagnostics;
  final List<NavigatorObserver> observers;
}

/// A redirect target expressed as a typed page-entry tear-off.
///
/// Referencing the function makes renames and removals compile-time failures.
/// The generator maps the function identity to its generated typed location,
/// so handwritten route code never contains a path string.
final class FileRouteRedirect {
  const FileRouteRedirect.to(this.target);

  final Function target;
}

/// Immutable, type-indexed dependencies injected into generated route pages.
///
/// Route functions declare dependencies as required positional parameters.
/// The file-route generator resolves them through this scope, leaving path and
/// query parameters as the only fields on generated navigation values.
sealed class FileRouteDependencyBinding {
  const FileRouteDependencyBinding();

  Type get type;

  Object get value;
}

final class FileRouteDependency<T extends Object>
    extends FileRouteDependencyBinding {
  const FileRouteDependency(this.value) : super();

  @override
  final T value;

  @override
  Type get type => T;
}

final class FileRouteScope extends InheritedWidget {
  FileRouteScope({
    required Iterable<FileRouteDependencyBinding> dependencies,
    required super.child,
    super.key,
  }) : _dependencies = Map.unmodifiable(_index(dependencies));

  final Map<Type, Object> _dependencies;

  static T read<T extends Object>(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FileRouteScope>();
    if (scope == null) {
      throw StateError('No FileRouteScope exists above the generated router.');
    }
    final dependency = scope._dependencies[T];
    if (dependency == null) {
      throw StateError('No route dependency of type `$T` was registered.');
    }
    if (dependency is T) return dependency;
    throw StateError('Route dependency `$T` violated its typed binding.');
  }

  static Map<Type, Object> _index(
    Iterable<FileRouteDependencyBinding> dependencies,
  ) {
    final result = <Type, Object>{};
    for (final dependency in dependencies) {
      final type = dependency.type;
      if (result.containsKey(type)) {
        throw ArgumentError('Route dependency `$type` was registered twice.');
      }
      result[type] = dependency.value;
    }
    return result;
  }

  @override
  bool updateShouldNotify(FileRouteScope oldWidget) {
    if (_dependencies.length != oldWidget._dependencies.length) return true;
    for (final entry in _dependencies.entries) {
      if (!identical(entry.value, oldWidget._dependencies[entry.key])) {
        return true;
      }
    }
    return false;
  }
}
