import 'dart:convert';

/// Tool-owned package graph configuration committed as `nodus.lock`.
///
/// The lock is intentionally JSON: build_runner can read it as a package
/// asset without introducing a handwritten Dart graph root.
final class NodusLock {
  const NodusLock({
    required this.packageName,
    required this.graphName,
    required this.schemaVersion,
    required this.targets,
    required this.defaultTarget,
    this.schemaFingerprint,
    this.localSchemaFingerprint,
    this.sourceBoundaries = const [],
  });

  static const formatVersion = 1;

  final String packageName;
  final String graphName;
  final int schemaVersion;
  final List<String> targets;
  final String? defaultTarget;
  final String? schemaFingerprint;

  /// Fingerprint of the declarations [schemaVersion] describes locally.
  final String? localSchemaFingerprint;
  final List<NodusSourceBoundary> sourceBoundaries;

  factory NodusLock.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('nodus.lock must contain one JSON object.');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (json['formatVersion'] != formatVersion) {
      throw FormatException(
        'Unsupported nodus.lock formatVersion `${json['formatVersion']}`.',
      );
    }
    final packageName = _requiredIdentifier(json, 'packageName');
    final graphName = _requiredIdentifier(json, 'graphName');
    if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(graphName) ||
        _dartReservedWords.contains(graphName)) {
      throw const FormatException(
        'nodus.lock graphName must be a public UpperCamelCase Dart type name.',
      );
    }
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int || schemaVersion < 1) {
      throw const FormatException(
        'nodus.lock schemaVersion must be a positive integer.',
      );
    }
    final rawTargets = json['targets'];
    if (rawTargets is! List || rawTargets.isEmpty) {
      throw const FormatException(
        'nodus.lock targets must contain at least one target.',
      );
    }
    final targets = <String>[];
    for (final target in rawTargets) {
      if (target is! String || !isValidNodusTargetName(target)) {
        throw FormatException('Invalid Nodus target `$target`.');
      }
      if (!targets.addUnique(target)) {
        throw FormatException('Duplicate Nodus target `$target`.');
      }
    }
    final defaultTarget = json['defaultTarget'];
    if (defaultTarget is! String || !targets.contains(defaultTarget)) {
      throw const FormatException(
        'nodus.lock defaultTarget must name one configured target.',
      );
    }
    final schemaFingerprint = _optionalDigest(json, 'schemaFingerprint');
    final localSchemaFingerprint = _optionalDigest(
      json,
      'localSchemaFingerprint',
    );
    final sourceBoundaries = _decodeSourceBoundaries(json['sourceBoundaries']);
    return NodusLock(
      packageName: packageName,
      graphName: graphName,
      schemaVersion: schemaVersion,
      targets: List.unmodifiable(targets),
      defaultTarget: defaultTarget,
      schemaFingerprint: schemaFingerprint,
      localSchemaFingerprint: localSchemaFingerprint,
      sourceBoundaries: sourceBoundaries,
    );
  }

  NodusLock copyWith({
    int? schemaVersion,
    String? schemaFingerprint,
    String? localSchemaFingerprint,
  }) => NodusLock(
    packageName: packageName,
    graphName: graphName,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    targets: targets,
    defaultTarget: defaultTarget,
    schemaFingerprint: schemaFingerprint ?? this.schemaFingerprint,
    localSchemaFingerprint:
        localSchemaFingerprint ?? this.localSchemaFingerprint,
    sourceBoundaries: sourceBoundaries,
  );

  String encode() {
    final encoder = const JsonEncoder.withIndent('  ');
    final json = <String, Object?>{
      'formatVersion': formatVersion,
      'packageName': packageName,
      'graphName': graphName,
      'schemaVersion': schemaVersion,
      'schemaFingerprint': schemaFingerprint,
      if (localSchemaFingerprint != null)
        'localSchemaFingerprint': localSchemaFingerprint,
      'targets': targets,
      'defaultTarget': defaultTarget,
      if (sourceBoundaries.isNotEmpty)
        'sourceBoundaries': [
          for (final boundary in sourceBoundaries) boundary.toJson(),
        ],
    };
    return '${encoder.convert(json)}\n';
  }
}

/// One opt-in source dependency boundary enforced by `nodus check`.
final class NodusSourceBoundary {
  const NodusSourceBoundary({
    required this.name,
    required this.sourceDirectories,
    this.forbiddenDirectories = const [],
    this.forbiddenPackages = const [],
  });

  final String name;
  final List<String> sourceDirectories;
  final List<String> forbiddenDirectories;
  final List<String> forbiddenPackages;

  Map<String, Object?> toJson() => {
    'name': name,
    'sourceDirectories': sourceDirectories,
    if (forbiddenDirectories.isNotEmpty)
      'forbiddenDirectories': forbiddenDirectories,
    if (forbiddenPackages.isNotEmpty) 'forbiddenPackages': forbiddenPackages,
  };
}

List<NodusSourceBoundary> _decodeSourceBoundaries(Object? source) {
  if (source == null) return const [];
  if (source is! List) {
    throw const FormatException('nodus.lock sourceBoundaries must be a list.');
  }
  final result = <NodusSourceBoundary>[];
  final names = <String>{};
  for (final raw in source) {
    if (raw is! Map) {
      throw const FormatException(
        'Each nodus.lock source boundary must be an object.',
      );
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final name = _requiredIdentifier(json, 'name');
    if (!names.add(name)) {
      throw FormatException('Duplicate source boundary `$name`.');
    }
    final forbiddenDirectories = _optionalPathSegments(
      json,
      'forbiddenDirectories',
    );
    final forbiddenPackages = _optionalPackagePrefixes(
      json,
      'forbiddenPackages',
    );
    if (forbiddenDirectories.isEmpty && forbiddenPackages.isEmpty) {
      throw const FormatException(
        'A nodus.lock source boundary must forbid at least one directory or '
        'package prefix.',
      );
    }
    result.add(
      NodusSourceBoundary(
        name: name,
        sourceDirectories: _requiredPathSegments(json, 'sourceDirectories'),
        forbiddenDirectories: forbiddenDirectories,
        forbiddenPackages: forbiddenPackages,
      ),
    );
  }
  return List.unmodifiable(result);
}

List<String> _requiredPathSegments(Map<String, Object?> json, String key) =>
    _requiredUniqueStrings(json, key, RegExp(r'^[A-Za-z][A-Za-z0-9_]*$'));

List<String> _optionalPathSegments(Map<String, Object?> json, String key) =>
    _optionalUniqueStrings(json, key, RegExp(r'^[A-Za-z][A-Za-z0-9_]*$'));

List<String> _optionalPackagePrefixes(Map<String, Object?> json, String key) =>
    _optionalUniqueStrings(json, key, RegExp(r'^[a-z][a-z0-9_]*$'));

List<String> _optionalUniqueStrings(
  Map<String, Object?> json,
  String key,
  RegExp pattern,
) {
  final raw = json[key];
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('nodus.lock source boundary $key must be a list.');
  }
  final result = <String>[];
  for (final value in raw) {
    if (value is! String ||
        !pattern.hasMatch(value) ||
        !result.addUnique(value)) {
      throw FormatException('Invalid or duplicate source boundary $key value.');
    }
  }
  return List.unmodifiable(result);
}

List<String> _requiredUniqueStrings(
  Map<String, Object?> json,
  String key,
  RegExp pattern,
) {
  final raw = json[key];
  if (raw is! List || raw.isEmpty) {
    throw FormatException('nodus.lock source boundary $key must be non-empty.');
  }
  final result = <String>[];
  for (final value in raw) {
    if (value is! String ||
        !pattern.hasMatch(value) ||
        !result.addUnique(value)) {
      throw FormatException('Invalid or duplicate source boundary $key value.');
    }
  }
  return List.unmodifiable(result);
}

final _wireName = RegExp(r'^[a-z][a-z0-9_]*$');
final _dartIdentifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
const _dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

String _lowerCamel(String value) {
  final parts = value.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join();
}

bool isValidNodusTargetName(String value) =>
    _wireName.hasMatch(value) &&
    !_dartReservedWords.contains(_lowerCamel(value)) &&
    !_generatedFactoryTargetNames.contains(value);

const _generatedFactoryTargetNames = {'in_memory', 'with_connectors'};

String? _optionalDigest(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw FormatException(
      'nodus.lock $key must be null or one SHA-256 digest.',
    );
  }
  return value;
}

String _requiredIdentifier(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || !_dartIdentifier.hasMatch(value)) {
    throw FormatException('nodus.lock $key must be a Dart identifier.');
  }
  return value;
}

extension on List<String> {
  bool addUnique(String value) {
    if (contains(value)) return false;
    add(value);
    return true;
  }
}
