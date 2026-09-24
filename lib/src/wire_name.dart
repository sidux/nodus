/// Canonical snake_case spelling that generation derives from a Dart
/// identifier for tables, columns, and persisted enum values.
String wireNameOf(String identifier) => identifier
    .replaceAllMapped(
      RegExp('([A-Z]+)([A-Z][a-z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toLowerCase();

/// The persisted and synchronized spelling of an enum value.
extension EnumWireName on Enum {
  /// For example `TaskStatus.inProgress.wireName == 'in_progress'`.
  String get wireName => wireNameOf(name);
}

/// Wire-name lookups mirroring `values.byName` and `values.asNameMap`.
extension EnumWireNames<T extends Enum> on List<T> {
  /// The value whose [EnumWireName.wireName] is [wireName].
  ///
  /// Throws an [ArgumentError] for an unknown name, like `byName`.
  T byWireName(String wireName) =>
      asWireNameMap()[wireName] ??
      (throw ArgumentError.value(wireName, 'wireName', 'No enum value'));

  Map<String, T> asWireNameMap() => {
    for (final value in this) value.wireName: value,
  };
}
