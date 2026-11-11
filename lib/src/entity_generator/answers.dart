import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

/// An [AnswersSpec] checked against its answer, question, and option
/// entities.
final class ResolvedAnswers {
  ResolvedAnswers._({
    required this.answer,
    required this.question,
    required this.questionReference,
    required this.variant,
    required this.cases,
    required this.option,
    required this.log,
    required this.logReference,
  });

  factory ResolvedAnswers.of(EntitySpec answer, EntityGraphSpec graph) {
    final spec = answer.answers!;
    FieldSpec field(EntitySpec entity, String name) =>
        entity.fields.where((field) => field.name == name).firstOrNull ??
        (throw InvalidGenerationSourceError(
          'Answers names `$name`, which is not a field of ${entity.className}.',
        ));
    EntitySpec entity(String className) => graph.entities.singleWhere(
      (candidate) => candidate.className == className,
    );
    final questionReference = field(answer, spec.questionFieldName);
    final question = entity(
      questionReference.reference?.targetClassName ??
          (throw InvalidGenerationSourceError(
            'Answers.question must be a reference of ${answer.className}.',
          )),
    );
    final kind = field(question, spec.kindFieldName);
    if (!kind.isEnum) {
      throw InvalidGenerationSourceError(
        'Answers.kind must be an enum field of ${question.className}.',
      );
    }
    PersistedVariantSpec? variant;
    final cases = <String, (PersistedVariantCaseSpec, FieldSpec)>{};
    for (final MapEntry(key: constant, value: name) in spec.cases.entries) {
      if (!kind.enumValues.contains(constant)) {
        throw InvalidGenerationSourceError(
          'Answers.cases names `$constant`, which is not a ${kind.dartType}.',
        );
      }
      for (final candidate in answer.persistedVariants) {
        for (final variantCase in candidate.cases) {
          final caseField = variantCase.fields
              .where((field) => field.name == name)
              .firstOrNull;
          if (caseField == null) continue;
          variant ??= candidate;
          cases[constant] = (variantCase, caseField);
        }
      }
      if (!cases.containsKey(constant)) {
        throw InvalidGenerationSourceError(
          'Answers.cases maps `$constant` to `$name`, which is not a variant '
          'case field of ${answer.className}.',
        );
      }
    }
    final missing = kind.enumValues.where((value) => !cases.containsKey(value));
    if (missing.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'Answers.cases must map every ${kind.dartType}: ${missing.join(', ')}.',
      );
    }
    EntitySpec? option;
    if (spec.optionFieldName case final name?) {
      option = entity(field(answer, name).reference!.targetClassName);
      field(option, spec.optionQuestionFieldName!);
    }
    final logReference = answer.fields
        .where((field) => field.reference?.aggregateMember == true)
        .firstOrNull;
    final log = logReference == null
        ? null
        : entity(logReference.reference!.targetClassName);
    final resolved = ResolvedAnswers._(
      answer: answer,
      question: question,
      questionReference: questionReference,
      variant: variant!,
      cases: cases,
      option: option,
      log: log?.checkIns == null ? null : log,
      logReference: log?.checkIns == null ? null : logReference,
    );
    for (final name in [
      spec.labelFieldName,
      ?spec.minFieldName,
      ?spec.maxFieldName,
    ]) {
      field(question, name);
    }
    if (spec.numberFieldName case final name?) field(answer, name);
    return resolved;
  }

  final EntitySpec answer;
  final EntitySpec question;
  final FieldSpec questionReference;
  final PersistedVariantSpec variant;
  final Map<String, (PersistedVariantCaseSpec, FieldSpec)> cases;
  final EntitySpec? option;

  /// The [CheckIns] log the answers belong to, when there is one.
  final EntitySpec? log;
  final FieldSpec? logReference;

  AnswersSpec get spec => answer.answers!;
  FieldSpec questionField(String name) =>
      question.fields.singleWhere((field) => field.name == name);
  FieldSpec answerField(String name) =>
      answer.fields.singleWhere((field) => field.name == name);
  FieldSpec get kind => questionField(spec.kindFieldName);
  String get table => 'public.${answer.tableName}';
  String get recordFunction => 'public.${answer.tableName}_answer';

  /// The answer field sharing the log's subject reference, if any.
  FieldSpec? get subject {
    final logSubject = log?.checkIns?.subjectFieldName;
    if (logSubject == null) return null;
    final subjectClass = log!.fields
        .singleWhere((field) => field.name == logSubject)
        .reference!
        .targetClassName;
    return answer.fields
        .where((field) => field.reference?.targetClassName == subjectClass)
        .firstOrNull;
  }
}

/// Generated `require<Answer>` for every [Answers] entity.
String emitAnswersDart(EntityGraphSpec graph) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (entity.answers == null) continue;
    final rule = ResolvedAnswers.of(entity, graph);
    final spec = rule.spec;
    final kindType = rule.kind.dartType.replaceAll('?', '');
    final label = 'question.${spec.labelFieldName}';
    String refuse(String message) =>
        "throw EntityValidationException(entityType: '${entity.className}', "
        "field: '${rule.variant.name}', message: '\${$label} $message');";
    final option = rule.option;
    buffer
      ..writeln()
      ..writeln(
        '/// Refuses a ${entity.className} that does not answer [question] as '
        'declared;',
      )
      ..writeln('/// [option] is the chosen option, when the answer names one.')
      ..writeln('void require${entity.className}({')
      ..writeln('  required ${rule.question.className} question,')
      ..writeln(
        '  required ${rule.variant.dartType.replaceAll('?', '')} value,',
      );
    if (option != null) {
      buffer.writeln('  ${option.className}? option,');
    }
    buffer
      ..writeln('}) {')
      ..writeln('  final matches = switch (question.${spec.kindFieldName}) {');
    for (final MapEntry(key: constant, value: (variantCase, _))
        in rule.cases.entries) {
      buffer.writeln(
        '    $kindType.$constant => value is ${variantCase.className},',
      );
    }
    buffer
      ..writeln('  };')
      ..writeln(
        '  if (!matches) ${refuse('has an answer of the wrong kind.')}',
      );
    if (spec.numberFieldName case final number?) {
      final numberCase = rule.cases.values
          .singleWhere((entry) => entry.$2.name == number)
          .$1;
      final bounds = [
        if (spec.minFieldName case final min?)
          '(question.$min != null && $number < question.$min!)',
        if (spec.maxFieldName case final max?)
          '(question.$max != null && $number > question.$max!)',
      ];
      if (bounds.isNotEmpty) {
        buffer.writeln(
          '  if (value case ${numberCase.className}(:final $number) '
          'when ${bounds.join(' || ')}) ${refuse('is outside its valid range.')}',
        );
      }
    }
    if (option != null) {
      final optionField = spec.optionFieldName!;
      final optionCase = rule.cases.values
          .singleWhere((entry) => entry.$2.name == optionField)
          .$1;
      buffer.writeln(
        '  if (value case ${optionCase.className}(:final $optionField) '
        'when option == null || option.id != $optionField || '
        'option.${spec.optionQuestionFieldName} != question.id) '
        '${refuse('has an invalid option.')}',
      );
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

/// The trigger enforcing every [Answers] rule, and the function agent
/// check-ins record answers through.
String emitAnswersSql(EntityGraphSpec graph) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (entity.answers == null) continue;
    final rule = ResolvedAnswers.of(entity, graph);
    final spec = rule.spec;
    final q = rule.question;
    final kind = rule.kind.columnName;
    final label = rule.questionField(spec.labelFieldName).columnName;
    final wrongKind = [
      for (final MapEntry(key: constant, value: (_, field))
          in rule.cases.entries)
        "when ${_quote(snakeCase(constant))} then new.${field.columnName} is null",
    ];
    final checks = <String>[
      '''
  if (case question.$kind ${wrongKind.join(' ')} else true end) then
    raise exception '% has an answer of the wrong kind.', question.$label using errcode = '23514';
  end if;''',
    ];
    if (spec.numberFieldName case final name?) {
      final number = rule.answerField(name).columnName;
      final bounds = [
        if (spec.minFieldName case final min?)
          'new.$number < question.${rule.questionField(min).columnName}',
        if (spec.maxFieldName case final max?)
          'new.$number > question.${rule.questionField(max).columnName}',
      ];
      checks.add('''
  if new.$number is not null and (${bounds.join(' or ')}) then
    raise exception '% is outside its valid range.', question.$label using errcode = '23514';
  end if;''');
    }
    final option = rule.option;
    if (option != null) {
      final column = rule.answerField(spec.optionFieldName!).columnName;
      final optionQuestion = option.fields
          .singleWhere((field) => field.name == spec.optionQuestionFieldName)
          .columnName;
      checks.add('''
  if new.$column is not null and not exists (
    select 1 from public.${option.tableName} option_row
    where option_row.id = new.$column and option_row.$optionQuestion = new.${rule.questionReference.columnName}
  ) then
    raise exception '% has an invalid option.', question.$label using errcode = '23514';
  end if;''');
    }
    final watched = [
      rule.questionReference.columnName,
      for (final (_, field) in rule.cases.values) field.columnName,
    ];
    final trigger = '${entity.tableName}_answers';
    buffer.writeln('''
create or replace function public.$trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
declare
  question public.${q.tableName};
begin
${entity.hasSoftDeletableCapability ? '  if new.deleted_at is not null then\n    return new;\n  end if;\n' : ''}  select * into question from public.${q.tableName} question_row
  where question_row.id = new.${rule.questionReference.columnName};
  if question.id is null then
    raise exception 'The question this answers does not exist' using errcode = '23514';
  end if;
${checks.join('\n')}
  return new;
end;
\$\$;

revoke all on function public.$trigger() from public, anon, authenticated, service_role;
drop trigger if exists $trigger on ${rule.table};
create trigger $trigger before insert or update of ${watched.join(', ')} on ${rule.table} for each row execute function public.$trigger();
''');
    if (rule.log != null) buffer.writeln(_recordSql(rule));
  }
  return buffer.toString();
}

/// Records the answers an agent gives with a check-in: an object keyed by
/// question id. A question it leaves out keeps no answer, as when the
/// application replaces a check-in's answers.
String _recordSql(ResolvedAnswers rule) {
  final answer = rule.answer;
  final log = rule.log!;
  final q = rule.question;
  final questionColumn = rule.questionReference.columnName;
  final logColumn = rule.logReference!.columnName;
  final subject = rule.subject;
  final logSubject = log.fields
      .singleWhere((field) => field.name == log.checkIns!.subjectFieldName)
      .columnName;
  final questionSubject = subject == null
      ? null
      : q.fields
            .where(
              (field) =>
                  field.reference?.targetClassName ==
                  subject.reference!.targetClassName,
            )
            .firstOrNull;
  String cast(FieldSpec field) {
    final type = field.dartType.replaceAll('?', '');
    final text = "(raw #>> '{}')";
    return switch (type) {
      'double' || 'num' => 'to_jsonb($text::numeric)',
      'int' => 'to_jsonb($text::bigint)',
      'bool' => 'to_jsonb($text::boolean)',
      'LocalDate' => 'to_jsonb($text::date)',
      'DateTime' => 'to_jsonb($text::timestamptz)',
      'String' => 'to_jsonb(btrim($text))',
      _ when type.startsWith('LocalId<') => 'to_jsonb($text::uuid)',
      _ => throw InvalidGenerationSourceError(
        'Answers cannot read a `$type` answer from an agent.',
      ),
    };
  }

  final kind = rule.kind.columnName;
  final caseValues = <String, String>{
    for (final MapEntry(key: constant, value: (_, field)) in rule.cases.entries)
      field.name:
          "case when question.$kind = ${_quote(snakeCase(constant))} then ${cast(field)} else 'null'::jsonb end",
  };
  final patch = [
    for (final MapEntry(:key, :value) in caseValues.entries)
      '${_quote(key)}, $value',
  ].join(', ');
  final createValues = <String, String>{
    answer.ownerField.name: 'to_jsonb(auth.uid())',
    rule.logReference!.name: 'to_jsonb(p_log_id)',
    rule.questionReference.name: 'to_jsonb(question.id)',
    if (subject != null) subject.name: 'to_jsonb(log_row.$logSubject)',
    ...caseValues,
  };
  final create = [
    "'${answer.idField.name}', to_jsonb(answer_id)",
    for (final field in answer.createFields)
      if (field.name != answer.idField.name &&
          field.name != EntityConventions.orderRankFieldName)
        '${_quote(field.name)}, ${createValues[field.name] ?? (field.nullable ? "'null'::jsonb" : throw InvalidGenerationSourceError('An agent answer must give `${field.name}` of ${answer.className} a value.'))}',
  ].join(', ');
  String push(String operation, String entityId, String body, String base) =>
      '''
    perform public.push_${answer.tableName}_operations(jsonb_build_array(jsonb_build_object(
      'operationId', gen_random_uuid(),
      'operation', '$operation',
      'entityType', '${answer.className}',
      'entityId', $entityId,
      'baseServerVersion', $base,
      'protocolVersion', ${answer.protocolVersion},
      'patch', jsonb_build_object($body)
    )));''';
  return '''
create or replace function ${rule.recordFunction}(p_log_id uuid, p_answers jsonb)
returns void
language plpgsql
volatile
set search_path = ''
as \$\$
declare
  log_row public.${log.tableName};
  question public.${q.tableName};
  existing public.${answer.tableName};
  answer_key text;
  raw jsonb;
  answer_id uuid;
  given text[];
begin
  if p_answers is null or jsonb_typeof(p_answers) = 'null' then
    return;
  end if;
  if jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers are an object keyed by question id' using errcode = '22023';
  end if;
  select * into log_row from public.${log.tableName} item where item.id = p_log_id;
  given := array(
    select entry.key from jsonb_each(p_answers) entry
    where jsonb_typeof(entry.value) <> 'null' and entry.value <> '""'::jsonb
  );
  for existing in
    select * from ${rule.table} item
    where item.$logColumn = p_log_id and item.deleted_at is null
      and not (item.$questionColumn::text = any(given))
  loop
${push('delete', 'existing.id', "'deletedAt', public.agent_now()", 'existing.server_version')}
  end loop;
  foreach answer_key in array given loop
    raw := p_answers -> answer_key;
    select * into question from public.${q.tableName} question_row
    where question_row.id::text = answer_key${q.hasSoftDeletableCapability ? ' and question_row.deleted_at is null' : ''}${questionSubject == null ? '' : ' and question_row.${questionSubject.columnName} = log_row.$logSubject'};
    if question.id is null then
      raise exception 'Unknown question "%"', answer_key using errcode = '22023';
    end if;
    select * into existing from ${rule.table} item
    where item.$logColumn = p_log_id and item.$questionColumn = question.id
    order by item.deleted_at nulls first limit 1;
    if existing.id is null then
      answer_id := gen_random_uuid();
${push('create', 'answer_id', create, '0')}
    else
      if existing.deleted_at is not null then
${push('delete', 'existing.id', "'deletedAt', 'null'::jsonb", 'existing.server_version')}
        select * into existing from ${rule.table} item where item.id = existing.id;
      end if;
${push('patch', 'existing.id', patch, 'existing.server_version')}
    end if;
  end loop;
end;
\$\$;

revoke all on function ${rule.recordFunction}(uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function ${rule.recordFunction}(uuid, jsonb) to authenticated;
''';
}

String _quote(String value) => "'${value.replaceAll("'", "''")}'";
