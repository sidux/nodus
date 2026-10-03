/// The branch of the generated change-recipients function for [entityType],
/// or an empty string when its changes are not addressed to anyone.
String changeRecipientsCase(String sql, String entityType) {
  final start = sql.indexOf("    when '$entityType' then\n");
  if (start < 0) return '';
  final rest = sql.substring(start + 1);
  final next = RegExp(r"\n    (when '|else\n)").firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}
