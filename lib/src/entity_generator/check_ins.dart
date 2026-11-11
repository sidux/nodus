import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

/// A [CheckInsSpec] checked against its log, subject, owner, and undo
/// entities.
final class ResolvedCheckIns {
  ResolvedCheckIns._({
    required this.log,
    required this.subject,
    required this.owner,
    required this.undo,
    required this.answers,
  });

  factory ResolvedCheckIns.of(EntitySpec log, EntityGraphSpec graph) {
    final spec = log.checkIns!;
    EntitySpec entity(String className, String role) =>
        graph.entities
            .where((entity) => entity.className == className)
            .firstOrNull ??
        (throw InvalidGenerationSourceError(
          'CheckIns on ${log.className} needs the $role entity $className in '
          'the graph.',
        ));
    final subjectField = _field(log, spec.subjectFieldName);
    final subjectClass =
        subjectField.reference?.targetClassName ??
        (throw InvalidGenerationSourceError(
          'CheckIns.subject `${spec.subjectFieldName}` of ${log.className} '
          'must be a reference.',
        ));
    final resolved = ResolvedCheckIns._(
      log: log,
      subject: entity(subjectClass, 'subject'),
      owner: entity(log.ownerClassName, 'owner'),
      undo: entity(spec.undoneAsClassName, 'UndoneAs'),
      answers: graph.entities
          .where(
            (candidate) =>
                candidate.answers != null &&
                candidate.fields.any(
                  (field) =>
                      field.reference?.aggregateMember == true &&
                      field.reference!.targetClassName == log.className,
                ),
          )
          .firstOrNull,
    );
    resolved._validate();
    return resolved;
  }

  final EntitySpec log;
  final EntitySpec subject;
  final EntitySpec owner;
  final EntitySpec undo;

  /// The entity answering the subject's questions with each check-in.
  final EntitySpec? answers;

  /// Records an agent's answers for one check-in, when there are answers.
  String? get recordAnswers =>
      answers == null ? null : 'public.${answers!.tableName}_answer';

  CheckInsSpec get spec => log.checkIns!;
  DayPartsSpec get dayParts => spec.dayParts;

  FieldSpec get subjectField => _field(log, spec.subjectFieldName);
  FieldSpec get date => _field(log, spec.dateFieldName);
  FieldSpec get part => _field(log, spec.partFieldName);
  FieldSpec get at => _field(log, spec.atFieldName);
  FieldSpec get timezone => _field(owner, spec.timezoneFieldName);
  FieldSpec get scheduledParts => _field(subject, spec.scheduledPartsFieldName);
  List<FieldSpec> get details => [
    for (final name in spec.detailFieldNames) _field(log, name),
  ];
  FieldSpec get undoComment => _field(undo, spec.undoCommentFieldName);

  /// The subject's time field logging starts from, if declared.
  FieldSpec? get since => spec.sinceFieldName == null
      ? null
      : _field(subject, spec.sinceFieldName!);

  /// The subject variant case limiting loggable weekdays, with its field.
  (PersistedVariantSpec, PersistedVariantCaseSpec, FieldSpec)? get days {
    final name = spec.daysFieldName;
    if (name == null) return null;
    for (final variant in subject.persistedVariants) {
      for (final variantCase in variant.cases) {
        for (final field in variantCase.fields) {
          if (field.name == name) return (variant, variantCase, field);
        }
      }
    }
    throw InvalidGenerationSourceError(
      'CheckIns.days `$name` is not a variant case field of '
      '${subject.className}.',
    );
  }

  /// Subject variant cases that leave it unscheduled, with their field.
  List<(PersistedVariantSpec, PersistedVariantCaseSpec, FieldSpec)>
  get unscheduled => [
    for (final name in spec.unscheduledFieldNames)
      for (final variant in subject.persistedVariants)
        for (final variantCase in variant.cases)
          for (final field in variantCase.fields)
            if (field.name == name) (variant, variantCase, field),
  ];

  String get owesFunction => 'public.${log.tableName}_owes_check_in';

  /// The parts of the day other than the whole day, in hour order.
  List<String> get parts => [for (final (name, _) in dayParts.starts) name];

  /// The part enum's Dart type, such as `TimeRange`.
  String get partType => part.dartType.replaceAll('?', '');

  /// The generated function naming the part of the day of a moment.
  String get partAtDart => '${lowerCamelCase(partType)}At';
  String get partAtSql => 'public.${snakeCase(partType)}_at';

  String get checkInFunction => 'public.${log.tableName}_check_in';
  String get undoFunction => 'public.${log.tableName}_undo_check_in';
  String get logDayFunction => 'public.${log.tableName}_log_day';

  /// The wire value of the part enum constant [name].
  String wire(String name) =>
      part.enumWireValues[part.enumValues.indexOf(name)];

  /// The [ScalarFlags] bit of the part enum constant [name] in
  /// [scheduledParts].
  int bit(String name) =>
      1 << scheduledParts.scalarValue!.flags!.indexOf(wire(name));

  /// Each interval with its subject variant case and the case's presence
  /// field, which is set exactly while the case is active.
  List<(EverySpec, PersistedVariantSpec, PersistedVariantCaseSpec, FieldSpec)>
  get intervals => [for (final every in spec.intervals) _interval(every)];

  (EverySpec, PersistedVariantSpec, PersistedVariantCaseSpec, FieldSpec)
  _interval(EverySpec every) {
    for (final variant in subject.persistedVariants) {
      for (final variantCase in variant.cases) {
        final field = variantCase.fields
            .where((field) => field.name == every.fieldName)
            .firstOrNull;
        if (field == null) continue;
        if (variantCase.presenceField?.name != field.name) {
          throw InvalidGenerationSourceError(
            'Every `${every.fieldName}` must be the required field of '
            '${variantCase.className}.',
          );
        }
        return (every, variant, variantCase, field);
      }
    }
    throw InvalidGenerationSourceError(
      'Every `${every.fieldName}` is not a variant case field of '
      '${subject.className}.',
    );
  }

  void _validate() {
    if (!log.hasSoftDeletableCapability) {
      throw InvalidGenerationSourceError(
        'CheckIns need a soft-deletable log: ${log.className}.',
      );
    }
    if (date.dartType != 'LocalDate' || at.dartType != 'DateTime') {
      throw InvalidGenerationSourceError(
        'CheckIns.date must be a LocalDate and CheckIns.at a DateTime.',
      );
    }
    if (!part.isEnum || part.nullable) {
      throw InvalidGenerationSourceError(
        'CheckIns.part must be a non-null enum field.',
      );
    }
    final flags = scheduledParts.scalarValue?.flags;
    final named = [
      for (final (name, _) in dayParts.starts) name,
      dayParts.wholeDay,
    ];
    for (final name in named) {
      if (!part.enumValues.contains(name)) {
        throw InvalidGenerationSourceError(
          'DayParts names `$name`, which is not a value of $partType.',
        );
      }
      if (flags == null || !flags.contains(wire(name))) {
        throw InvalidGenerationSourceError(
          'CheckIns.scheduledParts must be ScalarFlags naming every part of '
          'the day, including `${wire(name)}`.',
        );
      }
    }
    if (timezone.dartType.replaceAll('?', '') != 'String') {
      throw InvalidGenerationSourceError(
        'CheckIns.timezone must be a String field of ${owner.className}.',
      );
    }
    for (final refusal in [...spec.refusals, ...spec.agentRefusals]) {
      if (_field(subject, refusal.fieldName).dartType != 'bool') {
        throw InvalidGenerationSourceError(
          'A CheckIns refusal reads a bool field of ${subject.className}: '
          '`${refusal.fieldName}`.',
        );
      }
    }
    intervals;
    details;
    if (days case (_, _, final field)) {
      const weekdays = [
        'sunday',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
      ];
      final flags = field.scalarValue?.flags;
      if (flags == null || flags.join(',') != weekdays.join(',')) {
        throw InvalidGenerationSourceError(
          'CheckIns.days must be ScalarFlags naming the weekdays, sunday '
          'first: `${field.name}`.',
        );
      }
    }
    if (since case final field? when field.dartType != 'DateTime') {
      throw InvalidGenerationSourceError(
        'CheckIns.since must be a DateTime field: `${field.name}`.',
      );
    }
    if (unscheduled.length != spec.unscheduledFieldNames.length) {
      throw InvalidGenerationSourceError(
        'CheckIns.unscheduled names a field that is not a variant case field '
        'of ${subject.className}.',
      );
    }
    if (spec.loggedAtHour < 0 || spec.loggedAtHour > 23) {
      throw InvalidGenerationSourceError(
        'CheckIns.loggedAtHour must be an hour from 0 to 23.',
      );
    }
    for (final name in [
      spec.subjectFieldName,
      spec.dateFieldName,
      spec.partFieldName,
    ]) {
      _field(undo, name);
    }
    if (undoComment.dartType != 'String?') {
      throw InvalidGenerationSourceError(
        'UndoneAs.comment must be a nullable String field of '
        '${undo.className}.',
      );
    }
    if ((spec.checkInTool != null ||
            spec.undoTool != null ||
            spec.logTool != null) &&
        log.agentAccess == null) {
      throw InvalidGenerationSourceError(
        'Agent check-in tools need AgentAccess on ${log.className}.',
      );
    }
  }
}

FieldSpec _field(EntitySpec entity, String name) =>
    entity.fields.where((field) => field.name == name).firstOrNull ??
    (throw InvalidGenerationSourceError(
      '`$name` is not a field of ${entity.className}.',
    ));

String _words(String camel) => snakeCase(camel).replaceAll('_', ' ');

/// Generated Dart for every declared check-in log: the part-of-day function
/// of each part enum, and `beginCheckIn` and `undoCheckIn` on the subject.
String emitCheckInsDart(
  EntityGraphSpec graph,
  String entityGraphName,
  Set<String> aggregateTypes,
) {
  final buffer = StringBuffer();
  final partFunctions = <String>{};
  for (final log in graph.entities) {
    if (log.checkIns == null) continue;
    final resolved = ResolvedCheckIns.of(log, graph);
    if (partFunctions.add(resolved.partAtDart)) {
      buffer
        ..writeln()
        ..write(_partAtDart(resolved));
    }
    buffer
      ..writeln()
      ..write(
        _DartCheckIns(
          resolved,
          entityGraphName,
          aggregate: aggregateTypes.contains(log.className),
        ).emit(),
      );
  }
  return buffer.toString();
}

String _partAtDart(ResolvedCheckIns resolved) {
  final type = resolved.partType;
  final parts = resolved.dayParts.starts.reversed.toList();
  final buffer = StringBuffer()
    ..writeln('/// The part of the day [moment] falls in, on its local clock.')
    ..writeln('$type ${resolved.partAtDart}(DateTime moment) {')
    ..writeln('  final hour = moment.toLocal().hour;');
  for (final (name, hour) in parts.take(parts.length - 1)) {
    buffer.writeln('  if (hour >= $hour) return $type.$name;');
  }
  buffer
    ..writeln('  return $type.${parts.last.$1};')
    ..writeln('}');
  return buffer.toString();
}

final class _DartCheckIns {
  _DartCheckIns(this.resolved, this.entityGraphName, {required this.aggregate});

  final ResolvedCheckIns resolved;
  final String entityGraphName;
  final bool aggregate;

  EntitySpec get log => resolved.log;
  String get logType => log.className;
  String get fields => '${logType}Fields';
  String get partType => resolved.partType;
  String get wholeDay => '$partType.${resolved.dayParts.wholeDay}';
  String get draftType =>
      aggregate ? '${logType}AggregateDraft' : '${logType}MutationDraft';
  String get subjectWords => _words(resolved.subject.className);
  String get partWords => _words(resolved.part.name);

  String _throw(String field, String message, String indent) =>
      '${indent}throw const EntityValidationException(\n'
      "$indent  entityType: '$logType',\n"
      "$indent  field: '$field',\n"
      '$indent  message: ${dartLiteral(message)},\n'
      '$indent);';

  /// The active interval as `(amount, days)`, or null.
  String get _intervalSwitch {
    final cases = [
      for (final (every, _, variantCase, field) in resolved.intervals)
        '${variantCase.className}(:final ${field.name}) => '
            '(amount: ${field.name}, days: ${every.days})',
    ];
    final variant = resolved.intervals.first.$2.name;
    return 'switch (this.$variant) { ${cases.join(', ')}, _ => null }';
  }

  /// Whether an interval case of the subject is active.
  String get _intervalActive => [
    for (final (_, variant, variantCase, _) in resolved.intervals)
      'this.${variant.name} is ${variantCase.className}',
  ].join(' || ');

  String emit() {
    final subject = resolved.subject;
    final spec = resolved.spec;
    final hasIntervals = resolved.intervals.isNotEmpty;
    final details = resolved.details;
    final detailParameters = [
      for (final field in details)
        if (field.nullable)
          '${field.dartType} ${field.name},'
        else
          '${field.dartType} ${field.name} = ${_default(field)},',
    ];
    final subjectId = resolved.subjectField.name;
    final buffer = StringBuffer()
      ..writeln(
        'extension ${subject.className}CheckIns on ${subject.className} {',
      )
      ..writeln(
        '  /// Starts checking this $subjectWords in now; saving the returned '
        'draft records',
      )
      ..writeln(
        '  /// it. [${resolved.part.name}] defaults to the current part of the '
        'day.',
      )
      ..writeln('  Future<$draftType> beginCheckIn(')
      ..writeln('    $entityGraphName entityGraph, {')
      ..writeln('    $partType? ${resolved.part.name},');
    for (final parameter in detailParameters) {
      buffer.writeln('    $parameter');
    }
    buffer
      ..writeln('  }) async {')
      ..write(_requireLive('    '));
    for (final refusal in spec.refusals) {
      buffer
        ..writeln('    if (this.${refusal.fieldName}) {')
        ..writeln(_throw(subjectId, refusal.message, '      '))
        ..writeln('    }');
    }
    buffer
      ..writeln('    final now = entityGraph.nowUtc();')
      ..writeln('    final local = now.toLocal();')
      ..writeln('    final today = LocalDate.fromDateTime(local);')
      ..writeln('    final current = ${resolved.partAtDart}(local);')
      ..writeln('    final requested = ${resolved.part.name} ?? current;')
      ..writeln(
        '    final wholeDay = this.${resolved.scheduledParts.name}.contains($wholeDay);',
      )
      ..writeln(
        '    if (!wholeDay && !this.${resolved.scheduledParts.name}.contains(requested)) {',
      )
      ..writeln(
        _throw(
          resolved.part.name,
          'The $subjectWords is not scheduled for this $partWords.',
          '      ',
        ),
      )
      ..writeln('    }')
      ..writeln('    if (!wholeDay && requested != current) {')
      ..writeln(
        _throw(
          resolved.part.name,
          'The $subjectWords can only be checked in during the current '
              '$partWords.',
          '      ',
        ),
      )
      ..writeln('    }')
      ..writeln('    final part = wholeDay ? $wholeDay : requested;')
      ..writeln('    $logType? existing;');
    final slot =
        '      existing = await ${logType}List.owned(\n'
        '        entityGraph,\n'
        '        where:\n'
        '            $fields.$subjectId.equals(id) &\n'
        '            $fields.${resolved.date.name}.equals(today) &\n'
        '            $fields.${resolved.part.name}.equals(part),\n'
        '        orderBy: $fields.${resolved.at.name}.descending(),\n'
        '        tombstones: TombstoneVisibility.include,\n'
        '        pageSize: 1,\n'
        '      ).useAll((rows) => rows.firstOrNull);\n'
        '      if (existing?.deletedAt != null) await existing!.restore();\n';
    if (hasIntervals) {
      buffer
        ..writeln('    final interval = $_intervalSwitch;')
        ..writeln('    if (interval != null) {')
        ..writeln('      final latest = await ${logType}List.owned(')
        ..writeln('        entityGraph,')
        ..writeln('        where: $fields.$subjectId.equals(id),')
        ..writeln('        orderBy: $fields.${resolved.at.name}.descending(),')
        ..writeln('        pageSize: 1,')
        ..writeln('      ).useAll((rows) => rows.firstOrNull);')
        ..writeln('      if (latest != null) {')
        ..writeln('        final last = latest.${resolved.at.name}.toLocal();')
        ..writeln('        final due = interval.days')
        ..writeln(
          '            ? DateTime(last.year, last.month, last.day + interval.amount)',
        )
        ..writeln('            : last.add(Duration(hours: interval.amount));')
        ..writeln('        if (local.isBefore(due)) {')
        ..writeln(
          _throw(
            resolved.at.name,
            'The $subjectWords is not due yet.',
            '          ',
          ),
        )
        ..writeln('        }')
        ..writeln('      }')
        ..writeln('    } else {')
        ..write(slot)
        ..writeln('    }');
    } else {
      buffer
        ..writeln('    {')
        ..write(slot)
        ..writeln('    }');
    }
    final create = aggregate
        ? '$draftType.create(entityGraph)'
        : 'entityGraph.${log.setAccessor}.beginCreate()';
    final edit = aggregate
        ? 'await existing.beginAggregateEdit(entityGraph)'
        : 'existing.beginEdit()';
    final row = aggregate ? 'draft.root' : 'draft';
    buffer
      ..writeln('    final draft = existing == null ? $create : $edit;')
      ..writeln('    $row')
      ..write('      ..${resolved.at.name} = now');
    for (final field in details) {
      buffer.write('\n      ..${field.name} = ${field.name}');
    }
    buffer
      ..writeln(';')
      ..writeln('    if (draft.isCreating) {')
      ..writeln('      $row')
      ..writeln('        ..$subjectId = id')
      ..writeln('        ..${resolved.date.name} = today')
      ..writeln('        ..${resolved.part.name} = part;')
      ..writeln('    }')
      ..writeln('    return draft;')
      ..writeln('  }')
      ..writeln()
      ..write(_undo())
      ..writeln()
      ..write(_logDay())
      ..writeln()
      ..write(_owes())
      ..writeln('}');
    return buffer.toString();
  }

  String _requireLive(String indent) {
    final subject = resolved.subject;
    if (!subject.hasSoftDeletableCapability) return '';
    return '${indent}if (deletedAt != null) {\n'
        '$indent  throw EntityNotFoundException(\n'
        "$indent    entityType: '${subject.className}',\n"
        '$indent    entityId: id.value,\n'
        '$indent  );\n'
        '$indent}\n';
  }

  String _undo() {
    final subjectId = resolved.subjectField.name;
    final date = resolved.date.name;
    final part = resolved.part.name;
    final at = resolved.at.name;
    final hasIntervals = resolved.intervals.isNotEmpty;
    final buffer = StringBuffer()
      ..writeln(
        '  /// Takes back the check-ins of [$date], today by default, in',
      )
      ..writeln(
        '  /// [$part], the current part of the day by default, and returns '
        'them;',
      )
      ..writeln(
        '  /// an interval $subjectWords takes back its latest check-in, '
        'whatever its day.',
      )
      ..writeln('  Future<List<$logType>> undoCheckIn(')
      ..writeln('    $entityGraphName entityGraph, {')
      ..writeln('    LocalDate? $date,')
      ..writeln('    $partType? $part,')
      ..writeln('    String? ${resolved.undoComment.name},')
      ..writeln('  }) async {')
      ..write(_requireLive('    '))
      ..writeln('    final local = entityGraph.nowUtc().toLocal();')
      ..writeln('    final day = $date ?? LocalDate.fromDateTime(local);')
      ..writeln(
        '    final wholeDay = this.${resolved.scheduledParts.name}.contains($wholeDay);',
      )
      ..writeln(
        '    final slot = wholeDay ? $wholeDay : ($part ?? ${resolved.partAtDart}(local));',
      )
      ..writeln('    final List<$logType> undone;');
    final ownSlots =
        '      undone = await ${logType}List.owned(\n'
        '        entityGraph,\n'
        '        where:\n'
        '            $fields.$subjectId.equals(id) &\n'
        '            $fields.$date.equals(day) &\n'
        '            (wholeDay\n'
        '                ? EntityPredicate<$logType>.all()\n'
        '                : $fields.$part.isIn({slot, $wholeDay})),\n'
        '        orderBy: $fields.$at.descending(),\n'
        '      ).useAll((rows) => List.of(rows));\n';
    if (hasIntervals) {
      buffer
        ..writeln('    if ($_intervalActive) {')
        ..writeln('      final latest = await ${logType}List.all(')
        ..writeln('        entityGraph,')
        ..writeln('        where: $fields.$subjectId.equals(id),')
        ..writeln('        orderBy: $fields.$at.descending(),')
        ..writeln('        pageSize: 1,')
        ..writeln('      ).useAll((rows) => rows.firstOrNull);')
        ..writeln('      if (latest == null) return const [];')
        ..writeln('      if (latest.ownerId != entityGraph.accountId) {')
        ..writeln(
          _throw(
            'ownerId',
            "The latest check-in is a collaborator's to undo.",
            '        ',
          ),
        )
        ..writeln('      }')
        ..writeln('      undone = [latest];')
        ..writeln('    } else {')
        ..write(ownSlots)
        ..writeln('    }');
    } else {
      buffer.write(ownSlots.replaceFirst('      ', '    '));
    }
    buffer
      ..writeln('    if (undone.isEmpty) return const [];')
      ..writeln('    await entityGraph.transaction(() async {')
      ..writeln('      for (final row in undone) {')
      ..writeln('        await row.remove();')
      ..writeln(
        '        await entityGraph.${resolved.undo.setAccessor}.create(',
      )
      ..writeln('          $subjectId: row.$subjectId,')
      ..writeln('          $date: row.$date,')
      ..writeln('          $part: row.$part,')
      ..writeln(
        '          ${resolved.undoComment.name}: ${resolved.undoComment.name},',
      )
      ..writeln('        );')
      ..writeln('      }')
      ..writeln('    });')
      ..writeln('    return undone;')
      ..writeln('  }');
    return buffer.toString();
  }

  String _logDay() {
    final subjectId = resolved.subjectField.name;
    final date = resolved.date.name;
    final part = resolved.part.name;
    final at = resolved.at.name;
    final flags = resolved.scheduledParts.name;
    final hasIntervals = resolved.intervals.isNotEmpty;
    final create = aggregate
        ? '$draftType.create(entityGraph)'
        : 'entityGraph.${log.setAccessor}.beginCreate()';
    final edit = aggregate
        ? 'await current.beginAggregateEdit(entityGraph)'
        : 'current.beginEdit()';
    final row = aggregate ? 'draft.root' : 'draft';
    final available = <String>[
      if (resolved.since case final since?)
        '$date.compareTo(LocalDate.fromDateTime(this.${since.name}.toLocal())) >= 0',
      if (resolved.days case (final variant, final variantCase, final field))
        'switch (this.${variant.name}) { ${variantCase.className}(:final ${field.name}) => '
            '${field.name}.toScalar() & (1 << day.weekday % 7) != 0, _ => true }',
    ];
    final buffer = StringBuffer()
      ..writeln(
        '  /// Starts logging [$date], a past day, for [$part] or else every '
        'part',
      )
      ..writeln(
        '  /// of the day this $subjectWords is scheduled for, skipping parts '
        'already',
      )
      ..writeln(
        '  /// logged; saving each returned draft records one. The check-ins '
        'record',
      )
      ..writeln(
        '  /// the time of day of [$at], or ${resolved.spec.loggedAtHour}:00.',
      )
      ..writeln('  Future<List<$draftType>> beginLogDay(')
      ..writeln('    $entityGraphName entityGraph, {')
      ..writeln('    required LocalDate $date,')
      ..writeln('    $partType? $part,')
      ..writeln('    DateTime? $at,')
      ..writeln('  }) async {')
      ..write(_requireLive('    '));
    for (final refusal in resolved.spec.refusals) {
      buffer
        ..writeln('    if (this.${refusal.fieldName}) {')
        ..writeln(_throw(subjectId, refusal.message, '      '))
        ..writeln('    }');
    }
    buffer
      ..writeln(
        '    final today = LocalDate.fromDateTime(entityGraph.nowUtc().toLocal());',
      )
      ..writeln('    if ($date.compareTo(today) >= 0) {')
      ..writeln(
        _throw(date, 'Only a day before today can be logged.', '      '),
      )
      ..writeln('    }')
      ..writeln('    final day = $date.toDateTime();');
    if (available.isNotEmpty) {
      buffer
        ..writeln('    if (!(${available.join(' && ')})) {')
        ..writeln(
          _throw(
            date,
            'The $subjectWords is not available on this date.',
            '      ',
          ),
        )
        ..writeln('    }');
    }
    buffer
      ..writeln('    final wholeDay = this.$flags.contains($wholeDay);')
      ..writeln(
        '    final scheduled = [for (final each in const [${[for (final name in resolved.parts) '$partType.$name'].join(', ')}]) if (this.$flags.contains(each)) each];',
      )
      ..writeln(
        '    final interval = ${hasIntervals ? _intervalActive : 'false'};',
      )
      ..writeln('    final requested = wholeDay')
      ..writeln('        ? [$wholeDay]')
      ..writeln('        : $part != null')
      ..writeln('        ? [$part]')
      ..writeln('        : interval')
      ..writeln('        ? scheduled.take(1).toList()')
      ..writeln('        : scheduled;')
      ..writeln(
        '    if (requested.isEmpty || requested.any((each) => !wholeDay && !scheduled.contains(each))) {',
      )
      ..writeln(
        _throw(
          part,
          'The $subjectWords is not scheduled for this $partWords.',
          '      ',
        ),
      )
      ..writeln('    }')
      ..writeln('    final existing = await ${logType}List.owned(')
      ..writeln('      entityGraph,')
      ..writeln(
        '      where: $fields.$subjectId.equals(id) & $fields.$date.equals($date),',
      )
      ..writeln('      orderBy: $fields.$at.descending(),')
      ..writeln('      tombstones: TombstoneVisibility.include,')
      ..writeln('    ).useAll((rows) => List.of(rows));')
      ..writeln(
        '    final live = {for (final row in existing) if (row.deletedAt == null) row.$part};',
      )
      ..writeln('    final logged = live.isEmpty')
      ..writeln('        ? const <$partType>{}')
      ..writeln('        : live.contains($wholeDay)')
      ..writeln('        ? (wholeDay ? {$wholeDay} : scheduled.toSet())')
      ..writeln('        : wholeDay')
      ..writeln('        ? {$wholeDay}')
      ..writeln('        : live.intersection(scheduled.toSet());')
      ..writeln('    final time = $at?.toLocal();')
      ..writeln('    final occurrence = DateTime(')
      ..writeln('      day.year,')
      ..writeln('      day.month,')
      ..writeln('      day.day,')
      ..writeln('      time?.hour ?? ${resolved.spec.loggedAtHour},')
      ..writeln('      time?.minute ?? 0,')
      ..writeln('      time?.second ?? 0,')
      ..writeln('      time?.millisecond ?? 0,')
      ..writeln('      time?.microsecond ?? 0,')
      ..writeln('    ).toUtc();')
      ..writeln('    final drafts = <$draftType>[];')
      ..writeln('    for (final each in requested) {')
      ..writeln('      if (!interval && logged.contains(each)) continue;')
      ..writeln('      final current = interval')
      ..writeln('          ? null')
      ..writeln(
        '          : existing.where((row) => row.$part == each).firstOrNull;',
      )
      ..writeln(
        '      if (current?.deletedAt != null) await current!.restore();',
      )
      ..writeln('      final draft = current == null ? $create : $edit;')
      ..writeln('      $row')
      ..write('        ..$at = occurrence');
    for (final field in resolved.details) {
      buffer.write(
        '\n        ..${field.name} = ${field.nullable ? 'null' : _default(field)}',
      );
    }
    buffer
      ..writeln(';')
      ..writeln('      if (draft.isCreating) {')
      ..writeln('        $row')
      ..writeln('          ..$subjectId = id')
      ..writeln('          ..$date = $date')
      ..writeln('          ..$part = each;')
      ..writeln('      }')
      ..writeln('      drafts.add(draft);')
      ..writeln('    }')
      ..writeln('    return drafts;')
      ..writeln('  }');
    return buffer.toString();
  }

  /// Whether the subject is scheduled on a day and the owner has not yet
  /// checked in every part of it.
  String _owes() {
    final subjectId = resolved.subjectField.name;
    final date = resolved.date.name;
    final part = resolved.part.name;
    final flags = resolved.scheduledParts.name;
    final free = [
      for (final (variant, variantCase, _) in resolved.unscheduled)
        'this.${variant.name} is ${variantCase.className}',
      if (resolved.intervals.isNotEmpty) _intervalActive,
    ];
    final days = switch (resolved.days) {
      (final variant, final variantCase, final field) =>
        'switch (this.${variant.name}) { ${variantCase.className}(:final ${field.name}) => '
            '${field.name}.toScalar() & (1 << day.toDateTime().weekday % 7) == 0, _ => false }',
      null => null,
    };
    final buffer = StringBuffer()
      ..writeln(
        '  /// Whether this $subjectWords is due on [day] and the account has '
        'not checked',
      )
      ..writeln('  /// in every part of the day it is scheduled for.')
      ..writeln(
        '  Future<bool> owesCheckInOn($entityGraphName entityGraph, LocalDate day) async {',
      );
    if (free.isNotEmpty) {
      buffer.writeln('    if (${free.join(' || ')}) return false;');
    }
    if (days != null) buffer.writeln('    if ($days) return false;');
    buffer
      ..writeln('    final logged = await ${logType}List.owned(')
      ..writeln('      entityGraph,')
      ..writeln(
        '      where: $fields.$subjectId.equals(id) & $fields.$date.equals(day),',
      )
      ..writeln('    ).useAll((rows) => {for (final row in rows) row.$part});')
      ..writeln('    if (logged.isEmpty) return true;')
      ..writeln(
        '    if (logged.contains($wholeDay) || this.$flags.contains($wholeDay)) return false;',
      )
      ..writeln(
        '    return const [${[for (final name in resolved.parts) '$partType.$name'].join(', ')}]',
      )
      ..writeln(
        '        .any((each) => this.$flags.contains(each) && !logged.contains(each));',
      )
      ..writeln('  }');
    return buffer.toString();
  }

  String _default(FieldSpec field) {
    final value = field.persistedDefaultValue;
    if (value == null) {
      throw InvalidGenerationSourceError(
        'A CheckIns detail must be nullable or have a default: '
        '`${field.name}` of $logType.',
      );
    }
    if (field.isEnum) {
      final index = field.enumWireValues.indexOf(value as String);
      return '${field.dartType}.${field.enumValues[index]}';
    }
    return dartLiteral(value);
  }
}
