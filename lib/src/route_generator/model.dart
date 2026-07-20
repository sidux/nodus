enum FileRouteKind { page, redirect, layout, guard, notFound }

enum RouteParameterKind {
  context,
  state,
  key,
  child,
  error,
  recovery,
  match,
  path,
  query,
  dependency,
}

enum RouteCodec {
  string,
  integer,
  decimal,
  boolean,
  dateTime,
  enumeration,
  localId,
}

final class FileRouteSpec {
  const FileRouteSpec({
    required this.assetImport,
    required this.importPrefix,
    required this.functionName,
    required this.routeClassName,
    required this.path,
    required this.scope,
    required this.kind,
    required this.parameters,
    required this.typeImports,
    required this.buildsPage,
    required this.isPageFunction,
  });

  final String assetImport;
  final String importPrefix;
  final String functionName;
  final String routeClassName;
  final String path;
  final List<String> scope;
  final FileRouteKind kind;
  final List<RouteParameterSpec> parameters;
  final List<String> typeImports;
  final bool buildsPage;
  final bool isPageFunction;

  List<RouteParameterSpec> get pathParameters => parameters
      .where((parameter) => parameter.kind == RouteParameterKind.path)
      .toList(growable: false);

  List<RouteParameterSpec> get queryParameters => parameters
      .where((parameter) => parameter.kind == RouteParameterKind.query)
      .toList(growable: false);
}

final class RouteParameterSpec {
  const RouteParameterSpec({
    required this.name,
    required this.dartType,
    required this.kind,
    required this.isNamed,
    required this.isNullable,
    required this.isRequired,
    required this.defaultCode,
    required this.codec,
    required this.localIdTypeArgument,
  });

  final String name;
  final String dartType;
  final RouteParameterKind kind;
  final bool isNamed;
  final bool isNullable;
  final bool isRequired;
  final String? defaultCode;
  final RouteCodec? codec;
  final String? localIdTypeArgument;
}

final class FileRouterSpec {
  const FileRouterSpec({
    required this.routes,
    required this.layouts,
    required this.guards,
    required this.notFound,
  });

  final List<FileRouteSpec> routes;
  final List<FileRouteSpec> layouts;
  final List<FileRouteSpec> guards;
  final FileRouteSpec notFound;
}
