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
  });

  static const formatVersion = 1;

  final String packageName;
  final String graphName;
  final int schemaVersion;
  final List<String> targets;
  final String? defaultTarget;
  final String? schemaFingerprint;

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
    final schemaFingerprint = json['schemaFingerprint'];
    if (schemaFingerprint != null &&
        (schemaFingerprint is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(schemaFingerprint))) {
      throw const FormatException(
        'nodus.lock schemaFingerprint must be null or one SHA-256 digest.',
      );
    }
    return NodusLock(
      packageName: packageName,
      graphName: graphName,
      schemaVersion: schemaVersion,
      targets: List.unmodifiable(targets),
      defaultTarget: defaultTarget,
      schemaFingerprint: schemaFingerprint as String?,
    );
  }

  NodusLock copyWith({int? schemaVersion, String? schemaFingerprint}) =>
      NodusLock(
        packageName: packageName,
        graphName: graphName,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        targets: targets,
        defaultTarget: defaultTarget,
        schemaFingerprint: schemaFingerprint ?? this.schemaFingerprint,
      );

  String encode() {
    final encoder = const JsonEncoder.withIndent('  ');
    final json = <String, Object?>{
      'formatVersion': formatVersion,
      'packageName': packageName,
      'graphName': graphName,
      'schemaVersion': schemaVersion,
      'schemaFingerprint': schemaFingerprint,
      'targets': targets,
      'defaultTarget': defaultTarget,
    };
    return '${encoder.convert(json)}\n';
  }
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
