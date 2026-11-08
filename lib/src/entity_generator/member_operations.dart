import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';
import 'sql_emitter.dart' show postgresType;

/// One part of a [DerivedIdentitySpec] key: a field or a persisted variant.
final class IdentityKeyPart {
  IdentityKeyPart._(this.name, {this.field, this.variant});

  final String name;
  final FieldSpec? field;
  final PersistedVariantSpec? variant;

  String get dartType => variant?.dartType ?? field!.dartType;

  /// Variant cases with the name each contributes, such as `task`.
  List<(PersistedVariantCaseSpec, String, FieldSpec)> get cases => [
    for (final variantCase in variant!.cases)
      (
        variantCase,
        _caseName(variantCase.className, variant!.dartType),
        variantCase.fields.single,
      ),
  ];
}

String _caseName(String className, String variantType) {
  final base = variantType.replaceAll('?', '');
  final stem = className.endsWith(base)
      ? className.substring(0, className.length - base.length)
      : className;
  return lowerCamelCase(stem);
}

/// A resolved [DerivedIdentitySpec] of [entity].
final class ResolvedIdentity {
  ResolvedIdentity._(this.entity, this.parts);

  factory ResolvedIdentity.of(EntitySpec entity) {
    final identity = entity.identity!;
    final parts = <IdentityKeyPart>[];
    for (final name in identity.keyFieldNames) {
      final variant = entity.persistedVariants
          .where((candidate) => candidate.name == name)
          .firstOrNull;
      if (variant != null) {
        for (final variantCase in variant.cases) {
          if (variantCase.fields.length != 1) {
            throw InvalidGenerationSourceError(
              'DerivedIdentity key `$name` of ${entity.className} needs one '
              'field per case.',
            );
          }
        }
        parts.add(IdentityKeyPart._(name, variant: variant));
        continue;
      }
      final field = entity.fields
          .where((candidate) => candidate.name == name)
          .firstOrNull;
      if (field == null) {
        throw InvalidGenerationSourceError(
          'DerivedIdentity key `$name` is not a field of ${entity.className}.',
        );
      }
      _dartText(field, 'x');
      parts.add(IdentityKeyPart._(name, field: field));
    }
    return ResolvedIdentity._(entity, parts);
  }

  final EntitySpec entity;
  final List<IdentityKeyPart> parts;

  String get namespace => entity.identity!.namespace;
  String get dartFunction => '${lowerCamelCase(entity.className)}IdFor';
  String get sqlFunction => 'public.${entity.tableName}_id_for';

  String dartDeclaration() {
    final parameters = [
      for (final part in parts) '${part.dartType} ${part.name}',
    ];
    final name = parts.map(_dartPart).join('/');
    return '''
/// The identity every device gives the ${entity.className} with this key.
LocalId<${entity.className}> $dartFunction(${parameters.join(', ')}) =>
    derivedLocalId<${entity.className}>('$namespace', '$name');
''';
  }

  String _dartPart(IdentityKeyPart part) {
    if (part.variant == null) return '\${${_dartText(part.field!, part.name)}}';
    final cases = [
      for (final (variantCase, caseName, field) in part.cases)
        "${variantCase.className}(:final ${field.name}) => "
            "'$caseName/\${${_dartText(field, field.name)}}'",
    ];
    return '\${switch (${part.name}) { ${cases.join(', ')} }}';
  }

  /// SQL columns the identity function takes, in order.
  List<FieldSpec> get sqlColumns => [
    for (final part in parts)
      if (part.variant == null)
        part.field!
      else
        for (final (_, _, field) in part.cases) field,
  ];

  String sqlDeclaration() {
    final parameters = [
      for (final column in sqlColumns)
        'p_${column.columnName} ${postgresType(column)}',
    ];
    final pieces = [
      for (final part in parts)
        if (part.variant == null)
          _sqlText(part.field!, 'p_${part.field!.columnName}')
        else
          'case ${[for (final (_, caseName, field) in part.cases) "when p_${field.columnName} is not null then '$caseName/' || ${_sqlText(field, 'p_${field.columnName}')}"].join(' ')} end',
    ];
    return '''
create or replace function $sqlFunction(${parameters.join(', ')})
returns uuid
language sql
immutable
set search_path = ''
as \$\$
  select public.nodus_uuid_v5('$namespace'::uuid, ${pieces.join(" || '/' || ")})
\$\$;
''';
  }

  String get sqlSignature =>
      '$sqlFunction(${sqlColumns.map(postgresType).join(', ')})';
}

String _dartText(FieldSpec field, String value) {
  final type = field.dartType.replaceAll('?', '');
  if (type.startsWith('LocalId<') || type == 'LocalDate') return '$value.value';
  if (type == 'String' || type == 'int') return value;
  throw InvalidGenerationSourceError(
    'DerivedIdentity cannot key on `${field.name}` of type $type.',
  );
}

String _sqlText(FieldSpec field, String value) {
  final type = field.dartType.replaceAll('?', '');
  if (type == 'LocalDate') return "to_char($value, 'YYYY-MM-DD')";
  return '$value::text';
}

/// The UUIDv5 the generated identity functions share with `derivedLocalId`.
const uuidV5Sql = r'''
create or replace function public.nodus_uuid_v5(p_namespace uuid, p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  hash bytea := substring(
    extensions.digest(
      decode(replace(p_namespace::text, '-', ''), 'hex') ||
        convert_to(p_name, 'UTF8'),
      'sha1'
    ) from 1 for 16
  );
begin
  hash := set_byte(hash, 6, (get_byte(hash, 6) & 15) | 80);
  hash := set_byte(hash, 8, (get_byte(hash, 8) & 63) | 128);
  return encode(hash, 'hex')::uuid;
end;
$$;
''';

/// Declared member operations of [root], checked against the member entity.
final class ResolvedMemberOperations {
  ResolvedMemberOperations._({
    required this.root,
    required this.member,
    required this.rootReference,
    required this.key,
    required this.identity,
    required this.graph,
  });

  factory ResolvedMemberOperations.of(EntitySpec root, EntityGraphSpec graph) {
    final declared = root.memberOperations!;
    final matches = [
      for (final entity in graph.entities)
        for (final field in entity.fields)
          if (field.reference?.targetClassName == root.className &&
              field.reference?.inverseName == declared.collection)
            (entity, field),
    ];
    if (matches.length != 1) {
      throw InvalidGenerationSourceError(
        'MemberOperations on ${root.className} name `${declared.collection}`, '
        'which is not the inverse of one reference.',
      );
    }
    final (member, rootReference) = matches.single;
    if (member.identity == null) {
      throw InvalidGenerationSourceError(
        'MemberOperations need a DerivedIdentity on ${member.className}.',
      );
    }
    final identity = ResolvedIdentity.of(member);
    if (identity.parts.length != 2 ||
        identity.parts.first.name != rootReference.name) {
      throw InvalidGenerationSourceError(
        'The DerivedIdentity of ${member.className} must key on '
        '`${rootReference.name}` and one more field.',
      );
    }
    if (!member.hasSoftDeletableCapability || !member.hasOrderedCapability) {
      throw InvalidGenerationSourceError(
        'MemberOperations need an ordered, soft-deletable member: '
        '${member.className}.',
      );
    }
    final resolved = ResolvedMemberOperations._(
      root: root,
      member: member,
      rootReference: rootReference,
      key: identity.parts.last,
      identity: identity,
      graph: graph,
    );
    for (final operation in declared.operations) {
      resolved._validate(operation);
    }
    return resolved;
  }

  final EntitySpec root;
  final EntitySpec member;
  final FieldSpec rootReference;
  final IdentityKeyPart key;
  final ResolvedIdentity identity;
  final EntityGraphSpec graph;

  List<MemberOperationSpec> get operations => root.memberOperations!.operations;
  String get collection => rootReference.reference!.inverseName;
  String get rowsClass => '_${member.className}OperationRows';

  FieldSpec field(String name) =>
      member.fields.where((field) => field.name == name).firstOrNull ??
      (throw InvalidGenerationSourceError(
        '`$name` is not a field of ${member.className}.',
      ));

  ActionSpec action(String name) =>
      member.actions.where((action) => action.methodName == name).firstOrNull ??
      (throw InvalidGenerationSourceError(
        '`$name` is not a declared action of ${member.className}.',
      ));

  OperationParameterSpec parameter(
    MemberOperationSpec operation,
    String name,
  ) =>
      operation.parameters
          .where((parameter) => parameter.name == name)
          .firstOrNull ??
      (throw InvalidGenerationSourceError(
        '`$name` is not a parameter of ${operation.name}.',
      ));

  /// The variant case and target entity a [KeyTargetValueSpec] reads.
  (PersistedVariantCaseSpec, FieldSpec, EntitySpec, FieldSpec) keyTarget(
    KeyTargetValueSpec value,
  ) {
    if (key.variant == null) {
      throw InvalidGenerationSourceError(
        'KeyTarget reads a case of a variant key; '
        '${member.className}.${key.name} is a plain field.',
      );
    }
    for (final (variantCase, _, field) in key.cases) {
      if (field.name != value.reference) continue;
      final target = graph.entities
          .where(
            (entity) => entity.className == field.reference?.targetClassName,
          )
          .firstOrNull;
      if (target == null) break;
      final targetField = target.fields
          .where((candidate) => candidate.name == value.field)
          .firstOrNull;
      if (targetField == null) {
        throw InvalidGenerationSourceError(
          '`${value.field}` is not a field of ${target.className}.',
        );
      }
      return (variantCase, field, target, targetField);
    }
    throw InvalidGenerationSourceError(
      'KeyTarget `${value.reference}` is not a reference case of '
      '${member.className}.${key.name}.',
    );
  }

  void _validate(MemberOperationSpec operation) {
    for (final parameter in operation.parameters) {
      if (parameter.fieldName != null) field(parameter.fieldName!);
      if (parameter.name == key.name) {
        throw InvalidGenerationSourceError(
          '${operation.name} cannot name a parameter `${key.name}`: it is the '
          'member key.',
        );
      }
    }
    void checkValue(OperationValueSpec value) {
      switch (value) {
        case MemberFieldValueSpec(:final field):
          this.field(field);
        case ParameterValueSpec(:final name):
          parameter(operation, name);
        case KeyTargetValueSpec():
          keyTarget(value);
      }
    }

    void checkCondition(OperationConditionSpec condition) {
      switch (condition) {
        case MemberLiveConditionSpec():
          break;
        case NotConditionSpec(:final condition):
          checkCondition(condition);
        case AllConditionSpec(:final conditions):
          conditions.forEach(checkCondition);
        case CompareConditionSpec(:final subject, :final kind, :final other):
          checkValue(subject);
          if (other != null) checkValue(other);
          if (kind == CompareKind.isIn) {
            final target = subject is MemberFieldValueSpec
                ? field(subject.field)
                : null;
            if (target == null || !target.isEnum) {
              throw InvalidGenerationSourceError(
                'Compare.isIn compares an enum field of ${member.className}.',
              );
            }
          }
      }
    }

    void checkSteps(List<MemberStepSpec> steps) {
      for (final step in steps) {
        switch (step) {
          case RequireStepSpec(:final condition):
            checkCondition(condition);
          case WhenStepSpec(:final condition, :final then, :final otherwise):
            checkCondition(condition);
            checkSteps(then);
            checkSteps(otherwise);
          case StopStepSpec():
            break;
          case EnsureMemberStepSpec(:final values, :final reset):
            values.keys.forEach(field);
            values.values.forEach(checkValue);
            if (reset != null) {
              for (final parameter in action(reset).parameters) {
                field(parameter.fieldName);
              }
            }
          case ActStepSpec(action: final name, :final arguments):
            final declared = action(name);
            for (final argument in arguments.keys) {
              if (!declared.parameters.any((p) => p.name == argument)) {
                throw InvalidGenerationSourceError(
                  '`$argument` is not a parameter of '
                  '${member.className}.$name.',
                );
              }
            }
            arguments.values.forEach(checkValue);
          case PlaceStepSpec(:final group, :final after, :final before):
            checkCondition(group);
            for (final anchor in [?after, ?before]) {
              if (!parameter(operation, anchor).isMember) {
                throw InvalidGenerationSourceError(
                  'Place.nextTo anchors must be member parameters: `$anchor`.',
                );
              }
            }
        }
      }
    }

    checkSteps(operation.steps);
  }
}

/// Generated Dart for every declared identity and member operation.
String emitMemberOperationsDart(EntityGraphSpec graph, String entityGraphName) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (entity.identity == null) continue;
    buffer
      ..writeln()
      ..write(ResolvedIdentity.of(entity).dartDeclaration());
  }
  for (final root in graph.entities) {
    if (root.memberOperations == null) continue;
    final resolved = ResolvedMemberOperations.of(root, graph);
    buffer
      ..writeln()
      ..write(_DartOperations(resolved, entityGraphName).emit());
    if (root.memberOperations!.root != null) {
      buffer
        ..writeln()
        ..write(_dayRootDart(resolved, entityGraphName));
    }
  }
  return buffer.toString();
}

final class _DartOperations {
  _DartOperations(this.operations, this.entityGraphName);

  final ResolvedMemberOperations operations;
  final String entityGraphName;

  EntitySpec get member => operations.member;
  String get memberType => member.className;
  String get keyName => operations.key.name;
  String get keyType => operations.key.dartType.replaceAll('?', '');
  String get set => 'entityGraph.${member.setAccessor}';

  String emit() {
    final buffer = StringBuffer()
      ..writeln(
        'extension ${operations.root.className}MemberOperations '
        'on ${operations.root.className} {',
      );
    for (final operation in operations.operations) {
      buffer
        ..writeln(_documentation(operation))
        ..writeln('  Future<void> ${operation.name}(')
        ..writeln('    $entityGraphName entityGraph,')
        ..write('    $keyType $keyName');
      if (operation.parameters.isEmpty) {
        buffer.writeln(',');
      } else {
        buffer.writeln(', {');
        for (final parameter in operation.parameters) {
          buffer.writeln('    ${_parameterType(parameter)} ${parameter.name},');
        }
        buffer.writeln('  }');
      }
      buffer
        ..writeln('  ) async {')
        ..writeln('    final rows = await $rowsClass.load(entityGraph, this);')
        ..writeln('    var member = rows.live($keyName);');
      _sequence(buffer, operation, operation.steps, '    ', atomic: false);
      buffer
        ..writeln('  }')
        ..writeln();
    }
    buffer
      ..writeln('}')
      ..writeln()
      ..write(_rowsClass());
    return buffer.toString();
  }

  String get rowsClass => operations.rowsClass;

  String _rowsClass() =>
      '''
/// One ${operations.root.className}'s ${operations.collection}, live and removed, in order.
final class $rowsClass {
  $rowsClass(this.all);

  static Future<$rowsClass> load(
    $entityGraphName entityGraph,
    ${operations.root.className} root,
  ) => root
      .${operations.collection}(entityGraph, tombstones: TombstoneVisibility.include)
      .useAll((rows) => $rowsClass(List.unmodifiable(rows)));

  final List<$memberType> all;

  Iterable<$memberType> get liveRows => all.where((row) => row.deletedAt == null);

  $memberType? live($keyType? key) => key == null
      ? null
      : liveRows.where((row) => row.$keyName == key).firstOrNull;

  $memberType? removed($keyType key) => all
      .where((row) => row.deletedAt != null && row.$keyName == key)
      .firstOrNull;
}
''';

  String _documentation(MemberOperationSpec operation) => [
    for (final line in operation.description.split('\n')) '  /// $line',
  ].join('\n');

  String _parameterType(OperationParameterSpec parameter) {
    if (parameter.isMember) return '$keyType?';
    final type = operations.field(parameter.fieldName!).dartType;
    return type.endsWith('?') ? type : '$type?';
  }

  /// The most changes any path through [steps] makes.
  static int _changes(List<MemberStepSpec> steps) {
    if (steps.isEmpty) return 0;
    final step = steps.first;
    final rest = steps.sublist(1);
    return switch (step) {
      StopStepSpec() => 0,
      RequireStepSpec() => _changes(rest),
      WhenStepSpec(:final then, :final otherwise) => [
        _endsPath(then) ? _changes(then) : _changes([...then, ...rest]),
        _endsPath(otherwise)
            ? _changes(otherwise)
            : _changes([...otherwise, ...rest]),
      ].reduce((a, b) => a > b ? a : b),
      EnsureMemberStepSpec(:final reset) =>
        (reset == null ? 2 : 3) + _changes(rest),
      ActStepSpec() || PlaceStepSpec() => 1 + _changes(rest),
    };
  }

  static bool _endsPath(List<MemberStepSpec> steps) =>
      steps.isNotEmpty && steps.last is StopStepSpec;

  /// Emits [steps], opening one graph transaction where a path from there
  /// can make two or more changes, so a single change is awaited on its own.
  void _sequence(
    StringBuffer buffer,
    MemberOperationSpec operation,
    List<MemberStepSpec> steps,
    String indent, {
    required bool atomic,
  }) {
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      final remaining = steps.sublist(index);
      final branchEnds =
          step is WhenStepSpec &&
          step.otherwise.isEmpty &&
          _endsPath(step.then);
      if (!atomic &&
          !branchEnds &&
          step is! RequireStepSpec &&
          _changes(remaining) >= 2) {
        buffer.writeln('${indent}await entityGraph.transaction(() async {');
        _sequence(buffer, operation, remaining, '$indent  ', atomic: true);
        buffer.writeln('$indent});');
        if (_endsPath(remaining)) buffer.writeln('${indent}return;');
        return;
      }
      if (branchEnds) {
        buffer.writeln(
          '${indent}if (${_condition(step.condition, 'member')}) {',
        );
        _sequence(buffer, operation, step.then, '$indent  ', atomic: atomic);
        buffer.writeln('$indent}');
        continue;
      }
      _steps(buffer, operation, [step], indent, atomic: atomic);
    }
  }

  void _steps(
    StringBuffer buffer,
    MemberOperationSpec operation,
    List<MemberStepSpec> steps,
    String indent, {
    required bool atomic,
  }) {
    for (final step in steps) {
      switch (step) {
        case RequireStepSpec(:final condition, :final message):
          buffer
            ..writeln(
              '${indent}if (${condition is NotConditionSpec ? _condition(condition.condition, 'member') : '!${_condition(condition, 'member')}'}) {',
            )
            ..writeln('$indent  throw const EntityValidationException(')
            ..writeln("$indent    entityType: '$memberType',")
            ..writeln("$indent    field: '$keyName',")
            ..writeln('$indent    message: ${dartLiteral(message)},')
            ..writeln('$indent  );')
            ..writeln('$indent}');
        case WhenStepSpec(:final condition, :final then, :final otherwise):
          buffer.writeln('${indent}if (${_condition(condition, 'member')}) {');
          _sequence(buffer, operation, then, '$indent  ', atomic: atomic);
          if (otherwise.isNotEmpty) {
            buffer.writeln('$indent} else {');
            _sequence(
              buffer,
              operation,
              otherwise,
              '$indent  ',
              atomic: atomic,
            );
          }
          buffer.writeln('$indent}');
        case StopStepSpec():
          buffer.writeln('${indent}return;');
        case EnsureMemberStepSpec(:final values, :final reset):
          final created = [
            'id: ${operations.identity.dartFunction}(id, $keyName)',
            '$keyName: $keyName',
            for (final entry in values.entries)
              '${entry.key}: ${_value(entry.value)}',
          ];
          buffer
            ..writeln('${indent}if (member == null) {')
            ..writeln('$indent  final removed = rows.removed($keyName);')
            ..writeln('$indent  if (removed == null) {')
            ..writeln(
              '$indent    member = await ${operations.collection}(entityGraph)'
              '.create(${created.join(', ')});',
            )
            ..writeln('$indent  } else {')
            ..writeln('$indent    await removed.restore();');
          if (reset != null) {
            final action = operations.action(reset);
            buffer.writeln(
              '$indent    await removed.$reset(${_resetArguments(action, values)});',
            );
          }
          buffer
            ..writeln('$indent    await $set.append(removed.id);')
            ..writeln('$indent    member = removed;')
            ..writeln('$indent  }')
            ..writeln('$indent}');
        case ActStepSpec(:final action, :final arguments):
          final declared = operations.action(action);
          final values = [
            for (final parameter in declared.parameters)
              _argument(
                parameter,
                arguments[parameter.name] == null
                    ? _fieldDefault(operations.field(parameter.fieldName))
                    : _value(arguments[parameter.name]!),
              ),
          ];
          buffer.writeln(
            '${indent}await member!.$action(${values.join(', ')});',
          );
        case PlaceStepSpec(:final group, :final after, :final before):
          if (after == null && before == null) {
            _placeAfterLast(buffer, group, indent);
            break;
          }
          buffer
            ..writeln('$indent{')
            ..writeln(
              '$indent  final inGroup = ${_condition(group, 'member')};',
            )
            ..writeln(
              '$indent  bool sameSide($memberType? other) => other != null && '
              'other.id != member!.id && ${_condition(group, 'other')} == inGroup;',
            )
            ..writeln(
              '$indent  final afterRow = rows.live(${after ?? 'null'});',
            )
            ..writeln(
              '$indent  final beforeRow = rows.live(${before ?? 'null'});',
            )
            ..writeln('$indent  if (sameSide(afterRow)) {')
            ..writeln(
              '$indent    await $set.moveAfter(member!.id, afterRow!.id);',
            )
            ..writeln('$indent  } else if (sameSide(beforeRow)) {')
            ..writeln(
              '$indent    await $set.moveBefore(member!.id, beforeRow!.id);',
            )
            ..writeln(
              '$indent  } else if (!inGroup && ${_condition(group, 'afterRow')}) {',
            );
          _placeAfterLast(buffer, group, '$indent    ');
          buffer
            ..writeln('$indent  }')
            ..writeln('$indent}');
      }
    }
  }

  void _placeAfterLast(
    StringBuffer buffer,
    OperationConditionSpec group,
    String indent,
  ) {
    buffer
      ..writeln('$indent{')
      ..writeln(
        '$indent  final placed = await $rowsClass.load(entityGraph, this);',
      )
      ..writeln('$indent  final anchors = [')
      ..writeln('$indent    for (final row in placed.liveRows)')
      ..writeln(
        '$indent      if (row.id != member!.id && ${_condition(group, 'row')}) row,',
      )
      ..writeln('$indent  ];')
      ..writeln('$indent  if (anchors.isEmpty) {')
      ..writeln('$indent    await $set.prepend(member!.id);')
      ..writeln('$indent  } else {')
      ..writeln('$indent    await $set.moveAfter(member!.id, anchors.last.id);')
      ..writeln('$indent  }')
      ..writeln('$indent}');
  }

  String _argument(ActionParameterSpec parameter, String value) =>
      parameter.named ? '${parameter.name}: $value' : value;

  String _resetArguments(
    ActionSpec action,
    Map<String, OperationValueSpec> values,
  ) => [
    for (final parameter in action.parameters)
      _argument(
        parameter,
        values[parameter.name] == null
            ? _fieldDefault(operations.field(parameter.fieldName))
            : _value(values[parameter.name]!),
      ),
  ].join(', ');

  String _fieldDefault(FieldSpec field) {
    final value = field.persistedDefaultValue;
    if (value == null) {
      if (field.nullable) return 'null';
      throw InvalidGenerationSourceError(
        'A member operation must give `${field.name}` of $memberType a value: '
        'it has no default.',
      );
    }
    if (field.isEnum) {
      final index = field.enumWireValues.indexOf(value as String);
      return '${field.dartType}.${field.enumValues[index]}';
    }
    return dartLiteral(value);
  }

  String _value(OperationValueSpec value) => switch (value) {
    MemberFieldValueSpec(:final field) => 'member!.$field',
    ParameterValueSpec(:final name) => name,
    KeyTargetValueSpec() => throw InvalidGenerationSourceError(
      'KeyTarget is only supported in Compare.isTrue.',
    ),
  };

  /// [condition] on the row named [subject], which may be null.
  String _condition(OperationConditionSpec condition, String subject) {
    switch (condition) {
      case MemberLiveConditionSpec():
        return '($subject != null)';
      case NotConditionSpec(:final condition):
        return '!${_condition(condition, subject)}';
      case AllConditionSpec(:final conditions):
        return '(${conditions.map((part) => _condition(part, subject)).join(' && ')})';
      case CompareConditionSpec(
        subject: final value,
        :final kind,
        :final values,
        :final other,
      ):
        return _compare(value, kind, values, other, subject);
    }
  }

  String _compare(
    OperationValueSpec value,
    CompareKind kind,
    List<String> values,
    OperationValueSpec? other,
    String subject,
  ) {
    // `member` is reassigned inside transactions, so Dart does not narrow it.
    final row = subject == 'member' ? 'member!' : subject;
    String operand(OperationValueSpec operand) => switch (operand) {
      MemberFieldValueSpec(:final field) => '$row.$field',
      ParameterValueSpec(:final name) => name,
      KeyTargetValueSpec() => throw InvalidGenerationSourceError(
        'KeyTarget is only supported in Compare.isTrue.',
      ),
    };
    String present(OperationValueSpec operand) => switch (operand) {
      MemberFieldValueSpec() => '$subject != null',
      ParameterValueSpec(:final name) => '$name != null',
      KeyTargetValueSpec() => 'true',
    };
    switch (kind) {
      case CompareKind.isIn:
        final field = operations.field((value as MemberFieldValueSpec).field);
        final type = field.dartType.replaceAll('?', '');
        final constants = values.map((name) => '$type.$name').join(', ');
        return '($subject != null && '
            'const <$type>{$constants}.contains(${operand(value)}))';
      case CompareKind.isNull:
        return value is ParameterValueSpec
            ? '(${value.name} == null)'
            : '(${present(value)} && ${operand(value)} == null)';
      case CompareKind.isTrue:
        if (value is KeyTargetValueSpec) return _keyTarget(value);
        return value is ParameterValueSpec
            ? '(${value.name} == true)'
            : '(${present(value)} && ${operand(value)})';
      case CompareKind.differs:
        final guards = {present(value), present(other!)};
        return '(${guards.join(' && ')} && '
            '${operand(value)} != ${operand(other)})';
    }
  }

  String _keyTarget(KeyTargetValueSpec value) {
    final (variantCase, field, target, targetField) = operations.keyTarget(
      value,
    );
    return '($keyName is ${variantCase.className} && '
        '(entityGraph.${target.setAccessor}.byId($keyName.${field.name})'
        '?.${targetField.name} ?? false))';
  }
}

/// The generated `<root>StartingValues` the application reads when it makes
/// a [DayRootSpec] root, matching the target's day-root function.
String _dayRootDart(
  ResolvedMemberOperations operations,
  String entityGraphName,
) {
  final root = operations.root;
  final spec = root.memberOperations!.root!;
  FieldSpec field(String name) =>
      root.fields.where((field) => field.name == name).firstOrNull ??
      (throw InvalidGenerationSourceError(
        '`$name` is not a field of ${root.className}.',
      ));
  final date = field(spec.dateFieldName);
  final buffer = StringBuffer()
    ..writeln(
      '/// The values a ${root.className} starts with on [${date.name}] when '
      'the day has none yet.',
    )
    ..writeln(
      'Future<({${[for (final name in spec.initial.keys) '${field(name).dartType} $name'].join(', ')}})> '
      '${lowerCamelCase(root.className)}StartingValues(',
    )
    ..writeln('  $entityGraphName entityGraph,')
    ..writeln('  LocalDate ${date.name},')
    ..writeln(') async {')
    ..writeln('  final day = ${date.name}.toDateTime();');
  for (final entry in spec.initial.entries) {
    final target = field(entry.key);
    switch (entry.value) {
      case WeekdayAverageSpec(
        :final fieldName,
        :final presentFieldName,
        :final days,
        :final minimum,
        :final fallback,
      ):
        final source = field(fieldName);
        final present = field(presentFieldName);
        final clamp = target.minValue != null && target.maxValue != null
            ? '.clamp(${target.minValue}, ${target.maxValue})'
            : '';
        buffer
          ..writeln('  final ${entry.key} = await ${root.className}List.owned(')
          ..writeln('    entityGraph,')
          ..writeln(
            '    where: ${root.className}Fields.${date.name}.isAtLeast('
            'LocalDate.fromDateTime(DateTime(day.year, day.month, day.day - $days))) &',
          )
          ..writeln(
            '        ${root.className}Fields.${date.name}.isLessThan(${date.name}) &',
          )
          ..writeln(
            '        ${root.className}Fields.${present.name}.isNotNull,',
          )
          ..writeln(
            '    orderBy: ${root.className}Fields.${date.name}.ascending(),',
          )
          ..writeln('    pageSize: $days,')
          ..writeln('  ).useAll((rows) {')
          ..writeln('    final values = [')
          ..writeln('      for (final row in rows)')
          ..writeln(
            '        if (row.${date.name}.toDateTime().weekday == day.weekday) '
            'row.${source.name},',
          )
          ..writeln('    ];')
          ..writeln('    if (values.length < $minimum) return $fallback$clamp;')
          ..writeln(
            '    return (values.reduce((a, b) => a + b) / values.length)'
            '.round()$clamp;',
          )
          ..writeln('  });');
      case CopyOfSpec(:final fieldName):
        if (!spec.initial.keys
            .takeWhile((key) => key != entry.key)
            .contains(fieldName)) {
          throw InvalidGenerationSourceError(
            'CopyOf(#$fieldName) must follow the starting value it copies.',
          );
        }
        buffer.writeln('  final ${entry.key} = $fieldName;');
      case BandedSpec(:final fieldName, :final bounds, :final values):
        final type = target.dartType.replaceAll('?', '');
        final branches = [
          for (var index = 0; index < bounds.length; index++)
            '$fieldName < ${bounds[index]} ? $type.${values[index]} : ',
        ];
        buffer.writeln(
          '  final ${entry.key} = ${branches.join()}$type.${values.last};',
        );
    }
  }
  buffer
    ..writeln(
      '  return (${[for (final name in spec.initial.keys) '$name: $name'].join(', ')});',
    )
    ..writeln('}');
  return buffer.toString();
}
