import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

Future<FileRouterSpec> parseFileRouter(BuildStep buildStep) async {
  final presentationAssets = <AssetId>{
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/*.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/**/*.dart'))
        .toList(),
  };
  for (final asset in presentationAssets) {
    final relative = asset.path.split('/presentation/').last;
    if (!relative.startsWith('pages/') && !relative.startsWith('components/')) {
      throw InvalidGenerationSourceError(
        'Feature presentation files must live under `pages/` or '
        '`components/`; found `${asset.path}`.',
      );
    }
  }
  final discovered = <AssetId>{
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/page.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/**/page.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/redirect.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/**/redirect.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/layout.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/**/layout.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/guard.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/**/guard.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/not_found.dart'))
        .toList(),
    ...await buildStep
        .findAssets(Glob('lib/features/*/presentation/pages/**/not_found.dart'))
        .toList(),
    buildStep.inputId,
  };
  final assets = discovered.toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final routes = <FileRouteSpec>[];
  final layouts = <FileRouteSpec>[];
  final guards = <FileRouteSpec>[];
  FileRouteSpec? notFound;
  for (var index = 0; index < assets.length; index++) {
    final parsed = await _parseAsset(buildStep, assets[index], index);
    switch (parsed.kind) {
      case FileRouteKind.layout:
        layouts.add(parsed);
      case FileRouteKind.guard:
        guards.add(parsed);
      case FileRouteKind.notFound:
        if (parsed.scope.isNotEmpty) {
          throw InvalidGenerationSourceError(
            'The typed error boundary must be at a feature page-tree root.',
          );
        }
        if (notFound != null) {
          throw InvalidGenerationSourceError(
            'Only one root feature not_found.dart is supported.',
          );
        }
        notFound = parsed;
      case FileRouteKind.page:
      case FileRouteKind.redirect:
        routes.add(parsed);
    }
  }
  _validateScopedFiles(layouts, 'layout');
  _validateScopedFiles(guards, 'guard');
  if (notFound == null) {
    throw InvalidGenerationSourceError(
      'Feature routing requires one root '
      '`lib/features/<feature>/presentation/pages/not_found.dart` '
      'as its typed error boundary.',
    );
  }
  _validateRoutes(routes);
  _validateScopeCoverage(layouts, routes, 'layout');
  _validateScopeCoverage(guards, routes, 'guard');
  routes.sort(_routeOrder);
  return FileRouterSpec(
    routes: List.unmodifiable(routes),
    layouts: List.unmodifiable(layouts),
    guards: List.unmodifiable(guards),
    notFound: notFound,
  );
}

Future<FileRouteSpec> _parseAsset(
  BuildStep buildStep,
  AssetId asset,
  int importIndex,
) async {
  final library = await buildStep.resolver.libraryFor(asset);
  if (asset.path.endsWith('/page.dart')) {
    return _parsePageAsset(library, asset, importIndex);
  }
  final functions = library.topLevelFunctions
      .where((function) => !function.name!.startsWith('_'))
      .toList();
  if (functions.length != 1) {
    throw InvalidGenerationSourceError(
      'Each route file must declare exactly one public top-level function.',
      element: functions.firstOrNull,
    );
  }
  final function = functions.single;
  final pathInfo = _pathFor(asset.path);
  final kind = switch (asset.path.split('/').last) {
    'layout.dart' => FileRouteKind.layout,
    'guard.dart' => FileRouteKind.guard,
    'not_found.dart' => FileRouteKind.notFound,
    'redirect.dart' => FileRouteKind.redirect,
    _ => throw InvalidGenerationSourceError(
      'Unsupported route convention `${asset.path}`.',
      element: function,
    ),
  };
  _validateFunctionName(function, kind);
  if ((kind == FileRouteKind.layout || kind == FileRouteKind.notFound) &&
      function.returnType.getDisplayString() != 'Widget') {
    throw InvalidGenerationSourceError(
      'Layout and not-found functions must return Widget.',
      element: function,
    );
  }
  if (kind == FileRouteKind.redirect &&
      function.returnType.getDisplayString() != 'FileRouteRedirect') {
    throw InvalidGenerationSourceError(
      'Redirect functions must return FileRouteRedirect.',
      element: function,
    );
  }
  if (kind == FileRouteKind.guard &&
      function.returnType.getDisplayString() != 'FileRouteRedirect?') {
    throw InvalidGenerationSourceError(
      'Guard functions must return FileRouteRedirect?.',
      element: function,
    );
  }
  final (:parameters, :typeImports) = _parseParameters(
    function.formalParameters,
    dynamicNames: pathInfo.$2,
    kind: kind,
    owner: function,
  );
  final package = asset.package;
  final relative = asset.path.substring('lib/'.length);
  final import = 'package:$package/$relative';
  typeImports.remove(import);
  typeImports.removeWhere(
    (uri) =>
        uri.startsWith('package:flutter/') ||
        uri.startsWith('package:go_router/') ||
        uri.startsWith('package:nodus/'),
  );
  return FileRouteSpec(
    assetImport: import,
    importPrefix: 'route$importIndex',
    functionName: function.name!,
    routeClassName: _routeClassName(function.name!, kind),
    path: pathInfo.$1,
    scope: List.unmodifiable(pathInfo.$3),
    kind: kind,
    parameters: List.unmodifiable(parameters),
    typeImports: typeImports.toList()..sort(),
    buildsPage: false,
    isPageFunction: false,
  );
}

FileRouteSpec _parsePageAsset(
  LibraryElement library,
  AssetId asset,
  int importIndex,
) {
  final pageClasses = library.classes
      .where(
        (candidate) =>
            candidate.name != null && candidate.name!.endsWith('Page'),
      )
      .toList(growable: false);
  final pageFunctions = library.topLevelFunctions
      .where(
        (candidate) =>
            candidate.name != null &&
            !candidate.name!.startsWith('_') &&
            candidate.name!.endsWith('Page'),
      )
      .toList(growable: false);
  if (pageClasses.length + pageFunctions.length != 1) {
    throw InvalidGenerationSourceError(
      'Each page.dart must contain exactly one public page entry: either a '
      'Widget class or a top-level Widget function ending in `Page`.',
      element: pageClasses.firstOrNull ?? pageFunctions.firstOrNull,
    );
  }
  final pageFunction = pageFunctions.firstOrNull;
  if (pageFunction != null) {
    if (pageFunction.returnType.getDisplayString() != 'Widget') {
      throw InvalidGenerationSourceError(
        '`${pageFunction.name}` must return Widget.',
        element: pageFunction,
      );
    }
    _validateFunctionName(pageFunction, FileRouteKind.page);
    return _pageSpec(
      asset: asset,
      importIndex: importIndex,
      name: pageFunction.name!,
      formalParameters: pageFunction.formalParameters,
      owner: pageFunction,
      buildsPage: false,
      isPageFunction: true,
    );
  }

  final page = pageClasses.single;
  if (!page.allSupertypes.any((type) => type.element.name == 'Widget')) {
    throw InvalidGenerationSourceError(
      '`${page.name}` must be a Flutter Widget.',
      element: page,
    );
  }
  final constructor = page.unnamedConstructor;
  if (constructor == null) {
    throw InvalidGenerationSourceError(
      '`${page.name}` must expose one unnamed constructor as its route contract.',
      element: page,
    );
  }
  return _pageSpec(
    asset: asset,
    importIndex: importIndex,
    name: page.name!,
    formalParameters: constructor.formalParameters,
    owner: constructor,
    buildsPage: page.allSupertypes.any(
      (type) => type.element.name == 'FileRoutePagePresentation',
    ),
    isPageFunction: false,
  );
}

FileRouteSpec _pageSpec({
  required AssetId asset,
  required int importIndex,
  required String name,
  required List<FormalParameterElement> formalParameters,
  required Element owner,
  required bool buildsPage,
  required bool isPageFunction,
}) {
  final pathInfo = _pathFor(asset.path);
  final (:parameters, :typeImports) = _parseParameters(
    formalParameters,
    dynamicNames: pathInfo.$2,
    kind: FileRouteKind.page,
    owner: owner,
  );
  final package = asset.package;
  final relative = asset.path.substring('lib/'.length);
  final import = 'package:$package/$relative';
  typeImports.removeWhere(
    (uri) =>
        uri.startsWith('package:flutter/') ||
        uri.startsWith('package:go_router/') ||
        uri.startsWith('package:nodus/'),
  );
  return FileRouteSpec(
    assetImport: import,
    importPrefix: 'route$importIndex',
    functionName: name,
    routeClassName: _routeClassName(name, FileRouteKind.page),
    path: pathInfo.$1,
    scope: List.unmodifiable(pathInfo.$3),
    kind: FileRouteKind.page,
    parameters: List.unmodifiable(parameters),
    typeImports: typeImports.toList()..sort(),
    buildsPage: buildsPage,
    isPageFunction: isPageFunction,
  );
}

({List<RouteParameterSpec> parameters, Set<String> typeImports})
_parseParameters(
  List<FormalParameterElement> formalParameters, {
  required List<String> dynamicNames,
  required FileRouteKind kind,
  required Element owner,
}) {
  final parameters = <RouteParameterSpec>[];
  final typeImports = <String>{};
  final requiredElementsByImport = <String, Set<Element>>{};
  final librariesByImport = <String, LibraryElement>{};
  for (final parameter in formalParameters) {
    final type = parameter.type;
    final typeName = type.getDisplayString();
    final parameterKind = _parameterKind(
      parameter,
      typeName,
      dynamicNames,
      kind,
    );
    final codec = switch (parameterKind) {
      RouteParameterKind.path ||
      RouteParameterKind.query => _codecFor(type, parameter),
      _ => null,
    };
    if ((kind == FileRouteKind.redirect || kind == FileRouteKind.guard) &&
        (parameterKind == RouteParameterKind.path ||
            parameterKind == RouteParameterKind.query)) {
      throw InvalidGenerationSourceError(
        'Redirects and guards read URL input from GoRouterState; their other parameters must be injected dependencies.',
        element: parameter,
      );
    }
    final defaultCode = parameter.defaultValueCode;
    if (parameterKind == RouteParameterKind.query &&
        !parameter.isRequiredNamed &&
        defaultCode == null &&
        type.nullabilitySuffix != NullabilitySuffix.question) {
      throw InvalidGenerationSourceError(
        'Optional query `${parameter.name}` must be nullable or declare a Dart default.',
        element: parameter,
      );
    }
    if (parameterKind == RouteParameterKind.path &&
        (type.nullabilitySuffix == NullabilitySuffix.question ||
            (!parameter.isRequiredNamed && parameter.isNamed))) {
      throw InvalidGenerationSourceError(
        'Dynamic path `${parameter.name}` must be required and non-null.',
        element: parameter,
      );
    }
    if (parameterKind == RouteParameterKind.dependency && parameter.isNamed) {
      throw InvalidGenerationSourceError(
        'Route dependencies are required positional parameters; named parameters are inferred as URL queries.',
        element: parameter,
      );
    }
    _collectTypeImports(
      type,
      typeImports,
      requiredElementsByImport,
      librariesByImport,
    );
    parameters.add(
      RouteParameterSpec(
        name: parameter.name!,
        dartType: typeName,
        kind: parameterKind,
        isNamed: parameter.isNamed,
        isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
        isRequired: parameter.isRequiredNamed || parameter.isRequiredPositional,
        defaultCode: defaultCode,
        codec: codec,
        localIdTypeArgument: _localIdArgument(typeName),
      ),
    );
  }
  for (final dynamicName in dynamicNames) {
    if (!parameters.any(
      (parameter) =>
          parameter.name == dynamicName &&
          parameter.kind == RouteParameterKind.path,
    )) {
      throw InvalidGenerationSourceError(
        'Folder `[$dynamicName]` requires a page entry parameter named `$dynamicName`.',
        element: owner,
      );
    }
  }
  _removeImportsCoveredByReexports(
    typeImports,
    requiredElementsByImport,
    librariesByImport,
  );
  return (parameters: parameters, typeImports: typeImports);
}

(String, List<String>, List<String>) _pathFor(String assetPath) {
  final match = RegExp(
    r'^lib/features/[^/]+/presentation/pages/(.*)$',
  ).firstMatch(assetPath);
  if (match == null) {
    throw InvalidGenerationSourceError(
      'Feature pages must live under '
      '`lib/features/<feature>/presentation/pages/`.',
    );
  }
  final relative = match.group(1)!;
  final parts = relative.split('/')..removeLast();
  final pathParts = <String>[];
  final dynamicNames = <String>[];
  for (final part in parts) {
    if (part.startsWith('(') && part.endsWith(')')) continue;
    final dynamic = RegExp(r'^\[([a-zA-Z_][a-zA-Z0-9_]*)\]$').firstMatch(part);
    if (dynamic != null) {
      final name = dynamic.group(1)!;
      dynamicNames.add(name);
      pathParts.add(':$name');
      continue;
    }
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(part)) {
      throw InvalidGenerationSourceError(
        'Static route folders must use lowercase kebab-case: `$part`.',
      );
    }
    pathParts.add(part);
  }
  return ('/${pathParts.join('/')}', dynamicNames, parts);
}

RouteParameterKind _parameterKind(
  FormalParameterElement parameter,
  String typeName,
  List<String> dynamicNames,
  FileRouteKind routeKind,
) {
  if (typeName == 'BuildContext') return RouteParameterKind.context;
  if (typeName == 'GoRouterState') return RouteParameterKind.state;
  if (typeName == 'Key' || typeName == 'Key?') return RouteParameterKind.key;
  if (typeName == 'FileRouteMatch') return RouteParameterKind.match;
  if (routeKind == FileRouteKind.layout && typeName == 'Widget') {
    return RouteParameterKind.child;
  }
  if (routeKind == FileRouteKind.notFound && parameter.name == 'error') {
    return RouteParameterKind.error;
  }
  if (routeKind == FileRouteKind.notFound && parameter.name == 'recover') {
    if (typeName != 'VoidCallback' && typeName != 'void Function()') {
      throw InvalidGenerationSourceError(
        'The not-found `recover` parameter must be a VoidCallback.',
        element: parameter,
      );
    }
    return RouteParameterKind.recovery;
  }
  if (dynamicNames.contains(parameter.name)) return RouteParameterKind.path;
  if (parameter.isNamed) return RouteParameterKind.query;
  return RouteParameterKind.dependency;
}

RouteCodec _codecFor(DartType type, Element element) {
  final nonNullable = type.getDisplayString().replaceAll('?', '');
  if (nonNullable.startsWith('LocalId<')) return RouteCodec.localId;
  if (type is InterfaceType && type.element is EnumElement) {
    return RouteCodec.enumeration;
  }
  return switch (nonNullable) {
    'String' => RouteCodec.string,
    'int' => RouteCodec.integer,
    'double' => RouteCodec.decimal,
    'bool' => RouteCodec.boolean,
    'DateTime' => RouteCodec.dateTime,
    _ => throw InvalidGenerationSourceError(
      'Unsupported route parameter type `$nonNullable`.',
      element: element,
    ),
  };
}

void _collectTypeImports(
  DartType type,
  Set<String> imports,
  Map<String, Set<Element>> requiredElementsByImport,
  Map<String, LibraryElement> librariesByImport,
) {
  if (type is! InterfaceType) return;
  final library = type.element.library;
  final uri = library.uri;
  if (uri.scheme == 'package' && !uri.path.startsWith('dart:')) {
    final import = Uri.decodeFull(uri.toString());
    imports.add(import);
    (requiredElementsByImport[import] ??= {}).add(type.element);
    librariesByImport[import] = library;
  }
  for (final argument in type.typeArguments) {
    _collectTypeImports(
      argument,
      imports,
      requiredElementsByImport,
      librariesByImport,
    );
  }
}

void _removeImportsCoveredByReexports(
  Set<String> imports,
  Map<String, Set<Element>> requiredElementsByImport,
  Map<String, LibraryElement> librariesByImport,
) {
  final retained = imports.toSet();
  final candidates = imports.toList()..sort();
  for (final candidate in candidates) {
    final required = requiredElementsByImport[candidate] ?? const <Element>{};
    final covered = required.every((element) {
      final name = element.name;
      if (name == null) return false;
      return retained.any((other) {
        if (other == candidate) return false;
        final library = librariesByImport[other];
        return identical(library?.exportNamespace.get2(name), element);
      });
    });
    if (covered) retained.remove(candidate);
  }
  imports
    ..clear()
    ..addAll(retained);
}

String? _localIdArgument(String typeName) {
  return RegExp(r'LocalId<(.+)>').firstMatch(typeName)?.group(1);
}

void _validateFunctionName(
  TopLevelFunctionElement function,
  FileRouteKind kind,
) {
  final expectedSuffix = switch (kind) {
    FileRouteKind.page || FileRouteKind.notFound => 'Page',
    FileRouteKind.redirect => 'Redirect',
    FileRouteKind.layout => 'Layout',
    FileRouteKind.guard => 'Guard',
  };
  if (!function.name!.endsWith(expectedSuffix)) {
    throw InvalidGenerationSourceError(
      '`${function.name}` must end in `$expectedSuffix` so its generated API name is deterministic.',
      element: function,
    );
  }
}

String _routeClassName(String functionName, FileRouteKind kind) {
  final suffix = switch (kind) {
    FileRouteKind.page || FileRouteKind.notFound => 'Page',
    FileRouteKind.redirect => 'Redirect',
    FileRouteKind.layout => 'Layout',
    FileRouteKind.guard => 'Guard',
  };
  final stem = functionName.substring(0, functionName.length - suffix.length);
  return '${stem[0].toUpperCase()}${stem.substring(1)}Route';
}

void _validateScopedFiles(List<FileRouteSpec> specs, String kind) {
  final scopes = <String>{};
  for (final spec in specs) {
    final key = spec.scope.join('/');
    if (!scopes.add(key)) {
      throw InvalidGenerationSourceError(
        'Only one $kind is allowed in route scope `${key.isEmpty ? '/' : key}`.',
      );
    }
  }
}

void _validateScopeCoverage(
  List<FileRouteSpec> specs,
  List<FileRouteSpec> routes,
  String kind,
) {
  for (final spec in specs) {
    final hasRoute = routes.any(
      (route) => _isScopePrefix(spec.scope, route.scope),
    );
    if (!hasRoute) {
      throw InvalidGenerationSourceError(
        'Route $kind `${spec.assetImport}` has no descendant page.',
      );
    }
  }
}

bool _isScopePrefix(List<String> prefix, List<String> value) {
  if (prefix.length > value.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (prefix[index] != value[index]) return false;
  }
  return true;
}

void _validateRoutes(List<FileRouteSpec> routes) {
  final paths = <String>{};
  final classes = <String>{};
  for (final route in routes) {
    if (!paths.add(route.path)) {
      throw InvalidGenerationSourceError(
        'Duplicate file route `${route.path}`.',
      );
    }
    if (!classes.add(route.routeClassName)) {
      throw InvalidGenerationSourceError(
        'Duplicate generated route class `${route.routeClassName}`.',
      );
    }
  }
}

int _routeOrder(FileRouteSpec left, FileRouteSpec right) {
  int dynamicCount(FileRouteSpec route) => ':'.allMatches(route.path).length;
  final byDynamic = dynamicCount(left).compareTo(dynamicCount(right));
  if (byDynamic != 0) return byDynamic;
  final byDepth = left.path
      .split('/')
      .length
      .compareTo(right.path.split('/').length);
  if (byDepth != 0) return byDepth;
  return left.path.compareTo(right.path);
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
