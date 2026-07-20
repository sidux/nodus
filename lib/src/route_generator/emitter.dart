import 'package:dart_style/dart_style.dart';

import 'model.dart';

String emitFileRouter(FileRouterSpec router) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Routes are merged from feature presentation/page trees.')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln("import 'package:nodus/nodus_flutter.dart';")
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import 'package:go_router/go_router.dart';");
  final allSpecs = <FileRouteSpec>[
    ...router.routes,
    ...router.layouts,
    ...router.guards,
    router.notFound,
  ];
  for (final spec in allSpecs) {
    buffer.writeln("import '${spec.assetImport}' as ${spec.importPrefix};");
  }
  final typeImports = {
    for (final spec in allSpecs) ...spec.typeImports,
  }.toList()..sort();
  for (final import in typeImports) {
    buffer.writeln("import '$import';");
  }
  buffer.writeln();

  for (final route in router.routes) {
    _emitNavigationValue(buffer, route);
  }
  final rootRoute = router.routes
      .where((route) => route.path == '/')
      .firstOrNull;
  _emitNotFound(
    buffer,
    router.notFound,
    recoveryRouteClass: rootRoute?.routeClassName,
  );
  if (allSpecs.any(
    (spec) => spec.parameters.any(
      (parameter) => parameter.kind == RouteParameterKind.match,
    ),
  )) {
    _emitRouteMatcher(buffer, router);
  }
  for (var index = 0; index < router.routes.length; index++) {
    _emitRouteBuilder(buffer, router.routes[index], index);
  }
  for (var index = 0; index < router.layouts.length; index++) {
    _emitLayoutBuilder(buffer, router.layouts[index], index);
  }
  for (var index = 0; index < router.guards.length; index++) {
    _emitGuardBuilder(buffer, router.guards[index], index);
  }
  if (router.routes.any(
    (route) => route.parameters.any(
      (parameter) => parameter.codec == RouteCodec.boolean,
    ),
  )) {
    buffer
      ..writeln('bool _decodeRouteBool(String source) => switch (source) {')
      ..writeln("  'true' => true,")
      ..writeln("  'false' => false,")
      ..writeln(
        "  _ => throw FormatException('Expected true or false.', source),",
      )
      ..writeln('};')
      ..writeln();
  }
  _emitRedirectResolver(buffer, router.routes);
  _emitRouterFactory(buffer, router);

  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).format(buffer.toString());
}

void _emitNavigationValue(StringBuffer buffer, FileRouteSpec route) {
  final pathParameters = _pathParametersInFolderOrder(route);
  final queryParameters = route.queryParameters;
  buffer.write(
    'final class ${route.routeClassName} implements FileRouteLocation {\n  const ',
  );
  buffer.write(route.routeClassName);
  if (pathParameters.isEmpty && queryParameters.isEmpty) {
    buffer.writeln('();');
  } else {
    buffer.write('(');
    for (final parameter in pathParameters) {
      buffer.write('this.${parameter.name}, ');
    }
    if (queryParameters.isNotEmpty) {
      buffer.writeln('{');
      for (final parameter in queryParameters) {
        final defaultCode = parameter.defaultCode;
        if (parameter.isRequired && defaultCode == null) {
          buffer.writeln('    required this.${parameter.name},');
        } else if (defaultCode != null) {
          buffer.writeln('    this.${parameter.name} = $defaultCode,');
        } else {
          buffer.writeln('    this.${parameter.name},');
        }
      }
      buffer.writeln('  });');
    } else {
      buffer.writeln(');');
    }
  }
  for (final parameter in [...pathParameters, ...queryParameters]) {
    buffer.writeln('  final ${parameter.dartType} ${parameter.name};');
  }
  buffer
    ..writeln('  String get location {')
    ..writeln("    final path = '${_locationPath(route, pathParameters)}';")
    ..writeln('    final query = <String, String>{};');
  for (final parameter in queryParameters) {
    final queryName = _queryName(parameter.name);
    final encoded = _encodeExpression(parameter, parameter.name);
    if (parameter.defaultCode case final defaultCode?) {
      buffer
        ..writeln('    if (${parameter.name} != $defaultCode) {')
        ..writeln("      query['$queryName'] = $encoded;")
        ..writeln('    }');
    } else if (parameter.isNullable) {
      buffer
        ..writeln('    if (${parameter.name} != null) {')
        ..writeln(
          "      query['$queryName'] = ${_encodeExpression(parameter, '${parameter.name}!')};",
        )
        ..writeln('    }');
    } else {
      buffer.writeln("    query['$queryName'] = $encoded;");
    }
  }
  buffer
    ..writeln('    if (query.isEmpty) return path;')
    ..writeln("    return '\$path?\${Uri(queryParameters: query).query}';")
    ..writeln('  }')
    ..writeln('  void go(BuildContext context) => context.go(location);')
    ..writeln('  Future<T?> push<T>(BuildContext context) =>')
    ..writeln('      context.push<T>(location);')
    ..writeln(
      '  void replace(BuildContext context) => context.replace(location);',
    )
    ..writeln('}')
    ..writeln();
}

List<RouteParameterSpec> _pathParametersInFolderOrder(FileRouteSpec route) {
  final byName = {
    for (final parameter in route.pathParameters) parameter.name: parameter,
  };
  return RegExp(r':([a-zA-Z_][a-zA-Z0-9_]*)')
      .allMatches(route.path)
      .map((match) => byName[match.group(1)]!)
      .toList(growable: false);
}

String _locationPath(
  FileRouteSpec route,
  List<RouteParameterSpec> pathParameters,
) {
  var path = route.path;
  for (final parameter in pathParameters) {
    final encoded = _encodeExpression(parameter, parameter.name);
    path = path.replaceFirst(
      ':${parameter.name}',
      '\${Uri.encodeComponent($encoded)}',
    );
  }
  return path;
}

void _emitNotFound(
  StringBuffer buffer,
  FileRouteSpec spec, {
  required String? recoveryRouteClass,
}) {
  final recovery = recoveryRouteClass == null
      ? '() {}'
      : '() => context.go(const $recoveryRouteClass().location)';
  buffer
    ..writeln('Widget _buildFileRouteNotFound(')
    ..writeln('  BuildContext context,')
    ..writeln('  GoRouterState state,')
    ..writeln('  Object error,')
    ..writeln(') {')
    ..writeln(
      '  return ${spec.importPrefix}.${spec.functionName}(${_arguments(spec, errorExpression: 'error', recoveryExpression: recovery)});',
    )
    ..writeln('}')
    ..writeln();
}

void _emitRouteBuilder(StringBuffer buffer, FileRouteSpec route, int index) {
  if (route.kind == FileRouteKind.redirect) return;
  final returnType = route.buildsPage ? 'Page<void>' : 'Widget';
  buffer
    ..writeln('$returnType _buildFileRoute$index(')
    ..writeln('  BuildContext context,')
    ..writeln('  GoRouterState state,')
    ..writeln(') {');
  final decoded = [...route.pathParameters, ...route.queryParameters];
  for (final parameter in decoded) {
    buffer.writeln('  late final ${parameter.dartType} ${parameter.name};');
  }
  if (decoded.isNotEmpty) {
    buffer.writeln('  try {');
    for (final parameter in route.pathParameters) {
      final raw = "state.pathParameters['${parameter.name}']!";
      buffer.writeln(
        '    ${parameter.name} = ${_decodeExpression(parameter, raw)};',
      );
    }
    for (final parameter in route.queryParameters) {
      final raw = "state.uri.queryParameters['${_queryName(parameter.name)}']";
      buffer.writeln(
        '    ${parameter.name} = ${_queryDecodeExpression(parameter, raw)};',
      );
    }
    buffer
      ..writeln('  } on FormatException catch (error) {')
      ..writeln(
        route.buildsPage
            ? '    return NoTransitionPage(key: state.pageKey, child: _buildFileRouteNotFound(context, state, error));'
            : '    return _buildFileRouteNotFound(context, state, error);',
      )
      ..writeln('  } on ArgumentError catch (error) {')
      ..writeln(
        route.buildsPage
            ? '    return NoTransitionPage(key: state.pageKey, child: _buildFileRouteNotFound(context, state, error));'
            : '    return _buildFileRouteNotFound(context, state, error);',
      )
      ..writeln('  }');
  }
  if (route.buildsPage) {
    buffer
      ..writeln(
        '  final page = ${route.importPrefix}.${route.functionName}(${_arguments(route)});',
      )
      ..writeln('  return page.buildRoutePage(context, state);');
  } else {
    buffer.writeln(
      '  return ${route.importPrefix}.${route.functionName}(${_arguments(route)});',
    );
  }
  buffer
    ..writeln('}')
    ..writeln();
}

void _emitLayoutBuilder(StringBuffer buffer, FileRouteSpec layout, int index) {
  buffer
    ..writeln('Widget _buildFileRouteLayout$index(')
    ..writeln('  BuildContext context,')
    ..writeln('  GoRouterState state,')
    ..writeln('  Widget child,')
    ..writeln(') => ${layout.importPrefix}.${layout.functionName}(')
    ..writeln('  ${_arguments(layout, childExpression: 'child')},')
    ..writeln(');')
    ..writeln();
}

void _emitGuardBuilder(StringBuffer buffer, FileRouteSpec guard, int index) {
  buffer
    ..writeln('String? _buildFileRouteGuard$index(')
    ..writeln('  BuildContext context,')
    ..writeln('  GoRouterState state,')
    ..writeln(') {')
    ..writeln(
      '  final redirect = ${guard.importPrefix}.${guard.functionName}(${_arguments(guard)});',
    )
    ..writeln(
      '  return redirect == null ? null : _resolveFileRouteRedirect(redirect);',
    )
    ..writeln('}')
    ..writeln();
}

void _emitRedirectResolver(StringBuffer buffer, List<FileRouteSpec> routes) {
  final targets = routes
      .where(
        (route) =>
            route.kind == FileRouteKind.page &&
            route.pathParameters.isEmpty &&
            route.queryParameters.every(
              (parameter) =>
                  parameter.defaultCode != null || parameter.isNullable,
            ),
      )
      .toList(growable: false);
  buffer.writeln(
    'String _resolveFileRouteRedirect(FileRouteRedirect redirect) {',
  );
  for (final route in targets) {
    final target = _pageTearOff(route);
    buffer
      ..writeln('  if (identical(redirect.target, $target)) {')
      ..writeln('    return const ${route.routeClassName}().location;')
      ..writeln('  }');
  }
  buffer
    ..writeln(
      "  throw StateError('A redirect must target a file page without required URL parameters.');",
    )
    ..writeln('}')
    ..writeln();
}

String _arguments(
  FileRouteSpec spec, {
  String childExpression = 'child',
  String errorExpression = 'error',
  String recoveryExpression = '() {}',
}) {
  final arguments = <String>[];
  for (final parameter in spec.parameters) {
    final expression = switch (parameter.kind) {
      RouteParameterKind.context => 'context',
      RouteParameterKind.state => 'state',
      RouteParameterKind.key => 'state.pageKey',
      RouteParameterKind.child => childExpression,
      RouteParameterKind.error => errorExpression,
      RouteParameterKind.recovery => recoveryExpression,
      RouteParameterKind.match => '_matchFileRoute(state)',
      RouteParameterKind.path || RouteParameterKind.query => parameter.name,
      RouteParameterKind.dependency =>
        'FileRouteScope.read<${parameter.dartType}>(context)',
    };
    arguments.add(
      parameter.isNamed ? '${parameter.name}: $expression' : expression,
    );
  }
  return arguments.join(', ');
}

void _emitRouterFactory(StringBuffer buffer, FileRouterSpec router) {
  final root = router.routes.where((route) => route.path == '/').firstOrNull;
  final initial = root == null
      ? router.routes.first.routeClassName
      : root.routeClassName;
  buffer
    ..writeln('GoRouter createFileRouter({')
    ..writeln('  String? initialLocation,')
    ..writeln(
      '  FileRouterConfiguration configuration = const FileRouterConfiguration(),',
    )
    ..writeln('}) {')
    ..writeln('  return GoRouter(')
    ..writeln('    navigatorKey: configuration.navigatorKey,')
    ..writeln(
      '    initialLocation: initialLocation ?? const $initial().location,',
    )
    ..writeln('    refreshListenable: configuration.refreshListenable,')
    ..writeln('    redirect: configuration.redirect,')
    ..writeln('    debugLogDiagnostics: configuration.debugLogDiagnostics,')
    ..writeln('    observers: configuration.observers,')
    ..writeln('    errorBuilder: (context, state) => _buildFileRouteNotFound(')
    ..writeln('      context, state, state.error ?? StateError(')
    ..writeln("        'No route matches \${state.uri.path}.',")
    ..writeln('      ),')
    ..writeln('    ),')
    ..writeln('    routes: [');
  final rootScope = _buildRouteScopeTree(router);
  _emitRootScope(buffer, router, rootScope, indent: '      ');
  buffer
    ..writeln('    ],')
    ..writeln('  );')
    ..writeln('}');
}

void _emitRouteMatcher(StringBuffer buffer, FileRouterSpec router) {
  buffer
    ..writeln('FileRouteMatch _matchFileRoute(GoRouterState state) {')
    ..writeln('  return switch (state.fullPath) {');
  for (final route in router.routes) {
    if (route.kind != FileRouteKind.page) continue;
    final target = _pageTearOff(route);
    buffer.writeln("    '${route.path}' => FileRouteMatch.page($target),");
  }
  buffer
    ..writeln('    _ => const FileRouteMatch.unknown(),')
    ..writeln('  };')
    ..writeln('}')
    ..writeln();
}

String _pageTearOff(FileRouteSpec route) =>
    '${route.importPrefix}.${route.functionName}'
    '${route.isPageFunction ? '' : '.new'}';

void _emitGoRoute(
  StringBuffer buffer,
  FileRouteSpec route,
  int index, {
  required String indent,
}) {
  buffer
    ..writeln('${indent}GoRoute(')
    ..writeln("$indent  path: '${route.path}',");
  if (route.kind == FileRouteKind.redirect) {
    buffer.writeln(
      '$indent  redirect: (context, state) => _resolveFileRouteRedirect('
      '${route.importPrefix}.${route.functionName}(${_arguments(route)})),',
    );
  } else if (route.buildsPage) {
    buffer.writeln('$indent  pageBuilder: _buildFileRoute$index,');
  } else {
    buffer.writeln('$indent  builder: _buildFileRoute$index,');
  }
  buffer.writeln('$indent),');
}

void _emitRootScope(
  StringBuffer buffer,
  FileRouterSpec router,
  _RouteScopeNode root, {
  required String indent,
}) {
  if (root.layout != null || root.guard != null) {
    _emitScopeShell(buffer, router, root, indent: indent);
    return;
  }
  _emitScopeEntries(buffer, router, root, indent: indent);
}

void _emitScopeShell(
  StringBuffer buffer,
  FileRouterSpec router,
  _RouteScopeNode node, {
  required String indent,
}) {
  buffer.writeln('${indent}ShellRoute(');
  if (node.layout case final layout?) {
    buffer.writeln(
      '$indent  builder: _buildFileRouteLayout${router.layouts.indexOf(layout)},',
    );
  }
  if (node.guard case final guard?) {
    buffer.writeln(
      '$indent  redirect: _buildFileRouteGuard${router.guards.indexOf(guard)},',
    );
  }
  buffer.writeln('$indent  routes: [');
  _emitScopeEntries(buffer, router, node, indent: '$indent    ');
  buffer
    ..writeln('$indent  ],')
    ..writeln('$indent),');
}

void _emitScopeEntries(
  StringBuffer buffer,
  FileRouterSpec router,
  _RouteScopeNode node, {
  required String indent,
}) {
  for (final route in node.routes) {
    _emitGoRoute(buffer, route, router.routes.indexOf(route), indent: indent);
  }
  for (final child in node.children) {
    _emitScopeShell(buffer, router, child, indent: indent);
  }
}

_RouteScopeNode _buildRouteScopeTree(FileRouterSpec router) {
  final nodes = <String, _RouteScopeNode>{'': _RouteScopeNode(const [])};
  _RouteScopeNode nodeFor(List<String> scope) =>
      nodes.putIfAbsent(scope.join('/'), () => _RouteScopeNode(scope));

  for (final layout in router.layouts) {
    nodeFor(layout.scope).layout = layout;
  }
  for (final guard in router.guards) {
    nodeFor(guard.scope).guard = guard;
  }

  final scopedNodes =
      nodes.values.where((node) => node.scope.isNotEmpty).toList()..sort(
        (left, right) => left.scope.length.compareTo(right.scope.length),
      );
  for (final node in scopedNodes) {
    final parent = nodes.values
        .where(
          (candidate) =>
              candidate.scope.length < node.scope.length &&
              _isScopePrefix(candidate.scope, node.scope),
        )
        .reduce(
          (left, right) =>
              left.scope.length > right.scope.length ? left : right,
        );
    parent.children.add(node);
  }

  for (final route in router.routes) {
    final owner = nodes.values
        .where((node) => _isScopePrefix(node.scope, route.scope))
        .reduce(
          (left, right) =>
              left.scope.length > right.scope.length ? left : right,
        );
    owner.routes.add(route);
  }
  for (final node in nodes.values) {
    node.children.sort(
      (left, right) => left.scope.join('/').compareTo(right.scope.join('/')),
    );
  }
  return nodes['']!;
}

bool _isScopePrefix(List<String> prefix, List<String> value) {
  if (prefix.length > value.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (prefix[index] != value[index]) return false;
  }
  return true;
}

final class _RouteScopeNode {
  _RouteScopeNode(this.scope);

  final List<String> scope;
  FileRouteSpec? layout;
  FileRouteSpec? guard;
  final List<FileRouteSpec> routes = [];
  final List<_RouteScopeNode> children = [];
}

String _queryDecodeExpression(RouteParameterSpec parameter, String raw) {
  final decode = _decodeExpression(parameter, '$raw!');
  if (parameter.defaultCode case final defaultCode?) {
    return '$raw == null ? $defaultCode : $decode';
  }
  if (parameter.isNullable) return '$raw == null ? null : $decode';
  return '$raw == null '
      "? throw const FormatException('Missing query `${_queryName(parameter.name)}`.') "
      ': $decode';
}

String _queryName(String source) => source
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]}-${match[2]}',
    )
    .replaceAll('_', '-')
    .toLowerCase();

String _decodeExpression(RouteParameterSpec parameter, String raw) {
  final nonNullable = parameter.dartType.replaceAll('?', '');
  return switch (parameter.codec!) {
    RouteCodec.string => raw,
    RouteCodec.integer => 'int.parse($raw)',
    RouteCodec.decimal => 'double.parse($raw)',
    RouteCodec.boolean => '_decodeRouteBool($raw)',
    RouteCodec.dateTime => 'DateTime.parse($raw).toUtc()',
    RouteCodec.enumeration => '$nonNullable.values.byName($raw)',
    RouteCodec.localId =>
      'parseLocalId<${parameter.localIdTypeArgument}>($raw)',
  };
}

String _encodeExpression(RouteParameterSpec parameter, String source) {
  return switch (parameter.codec!) {
    RouteCodec.string => source,
    RouteCodec.integer ||
    RouteCodec.decimal ||
    RouteCodec.boolean => '$source.toString()',
    RouteCodec.dateTime => '$source.toUtc().toIso8601String()',
    RouteCodec.enumeration => '$source.name',
    RouteCodec.localId => '$source.value',
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
