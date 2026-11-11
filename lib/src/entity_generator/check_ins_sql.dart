import 'dart:convert';

import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'check_ins.dart';
import 'model.dart';

/// SQL for every declared check-in log: the part-of-day function of each
/// part enum and the check-in and undo functions, applied through the
/// generated push functions as the calling account.
String emitCheckInsSql(EntityGraphSpec graph) {
  final logs = [
    for (final log in graph.entities)
      if (log.checkIns != null) CheckInsSql(ResolvedCheckIns.of(log, graph)),
  ];
  if (logs.isEmpty) return '';
  final buffer = StringBuffer()
    ..writeln('-- Check-in rules declared in Nodus.')
    ..writeln();
  final signatures = <String>[];
  final partFunctions = <String>{};
  for (final log in logs) {
    if (partFunctions.add(log.resolved.partAtSql)) {
      buffer.writeln(log.partAtSql());
      signatures.add('${log.resolved.partAtSql}(timestamptz, text)');
    }
    buffer
      ..writeln(log.checkInSql())
      ..writeln(log.logDaySql())
      ..writeln(log.owesSql())
      ..writeln(log.undoSql());
    signatures
      ..add('${log.resolved.checkInFunction}(uuid, jsonb)')
      ..add('${log.resolved.undoFunction}(uuid, jsonb)')
      ..add('${log.resolved.logDayFunction}(uuid, jsonb)')
      ..add('${log.resolved.owesFunction}(uuid, date)');
  }
  for (final signature in signatures) {
    buffer
      ..writeln(
        'revoke all on function $signature from public, anon, authenticated, '
        'service_role;',
      )
      ..writeln('grant execute on function $signature to authenticated;');
  }
  return buffer.toString();
}

/// The SQL form of one declared check-in log.
final class CheckInsSql {
  CheckInsSql(this.resolved);

  final ResolvedCheckIns resolved;

  EntitySpec get log => resolved.log;
  EntitySpec get subject => resolved.subject;
  String get logTable => 'public.${log.tableName}';
  String get subjectTable => 'public.${subject.tableName}';

  String partAtSql() {
    final cases = [
      for (final (name, hour) in resolved.dayParts.starts.reversed)
        if (hour > 0) 'when hour >= $hour then ${_quote(resolved.wire(name))}',
    ];
    return '''
create or replace function ${resolved.partAtSql}(p_moment timestamptz, p_timezone text)
returns text
language sql
stable
set search_path = ''
as \$\$
  select case ${cases.join(' ')} else ${_quote(resolved.wire(resolved.dayParts.starts.first.$1))} end
  from (select extract(hour from p_moment at time zone p_timezone)::int as hour) moment
\$\$;
''';
  }

  /// Declarations and the opening checks both functions share.
  String _prelude(String partArgument, {List<String> declarations = const []}) {
    final flags = resolved.scheduledParts.columnName;
    final parts = [
      for (final (name, _) in resolved.dayParts.starts) name,
      resolved.dayParts.wholeDay,
    ];
    final bits = [
      for (final name in parts)
        'when ${_quote(resolved.wire(name))} then ${resolved.bit(name)}',
    ];
    return '''
declare
  subject $subjectTable;
  item $logTable;
  now_at timestamptz := now();
  zone text := coalesce(
    (select profile.${resolved.timezone.columnName} from public.${resolved.owner.tableName} profile where profile.id = auth.uid()),
    'UTC'
  );
  today date := (now_at at time zone zone)::date;
  current_part text := ${resolved.partAtSql}(now_at, zone);
  requested text := coalesce(nullif(p_arguments ->> ${_quote(partArgument)}, ''), current_part);
  whole_day boolean;
  slot text;
  interval_active boolean;
  result uuid[] := '{}';
${[for (final declaration in declarations) '  $declaration'].join('\n')}
begin
  select * into subject from $subjectTable subject_row
  where subject_row.id = p_subject_id${subject.hasSoftDeletableCapability ? ' and subject_row.deleted_at is null' : ''};
  if subject.id is null then
    raise exception '${_capitalized(_words(subject.className))} not found' using errcode = 'P0002';
  end if;
  if (case requested ${bits.join(' ')} end) is null then
    raise exception 'Unknown ${_words(resolved.part.name)} "%"', requested using errcode = '22023';
  end if;
  whole_day := (subject.$flags & ${resolved.bit(resolved.dayParts.wholeDay)}) <> 0;
  slot := case when whole_day then ${_quote(resolved.wire(resolved.dayParts.wholeDay))} else requested end;
  interval_active := ${_intervalActive('subject')};''';
  }

  String _intervalActive(String row) {
    final checks = [
      for (final (_, _, _, field) in resolved.intervals)
        '$row.${field.columnName} is not null',
    ];
    return checks.isEmpty ? 'false' : '(${checks.join(' or ')})';
  }

  String checkInSql() {
    final spec = resolved.spec;
    final part = resolved.part.name;
    final subjectWords = _words(subject.className);
    final partWords = _words(part);
    final at = resolved.at.columnName;
    final refusals = [
      for (final refusal in spec.refusals)
        '  if subject.${_column(subject, refusal.fieldName)} then\n'
            "    raise exception ${_quote(refusal.message)} using errcode = '22023';\n"
            '  end if;',
    ];
    final due = [
      for (final (every, _, _, field) in resolved.intervals)
        every.days
            ? '(subject.${field.columnName} is not null and today < (item.$at at time zone zone)::date + subject.${field.columnName}::int)'
            : '(subject.${field.columnName} is not null and now_at < item.$at + make_interval(hours => subject.${field.columnName}::int))',
    ];
    final detailPatch = [
      "${_quote(resolved.at.name)}, to_jsonb(now_at)",
      for (final field in resolved.details)
        '${_quote(field.name)}, coalesce(p_arguments -> ${_quote(field.name)}, ${_defaultJson(field)})',
    ].join(', ');
    return '''
create or replace function ${resolved.checkInFunction}(
  p_subject_id uuid,
  p_arguments jsonb
)
returns uuid
language plpgsql
volatile
set search_path = ''
as \$\$
${_prelude(part)}
${refusals.join('\n')}
  if not whole_day and (subject.${resolved.scheduledParts.columnName} & (case requested ${_bitCases()} end)) = 0 then
    raise exception ${_quote('The $subjectWords is not scheduled for this $partWords.')} using errcode = '22023';
  end if;
  if not whole_day and requested <> current_part then
    raise exception ${_quote('The $subjectWords can only be checked in during the current $partWords.')} using errcode = '22023';
  end if;
  if interval_active then
    select * into item from $logTable log_row
    where log_row.${resolved.subjectField.columnName} = p_subject_id
      and log_row.${log.ownerField.columnName} = auth.uid()
      and log_row.deleted_at is null
    order by log_row.$at desc, log_row.id desc limit 1;
    if item.id is not null and (${due.isEmpty ? 'false' : due.join(' or ')}) then
      raise exception ${_quote('The $subjectWords is not due yet.')} using errcode = '22023';
    end if;
    item := null;
  else
    select * into item from $logTable log_row
    where log_row.${resolved.subjectField.columnName} = p_subject_id
      and log_row.${log.ownerField.columnName} = auth.uid()
      and log_row.${resolved.date.columnName} = today
      and log_row.${resolved.part.columnName} = slot
    order by log_row.$at desc, log_row.id desc limit 1;
  end if;
  if item.id is null then
    item.id := gen_random_uuid();
${_push(log, operation: 'create', entityId: 'item.id', patch: _createPatch(), indent: '    ')}
  else
    if item.deleted_at is not null then
${_push(log, operation: 'delete', entityId: 'item.id', patch: "'deletedAt', 'null'::jsonb", base: 'item.server_version', indent: '      ')}
      select * into item from $logTable log_row where log_row.id = item.id;
    end if;
${_push(log, operation: 'patch', entityId: 'item.id', patch: detailPatch, base: 'item.server_version', indent: '    ')}
  end if;
${resolved.recordAnswers == null ? '' : "  perform ${resolved.recordAnswers}(item.id, p_arguments -> 'answers');"}
  return item.id;
end;
\$\$;
''';
  }

  String logDaySql() {
    final subjectWords = _words(subject.className);
    final partWords = _words(resolved.part.name);
    final flags = resolved.scheduledParts.columnName;
    final at = resolved.at.columnName;
    final whole = _quote(resolved.wire(resolved.dayParts.wholeDay));
    final scheduled =
        'array(select listed.part from unnest(array[${[for (final name in resolved.parts) _quote(resolved.wire(name))].join(', ')}]) '
        'with ordinality listed(part, position) '
        'where (subject.$flags & (case listed.part ${_bitCases()} end)) <> 0 order by listed.position)';
    final available = [
      if (resolved.since case final since?)
        'day >= (subject.${since.columnName} at time zone zone)::date',
      if (resolved.days case (_, _, final field))
        '(subject.${field.columnName} is null or (subject.${field.columnName} & (1 << extract(dow from day)::int)) <> 0)',
    ];
    final detailPatch = [
      "${_quote(resolved.at.name)}, to_jsonb(logged_at)",
      for (final field in resolved.details)
        '${_quote(field.name)}, ${_defaultJson(field)}',
    ].join(', ');
    return '''
create or replace function ${resolved.logDayFunction}(
  p_subject_id uuid,
  p_arguments jsonb
)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as \$\$
${_prelude(resolved.part.name, declarations: ['day date;', 'parts text[];', 'scheduled text[];', 'live text[];', 'logged text[];', 'logged_at timestamptz;', 'part text;'])}
${[for (final refusal in resolved.spec.refusals) "  if subject.${_column(subject, refusal.fieldName)} then\n    raise exception ${_quote(refusal.message)} using errcode = '22023';\n  end if;"].join('\n')}
  day := (public.agent_required(p_arguments, ${_quote(resolved.date.name)}) #>> '{}')::date;
  if day >= today then
    raise exception 'Only a day before today can be logged.' using errcode = '22023';
  end if;
${available.isEmpty ? '' : '''  if not (${available.join(' and ')}) then
    raise exception ${_quote('The $subjectWords is not available on this date.')} using errcode = '22023';
  end if;'''}
  scheduled := $scheduled;
  parts := case
    when whole_day then array[$whole]
    when nullif(p_arguments ->> ${_quote(resolved.part.name)}, '') is not null then array[requested]
    when interval_active then scheduled[1:1]
    else scheduled
  end;
  if cardinality(parts) = 0 or (not whole_day and not (parts <@ scheduled)) then
    raise exception ${_quote('The $subjectWords is not scheduled for this $partWords.')} using errcode = '22023';
  end if;
  live := array(
    select distinct log_row.${resolved.part.columnName} from $logTable log_row
    where log_row.${resolved.subjectField.columnName} = p_subject_id
      and log_row.${log.ownerField.columnName} = auth.uid()
      and log_row.${resolved.date.columnName} = day
      and log_row.deleted_at is null
  );
  logged := case
    when cardinality(live) = 0 then '{}'::text[]
    when $whole = any(live) then case when whole_day then array[$whole] else scheduled end
    when whole_day then array[$whole]
    else array(select unnest(live) intersect select unnest(scheduled))
  end;
  logged_at := (day + coalesce(
    (nullif(p_arguments ->> ${_quote(resolved.at.name)}, '')::timestamptz at time zone zone)::time,
    make_time(${resolved.spec.loggedAtHour}, 0, 0)
  )) at time zone zone;
  foreach part in array parts loop
    continue when not interval_active and part = any(logged);
    item := null;
    if not interval_active then
      select * into item from $logTable log_row
      where log_row.${resolved.subjectField.columnName} = p_subject_id
        and log_row.${log.ownerField.columnName} = auth.uid()
        and log_row.${resolved.date.columnName} = day
        and log_row.${resolved.part.columnName} = part
      order by log_row.$at desc, log_row.id desc limit 1;
    end if;
    if item.id is null then
      item.id := gen_random_uuid();
${_push(
      log,
      operation: 'create',
      entityId: 'item.id',
      patch: _createPatch(date: 'day', part: 'part', at: 'logged_at', detailsFromArguments: false),
      indent: '      ',
    )}
    else
      if item.deleted_at is not null then
${_push(log, operation: 'delete', entityId: 'item.id', patch: "'deletedAt', 'null'::jsonb", base: 'item.server_version', indent: '        ')}
        select * into item from $logTable log_row where log_row.id = item.id;
      end if;
${_push(log, operation: 'patch', entityId: 'item.id', patch: detailPatch, base: 'item.server_version', indent: '      ')}
    end if;
${resolved.recordAnswers == null ? '' : "    perform ${resolved.recordAnswers}(item.id, p_arguments -> 'answers');"}
    result := result || item.id;
  end loop;
  return result;
end;
\$\$;
''';
  }

  /// Whether the caller owes the subject a check-in on a day: it is
  /// scheduled then and not every part of it is checked in.
  String owesSql() {
    final flags = resolved.scheduledParts.columnName;
    final free = [
      for (final (_, _, field) in resolved.unscheduled)
        'subject.${field.columnName} is not null',
      for (final (_, _, _, field) in resolved.intervals)
        'subject.${field.columnName} is not null',
      if (resolved.days case (_, _, final field))
        '(subject.${field.columnName} is not null and (subject.${field.columnName} & (1 << extract(dow from p_day)::int)) = 0)',
    ];
    final whole = _quote(resolved.wire(resolved.dayParts.wholeDay));
    return '''
create or replace function ${resolved.owesFunction}(p_subject_id uuid, p_day date)
returns boolean
language plpgsql
stable
set search_path = ''
as \$\$
declare
  subject $subjectTable;
  logged text[];
begin
  select * into subject from $subjectTable subject_row where subject_row.id = p_subject_id;
  if subject.id is null${free.isEmpty ? '' : ' or ${free.join(' or ')}'} then
    return false;
  end if;
  logged := array(
    select log_row.${resolved.part.columnName} from $logTable log_row
    where log_row.${resolved.subjectField.columnName} = p_subject_id
      and log_row.${log.ownerField.columnName} = auth.uid()
      and log_row.${resolved.date.columnName} = p_day
      and log_row.deleted_at is null
  );
  if cardinality(logged) = 0 then
    return true;
  end if;
  if $whole = any(logged) or (subject.$flags & ${resolved.bit(resolved.dayParts.wholeDay)}) <> 0 then
    return false;
  end if;
  return exists (
    select 1 from unnest(array[${[for (final name in resolved.parts) _quote(resolved.wire(name))].join(', ')}]) part
    where (subject.$flags & (case part ${_bitCases()} end)) <> 0 and not (part = any(logged))
  );
end;
\$\$;
''';
  }

  String _bitCases() => [
    for (final (name, _) in resolved.dayParts.starts)
      'when ${_quote(resolved.wire(name))} then ${resolved.bit(name)}',
    'else ${resolved.bit(resolved.dayParts.wholeDay)}',
  ].join(' ');

  String _createPatch({
    String date = 'today',
    String part = 'slot',
    String at = 'now_at',
    bool detailsFromArguments = true,
  }) {
    final values = <String, String>{
      log.ownerField.name: 'to_jsonb(auth.uid())',
      resolved.subjectField.name: 'to_jsonb(p_subject_id)',
      resolved.date.name: 'to_jsonb($date)',
      resolved.part.name: 'to_jsonb($part)',
      resolved.at.name: 'to_jsonb($at)',
      for (final field in resolved.details)
        field.name: detailsFromArguments
            ? 'coalesce(p_arguments -> ${_quote(field.name)}, ${_defaultJson(field)})'
            : _defaultJson(field),
    };
    final entries = <String>["'${log.idField.name}', to_jsonb(item.id)"];
    for (final field in log.createFields) {
      if (field.name == EntityConventions.orderRankFieldName ||
          field.name == log.idField.name) {
        continue;
      }
      final value =
          values[field.name] ??
          (field.persistedDefaultValue != null
              ? _jsonLiteral(field.persistedDefaultValue)
              : field.nullable
              ? "'null'::jsonb"
              : throw InvalidGenerationSourceError(
                  'A check-in must give `${field.name}` of ${log.className} '
                  'a value: it has no default.',
                ));
      entries.add('${_quote(field.name)}, $value');
    }
    return entries.join(', ');
  }

  String undoSql() {
    final undo = resolved.undo;
    final subjectColumn = resolved.subjectField.columnName;
    final owner = log.ownerField.columnName;
    final at = resolved.at.columnName;
    final undoValues = <String, String>{
      undo.ownerField.name: 'to_jsonb(auth.uid())',
      resolved.subjectField.name: 'to_jsonb(item.$subjectColumn)',
      resolved.date.name: 'to_jsonb(item.${resolved.date.columnName})',
      resolved.part.name: 'to_jsonb(item.${resolved.part.columnName})',
      resolved.undoComment.name:
          "coalesce(to_jsonb(nullif(btrim(p_arguments ->> ${_quote(resolved.undoComment.name)}), '')), 'null'::jsonb)",
    };
    final undoPatch = [
      "'${undo.idField.name}', to_jsonb(undo_id)",
      for (final field in undo.createFields)
        if (field.name != EntityConventions.orderRankFieldName &&
            field.name != undo.idField.name)
          '${_quote(field.name)}, ${undoValues[field.name] ?? (field.persistedDefaultValue != null
                  ? _jsonLiteral(field.persistedDefaultValue)
                  : field.nullable
                  ? "'null'::jsonb"
                  : throw InvalidGenerationSourceError('An undone check-in must give `${field.name}` of ${undo.className} a value.'))}',
    ].join(', ');
    final undoOne =
        '${_push(log, operation: 'delete', entityId: 'item.id', patch: "'deletedAt', to_jsonb(now_at)", base: 'item.server_version', indent: '    ')}\n'
        '    undo_id := gen_random_uuid();\n'
        '${_push(undo, operation: 'create', entityId: 'undo_id', patch: undoPatch, indent: '    ')}\n'
        '    result := result || item.id;';
    return '''
create or replace function ${resolved.undoFunction}(
  p_subject_id uuid,
  p_arguments jsonb
)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as \$\$
${_prelude(resolved.part.name, declarations: ['day date;', 'undo_id uuid;'])}
  day := coalesce(nullif(p_arguments ->> ${_quote(resolved.date.name)}, '')::date, today);
  if interval_active then
    select * into item from $logTable log_row
    where log_row.$subjectColumn = p_subject_id and log_row.deleted_at is null
    order by log_row.$at desc, log_row.id desc limit 1;
    if item.id is null then
      return result;
    end if;
    if item.$owner <> auth.uid() then
      raise exception ${_quote("The latest check-in is a collaborator's to undo.")} using errcode = '22023';
    end if;
$undoOne
    return result;
  end if;
  for item in
    select * from $logTable log_row
    where log_row.$subjectColumn = p_subject_id
      and log_row.$owner = auth.uid()
      and log_row.${resolved.date.columnName} = day
      and log_row.deleted_at is null
      and (whole_day or log_row.${resolved.part.columnName} in (slot, ${_quote(resolved.wire(resolved.dayParts.wholeDay))}))
    order by log_row.$at desc, log_row.id desc
  loop
$undoOne
  end loop;
  return result;
end;
\$\$;
''';
  }

  String _defaultJson(FieldSpec field) {
    final value = field.persistedDefaultValue;
    if (value != null) return _jsonLiteral(value);
    if (field.nullable) return "'null'::jsonb";
    throw InvalidGenerationSourceError(
      'A CheckIns detail must be nullable or have a default: '
      '`${field.name}` of ${log.className}.',
    );
  }
}

String _column(EntitySpec entity, String name) =>
    entity.fields.firstWhere((field) => field.name == name).columnName;

String _push(
  EntitySpec entity, {
  required String operation,
  required String entityId,
  required String patch,
  String base = '0',
  String indent = '  ',
}) =>
    '''${indent}perform public.push_${entity.tableName}_operations(jsonb_build_array(jsonb_build_object(
$indent  'operationId', gen_random_uuid(),
$indent  'operation', '$operation',
$indent  'entityType', '${entity.className}',
$indent  'entityId', $entityId,
$indent  'baseServerVersion', $base,
$indent  'protocolVersion', ${entity.protocolVersion},
$indent  'patch', jsonb_build_object($patch)
$indent)));''';

String _jsonLiteral(Object? value) => "${_quote(jsonEncode(value))}::jsonb";

String _quote(String value) => "'${value.replaceAll("'", "''")}'";

String _words(String camel) => snakeCase(camel).replaceAll('_', ' ');

String _capitalized(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
