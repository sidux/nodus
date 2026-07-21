import 'package:dart_style/dart_style.dart';
import 'package:nodus/nodus.dart';

import 'model.dart';

String _fieldMember(FieldSpec field) =>
    field.generatedOnly ? '_${field.name}' : field.name;

String _fieldReference(EntitySpec spec, FieldSpec field) =>
    '${spec.className}Fields.${_fieldMember(field)}';

String _entityRead(FieldSpec field, {String entity = 'entity'}) =>
    field.generatedOnly
    ? '$entity.generatedAccess.generatedOrderAccess!.generatedOrderRank'
    : '$entity.${field.name}';

String _recordRead(FieldSpec field) =>
    field.generatedOnly ? 'generatedOrderRank' : field.name;

String _nullableType(String dartType) =>
    dartType.endsWith('?') ? dartType : '$dartType?';

const _driftTableMemberNames = <String>{
  'tableName',
  'withoutRowId',
  'dontWriteConstraints',
  'isStrict',
  'primaryKey',
  'uniqueKeys',
  'customConstraints',
  'integer',
  'int64',
  'intEnum',
  'text',
  'textEnum',
  'boolean',
  'dateTime',
  'blob',
  'real',
  'sqliteAny',
  'customType',
};

Map<FieldSpec, String> _driftColumnGetters(EntitySpec spec) {
  final usedNames = <String>{
    ..._driftTableMemberNames,
    for (final field in spec.fields)
      if (!_driftTableMemberNames.contains(field.name)) field.name,
  };
  final getters = <FieldSpec, String>{};
  for (final field in spec.fields) {
    if (!_driftTableMemberNames.contains(field.name)) {
      getters[field] = field.name;
      continue;
    }
    var candidate = '${field.name}Column';
    while (!usedNames.add(candidate)) {
      candidate = '${candidate}Column';
    }
    getters[field] = candidate;
  }
  return getters;
}

String emitDart(EntitySpec spec, {bool privateEntityOutputs = false}) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Source: ${spec.inputImport}')
    ..writeln('// ignore_for_file: invalid_null_aware_operator, type=lint')
    ..writeln()
    ..writeln("import 'package:drift/drift.dart';")
    ..writeln("import 'package:mobx/mobx.dart';")
    ..writeln("import 'package:nodus/nodus.dart';")
    ..writeln("import '${spec.inputImport}';");
  for (final import in spec.typeImports) {
    buffer.writeln("import '$import';");
  }
  for (final targetImport
      in spec.fields
          .map((field) => field.reference?.targetInputImport)
          .whereType<String>()
          .toSet()) {
    if (targetImport == spec.inputImport) continue;
    buffer.writeln(
      "import '${_generatedEntityImport(targetImport, privateOutput: privateEntityOutputs)}';",
    );
  }
  buffer.writeln();

  _emitDriftSchema(buffer, spec);
  _emitDescriptor(buffer, spec);
  _emitRecord(buffer, spec);
  _emitMutationDraft(buffer, spec);
  _emitRelationships(buffer, spec);
  _emitFields(buffer, spec);
  _emitSet(buffer, spec);
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).format(buffer.toString());
}

void _emitFields(StringBuffer buffer, EntitySpec spec) {
  buffer.writeln('abstract final class ${spec.className}Fields {');
  for (final field in spec.fields) {
    final fieldClass = _queryFieldClass(field);
    final valueType = field.dartType.replaceAll('?', '');
    buffer
      ..writeln(
        '  static const _${field.name}Persistence = EntityFieldDescriptor(',
      )
      ..writeln("    name: '${field.name}',")
      ..writeln("    columnName: '${field.columnName}',")
      ..writeln('    kind: EntityFieldKind.${_fieldKind(field)},');
    buffer
      ..writeln('    nullable: ${field.nullable},')
      ..writeln('    mutable: ${spec.isPatchable(field)},')
      ..writeln('    sinceProtocolVersion: ${field.sinceProtocolVersion},')
      ..writeln(
        '    renamedFrom: ${field.renamedFrom == null ? 'null' : _dartLiteral(field.renamedFrom)},',
      )
      ..writeln('    hasProtocolDefault: ${field.defaultValue != null},')
      ..writeln(
        '    protocolDefault: ${_dartLiteral(field.persistedDefaultValue)},',
      )
      ..writeln(
        '    inCreatePayload: ${field.inCreatePayload && !spec.isCommandOnly(field)},',
      )
      ..writeln(
        '    conflictPolicy: FieldConflictPolicy.${_conflict(field.conflict)},',
      )
      ..writeln(
        '    reference: ${field.reference == null ? 'null' : 'EntityReferenceDescriptor(targetEntityType: \'${field.reference!.targetClassName}\', onDelete: ReferenceDeleteAction.${field.reference!.onDelete.name}${field.isComposition ? ', composition: true' : ''})'},',
      );
    if (field.transitions.isNotEmpty) {
      buffer.writeln(
        '    allowedTransitions: ${_transitionDescriptorLiteral(field)},',
      );
    }
    if (_hasScalarConstraints(field)) {
      buffer.writeln('    constraints: EntityFieldConstraints(');
      if (field.minLength case final value?) {
        buffer.writeln('      minLength: $value,');
      }
      if (field.allowWhitespace) {
        buffer.writeln('      allowWhitespace: true,');
      }
      if (field.maxLength case final value?) {
        buffer.writeln('      maxLength: $value,');
      }
      if (field.minValue case final value?) {
        buffer.writeln('      minValue: $value,');
      }
      if (field.maxValue case final value?) {
        buffer.writeln('      maxValue: $value,');
      }
      if (field.allowedValues.isNotEmpty) {
        buffer.writeln(
          '      allowedValues: ${_dartLiteral(field.allowedValues)},',
        );
      }
      buffer.writeln('    ),');
    }
    buffer
      ..writeln('  );')
      ..writeln(
        '  static final ${_fieldMember(field)} = '
        'Persisted$fieldClass<${spec.className}, $valueType>(',
      )
      ..writeln('    persistence: _${field.name}Persistence,')
      ..writeln('    read: (entity) => ${_entityRead(field)},')
      ..writeln('    encode: (value) => ${_encodeExpression(field, 'value')},')
      ..writeln(
        '    decode: (source) => ${_decodeExpression(field, 'source')},',
      )
      ..writeln('  );');
  }
  buffer.writeln('  static final _persistence = <EntityFieldDescriptor>[');
  for (final field in spec.fields) {
    buffer.writeln('    ${_fieldMember(field)}.persistence,');
  }
  buffer
    ..writeln('  ];')
    ..writeln('}')
    ..writeln();
}

bool _hasScalarConstraints(FieldSpec field) =>
    field.minLength != null ||
    field.maxLength != null ||
    field.minValue != null ||
    field.maxValue != null ||
    field.allowedValues.isNotEmpty;

String _transitionDescriptorLiteral(FieldSpec field) {
  if (field.transitions.isEmpty) return 'const []';
  return 'const [${field.transitions.map((transition) => 'EntityValueTransition(${_dartLiteral(transition.fromWire)}, ${_dartLiteral(transition.toWire)})').join(', ')}]';
}

void _emitDriftSchema(StringBuffer buffer, EntitySpec spec) {
  final tableClass = '${spec.className}Rows';
  final columnGetters = _driftColumnGetters(spec);
  for (final index in spec.indexes) {
    final unique = index.unique ? 'UNIQUE ' : '';
    final columns = spec.indexColumns(index);
    final terms = index.unordered
        ? ['min(${columns.join(', ')})', 'max(${columns.join(', ')})']
        : columns;
    final name = spec.indexName(index);
    final condition = _indexConditionSql(spec, index);
    buffer.writeln(
      '@TableIndex.sql(${_dartLiteral('CREATE ${unique}INDEX $name '
      'ON ${spec.tableName} (${terms.join(', ')})$condition')})',
    );
  }
  buffer
    ..writeln('class $tableClass extends Table {')
    ..writeln("  @override String get tableName => '${spec.tableName}';");
  for (final field in spec.fields) {
    final columnType = switch (field.sqlType) {
      SqlType.boolean => 'BoolColumn',
      SqlType.integer => 'IntColumn',
      SqlType.real => 'RealColumn',
      SqlType.text ||
      SqlType.uuid ||
      SqlType.date ||
      SqlType.timestampWithTimeZone => 'TextColumn',
    };
    final builderMethod = switch (field.sqlType) {
      SqlType.boolean => 'boolean',
      SqlType.integer => 'integer',
      SqlType.real => 'real',
      SqlType.text ||
      SqlType.uuid ||
      SqlType.date ||
      SqlType.timestampWithTimeZone => 'text',
    };
    final builder = '$builderMethod()';
    final modifiers = <String>[
      ".named('${field.columnName}')",
      if (field.nullable) '.nullable()',
      if (field.defaultValue != null)
        '.withDefault(const Constant(${_sqliteDefaultLiteral(field)}))',
    ].join();
    buffer.writeln(
      '  $columnType get ${columnGetters[field]} => $builder$modifiers();',
    );
  }
  final checks = <String>[
    for (final field in spec.fields)
      if (field.minLength != null)
        "'CHECK (length(${field.allowWhitespace ? field.columnName : 'trim(${field.columnName})'}) >= ${field.minLength})'",
    for (final field in spec.fields)
      if (field.maxLength != null)
        "'CHECK (length(${field.columnName}) <= ${field.maxLength})'",
    for (final field in spec.fields)
      if (field.minValue != null)
        "'CHECK (${field.columnName} >= ${field.minValue})'",
    for (final field in spec.fields)
      if (field.maxValue != null)
        "'CHECK (${field.columnName} <= ${field.maxValue})'",
    for (final field in spec.fields)
      if (field.allowedValues.isNotEmpty)
        _dartLiteral(
          'CHECK (${field.columnName} IN '
          '(${field.allowedValues.map(_sqlStringLiteral).join(', ')}))',
        ),
    for (final field in spec.fields)
      if (field.greaterThan case final otherName?)
        _dartLiteral(
          'CHECK (${field.columnName} > '
          '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
        ),
    for (final field in spec.fields)
      if (field.greaterThanOrEqual case final otherName?)
        _dartLiteral(
          'CHECK (${field.columnName} >= '
          '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
        ),
    for (final field in spec.fields)
      if (field.requires case final otherName?)
        _dartLiteral(
          'CHECK (${field.columnName} IS NULL OR '
          '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName} IS NOT NULL)',
        ),
    for (final field in spec.fields)
      if (field.notEqualTo case final otherName?)
        _dartLiteral(
          'CHECK (${field.columnName} IS NULL OR '
          '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName} IS NULL OR '
          '${field.columnName} <> '
          '${spec.fields.singleWhere((candidate) => candidate.name == otherName).columnName})',
        ),
    for (final field in spec.fields)
      if (field.isEnum)
        _dartLiteral(
          'CHECK (${field.columnName} IN '
          '(${field.enumWireValues.map(_sqlStringLiteral).join(', ')}))',
        ),
    for (final group in spec.exclusiveFieldGroups)
      _dartLiteral(
        'CHECK (${group.fields.map((name) {
          final column = spec.fields.singleWhere((field) => field.name == name).columnName;
          return 'CASE WHEN $column IS NOT NULL THEN 1 ELSE 0 END';
        }).join(' + ')} ${group.allowNone ? '<=' : '='} 1)',
      ),
    for (final index in spec.compoundIndexes.where(
      (candidate) => candidate.unordered,
    ))
      _dartLiteral(
        'CHECK (${spec.ownerField.columnName} <> '
        '${spec.fields.singleWhere((field) => field.name == index.fields.single).columnName})',
      ),
  ];
  if (checks.isNotEmpty) {
    buffer.writeln(
      '  @override List<String> get customConstraints => [${checks.join(', ')}];',
    );
  }
  buffer
    ..writeln(
      '  IntColumn get localRevision => integer().named('
      "'local_revision')();",
    )
    ..writeln(
      "  TextColumn get acceptedSnapshot => text().named('accepted_snapshot').nullable()();",
    )
    ..writeln(
      '  @override Set<Column<Object>> get primaryKey => {${spec.idField.name}};',
    )
    ..writeln('}')
    ..writeln();
}

void _emitDescriptor(StringBuffer buffer, EntitySpec spec) {
  final descriptorName = '${spec.className}Descriptor';
  final recordName = '${spec.className}Record';
  final uniqueIndexes = spec.indexes.where((index) => index.unique).toList();
  buffer
    ..writeln(
      'final class $descriptorName implements '
      'EntityDescriptor<${spec.className}, $recordName>, '
      'EntityIdentityDescriptor<${spec.className}>'
      '${uniqueIndexes.isEmpty ? '' : ', EntityUniqueConstraintDescriptor'}'
      '${spec.guardedActions.isEmpty ? '' : ', ActionPolicyProvider'}'
      '${spec.hasOrderedCapability ? ', OrderedDescriptor' : ''}'
      '${spec.hasActivityTrackedCapability ? ', ActivityTrackedEntityDescriptor' : ''}'
      '${spec.isActivityEntry ? ', ActivityEntryEntityDescriptor' : ''} {',
    )
    ..writeln('  const $descriptorName();')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  EntityIdentity<${spec.className}> nextIdentity(')
    ..writeln('    EntityIdGenerator generator,')
    ..writeln('  ) => EntityIdentity(')
    ..writeln('    descriptor: this,')
    ..writeln('    id: generator.next<${spec.className}>(),')
    ..writeln('  );')
    ..writeln('  @override')
    ..writeln(
      '  EntityIdentity<${spec.className}> parseIdentity(String source) =>',
    )
    ..writeln(
      '      EntityIdentity(descriptor: this, id: parseLocalId(source));',
    )
    ..writeln()
    ..writeln("  @override String get entityType => '${spec.className}';")
    ..writeln(
      '  @override Cardinality get cardinality => '
      'Cardinality.${spec.cardinality.name};',
    )
    ..writeln("  @override String get tableName => '${spec.tableName}';")
    ..writeln(
      '  @override String? get collaborationTableName => '
      '${spec.security.collaboration?.isDirect ?? false ? "'${spec.security.collaboration!.membershipTable}'" : 'null'};',
    )
    ..writeln('  @override int get protocolVersion => ${spec.protocolVersion};')
    ..writeln();
  if (spec.hasActivityTrackedCapability) {
    buffer
      ..writeln('  @override')
      ..writeln('  String activityLabel(GeneratedEntityRecord entity) {')
      ..writeln('    if (entity is! $recordName) {')
      ..writeln(
        "      throw StateError('Activity source does not belong to ${spec.className}.');",
      )
      ..writeln('    }')
      ..writeln('    final label = entity.activityLabel.trim();')
      ..writeln('    if (label.isEmpty || label.length > 240) {')
      ..writeln('      throw const EntityValidationException(')
      ..writeln("        entityType: '${spec.className}',")
      ..writeln("        field: 'activityLabel',")
      ..writeln(
        "        message: 'An activity label must contain 1 to 240 characters.',",
      )
      ..writeln('      );')
      ..writeln('    }')
      ..writeln('    return label;')
      ..writeln('  }')
      ..writeln();
  }
  if (spec.hasOrderedCapability) {
    final scopeFields = spec.orderScopeFields;
    final membershipFields = spec.orderMembershipConditions;
    buffer
      ..writeln('  @override')
      ..writeln(
        '  List<EntityFieldDescriptor> get orderScopeFields => const [',
      );
    for (final field in scopeFields) {
      buffer.writeln('    ${spec.className}Fields._${field.name}Persistence,');
    }
    buffer
      ..writeln('  ];')
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  List<EntityFieldValueCondition> get orderMembershipConditions => const [',
      );
    for (final (field, value) in membershipFields) {
      buffer
        ..writeln('    EntityFieldValueCondition(')
        ..writeln(
          '      field: ${spec.className}Fields._${field.name}Persistence,',
        )
        ..writeln('      value: ${_dartLiteral(value)},')
        ..writeln('    ),');
    }
    buffer
      ..writeln('  ];')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  bool isOrderMember(JsonMap fields) =>')
      ..writeln(
        '      orderMembershipConditions.every((condition) => condition.matches(fields));',
      )
      ..writeln()
      ..writeln('  @override')
      ..writeln('  String orderScopeKey(JsonMap fields) {');
    if (scopeFields.isEmpty) {
      buffer.writeln("    return 'root';");
    } else if (spec.usesEncodedOrderScopeKey) {
      for (final field in scopeFields) {
        buffer
          ..writeln("    if (!fields.containsKey('${field.name}')) {")
          ..writeln('      throw const FormatException(')
          ..writeln(
            "        'Expected ${spec.className}.${field.name} in its ordered scope.',",
          )
          ..writeln('      );')
          ..writeln('    }');
      }
      buffer
        ..writeln('    return encodeOrderScopeKey([')
        ..writeAll(
          scopeFields.map((field) => "      fields['${field.name}'],\n"),
        )
        ..writeln('    ]);');
    } else {
      final scopeField = scopeFields.single;
      buffer
        ..writeln("    final value = fields['${scopeField.name}'];")
        ..writeln('    if (value is String && value.isNotEmpty) return value;')
        ..writeln('    throw FormatException(')
        ..writeln(
          "      'Expected ${spec.className}.${scopeField.name} to identify its ordered scope.',",
        )
        ..writeln('      value,')
        ..writeln('    );');
    }
    buffer
      ..writeln('  }')
      ..writeln();
  }
  if (uniqueIndexes.isNotEmpty) {
    buffer
      ..writeln('  @override')
      ..writeln(
        '  List<EntityUniqueConstraint> get uniqueConstraints => const [',
      );
    for (final index in uniqueIndexes) {
      final fieldNames = index.fieldNames.map((name) => "'$name'").join(', ');
      final name = spec.indexName(index);
      final condition = index.condition;
      buffer
        ..writeln('    EntityUniqueConstraint(')
        ..writeln("      name: '$name',")
        ..writeln('      fieldNames: [$fieldNames],');
      if (index.unordered) {
        buffer.writeln('      unordered: true,');
      }
      if (index.activeOnly) {
        buffer
          ..writeln('      condition: EntityUniqueConstraintCondition(')
          ..writeln(
            "        fieldName: '${EntityConventions.deletedAtFieldName}',",
          )
          ..writeln('        values: [null],')
          ..writeln('      ),');
      } else if (condition != null) {
        buffer
          ..writeln('      condition: EntityUniqueConstraintCondition(')
          ..writeln("        fieldName: '${condition.field}',")
          ..writeln('        values: ${_dartLiteral(condition.values)},')
          ..writeln('      ),');
      }
      buffer.writeln('    ),');
    }
    buffer
      ..writeln('  ];')
      ..writeln();
  }
  if (spec.guardedActions.isNotEmpty) {
    final initialFields = spec.fields.where(
      (field) =>
          spec.isFixedActionTarget(field) &&
          field.transitions.isEmpty &&
          (field.nullable || field.defaultValue != null),
    );
    buffer
      ..writeln('  @override')
      ..writeln(
        '  ActionPolicy get actionPolicy => const '
        'ActionPolicy(',
      )
      ..writeln('    actions: [');
    for (final action in spec.guardedActions) {
      buffer
        ..writeln('      ActionDefinition(')
        ..writeln('        fieldNames: ${_dartLiteral(action.targetFields)},')
        ..writeln(
          '        guardedFieldNames: '
          '${_dartLiteral(spec.guardedActionFields(action))},',
        )
        ..writeln('        assignments: [');
      for (final assignment in action.assignments) {
        final field = spec.fields.singleWhere(
          (field) => field.name == assignment.fieldName,
        );
        final constructor = switch (assignment.kind) {
          ActionValueKind.literal =>
            'ActionAssignment.literal('
                '${_dartLiteral(field.name)}, '
                '${_dartLiteral(field.isEnum ? snakeCase(assignment.literal! as String) : assignment.literal)})',
          ActionValueKind.clockNow =>
            'ActionAssignment.clockNow('
                '${_dartLiteral(field.name)}'
                '${field.nullable ? ', firstWriteOnly: true' : ''})',
          ActionValueKind.clear =>
            'ActionAssignment.clear('
                '${_dartLiteral(field.name)})',
        };
        buffer.writeln('          $constructor,');
      }
      buffer
        ..writeln('        ],')
        ..writeln('      ),');
    }
    buffer
      ..writeln('    ],')
      ..writeln('    fixedInitialValues: {');
    for (final field in initialFields) {
      buffer.writeln(
        '      ${_dartLiteral(field.name)}: '
        '${_dartLiteral(field.persistedDefaultValue)},',
      );
    }
    buffer
      ..writeln('    },')
      ..writeln('  );')
      ..writeln();
  }
  buffer
    ..writeln('  @override')
    ..writeln('  EntitySemanticCommand<dynamic> decodeSemanticCommand(')
    ..writeln('    String name, JsonMap payload,')
    ..writeln('  ) => switch (name) {');
  if (spec.canCollaborate) {
    final accountType = _entityIdArgument(spec.ownerField.dartType);
    buffer
      ..writeln("    'setCollaborator' => SetCollaboratorCommand<")
      ..writeln('      ${spec.className}, $accountType')
      ..writeln('    >.fromWire(')
      ..writeln('      payload, parseId: parseLocalId<$accountType>,')
      ..writeln('    ),');
  }
  if (spec.hasOrderedCapability) {
    buffer
      ..writeln("    'moveInOrder' => MoveOrderedCommand<${spec.className}>")
      ..writeln('        .fromWire(payload, parseId: parseLocalId),');
    if (spec.cardinality == Cardinality.bounded) {
      buffer
        ..writeln("    'reorder' => ReorderOrderedCommand<${spec.className}>")
        ..writeln('        .fromWire(payload, parseId: parseLocalId),');
    }
    if (spec.orderScopeTransferAction != null) {
      buffer
        ..writeln(
          "    'transferInOrder' => TransferOrderedCommand<${spec.className}>.fromWire(",
        )
        ..writeln("      payload, entityType: '${spec.className}',")
        ..writeln('      targetScopeFields: const [');
      for (final field in spec.orderScopeTransferFields) {
        buffer.writeln(
          '        ${spec.className}Fields._${field.name}Persistence,',
        );
      }
      buffer
        ..writeln('      ],')
        ..writeln('    ),');
    }
  }
  buffer
    ..writeln('    _ => throw RejectedSyncException.validation(')
    ..writeln("      code: 'unsupported_command',")
    ..writeln(
      "      message: 'Unsupported ${spec.className} semantic command.',",
    )
    ..writeln('    ),')
    ..writeln('  };')
    ..writeln()
    ..writeln('  @override')
    ..writeln(
      '  List<EntityFieldDescriptor> get fields => '
      '${spec.className}Fields._persistence;',
    )
    ..writeln()
    ..writeln('  @override')
    ..writeln('  $recordName instantiate({')
    ..writeln('    required EntityMutationSink mutationSink,')
    ..writeln('    required Clock clock,')
    ..writeln('    required JsonMap fields,')
    ..writeln('    required int localRevision,')
    ..writeln('  }) {')
    ..writeln('    return $recordName._(')
    ..writeln('      mutationSink: mutationSink,')
    ..writeln('      clock: clock,')
    ..writeln('      localRevision: localRevision,');
  for (final field in spec.fields) {
    buffer.writeln(
      '      ${field.name}: ${_fieldReference(spec, field)}.decode('
      "fields['${field.name}']),",
    );
  }
  buffer
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

String _indexConditionSql(EntitySpec spec, IndexSpec index) {
  if (index.activeOnly) {
    return ' WHERE ${EntityConventions.deletedAtColumnName} IS NULL';
  }
  final condition = index.condition;
  if (condition == null) return '';
  final column = spec.fields
      .singleWhere((field) => field.name == condition.field)
      .columnName;
  return ' WHERE $column IN '
      '(${condition.values.map(_indexSqlLiteral).join(', ')})';
}

String _indexSqlLiteral(Object value) => switch (value) {
  final String value => "'${value.replaceAll("'", "''")}'",
  final bool value => value ? '1' : '0',
  final int value => value.toString(),
  _ => throw StateError('Unsupported generated index condition value.'),
};

void _emitRelationships(StringBuffer buffer, EntitySpec spec) {
  final relationships = spec.fields
      .where((field) => field.reference != null)
      .toList();
  if (relationships.isEmpty) return;
  buffer.writeln(
    'extension ${spec.className}GeneratedRelationships on ${spec.className} {',
  );
  for (final field in relationships) {
    final reference = field.reference!;
    final idExpression = field.nullable
        ? '${field.name}?.value'
        : '${field.name}.value';
    buffer
      ..writeln(
        '  ${reference.targetClassName}? get ${reference.accessorName} {',
      )
      ..writeln('    return generatedAccess.resolveGeneratedReference(')
      ..writeln('        const ${reference.targetClassName}Descriptor(),')
      ..writeln('        $idExpression,')
      ..writeln('      );')
      ..writeln('  }');
  }
  buffer
    ..writeln('}')
    ..writeln();
}

void _emitRecord(StringBuffer buffer, EntitySpec spec) {
  final recordName = '${spec.className}Record';
  final usesClock =
      spec.actions.isNotEmpty ||
      spec.commands.isNotEmpty ||
      spec.draftEditableFields.isNotEmpty ||
      spec.fields.any((field) => field.isMutable && !spec.isCommandOnly(field));
  buffer
    ..writeln(
      'final class $recordName extends ${spec.className} '
      'implements TypedGeneratedEntityRecord<${spec.className}>, '
      'GeneratedEntityAccess<${spec.className}>'
      '${spec.hasOrderedCapability ? ', GeneratedOrderedEntityAccess<${spec.className}>' : ''} {',
    )
    ..writeln('  $recordName._({')
    ..writeln('    required EntityMutationSink mutationSink,')
    ..writeln('    required Clock clock,')
    ..writeln('    required int localRevision,');
  for (final field in spec.fields) {
    buffer.writeln('    required ${field.dartType} ${field.name},');
  }
  buffer.writeln('  }) : _mutationSink = mutationSink,');
  if (usesClock) {
    buffer.writeln('       _clock = clock,');
  }
  buffer
    ..writeln('       _localRevision = localRevision,')
    ..writeln('       ${spec.idField.name} = ${spec.idField.name},');
  final observableFields = spec.fields.where((field) => !field.isId).toList();
  for (var index = 0; index < observableFields.length; index++) {
    final field = observableFields[index];
    final suffix = index == observableFields.length - 1 ? ' {' : ',';
    buffer.writeln(
      '       _${field.name}Store = Observable(${field.name})$suffix',
    );
  }
  for (final field in spec.fields.where(_hasValidation)) {
    _emitFieldValidation(
      buffer,
      spec,
      field,
      valueExpression: field.name,
      indent: '    ',
    );
  }
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (field) => field.name,
    indent: '    ',
  );
  buffer.writeln('  }');
  _emitDetachedRecordFactory(buffer, spec);
  buffer
    ..writeln()
    ..writeln('  final EntityMutationSink _mutationSink;');
  if (usesClock) {
    buffer.writeln('  final Clock _clock;');
  }
  buffer
    ..writeln('  int _localRevision;')
    ..writeln(
      '  Future<LocalMutationCommitResult> _generatedLocalCommit = '
      'Future.value(const LocalMutationCommitResult.success());',
    )
    ..writeln(
      '  Future<void> _generatedMutationCompletion('
      'Future<LocalMutationCommitResult> commit) => '
      '_mutationSink.isInMutationTransaction '
      '? Future<void>.value() : LocalMutationCompletion(commit);',
    )
    ..writeln()
    ..writeln('  @override')
    ..writeln('  ${spec.className} get generatedDomain => this;')
    ..writeln('  @override')
    ..writeln(
      '  GeneratedEntityAccess<${spec.className}> get generatedAccess => this;',
    )
    ..writeln('  @override')
    ..writeln(
      spec.hasOrderedCapability
          ? '  GeneratedOrderedEntityAccess<${spec.className}> '
                'get generatedOrderAccess => this;'
          : '  GeneratedOrderedEntityAccess<${spec.className}>? '
                'get generatedOrderAccess => null;',
    )
    ..writeln('  @override')
    ..writeln(
      '  D? resolveGeneratedReference<D, '
      'R extends TypedGeneratedEntityRecord<D>>(',
    )
    ..writeln('    EntityDescriptor<D, R> descriptor,')
    ..writeln('    String? entityId,')
    ..writeln('  ) => _mutationSink.resolveReference(descriptor, entityId);')
    ..writeln('  @override')
    ..writeln('  Future<R> runGeneratedTransaction<R>(')
    ..writeln('    Future<R> Function() body,')
    ..writeln('  ) => _mutationSink.runEntityTransaction(body);')
    ..writeln('  @override')
    ..writeln('  Future<void> recordGeneratedCommand(')
    ..writeln('    EntitySemanticCommand<${spec.className}> command,')
    ..writeln('  ) {');
  final tombstone = spec.fields
      .where((field) => field.name == EntityConventions.deletedAtFieldName)
      .firstOrNull;
  if (tombstone != null) {
    _emitDeletedMutationGuard(buffer, spec, fieldName: 'command');
  }
  if (spec.canCollaborate) {
    buffer
      ..writeln('    _mutationSink.validateMutationAuthorization(')
      ..writeln('      entity: this,')
      ..writeln('      operation: RlsOperation.update,')
      ..writeln('      principals: const [RlsPrincipal.owner],')
      ..writeln('    );');
  }
  buffer
    ..writeln(
      '    _generatedLocalCommit = '
      '_mutationSink.recordEntityCommand<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln('      command: command,')
    ..writeln('      rollbackIfCurrent: () {},')
    ..writeln('    );')
    ..writeln('    return _generatedMutationCompletion(_generatedLocalCommit);')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln('  void validateGeneratedDraft() {')
    ..writeln('    _mutationSink.validateDraftTarget(this);')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln(
      '  Future<void> awaitGeneratedLocalCommit(int expectedRevision) async {',
    )
    ..writeln('    if (_localRevision != expectedRevision) {')
    ..writeln('      throw EntityDraftStateException(')
    ..writeln("        entityType: '${spec.className}',")
    ..writeln('        entityId: generatedEntityId,')
    ..writeln('        reason: EntityDraftFailureReason.stale,')
    ..writeln("        message: 'Another mutation replaced the draft commit.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final result = await _generatedLocalCommit;')
    ..writeln('    result.throwIfFailed();')
    ..writeln('  }')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final ${spec.idField.dartType} ${spec.idField.name};');
  if (spec.ownership == Ownership.identity) {
    buffer
      ..writeln('  @override')
      ..writeln(
        '  ${spec.idField.dartType} get ${EntityConventions.ownerFieldName} => '
        '${spec.idField.name};',
      );
  }
  for (final field in observableFields) {
    buffer
      ..writeln('  final Observable<${field.dartType}> _${field.name}Store;')
      ..writeln('  @override');
    if (field.generatedOnly) {
      buffer.writeln(
        '  OrderRank get generatedOrderRank => _${field.name}Store.value;',
      );
    } else {
      buffer.writeln(
        '  ${field.dartType} get ${field.name} => _${field.name}Store.value;',
      );
    }
    if (field.isMutable && !spec.isCommandOnly(field)) {
      _emitSetter(buffer, spec, field);
    }
  }
  if (spec.hasOrderedCapability) {
    final scopeFields = spec.orderScopeFields;
    buffer
      ..writeln('  @override')
      ..writeln('  bool get generatedIsOrderMember =>')
      ..writeln(
        '      ${spec.orderMembershipConditions.map((condition) => switch (condition.$2) {
          null => '_${condition.$1.name}Store.value == null',
          true => '_${condition.$1.name}Store.value',
          false => '!_${condition.$1.name}Store.value',
          _ => throw StateError('Unsupported generated order membership condition.'),
        }).join(' && ')};',
      )
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        scopeFields.isEmpty
            ? "  String get generatedOrderScopeKey => 'root';"
            : spec.usesEncodedOrderScopeKey
            ? '  String get generatedOrderScopeKey => encodeOrderScopeKey(['
            : '  String get generatedOrderScopeKey => '
                  '_${scopeFields.single.name}Store.value.value;',
      );
    if (scopeFields.isNotEmpty && spec.usesEncodedOrderScopeKey) {
      for (final field in scopeFields) {
        buffer.writeln(
          '    ${_fieldReference(spec, field)}.encode(_${field.name}Store.value),',
        );
      }
      buffer.writeln('  ]);');
    }
    _emitOrderMove(buffer, spec);
  }
  for (final action in spec.actions) {
    _emitAction(buffer, spec, action);
  }
  for (final command in spec.commands) {
    _emitCommand(buffer, spec, command);
  }
  _emitGeneratedDraftMutation(buffer, spec);
  if (spec.canCollaborate) {
    _emitRecordCollaborationApi(buffer, spec);
  }
  buffer
    ..writeln()
    ..writeln('  @override')
    ..writeln("  String get generatedEntityType => '${spec.className}';")
    ..writeln('  @override')
    ..writeln('  String get generatedEntityId => ${spec.idField.name}.value;')
    ..writeln('  @override')
    ..writeln('  String get generatedOwnerId => ${spec.ownerField.name}.value;')
    ..writeln('  @override')
    ..writeln('  bool generatedHasParticipant(String principalId) =>')
    ..writeln(
      spec.participantFields.isEmpty
          ? '      false;'
          : '      ${spec.participantFields.map((field) => '${field.name}.value == principalId').join(' || ')};',
    )
    ..writeln('  @override')
    ..writeln(
      '  ServerVersion get generatedServerVersion => '
      '${spec.serverVersionField.name};',
    )
    ..writeln('  @override')
    ..writeln('  int get generatedLocalRevision => _localRevision;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  JsonMap generatedCreateSnapshot() => {');
  for (final field in spec.fields.where(
    (field) => field.inCreatePayload && !spec.isCommandOnly(field),
  )) {
    buffer.writeln(
      "    '${field.name}': ${_fieldReference(spec, field)}.encode(${_recordRead(field)}),",
    );
  }
  buffer
    ..writeln('  };')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  JsonMap generatedSnapshot() => {');
  for (final field in spec.fields) {
    buffer.writeln(
      "    '${field.name}': ${_fieldReference(spec, field)}.encode(${_recordRead(field)}),",
    );
  }
  buffer
    ..writeln('  };')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  void generatedApplyRemote({')
    ..writeln('    required JsonMap fields,')
    ..writeln('    required ServerVersion serverVersion,')
    ..writeln('    required int localRevision,')
    ..writeln('  }) {');
  final remotelyAppliedFields = observableFields.where(
    (field) => field.name != spec.serverVersionField.name,
  );
  for (final field in remotelyAppliedFields) {
    buffer
      ..writeln(
        "    final has${field.capitalizedName} = fields.containsKey('${field.name}');",
      )
      ..writeln(
        '    late final ${field.dartType} remote${field.capitalizedName};',
      )
      ..writeln('    if (has${field.capitalizedName}) {')
      ..writeln(
        "      remote${field.capitalizedName} = ${_fieldReference(spec, field)}.decode(fields['${field.name}']);",
      );
    _emitFieldValidation(
      buffer,
      spec,
      field,
      valueExpression: 'remote${field.capitalizedName}',
      indent: '      ',
    );
    buffer.writeln('    }');
  }
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (field) => field.isId
        ? field.name
        : 'has${field.capitalizedName} '
              '? remote${field.capitalizedName} : ${_recordRead(field)}',
    indent: '    ',
  );
  buffer.writeln('    runInAction(() {');
  for (final field in remotelyAppliedFields) {
    buffer
      ..writeln('      if (has${field.capitalizedName}) {')
      ..writeln(
        '        _${field.name}Store.value = remote${field.capitalizedName};',
      )
      ..writeln('      }');
  }
  buffer
    ..writeln(
      '      _${spec.serverVersionField.name}Store.value = serverVersion;',
    )
    ..writeln('      _localRevision = localRevision;')
    ..writeln('    });')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

void _emitGeneratedDraftMutation(StringBuffer buffer, EntitySpec spec) {
  final fields = spec.draftEditableFields;
  if (fields.isEmpty) {
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Future<void> applyGeneratedDraft({')
      ..writeln('    required TypedEntityPatch<${spec.className}> base,')
      ..writeln('    required TypedEntityPatch<${spec.className}> candidate,')
      ..writeln('  }) => throw UnsupportedError(')
      ..writeln(
        "    '${spec.className} has no ordinary draft-editable fields.',",
      )
      ..writeln('  );');
    return;
  }
  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;

  buffer
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Future<void> applyGeneratedDraft({')
    ..writeln('    required TypedEntityPatch<${spec.className}> base,')
    ..writeln('    required TypedEntityPatch<${spec.className}> candidate,')
    ..writeln('  }) {');
  for (final field in fields) {
    buffer
      ..writeln(
        '    final base${field.capitalizedName} = '
        "${_fieldReference(spec, field)}.decode(base['${field.name}']);",
      )
      ..writeln(
        '    final candidate${field.capitalizedName} = '
        "${_fieldReference(spec, field)}.decode(candidate['${field.name}']);",
      );
  }
  for (final field in fields) {
    buffer
      ..writeln(
        '    final next${field.capitalizedName} = '
        '${_normalizedEntityValueExpression(field, 'candidate${field.capitalizedName}')};',
      )
      ..writeln(
        '    final ${field.name}DraftChanged = '
        '${_entityValueChangedExpression(field, 'base${field.capitalizedName}', 'next${field.capitalizedName}')};',
      )
      ..writeln(
        '    final ${field.name}CurrentChanged = '
        '${_entityValueChangedExpression(field, 'base${field.capitalizedName}', '_${field.name}Store.value')};',
      )
      ..writeln(
        '    final ${field.name}Changed = ${field.name}DraftChanged && '
        '${_entityValueChangedExpression(field, '_${field.name}Store.value', 'next${field.capitalizedName}')};',
      )
      ..writeln(
        '    final ${field.name}Overlaps = ${field.name}Changed && '
        '${field.name}CurrentChanged;',
      );
  }
  final overlaps = fields.map((field) => '${field.name}Overlaps').join(' || ');
  final changed = fields.map((field) => '${field.name}Changed').join(' || ');
  buffer
    ..writeln('    if ($overlaps) {')
    ..writeln('      throw EntityDraftFieldConflictException(')
    ..writeln("        entityType: '${spec.className}',")
    ..writeln('        entityId: generatedEntityId,')
    ..writeln('        fields: [');
  for (final field in fields) {
    buffer.writeln("          if (${field.name}Overlaps) '${field.name}',");
  }
  buffer
    ..writeln('        ],')
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    if (!($changed)) return Future.value();');
  if (spec.fields.any(
    (field) => field.name == EntityConventions.deletedAtFieldName,
  )) {
    _emitDeletedMutationGuard(buffer, spec, fieldName: 'draft');
  }
  for (final field in fields.where(_hasValidation)) {
    buffer.writeln('    if (${field.name}Changed) {');
    _emitFieldValidation(
      buffer,
      spec,
      field,
      valueExpression: 'next${field.capitalizedName}',
      indent: '      ',
    );
    buffer.writeln('    }');
  }
  final fieldNames = fields.map((field) => field.name).toSet();
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (field) => fieldNames.contains(field.name)
        ? '${field.name}Changed ? next${field.capitalizedName} : ${_recordRead(field)}'
        : _recordRead(field),
    indent: '    ',
  );
  for (final field in fields) {
    _emitMutationAuthorization(
      buffer,
      spec,
      field,
      operation: RlsOperation.update,
      oldValueExpression: '_${field.name}Store.value',
      newValueExpression: 'next${field.capitalizedName}',
      changedExpression: '${field.name}Changed',
      indent: '    ',
    );
  }
  buffer.writeln('    final mutationTime = _clock.nowUtc();');
  for (final field in fields) {
    buffer.writeln(
      '    final old${field.capitalizedName} = _${field.name}Store.value;',
    );
  }
  if (autoUpdated != null) {
    buffer.writeln('    final oldUpdatedAt = _${autoUpdated.name}Store.value;');
  }
  buffer
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() {');
  for (final field in fields) {
    buffer
      ..writeln('      if (${field.name}Changed) {')
      ..writeln(
        '        _${field.name}Store.value = next${field.capitalizedName};',
      )
      ..writeln('      }');
  }
  if (autoUpdated != null) {
    buffer.writeln('      _${autoUpdated.name}Store.value = mutationTime;');
  }
  buffer
    ..writeln('    });')
    ..writeln(
      '    var generatedDraftPatch = '
      'TypedEntityPatch<${spec.className}>.empty();',
    );
  for (final field in fields) {
    buffer
      ..writeln('    if (${field.name}Changed) {')
      ..writeln(
        '      final fieldPatch = ${_fieldReference(spec, field)}'
        '.patch(next${field.capitalizedName});',
      )
      ..writeln(
        '      generatedDraftPatch = generatedDraftPatch.merge(fieldPatch);',
      )
      ..writeln('    }');
  }
  buffer
    ..writeln('    final syncPatch = generatedDraftPatch;')
    ..writeln(
      '    _generatedLocalCommit = '
      '_mutationSink.recordEntityMutation<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln(
      autoUpdated == null
          ? '      patch: syncPatch,'
          : '      patch: syncPatch.merge(${_fieldReference(spec, autoUpdated)}.patch(mutationTime)),',
    )
    ..writeln('      syncPatch: syncPatch,')
    ..writeln('      occurredAt: mutationTime,');
  if (spec.hasActivityTrackedCapability) {
    buffer.writeln(
      "      activityOperation: ActivityOperation.action('edit'),",
    );
  }
  buffer
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;');
  for (final field in fields) {
    buffer
      ..writeln('        if (${field.name}Changed) {')
      ..writeln(
        '          _${field.name}Store.value = old${field.capitalizedName};',
      )
      ..writeln('        }');
  }
  if (autoUpdated != null) {
    buffer.writeln('        _${autoUpdated.name}Store.value = oldUpdatedAt;');
  }
  buffer
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('    return _generatedMutationCompletion(_generatedLocalCommit);')
    ..writeln('  }');
}

void _emitMutationDraft(StringBuffer buffer, EntitySpec spec) {
  final editableFields = spec.draftEditableFields;
  final transfer = spec.orderScopeTransferAction;
  if (!spec.canCreatePublicly && editableFields.isEmpty && transfer == null) {
    return;
  }

  final draftName = '${spec.className}MutationDraft';
  final fields = <String, String>{};
  for (final field in spec.createParameters) {
    fields[field.name] = field.dartType;
  }
  for (final field in editableFields) {
    fields[field.name] = field.dartType;
  }
  for (final action in [transfer].whereType<ActionSpec>()) {
    for (final parameter in action.parameters) {
      fields[parameter.name] = parameter.dartType;
    }
  }

  final editFields = <FieldSpec>[
    ...editableFields,
    for (final field in spec.orderScopeTransferFields)
      if (!editableFields.contains(field)) field,
  ];
  final editFieldNames = editFields.map((field) => field.name).toSet();
  if (editFields.isNotEmpty) {
    buffer
      ..writeln(
        'extension ${spec.className}GeneratedEditing on ${spec.className} {',
      )
      ..writeln('  $draftName beginEdit() => $draftName.edit(this);')
      ..writeln('}')
      ..writeln();
  }
  buffer
    ..writeln('final class $draftName ')
    ..writeln('    implements EntityMutationDraft<${spec.className}> {');
  final entries = fields.entries.toList(growable: false);
  if (spec.canCreatePublicly) {
    buffer
      ..writeln('  $draftName.create(this._set)')
      ..writeln(
        '      : _entity = null${entries.isEmpty && editFields.isEmpty ? ';' : ','}',
      );
    for (final field in editFields) {
      buffer.writeln('        _base${field.capitalizedName} = null,');
    }
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final field = spec.createParameters
          .where((candidate) => candidate.name == entry.key)
          .firstOrNull;
      final initializer = field == null
          ? 'EntityDraftField<${entry.value}>.unset()'
          : field.defaultValue != null
          ? 'EntityDraftField<${entry.value}>.value(${_domainDefaultLiteral(field)})'
          : field.nullable
          ? 'EntityDraftField<${entry.value}>.value(null)'
          : 'EntityDraftField<${entry.value}>.unset()';
      final suffix = index == entries.length - 1 ? ';' : ',';
      buffer.writeln('        _${entry.key}Field = $initializer$suffix');
    }
  }
  if (editFields.isNotEmpty) {
    buffer
      ..writeln('  $draftName.edit(${spec.className} entity)')
      ..writeln('      : _set = null,')
      ..writeln('        _entity = entity,');
    for (final field in editFields) {
      buffer.writeln(
        '        _base${field.capitalizedName} = entity.${field.name},',
      );
    }
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final suffix = index == entries.length - 1 ? ';' : ',';
      final writable = editFieldNames.contains(entry.key)
          ? ''
          : ', writable: false';
      buffer.writeln(
        '        _${entry.key}Field = EntityDraftField<${entry.value}>.value('
        'entity.${entry.key}$writable)$suffix',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('  final ${spec.className}Set? _set;')
    ..writeln('  final ${spec.className}? _entity;');
  for (final field in editFields) {
    buffer.writeln(
      '  final ${_nullableType(field.dartType)} _base${field.capitalizedName};',
    );
  }
  buffer
    ..writeln('  bool _consumed = false;')
    ..writeln()
    ..writeln('  bool get isCreating => _entity == null;')
    ..writeln('  ${spec.className}? get entity => _entity;')
    ..writeln('  @override bool get isConsumed => _consumed;');
  for (final entry in fields.entries) {
    buffer
      ..writeln('  final EntityDraftField<${entry.value}> _${entry.key}Field;')
      ..writeln(
        '  EntityDraftField<${entry.value}> get ${entry.key}Field => '
        '_${entry.key}Field;',
      )
      ..writeln(
        '  ${entry.value} get ${entry.key} => _${entry.key}Field.value;',
      )
      ..writeln(
        '  set ${entry.key}(${entry.value} value) => '
        '_${entry.key}Field.value = value;',
      );
  }
  buffer
    ..writeln()
    ..writeln('  @override')
    ..writeln('  void discard() => _consumed = true;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Future<${spec.className}> save() async {')
    ..writeln('    if (_consumed) {')
    ..writeln('      throw EntityDraftStateException(')
    ..writeln("        entityType: '${spec.className}',")
    ..writeln("        entityId: _entity?.id.value ?? '<new>',")
    ..writeln('        reason: EntityDraftFailureReason.consumed,')
    ..writeln("        message: 'This mutation draft is already consumed.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final current = _entity;');
  if (spec.canCreatePublicly) {
    buffer
      ..writeln('    if (current == null) {')
      ..writeln('      final created = await _set!.create(');
    for (final field in spec.createParameters) {
      buffer.writeln(
        "        ${field.name}: _${field.name}Field.requireValue(entityType: '${spec.className}', field: '${field.name}'),",
      );
    }
    buffer
      ..writeln('      );')
      ..writeln('      _consumed = true;')
      ..writeln('      return created;')
      ..writeln('    }');
  } else {
    buffer
      ..writeln('    if (current == null) {')
      ..writeln(
        "      throw StateError('${spec.className} cannot be created.');",
      )
      ..writeln('    }');
  }
  buffer.writeln('    current.generatedAccess.validateGeneratedDraft();');
  if (transfer != null) {
    final transferFields = spec.orderScopeTransferFields;
    final overlaps = transferFields
        .map(
          (field) =>
              '${_entityValueChangedExpression(field, '_base${field.capitalizedName}', field.name)} && '
              '${_entityValueChangedExpression(field, '_base${field.capitalizedName}', 'current.${field.name}')} && '
              '${_entityValueChangedExpression(field, 'current.${field.name}', field.name)}',
        )
        .join(' || ');
    buffer
      ..writeln('    if ($overlaps) {')
      ..writeln('      throw EntityDraftFieldConflictException(')
      ..writeln("        entityType: '${spec.className}',")
      ..writeln('        entityId: current.id.value,')
      ..writeln('        fields: [');
    for (final field in transferFields) {
      final overlap =
          '${_entityValueChangedExpression(field, '_base${field.capitalizedName}', field.name)} && '
          '${_entityValueChangedExpression(field, '_base${field.capitalizedName}', 'current.${field.name}')} && '
          '${_entityValueChangedExpression(field, 'current.${field.name}', field.name)}';
      buffer.writeln("          if ($overlap) '${field.name}',");
    }
    buffer
      ..writeln('        ],')
      ..writeln('      );')
      ..writeln('    }');
  }
  buffer.writeln(
    '    await current.generatedAccess.runGeneratedTransaction(() async {',
  );
  if (editableFields.isNotEmpty) {
    final first = editableFields.first;
    final firstBase = first.nullable
        ? '_base${first.capitalizedName}'
        : '_base${first.capitalizedName} as ${first.dartType}';
    buffer.writeln(
      '      final generatedDraftBase = ${_fieldReference(spec, first)}'
      '.patch($firstBase)',
    );
    for (final field in editableFields.skip(1)) {
      final base = field.nullable
          ? '_base${field.capitalizedName}'
          : '_base${field.capitalizedName} as ${field.dartType}';
      buffer.writeln(
        '          .merge(${_fieldReference(spec, field)}'
        '.patch($base))',
      );
    }
    buffer.writeln('          ;');
    buffer.writeln(
      '      final generatedDraftCandidate = ${_fieldReference(spec, first)}'
      '.patch(${first.name})',
    );
    for (final field in editableFields.skip(1)) {
      buffer.writeln(
        '          .merge(${_fieldReference(spec, field)}'
        '.patch(${field.name}))',
      );
    }
    buffer
      ..writeln('          ;')
      ..writeln('      await current.generatedAccess.applyGeneratedDraft(')
      ..writeln('        base: generatedDraftBase,')
      ..writeln('        candidate: generatedDraftCandidate,')
      ..writeln('      );');
  }
  if (transfer case final action?) {
    final changed = action.parameters
        .map((parameter) => '${parameter.name} != current.${parameter.name}')
        .join(' || ');
    buffer.writeln('      if ($changed) {');
    _emitDraftActionInvocation(buffer, spec, action, indent: '        ');
    buffer.writeln('      }');
  }
  buffer
    ..writeln('    });')
    ..writeln('    _consumed = true;')
    ..writeln('    return current;')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

void _emitDraftActionInvocation(
  StringBuffer buffer,
  EntitySpec spec,
  ActionSpec action, {
  required String indent,
}) {
  final positional = action.parameters
      .where((parameter) => !parameter.named)
      .map((parameter) => parameter.name)
      .join(', ');
  final named = action.parameters
      .where((parameter) => parameter.named)
      .map((parameter) => '${parameter.name}: ${parameter.name}')
      .join(', ');
  final arguments = [
    if (positional.isNotEmpty) positional,
    if (named.isNotEmpty) named,
  ].join(', ');
  buffer.writeln('$indent await current.${action.methodName}($arguments);');
}

void _emitDetachedRecordFactory(StringBuffer buffer, EntitySpec spec) {
  final recordName = '${spec.className}Record';
  final requiresDetachedNow = spec.fields.any(
    (field) =>
        (field.serverGenerated &&
            field.name == EntityConventions.createdAtFieldName) ||
        field.autoUpdated,
  );
  buffer
    ..writeln()
    ..writeln('  /// Creates an explicitly non-persisted preview or fixture.')
    ..writeln('  factory $recordName.detached({');
  for (final field in spec.fields) {
    if (field.generatedOnly) {
      continue;
    } else if (field.serverGenerated &&
        field.name == EntityConventions.createdAtFieldName) {
      buffer.writeln('    DateTime? ${field.name},');
    } else if (field.autoUpdated) {
      buffer.writeln('    DateTime? ${field.name},');
    } else if (field.name == EntityConventions.serverVersionFieldName) {
      buffer.writeln('    ServerVersion ${field.name} = ServerVersion.zero,');
    } else if (field.nullable) {
      buffer.writeln('    ${field.dartType} ${field.name},');
    } else if (field.defaultValue != null) {
      buffer.writeln(
        '    ${field.dartType} ${field.name} = ${_domainDefaultLiteral(field)},',
      );
    } else {
      buffer.writeln('    required ${field.dartType} ${field.name},');
    }
  }
  buffer
    ..writeln('    Clock clock = const SystemClock(),')
    ..writeln(
      '    EntityMutationSink mutationSink = '
      'const DetachedEntityMutationSink(),',
    )
    ..writeln('  }) {');
  if (requiresDetachedNow) {
    buffer.writeln('    final detachedNow = clock.nowUtc();');
  }
  buffer
    ..writeln('    return const ${spec.className}Descriptor().instantiate(')
    ..writeln('      mutationSink: mutationSink,')
    ..writeln('      clock: clock,')
    ..writeln('      localRevision: 0,')
    ..writeln('      fields: {');
  for (final field in spec.fields) {
    final value = field.generatedOnly
        ? _domainDefaultLiteral(field)
        : (field.serverGenerated &&
                  field.name == EntityConventions.createdAtFieldName) ||
              field.autoUpdated
        ? '${field.name} ?? detachedNow'
        : field.name;
    buffer.writeln(
      "        '${field.name}': ${_fieldReference(spec, field)}.encode($value),",
    );
  }
  buffer
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('  }');
}

bool _hasValidation(FieldSpec field) =>
    field.minLength != null ||
    field.maxLength != null ||
    field.minValue != null ||
    field.maxValue != null ||
    field.allowedValues.isNotEmpty;

void _emitFieldValidation(
  StringBuffer buffer,
  EntitySpec spec,
  FieldSpec field, {
  required String valueExpression,
  required String indent,
}) {
  late final String constrainedValue;
  if (field.isScalarValue && field.nullable) {
    constrainedValue = 'validated${field.capitalizedName}';
    buffer.writeln(
      '$indent final $constrainedValue = $valueExpression?.toScalar();',
    );
  } else {
    constrainedValue = field.isScalarValue
        ? '$valueExpression.toScalar()'
        : valueExpression;
  }

  void emitCheck(String condition, String message) {
    buffer
      ..writeln('$indent if ($condition) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${field.name}',")
      ..writeln("$indent    message: '$message',")
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }

  if (field.minLength case final minimum?) {
    final measured = field.allowWhitespace
        ? '$constrainedValue.length'
        : '$constrainedValue.trim().length';
    final comparison = '$measured < $minimum';
    emitCheck(
      field.nullable ? '$constrainedValue != null && $comparison' : comparison,
      field.allowWhitespace
          ? 'Must contain at least $minimum character(s).'
          : 'Must contain at least $minimum non-whitespace character(s).',
    );
  }
  if (field.maxLength case final maximum?) {
    final comparison = '$constrainedValue.length > $maximum';
    emitCheck(
      field.nullable ? '$constrainedValue != null && $comparison' : comparison,
      'Must contain at most $maximum character(s).',
    );
  }
  if (field.minValue case final minimum?) {
    final comparison = '$constrainedValue < $minimum';
    emitCheck(
      field.nullable ? '$constrainedValue != null && $comparison' : comparison,
      'Must be greater than or equal to $minimum.',
    );
  }
  if (field.maxValue case final maximum?) {
    final comparison = '$constrainedValue > $maximum';
    emitCheck(
      field.nullable ? '$constrainedValue != null && $comparison' : comparison,
      'Must be less than or equal to $maximum.',
    );
  }
  if (field.allowedValues.isNotEmpty) {
    final values =
        'const {${field.allowedValues.map(_dartLiteral).join(', ')}}';
    final comparison = '!($values).contains($constrainedValue)';
    emitCheck(
      field.nullable ? '$constrainedValue != null && $comparison' : comparison,
      'Must be one of the declared allowed values.',
    );
  }
}

void _emitCrossFieldValidations(
  StringBuffer buffer,
  EntitySpec spec, {
  required String Function(FieldSpec field) valueFor,
  required String indent,
}) {
  for (final field in spec.fields) {
    final otherName = field.greaterThan;
    if (otherName == null) continue;
    final other = spec.fields.singleWhere(
      (candidate) => candidate.name == otherName,
    );
    final value = '(${valueFor(field)})';
    final otherValue = '(${valueFor(other)})';
    late final String condition;
    if (field.nullable || other.nullable) {
      final candidateValue = 'candidate${field.capitalizedName}';
      final candidateOther =
          'candidate${other.capitalizedName}For${field.capitalizedName}';
      buffer
        ..writeln('$indent final $candidateValue = $value;')
        ..writeln('$indent final $candidateOther = $otherValue;');
      condition =
          '$candidateValue != null && $candidateOther != null && '
          '$candidateValue <= $candidateOther';
    } else {
      condition = '$value <= $otherValue';
    }
    buffer
      ..writeln('$indent if ($condition) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${field.name}',")
      ..writeln("$indent    message: 'Must be greater than `${other.name}`.',")
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
  for (final field in spec.fields) {
    final otherName = field.greaterThanOrEqual;
    if (otherName == null) continue;
    final other = spec.fields.singleWhere(
      (candidate) => candidate.name == otherName,
    );
    final value = '(${valueFor(field)})';
    final otherValue = '(${valueFor(other)})';
    late final String condition;
    if (field.nullable || other.nullable) {
      final candidateValue = 'candidate${field.capitalizedName}';
      final candidateOther =
          'candidate${other.capitalizedName}For${field.capitalizedName}';
      buffer
        ..writeln('$indent final $candidateValue = $value;')
        ..writeln('$indent final $candidateOther = $otherValue;');
      condition =
          '$candidateValue != null && $candidateOther != null && '
          '$candidateValue < $candidateOther';
    } else {
      condition = '$value < $otherValue';
    }
    buffer
      ..writeln('$indent if ($condition) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${field.name}',")
      ..writeln(
        "$indent    message: 'Must be greater than or equal to `${other.name}`.',",
      )
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
  for (final field in spec.fields) {
    final otherName = field.requires;
    if (otherName == null) continue;
    final other = spec.fields.singleWhere(
      (candidate) => candidate.name == otherName,
    );
    final value = '(${valueFor(field)})';
    final otherValue = '(${valueFor(other)})';
    buffer
      ..writeln('$indent if ($value != null && $otherValue == null) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${field.name}',")
      ..writeln("$indent    message: 'Requires `${other.name}`.',")
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
  for (final field in spec.fields) {
    final otherName = field.notEqualTo;
    if (otherName == null) continue;
    final other = spec.fields.singleWhere(
      (candidate) => candidate.name == otherName,
    );
    final value = '(${valueFor(field)})';
    final otherValue = '(${valueFor(other)})';
    final equality = '$value == $otherValue';
    final condition = field.nullable || other.nullable
        ? '$value != null && $otherValue != null && $equality'
        : equality;
    buffer
      ..writeln('$indent if ($condition) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${field.name}',")
      ..writeln("$indent    message: 'Must differ from `${other.name}`.',")
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
  for (final group in spec.exclusiveFieldGroups) {
    final nonNullCount = group.fields
        .map(
          (name) =>
              '((${valueFor(spec.fields.singleWhere((field) => field.name == name))}) '
              '!= null ? 1 : 0)',
        )
        .join(' + ');
    buffer
      ..writeln(
        '$indent if ($nonNullCount ${group.allowNone ? '>' : '!='} 1) {',
      )
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${group.fields.first}',")
      ..writeln(
        "$indent    message: '${group.allowNone ? 'At most' : 'Exactly'} one of `${group.fields.join('`, `')}` may be set.',",
      )
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
  for (final index in spec.compoundIndexes.where(
    (candidate) => candidate.unordered,
  )) {
    final other = spec.fields.singleWhere(
      (field) => field.name == index.fields.single,
    );
    final owner = spec.ownerField;
    buffer
      ..writeln('$indent if ((${valueFor(owner)}) == (${valueFor(other)})) {')
      ..writeln('$indent  throw const EntityValidationException(')
      ..writeln("$indent    entityType: '${spec.className}',")
      ..writeln("$indent    field: '${other.name}',")
      ..writeln("$indent    message: 'Must differ from the owner.',")
      ..writeln('$indent  );')
      ..writeln('$indent}');
  }
}

void _emitCommand(StringBuffer buffer, EntitySpec spec, CommandSpec command) {
  final field = spec.fields.singleWhere(
    (field) => field.name == command.targetField,
  );
  final parameter = command.parameterName;
  final valueExpression = switch (command.value) {
    SyncCommandValue.clockNow => '_clock.nowUtc()',
    SyncCommandValue.clear => 'null',
    SyncCommandValue.parameter
        when field.sqlType == SqlType.timestampWithTimeZone =>
      '${parameter!}.toUtc()',
    SyncCommandValue.parameter => parameter!,
  };
  final signature = switch (command.value) {
    SyncCommandValue.clockNow => 'Future<void> ${command.methodName}()',
    SyncCommandValue.clear => 'Future<void> ${command.methodName}()',
    SyncCommandValue.parameter =>
      'Future<void> ${command.methodName}(${command.parameterType} $parameter)',
  };
  final mutationTimeExpression = command.value == SyncCommandValue.clockNow
      ? 'commandValue'
      : '_clock.nowUtc()';
  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;
  buffer
    ..writeln('  @override')
    ..writeln('  $signature {');
  if (field.name == EntityConventions.deletedAtFieldName) {
    buffer
      ..writeln('    final oldValue = _${field.name}Store.value;')
      ..writeln(
        command.value == SyncCommandValue.clear
            ? '    if (oldValue == null) return Future.value();'
            : '    if (oldValue != null) return Future.value();',
      )
      ..writeln(
        command.value == SyncCommandValue.clear
            ? '    const DateTime? commandValue = null;'
            : '    final commandValue = $valueExpression;',
      );
  } else {
    buffer
      ..writeln('    final commandValue = $valueExpression;')
      ..writeln('    final oldValue = _${field.name}Store.value;')
      ..writeln('    if (oldValue == commandValue) return Future.value();');
  }
  _emitMutationAuthorization(
    buffer,
    spec,
    field,
    operation: RlsOperation.delete,
    oldValueExpression: 'oldValue',
    newValueExpression: 'commandValue',
    indent: '    ',
  );
  buffer.writeln('    final mutationTime = $mutationTimeExpression;');
  if (autoUpdated != null) {
    buffer.writeln('    final oldUpdatedAt = _${autoUpdated.name}Store.value;');
  }
  buffer
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() {')
    ..writeln('      _${field.name}Store.value = commandValue;');
  if (autoUpdated != null) {
    buffer.writeln('      _${autoUpdated.name}Store.value = mutationTime;');
  }
  buffer
    ..writeln('    });')
    ..writeln(
      '    final syncPatch = ${spec.className}Fields.${field.name}.patch(commandValue);',
    )
    ..writeln(
      '    _generatedLocalCommit = '
      '_mutationSink.recordEntityMutation<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln(
      autoUpdated == null
          ? '      patch: syncPatch,'
          : '      patch: syncPatch.merge(${spec.className}Fields.${autoUpdated.name}.patch(mutationTime)),',
    )
    ..writeln('      syncPatch: syncPatch,')
    ..writeln('      operation: SyncMutationOperation.delete,')
    ..writeln('      kind: PushSyncWorkKind.semanticCommand,')
    ..writeln('      persistsEntityState: true,');
  buffer.writeln('      occurredAt: mutationTime,');
  if (spec.hasActivityTrackedCapability) {
    buffer.writeln(
      '      activityOperation: '
      '${_activityOperationExpression(command.methodName)},',
    );
  }
  buffer
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;')
    ..writeln('        _${field.name}Store.value = oldValue;');
  if (autoUpdated != null) {
    buffer.writeln('        _${autoUpdated.name}Store.value = oldUpdatedAt;');
  }
  buffer
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('    return _generatedMutationCompletion(_generatedLocalCommit);')
    ..writeln('  }');
}

void _emitAction(StringBuffer buffer, EntitySpec spec, ActionSpec action) {
  if (spec.isOrderScopeTransferAction(action)) {
    _emitOrderScopeTransferAction(buffer, spec, action);
    return;
  }
  final targetFields = action.targetFields
      .map((name) => spec.fields.singleWhere((field) => field.name == name))
      .toList(growable: false);
  final assignments = {
    for (final assignment in action.assignments)
      assignment.fieldName: assignment,
  };
  final positional = action.parameters
      .where((parameter) => !parameter.named)
      .map((parameter) => '${parameter.dartType} ${parameter.name}')
      .join(', ');
  final named = action.parameters
      .where((parameter) => parameter.named)
      .map((parameter) => 'required ${parameter.dartType} ${parameter.name}')
      .join(', ');
  final parameters = [
    if (positional.isNotEmpty) positional,
    if (named.isNotEmpty) '{$named}',
  ].join(', ');
  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;

  buffer
    ..writeln('  @override')
    ..writeln('  Future<void> ${action.methodName}($parameters) {')
    ..writeln('    final _generatedActionTime = _clock.nowUtc();');
  for (final field in targetFields) {
    final assignment = assignments[field.name];
    buffer.writeln(
      '    final old${field.capitalizedName} = _${field.name}Store.value;',
    );
    final nextValue = assignment == null
        ? _normalizedEntityValueExpression(field, field.name)
        : _actionAssignmentExpression(field, assignment);
    buffer.writeln('    final next${field.capitalizedName} = $nextValue;');
    buffer.writeln(
      '    final ${field.name}Changed = '
      '${_entityValueChangedExpression(field, 'old${field.capitalizedName}', 'next${field.capitalizedName}')};',
    );
  }
  buffer.writeln(
    '    if (!(${targetFields.map((field) => '${field.name}Changed').join(' || ')})) return Future.value();',
  );
  if (spec.fields.any(
    (field) => field.name == EntityConventions.deletedAtFieldName,
  )) {
    _emitDeletedMutationGuard(buffer, spec, fieldName: action.methodName);
  }
  for (final field in targetFields) {
    _emitFieldValidation(
      buffer,
      spec,
      field,
      valueExpression: 'next${field.capitalizedName}',
      indent: '    ',
    );
    _emitTransitionValidation(
      buffer,
      spec,
      field,
      oldValueExpression: 'old${field.capitalizedName}',
      newValueExpression: 'next${field.capitalizedName}',
      changedExpression: '${field.name}Changed',
    );
  }
  final targetNames = targetFields.map((field) => field.name).toSet();
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (field) => targetNames.contains(field.name)
        ? 'next${field.capitalizedName}'
        : field.name,
    indent: '    ',
  );
  for (final field in targetFields) {
    _emitMutationAuthorization(
      buffer,
      spec,
      field,
      operation: RlsOperation.update,
      oldValueExpression: 'old${field.capitalizedName}',
      newValueExpression: 'next${field.capitalizedName}',
      changedExpression: '${field.name}Changed',
      indent: '    ',
    );
  }
  if (autoUpdated != null) {
    buffer.writeln('    final oldUpdatedAt = _${autoUpdated.name}Store.value;');
  }
  buffer
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() {');
  for (final field in targetFields) {
    buffer.writeln(
      '      _${field.name}Store.value = next${field.capitalizedName};',
    );
  }
  if (autoUpdated != null) {
    buffer.writeln(
      '      _${autoUpdated.name}Store.value = _generatedActionTime;',
    );
  }
  buffer
    ..writeln('    });')
    ..writeln(
      '    final syncPatch = '
      '${spec.className}Fields.${targetFields.first.name}.patch(next${targetFields.first.capitalizedName})',
    );
  for (final field in targetFields.skip(1)) {
    buffer.writeln(
      '      .merge(${spec.className}Fields.${field.name}.patch(next${field.capitalizedName}))',
    );
  }
  buffer.writeln('      ;');
  buffer
    ..writeln(
      '    _generatedLocalCommit = '
      '_mutationSink.recordEntityMutation<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln(
      autoUpdated == null
          ? '      patch: syncPatch,'
          : '      patch: syncPatch.merge(${spec.className}Fields.${autoUpdated.name}.patch(_generatedActionTime)),',
    )
    ..writeln('      syncPatch: syncPatch,')
    ..writeln('      occurredAt: _generatedActionTime,');
  if (spec.hasActivityTrackedCapability) {
    buffer.writeln(
      '      activityOperation: '
      '${_activityOperationExpression(action.methodName)},',
    );
  }
  buffer
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;');
  for (final field in targetFields) {
    buffer.writeln(
      '        _${field.name}Store.value = old${field.capitalizedName};',
    );
  }
  if (autoUpdated != null) {
    buffer.writeln('        _${autoUpdated.name}Store.value = oldUpdatedAt;');
  }
  buffer
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('    return _generatedMutationCompletion(_generatedLocalCommit);')
    ..writeln('  }');
}

String _activityOperationExpression(String methodName) => switch (methodName) {
  'archive' => 'ActivityOperation.archived',
  'unarchive' => 'ActivityOperation.unarchived',
  'activate' => 'ActivityOperation.activated',
  'deactivate' => 'ActivityOperation.deactivated',
  'remove' => 'ActivityOperation.removed',
  'restore' => 'ActivityOperation.restored',
  _ => "ActivityOperation.action('$methodName')",
};

void _emitOrderScopeTransferAction(
  StringBuffer buffer,
  EntitySpec spec,
  ActionSpec action,
) {
  final targetFields = spec.orderScopeTransferFields;
  final rankField = spec.orderRankField!;
  final positional = action.parameters
      .where((parameter) => !parameter.named)
      .map((parameter) => '${parameter.dartType} ${parameter.name}')
      .join(', ');
  final named = action.parameters
      .where((parameter) => parameter.named)
      .map((parameter) => 'required ${parameter.dartType} ${parameter.name}')
      .join(', ');
  final parameters = [
    if (positional.isNotEmpty) positional,
    if (named.isNotEmpty) '{$named}',
  ].join(', ');
  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;

  buffer
    ..writeln('  @override')
    ..writeln('  Future<void> ${action.methodName}($parameters) async {')
    ..writeln('    final _generatedActionTime = _clock.nowUtc();');
  for (final field in targetFields) {
    buffer
      ..writeln(
        '    final old${field.capitalizedName} = _${field.name}Store.value;',
      )
      ..writeln(
        '    final next${field.capitalizedName} = '
        '${_normalizedEntityValueExpression(field, field.name)};',
      )
      ..writeln(
        '    final ${field.name}Changed = '
        '${_entityValueChangedExpression(field, 'old${field.capitalizedName}', 'next${field.capitalizedName}')};',
      );
  }
  buffer.writeln(
    '    if (!(${targetFields.map((field) => '${field.name}Changed').join(' || ')})) return;',
  );
  if (spec.deletedAtField != null) {
    _emitDeletedMutationGuard(buffer, spec, fieldName: action.methodName);
  }
  for (final field in targetFields) {
    _emitFieldValidation(
      buffer,
      spec,
      field,
      valueExpression: 'next${field.capitalizedName}',
      indent: '    ',
    );
    _emitMutationAuthorization(
      buffer,
      spec,
      field,
      operation: RlsOperation.update,
      oldValueExpression: 'old${field.capitalizedName}',
      newValueExpression: 'next${field.capitalizedName}',
      changedExpression: '${field.name}Changed',
      indent: '    ',
    );
  }
  final targetNames = targetFields.map((field) => field.name).toSet();
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (field) => targetNames.contains(field.name)
        ? 'next${field.capitalizedName}'
        : field.name,
    indent: '    ',
  );
  buffer.writeln('    final targetScope = EntityPatch.fromWire({');
  for (final field in targetFields) {
    buffer.writeln(
      "      '${field.name}': ${_fieldReference(spec, field)}.encode(next${field.capitalizedName}),",
    );
  }
  buffer
    ..writeln('    });')
    ..writeln('    final transferSink = switch (_mutationSink) {')
    ..writeln('      final OrderedTransferMutationSink value => value,')
    ..writeln(
      "      _ => throw StateError('The attached mutation sink does not support ordered scope transfers.'),",
    )
    ..writeln('    };')
    ..writeln(
      '    final transferPlan = await transferSink.prepareEntityOrderTransfer<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln('      targetScope: targetScope,')
    ..writeln('      placement: OrderedPlacement.last,')
    ..writeln('    );')
    ..writeln('    final oldOrderRank = _${rankField.name}Store.value;');
  if (autoUpdated != null) {
    buffer.writeln('    final oldUpdatedAt = _${autoUpdated.name}Store.value;');
  }
  buffer
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() {');
  for (final field in targetFields) {
    buffer.writeln(
      '      _${field.name}Store.value = next${field.capitalizedName};',
    );
  }
  buffer.writeln('      _${rankField.name}Store.value = transferPlan.rank;');
  if (autoUpdated != null) {
    buffer.writeln(
      '      _${autoUpdated.name}Store.value = _generatedActionTime;',
    );
  }
  buffer
    ..writeln('    });')
    ..writeln(
      '    final localPatch = ${_fieldReference(spec, targetFields.first)}'
      '.patch(next${targetFields.first.capitalizedName})',
    );
  for (final field in targetFields.skip(1)) {
    buffer.writeln(
      '      .merge(${_fieldReference(spec, field)}.patch(next${field.capitalizedName}))',
    );
  }
  buffer.writeln(
    '      .merge(${_fieldReference(spec, rankField)}.patch(transferPlan.rank))',
  );
  if (autoUpdated != null) {
    buffer.writeln(
      '      .merge(${_fieldReference(spec, autoUpdated)}.patch(_generatedActionTime))',
    );
  }
  buffer
    ..writeln('      ;')
    ..writeln('    final transferChange = GeneratedOrderStateChange(')
    ..writeln('      entity: this,')
    ..writeln('      scopeKey: transferPlan.targetScopeKey,')
    ..writeln('      patch: localPatch,')
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;');
  for (final field in targetFields) {
    buffer.writeln(
      '        _${field.name}Store.value = old${field.capitalizedName};',
    );
  }
  buffer.writeln('        _${rankField.name}Store.value = oldOrderRank;');
  if (autoUpdated != null) {
    buffer.writeln('        _${autoUpdated.name}Store.value = oldUpdatedAt;');
  }
  buffer
    ..writeln('      },')
    ..writeln(
      '      bindLocalCommit: (commit) => _generatedLocalCommit = commit,',
    )
    ..writeln('    );')
    ..writeln('    try {')
    ..writeln(
      '      final commit = transferSink.recordEntityOrderTransfer<${spec.className}>(',
    )
    ..writeln('        entity: this,')
    ..writeln('        command: TransferOrderedCommand(')
    ..writeln('          targetScope: targetScope,')
    ..writeln('          placement: OrderedPlacement.last,')
    ..writeln(
      '          sourceScopeBaseVersion: transferPlan.sourceScopeBaseVersion,',
    )
    ..writeln(
      '          targetScopeBaseVersion: transferPlan.targetScopeBaseVersion,',
    )
    ..writeln('        ),')
    ..writeln('        transferChange: transferChange,')
    ..writeln(
      '        targetRebalanceChanges: transferPlan.targetRebalanceChanges,',
    )
    ..writeln('        occurredAt: _generatedActionTime,')
    ..writeln('      );')
    ..writeln('      transferChange.bindLocalCommit(commit);')
    ..writeln(
      '      for (final change in transferPlan.targetRebalanceChanges) {',
    )
    ..writeln('        change.bindLocalCommit(commit);')
    ..writeln('      }')
    ..writeln('      await _generatedMutationCompletion(commit);')
    ..writeln('      transferPlan.releasePreparedScopes();')
    ..writeln('      return;')
    ..writeln('    } catch (_) {')
    ..writeln('      transferChange.rollbackIfCurrent();')
    ..writeln('      transferPlan.rollbackPreparedChanges();')
    ..writeln('      rethrow;')
    ..writeln('    }')
    ..writeln('  }');
}

void _emitMutationAuthorization(
  StringBuffer buffer,
  EntitySpec spec,
  FieldSpec field, {
  required RlsOperation operation,
  required String oldValueExpression,
  required String newValueExpression,
  required String indent,
  String? changedExpression,
}) {
  final entityPrincipals = spec.security.grants
      .where((grant) => grant.operation == operation)
      .map((grant) => grant.principal)
      .toList(growable: false);
  final fieldPrincipals =
      operation == RlsOperation.update && field.updatePrincipals.isNotEmpty
      ? field.updatePrincipals
      : entityPrincipals;
  final condition = changedExpression;
  if (condition != null) buffer.writeln('$indent if ($condition) {');
  final nested = condition == null ? indent : '$indent  ';
  if (operation == RlsOperation.update && field.transitions.isNotEmpty) {
    final variable = '_generated${field.capitalizedName}Principals';
    buffer.writeln(
      '$nested final $variable = switch '
      '(($oldValueExpression, $newValueExpression)) {',
    );
    for (final transition in field.transitions) {
      final principals = transition.principals.isEmpty
          ? fieldPrincipals
          : transition.principals;
      buffer.writeln(
        '$nested  '
        '(${field.dartType}.${transition.from}, '
        '${field.dartType}.${transition.to}) => '
        '${_principalListLiteral(principals)},',
      );
    }
    buffer
      ..writeln('$nested  _ => const <RlsPrincipal>[],')
      ..writeln('$nested};')
      ..writeln('${nested}_mutationSink.validateMutationAuthorization(')
      ..writeln('$nested  entity: this,')
      ..writeln('$nested  operation: RlsOperation.${operation.name},')
      ..writeln('$nested  principals: $variable,')
      ..writeln('$nested);');
  } else {
    buffer
      ..writeln('${nested}_mutationSink.validateMutationAuthorization(')
      ..writeln('$nested  entity: this,')
      ..writeln('$nested  operation: RlsOperation.${operation.name},')
      ..writeln(
        '$nested  principals: ${_principalListLiteral(fieldPrincipals)},',
      )
      ..writeln('$nested);');
  }
  if (condition != null) buffer.writeln('$indent}');
}

String _principalListLiteral(Iterable<RlsPrincipal> principals) {
  final values = principals.toList(growable: false);
  if (values.isEmpty) return 'const <RlsPrincipal>[]';
  return 'const [${values.map((value) => 'RlsPrincipal.${value.name}').join(', ')}]';
}

String _actionAssignmentExpression(
  FieldSpec field,
  ActionAssignmentSpec assignment,
) => switch (assignment.kind) {
  ActionValueKind.literal when field.isEnum =>
    '${field.dartType.replaceAll('?', '')}.${assignment.literal}',
  ActionValueKind.literal => _dartLiteral(assignment.literal),
  ActionValueKind.clockNow =>
    field.nullable
        ? 'old${field.capitalizedName} ?? _generatedActionTime'
        : '_generatedActionTime',
  ActionValueKind.clear => 'null',
};

String _normalizedEntityValueExpression(FieldSpec field, String source) {
  if (field.isScalarValue) {
    final type = field.dartType.replaceAll('?', '');
    final normalized = '$type.fromScalar($source.toScalar())';
    return field.nullable ? '$source == null ? null : $normalized' : normalized;
  }
  if (field.dartType.replaceAll('?', '') == 'DateTime') {
    return field.nullable ? '$source?.toUtc()' : '$source.toUtc()';
  }
  return source;
}

String _entityValueChangedExpression(
  FieldSpec field,
  String oldValue,
  String newValue,
) => field.isScalarValue
    ? '!entityValuesEqual($oldValue, $newValue)'
    : '$oldValue != $newValue';

void _emitSetter(StringBuffer buffer, EntitySpec spec, FieldSpec field) {
  final operation = field.name == EntityConventions.deletedAtFieldName
      ? 'value == null ? SyncMutationOperation.patch : SyncMutationOperation.delete'
      : 'SyncMutationOperation.patch';
  final autoUpdated = spec.fields
      .where((field) => field.autoUpdated)
      .firstOrNull;
  buffer
    ..writeln('  @override')
    ..writeln('  set ${field.name}(${field.dartType} value) {');
  final normalizesValue =
      field.isScalarValue || field.dartType.replaceAll('?', '') == 'DateTime';
  final valueExpression = normalizesValue ? 'normalizedValue' : 'value';
  buffer
    ..writeln('    final oldValue = _${field.name}Store.value;')
    ..writeln(
      field.isScalarValue
          ? '    if (entityValuesEqual(oldValue, value)) return;'
          : '    if (oldValue == value) return;',
    );
  if (spec.fields.any(
        (candidate) => candidate.name == EntityConventions.deletedAtFieldName,
      ) &&
      field.name != EntityConventions.deletedAtFieldName) {
    _emitDeletedMutationGuard(buffer, spec, fieldName: field.name);
  }
  if (normalizesValue) {
    buffer.writeln(
      '    final normalizedValue = '
      '${_normalizedEntityValueExpression(field, 'value')};',
    );
  }
  _emitFieldValidation(
    buffer,
    spec,
    field,
    valueExpression: valueExpression,
    indent: '    ',
  );
  _emitTransitionValidation(
    buffer,
    spec,
    field,
    oldValueExpression: 'oldValue',
    newValueExpression: valueExpression,
  );
  _emitCrossFieldValidations(
    buffer,
    spec,
    valueFor: (candidate) =>
        candidate.name == field.name ? valueExpression : candidate.name,
    indent: '    ',
  );
  _emitMutationAuthorization(
    buffer,
    spec,
    field,
    operation: RlsOperation.update,
    oldValueExpression: 'oldValue',
    newValueExpression: valueExpression,
    indent: '    ',
  );
  buffer.writeln('    final mutationTime = _clock.nowUtc();');
  if (autoUpdated != null) {
    buffer.writeln('    final oldUpdatedAt = _${autoUpdated.name}Store.value;');
  }
  buffer
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() {')
    ..writeln('      _${field.name}Store.value = $valueExpression;');
  if (autoUpdated != null) {
    buffer.writeln('      _${autoUpdated.name}Store.value = mutationTime;');
  }
  buffer
    ..writeln('    });')
    ..writeln(
      '    final syncPatch = ${spec.className}Fields.${field.name}.patch($valueExpression);',
    )
    ..writeln(
      '    _generatedLocalCommit = '
      '_mutationSink.recordEntityMutation<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln(
      autoUpdated == null
          ? '      patch: syncPatch,'
          : '      patch: syncPatch.merge(${spec.className}Fields.${autoUpdated.name}.patch(mutationTime)),',
    )
    ..writeln('      syncPatch: syncPatch,')
    ..writeln('      operation: $operation,')
    ..writeln('      occurredAt: mutationTime,')
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;')
    ..writeln('        _${field.name}Store.value = oldValue;');
  if (autoUpdated != null) {
    buffer.writeln('        _${autoUpdated.name}Store.value = oldUpdatedAt;');
  }
  buffer
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('  }');
}

void _emitTransitionValidation(
  StringBuffer buffer,
  EntitySpec spec,
  FieldSpec field, {
  required String oldValueExpression,
  required String newValueExpression,
  String? changedExpression,
}) {
  if (field.transitions.isEmpty) return;
  final allowed = field.transitions
      .map(
        (transition) =>
            '($oldValueExpression == ${field.dartType}.${transition.from} && '
            '$newValueExpression == ${field.dartType}.${transition.to})',
      )
      .join(' || ');
  final invalid = changedExpression == null
      ? '!($allowed)'
      : '$changedExpression && !($allowed)';
  buffer
    ..writeln('    if ($invalid) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '${spec.className}',")
    ..writeln("        field: '${field.name}',")
    ..writeln("        message: 'State transition is not allowed.',")
    ..writeln('      );')
    ..writeln('    }');
}

void _emitDeletedMutationGuard(
  StringBuffer buffer,
  EntitySpec spec, {
  required String fieldName,
}) {
  buffer
    ..writeln('    if (_deletedAtStore.value != null) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '${spec.className}',")
    ..writeln("        field: '$fieldName',")
    ..writeln("        message: 'Deleted entities cannot be changed.',")
    ..writeln('      );')
    ..writeln('    }');
}

void _emitSet(StringBuffer buffer, EntitySpec spec) {
  final recordName = '${spec.className}Record';
  final setName = '${spec.className}Set';
  final createFields = spec.createFields;
  final createParameters = spec.createParameters;
  final engineType = 'LocalEntityEngine<${spec.className}, $recordName>';
  final cachesAuthenticatedOwner =
      spec.canCreatePublicly && spec.ownershipReferenceFields.isEmpty;
  buffer
    ..writeln('final class $setName {')
    ..writeln('  $setName($engineType engine)')
    ..writeln('      : _engine = engine,');
  if (cachesAuthenticatedOwner) {
    buffer.writeln(
      '        _ownerId = engine.authenticatedOwnerId<${spec.ownerClassName}>(),',
    );
  }
  if (spec.cardinality == Cardinality.bounded) {
    buffer.writeln(
      '        _queries = LocalEntityQueryCache<${spec.className}>('
      'source: engine.all);',
    );
  } else {
    buffer
      ..writeln('        _queries = LocalEntityQueryCache.database(')
      ..writeln('          loader: (spec, {required after, required limit}) =>')
      ..writeln('              engine.loadQueryPage(')
      ..writeln('                spec, after: after, limit: limit,')
      ..writeln('              ),')
      ..writeln('          invalidations: engine.projectionChanges,')
      ..writeln('        );');
  }
  buffer
    ..writeln('  final $engineType _engine;')
    ..writeln('  final LocalEntityQueryCache<${spec.className}> _queries;');
  final hasEditDraft = spec.draftEditableFields.isNotEmpty;
  if (spec.canCreatePublicly ||
      hasEditDraft ||
      spec.orderScopeTransferAction != null) {
    if (spec.canCreatePublicly) {
      buffer.writeln(
        '  ${spec.className}MutationDraft beginCreate() => '
        '${spec.className}MutationDraft.create(this);',
      );
    }
    if (hasEditDraft || spec.orderScopeTransferAction != null) {
      buffer.writeln(
        '  ${spec.className}MutationDraft beginEdit(${spec.className} entity) '
        '=> entity.beginEdit();',
      );
    }
  }
  if (cachesAuthenticatedOwner) {
    buffer.writeln('  final ${spec.ownerField.dartType} _ownerId;');
  }
  if (spec.cardinality == Cardinality.bounded) {
    buffer.writeln(
      '  ReadOnlyObservableList<${spec.className}> get all => _engine.all;',
    );
  }
  if (spec.cardinality == Cardinality.unbounded) {
    buffer
      ..writeln(
        '  Future<EntityLookupLease<${spec.className}>?> loadById('
        'LocalId<${spec.className}> id, {bool refresh = false}) => '
        '_engine.loadRawId(id.value, refresh: refresh);',
      )
      ..writeln(
        '  Future<R> useById<R>(LocalId<${spec.className}> id, '
        'LeaseAction<${spec.className}, R> action, '
        '{bool refresh = false}) =>',
      )
      ..writeln('      loadById(id, refresh: refresh).use(')
      ..writeln('        action,')
      ..writeln('        ifAbsent: () => throw EntityNotFoundException(')
      ..writeln("          entityType: '${spec.className}',")
      ..writeln('          entityId: id.value,')
      ..writeln('        ),')
      ..writeln('      );');
  }
  buffer.writeln(
    '  Stream<${spec.className}?> watchById('
    'LocalId<${spec.className}> id) => _engine.'
    '${spec.cardinality == Cardinality.bounded ? 'watchRawId' : 'watchLoadedRawId'}'
    '(id.value);',
  );
  if (spec.cardinality == Cardinality.bounded) {
    buffer
      ..writeln(
        '  ${spec.className}? byId(LocalId<${spec.className}> id) => '
        '_engine.byRawId(id.value);',
      )
      ..writeln(
        '  ${spec.className} require(LocalId<${spec.className}> id) => '
        '_engine.requireRawId(id.value);',
      );
    _emitUniqueLookups(buffer, spec);
  } else {
    buffer.writeln(
      '  EntityLookup<${spec.className}> lookup('
      'LocalId<${spec.className}> id, {',
    );
    buffer.writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
    if (spec.hasArchivableCapability) {
      buffer.writeln(
        '    ArchiveVisibility archives = ArchiveVisibility.include,',
      );
    }
    buffer
      ..writeln('  }) => EntityLookup(query(')
      ..writeln('    where: ${spec.className}Fields.id.equals(id),')
      ..writeln('    tombstones: tombstones,')
      ..write(spec.hasArchivableCapability ? '    archives: archives,\n' : '')
      ..writeln('    pageSize: 1,')
      ..writeln('  ));');
  }
  buffer
    ..writeln('  LocalEntityQuery<${spec.className}> query({')
    ..writeln('    EntityPredicate<${spec.className}>? where,')
    ..writeln('    EntityOrder<${spec.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  if (spec.hasArchivableCapability) {
    buffer.writeln(
      '    ArchiveVisibility archives = ArchiveVisibility.exclude,',
    );
  }
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln('  }) => _queries.acquire(EntityQuerySpec(')
    ..writeln('    where: _tombstonePredicate(tombstones) &');
  if (spec.hasArchivableCapability) {
    buffer.writeln('        _archivePredicate(archives) &');
  }
  buffer
    ..writeln('        (where ?? EntityPredicate<${spec.className}>.all()),')
    ..writeln('    orderBy: orderBy,')
    ..writeln('    pageSize: pageSize,')
    ..writeln('  ));');
  if (spec.hasOrderedCapability) {
    buffer.writeln(
      '  EntityOrder<${spec.className}> get canonicalOrder => '
      '${_fieldReference(spec, spec.orderRankField!)}.ascending('
      'tieBreakBy: (entity) => entity.id.value);',
    );
    if (spec.cardinality == Cardinality.bounded) {
      _emitBoundedOrderOperations(buffer, spec);
    } else {
      _emitUnboundedOrderOperations(buffer, spec);
    }
  }
  buffer
    ..writeln('  Stream<EntityQueryState<${spec.className}>> watchQuery({')
    ..writeln('    EntityPredicate<${spec.className}>? where,')
    ..writeln('    EntityOrder<${spec.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  if (spec.hasArchivableCapability) {
    buffer.writeln(
      '    ArchiveVisibility archives = ArchiveVisibility.exclude,',
    );
  }
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln(
      '    Iterable<PersistedEntityFieldReference<${spec.className}>> '
      'observeFields = const [],',
    )
    ..writeln('  }) => _queries.watch(')
    ..writeln('    EntityQuerySpec(')
    ..writeln('      where: _tombstonePredicate(tombstones) &');
  if (spec.hasArchivableCapability) {
    buffer.writeln('          _archivePredicate(archives) &');
  }
  buffer
    ..writeln('          (where ?? EntityPredicate<${spec.className}>.all()),')
    ..writeln('      orderBy: orderBy,')
    ..writeln('      pageSize: pageSize,')
    ..writeln('    ),')
    ..writeln('    observeFields: observeFields,')
    ..writeln('  );');
  buffer
    ..writeln(
      '  Stream<EntityQueryState<${spec.className}>> watchCompleteQuery({',
    )
    ..writeln('    EntityPredicate<${spec.className}>? where,')
    ..writeln('    EntityOrder<${spec.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  if (spec.hasArchivableCapability) {
    buffer.writeln(
      '    ArchiveVisibility archives = ArchiveVisibility.exclude,',
    );
  }
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln(
      '    Iterable<PersistedEntityFieldReference<${spec.className}>> '
      'observeFields = const [],',
    )
    ..writeln('  }) => _queries.watchComplete(')
    ..writeln('    EntityQuerySpec(')
    ..writeln('      where: _tombstonePredicate(tombstones) &');
  if (spec.hasArchivableCapability) {
    buffer.writeln('          _archivePredicate(archives) &');
  }
  buffer
    ..writeln('          (where ?? EntityPredicate<${spec.className}>.all()),')
    ..writeln('      orderBy: orderBy,')
    ..writeln('      pageSize: pageSize,')
    ..writeln('    ),')
    ..writeln('    observeFields: observeFields,')
    ..writeln('  );');
  if (spec.canCreatePublicly) {
    buffer.writeln(
      '  LocalId<${spec.className}> allocateId() => _engine.allocateId();',
    );
    final hasGeneratedCreatePlacement = spec.hasOrderedCapability;
    if (hasGeneratedCreatePlacement) {
      for (final (methodName, first) in const [
        ('create', false),
        ('createFirst', true),
      ]) {
        buffer
          ..writeln('  Future<${spec.className}> $methodName({')
          ..writeln('    LocalId<${spec.className}>? id,');
        _emitCreateParameters(buffer, createParameters);
        buffer
          ..writeln('  }) => _create(')
          ..writeln('    first: $first,')
          ..writeln('    id: id,');
        for (final field in createParameters) {
          buffer.writeln('    ${field.name}: ${field.name},');
        }
        buffer.writeln('  );');
      }
      buffer
        ..writeln('  Future<${spec.className}> _create({')
        ..writeln('    required bool first,');
    } else {
      buffer.writeln('  Future<${spec.className}> create({');
    }
    buffer.writeln('    LocalId<${spec.className}>? id,');
    _emitCreateParameters(buffer, createParameters);
    buffer.writeln('  }) {');
    if (spec.isComponent) {
      buffer
        ..writeln('    if (!_engine.isInMutationTransaction) {')
        ..writeln('      throw const EntityValidationException(')
        ..writeln("        entityType: '${spec.className}',")
        ..writeln("        field: 'composition',")
        ..writeln(
          "        message: 'A Component must be created inside an entity-graph transaction.',",
        )
        ..writeln('      );')
        ..writeln('    }');
    }
    final ownershipReferences = spec.ownershipReferenceFields;
    if (ownershipReferences.isNotEmpty) {
      if (ownershipReferences.length == 1 &&
          !ownershipReferences.single.nullable) {
        final ownershipReference = ownershipReferences.single;
        final reference = ownershipReference.reference!;
        buffer
          ..writeln('    final ownershipSource = _engine.resolveReference(')
          ..writeln('      const ${reference.targetClassName}Descriptor(),')
          ..writeln('      ${ownershipReference.name}.value,')
          ..writeln('    );')
          ..writeln('    if (ownershipSource == null) {')
          ..writeln('      throw const EntityValidationException(')
          ..writeln("        entityType: '${spec.className}',")
          ..writeln("        field: '${ownershipReference.name}',")
          ..writeln("        message: 'Ownership reference is not loaded.',")
          ..writeln('      );')
          ..writeln('    }')
          ..writeln(
            '    final inferredOwnerId = ownershipSource.${reference.ownershipSourceFieldName};',
          );
      } else {
        buffer.writeln(
          '    late final ${spec.ownerField.dartType} inferredOwnerId;',
        );
        for (final (index, ownershipReference) in ownershipReferences.indexed) {
          final reference = ownershipReference.reference!;
          buffer
            ..writeln(
              '    ${index == 0 ? 'if' : 'else if'} (${ownershipReference.name} != null) {',
            )
            ..writeln('      final ownershipSource = _engine.resolveReference(')
            ..writeln('        const ${reference.targetClassName}Descriptor(),')
            ..writeln('        ${ownershipReference.name}!.value,')
            ..writeln('      );')
            ..writeln('      if (ownershipSource == null) {')
            ..writeln('        throw const EntityValidationException(')
            ..writeln("          entityType: '${spec.className}',")
            ..writeln("          field: '${ownershipReference.name}',")
            ..writeln(
              "          message: 'Ownership reference is not loaded.',",
            )
            ..writeln('        );')
            ..writeln('      }')
            ..writeln(
              '      inferredOwnerId = ownershipSource.${reference.ownershipSourceFieldName};',
            )
            ..writeln('    }');
        }
        buffer
          ..writeln('    else {')
          ..writeln('      throw const EntityValidationException(')
          ..writeln("        entityType: '${spec.className}',")
          ..writeln("        field: '${ownershipReferences.first.name}',")
          ..writeln("        message: 'One ownership reference is required.',")
          ..writeln('      );')
          ..writeln('    }');
      }
    }
    buffer.writeln(
      hasGeneratedCreatePlacement
          ? '    return _engine.createInGeneratedOrder({'
          : '    return _engine.create({',
    );
    for (final field in createFields) {
      if (field == spec.orderRankField && hasGeneratedCreatePlacement) {
        continue;
      }
      final value = field == spec.ownerField
          ? ownershipReferences.isNotEmpty
                ? 'inferredOwnerId'
                : '_ownerId'
          : field.generatedOnly
          ? _domainDefaultLiteral(field)
          : field.transitions.isNotEmpty ||
                spec.hasInferredActionInitialValue(field)
          ? _domainDefaultLiteral(field)
          : field.name;
      buffer.writeln(
        "      '${field.name}': ${_fieldReference(spec, field)}.encode($value),",
      );
    }
    buffer
      ..writeln('    },')
      ..writeln(
        '    principals: ${_principalListLiteral(spec.security.grants.where((grant) => grant.operation == RlsOperation.insert).map((grant) => grant.principal))},',
      )
      ..writeln('    id: id,');
    if (hasGeneratedCreatePlacement) {
      buffer.writeln(
        '    placement: first '
        '? OrderedPlacement.first : OrderedPlacement.last,',
      );
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
    _emitCreateOrGetMethods(
      buffer,
      spec,
      cachesAuthenticatedOwner: cachesAuthenticatedOwner,
    );
  }
  buffer
    ..writeln(
      '  static EntityPredicate<${spec.className}> _tombstonePredicate(',
    )
    ..writeln('    TombstoneVisibility visibility,')
    ..writeln('  ) => switch (visibility) {')
    ..writeln(
      '    TombstoneVisibility.exclude => '
      '${_fieldReference(spec, spec.deletedAtField!)}.isNull,',
    )
    ..writeln(
      '    TombstoneVisibility.include => '
      'EntityPredicate<${spec.className}>.all(),',
    )
    ..writeln(
      '    TombstoneVisibility.only => '
      '${_fieldReference(spec, spec.deletedAtField!)}.isNotNull,',
    )
    ..writeln('  };');
  if (spec.hasArchivableCapability) {
    buffer
      ..writeln(
        '  static EntityPredicate<${spec.className}> _archivePredicate(',
      )
      ..writeln('    ArchiveVisibility visibility,')
      ..writeln('  ) => switch (visibility) {')
      ..writeln(
        '    ArchiveVisibility.exclude => '
        '${_fieldReference(spec, spec.archivedAtField!)}.isNull,',
      )
      ..writeln(
        '    ArchiveVisibility.include => '
        'EntityPredicate<${spec.className}>.all(),',
      )
      ..writeln(
        '    ArchiveVisibility.only => '
        '${_fieldReference(spec, spec.archivedAtField!)}.isNotNull,',
      )
      ..writeln('  };');
  }
  buffer.writeln('  void dispose() => _queries.dispose();');
  buffer
    ..writeln('}')
    ..writeln();
  if (spec.canCollaborate) {
    _emitCollaborationApi(buffer, spec);
  }
}

void _emitCreateOrGetMethods(
  StringBuffer buffer,
  EntitySpec spec, {
  required bool cachesAuthenticatedOwner,
}) {
  if (spec.cardinality != Cardinality.bounded) return;
  final createParameterNames = {
    for (final field in spec.createParameters) field.name,
  };
  for (final index in spec.indexes.where(
    (candidate) =>
        candidate.unique &&
        candidate.condition == null &&
        candidate.fieldNames.every(
          (name) =>
              !spec.fields.singleWhere((field) => field.name == name).nullable,
        ),
  )) {
    final lookupFields = index.ownerScoped
        ? index.fieldNames
              .where((name) => name != spec.ownerField.name)
              .toList(growable: false)
        : index.fieldNames;
    if (lookupFields.isEmpty ||
        lookupFields.any((name) => !createParameterNames.contains(name)) ||
        (index.ownerScoped && !cachesAuthenticatedOwner)) {
      continue;
    }
    final suffixFields = lookupFields.isEmpty ? index.fieldNames : lookupFields;
    final suffix = suffixFields.map(_upperCamelIdentifier).join('And');
    final lookupMethod = 'by$suffix${index.ownerScoped ? 'ForOwner' : ''}';
    final methodName =
        'createOrGetBy$suffix${index.ownerScoped ? 'ForOwner' : ''}';
    buffer
      ..writeln()
      ..writeln('  Future<${spec.className}> $methodName({')
      ..writeln('    LocalId<${spec.className}>? id,');
    _emitCreateParameters(buffer, spec.createParameters);
    buffer
      ..writeln('  }) async {')
      ..writeln('    final existing = $lookupMethod(');
    if (index.ownerScoped) {
      buffer.writeln('      ${spec.ownerField.name}: _ownerId,');
    }
    for (final fieldName in lookupFields) {
      buffer.writeln('      $fieldName: $fieldName,');
    }
    buffer
      ..writeln('    );')
      ..writeln('    if (existing != null) return existing;')
      ..writeln('    return create(')
      ..writeln('      id: id,');
    for (final field in spec.createParameters) {
      buffer.writeln('      ${field.name}: ${field.name},');
    }
    buffer
      ..writeln('    );')
      ..writeln('  }');
  }
}

void _emitCreateParameters(
  StringBuffer buffer,
  List<FieldSpec> createParameters,
) {
  for (final field in createParameters) {
    final required = !field.nullable && field.defaultValue == null;
    final defaultValue = field.defaultValue == null
        ? ''
        : ' = ${_domainDefaultLiteral(field)}';
    buffer.writeln(
      '    ${required ? 'required ' : ''}${field.dartType} ${field.name}$defaultValue,',
    );
  }
}

void _emitUnboundedOrderOperations(StringBuffer buffer, EntitySpec spec) {
  final idType = spec.idField.dartType;
  buffer
    ..writeln('  Future<void> prepend($idType id) =>')
    ..writeln('      _engine.moveInGeneratedOrder(')
    ..writeln('        entityId: id.value,')
    ..writeln('        placement: OrderedPlacement.first,')
    ..writeln('      );')
    ..writeln()
    ..writeln('  Future<void> append($idType id) =>')
    ..writeln('      _engine.moveInGeneratedOrder(')
    ..writeln('        entityId: id.value,')
    ..writeln('        placement: OrderedPlacement.last,')
    ..writeln('      );')
    ..writeln()
    ..writeln('  Future<void> moveBefore($idType id, $idType neighborId) =>')
    ..writeln('      _engine.moveInGeneratedOrder(')
    ..writeln('        entityId: id.value,')
    ..writeln('        placement: OrderedPlacement.before,')
    ..writeln('        anchorId: neighborId.value,')
    ..writeln('      );')
    ..writeln()
    ..writeln('  Future<void> moveAfter($idType id, $idType neighborId) =>')
    ..writeln('      _engine.moveInGeneratedOrder(')
    ..writeln('        entityId: id.value,')
    ..writeln('        placement: OrderedPlacement.after,')
    ..writeln('        anchorId: neighborId.value,')
    ..writeln('      );');
}

void _emitBoundedOrderOperations(StringBuffer buffer, EntitySpec spec) {
  final entity = spec.className;
  final idType = spec.idField.dartType;
  final canonicalScope = spec.hasRootOrderScope
      ? ''
      : ' && entity.generatedAccess.generatedOrderAccess!'
            '.generatedOrderScopeKey == target!.generatedAccess'
            '.generatedOrderAccess!.generatedOrderScopeKey';
  buffer
    ..writeln('  List<$entity> _canonicalOrderedItems($idType id) {')
    ..writeln('    final target = _engine.byRawId(id.value);')
    ..writeln(
      '    if (target == null || '
      '!target.generatedAccess.generatedOrderAccess!.generatedIsOrderMember) {',
    )
    ..writeln('      _validateOrderedMembers(-1);')
    ..writeln('    }')
    ..writeln(
      '    final items = _engine.all.where((entity) => '
      'entity.generatedAccess.generatedOrderAccess!.generatedIsOrderMember'
      '$canonicalScope).toList(growable: false);',
    )
    ..writeln('    items.sort(canonicalOrder.compare);')
    ..writeln('    return items;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> reorder(Iterable<$idType> entityIds) {')
    ..writeln('    final ids = entityIds.toList(growable: false);')
    ..writeln('    if (ids.isEmpty) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entity',")
    ..writeln("        field: 'order',")
    ..writeln(
      "        message: 'Exact reorder requires one complete non-empty canonical scope.',",
    )
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    if (ids.toSet().length != ids.length) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entity',")
    ..writeln("        field: 'order',")
    ..writeln("        message: 'Exact reorder identities must be unique.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final items = _canonicalOrderedItems(ids.first);')
    ..writeln(
      '    final canonicalIds = items.map((entity) => entity.id).toList();',
    )
    ..writeln('    if (canonicalIds.length != ids.length ||')
    ..writeln('        !canonicalIds.toSet().containsAll(ids)) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entity',")
    ..writeln("        field: 'order',")
    ..writeln(
      "        message: 'Exact reorder identities must match the complete active canonical scope.',",
    )
    ..writeln('      );')
    ..writeln('    }')
    ..writeln(
      '    if (_sameOrderedIds(canonicalIds, ids)) return Future.value();',
    )
    ..writeln('    return _recordExactOrder(items, ids);')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  bool _sameOrderedIds(List<$idType> left, List<$idType> right) {',
    )
    ..writeln('    for (var index = 0; index < left.length; index++) {')
    ..writeln('      if (left[index] != right[index]) return false;')
    ..writeln('    }')
    ..writeln('    return true;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> _recordExactOrder(')
    ..writeln('    List<$entity> items,')
    ..writeln('    List<$idType> ids,')
    ..writeln('  ) {')
    ..writeln(
      '    final ranks = GeneratedOrderRanks.allocate(count: ids.length)!;',
    )
    ..writeln('    final byId = <$idType, $entity>{')
    ..writeln('      for (final entity in items) entity.id: entity,')
    ..writeln('    };')
    ..writeln('    final changes = <GeneratedOrderStateChange<$entity>>[];')
    ..writeln('    try {')
    ..writeln('      for (final (index, id) in ids.indexed) {')
    ..writeln('        final entity = byId[id]!;')
    ..writeln(
      '        final change = entity.generatedAccess.generatedOrderAccess!',
    )
    ..writeln('            .prepareGeneratedOrderRank(ranks[index]);')
    ..writeln('        if (change != null) changes.add(change);')
    ..writeln('      }')
    ..writeln('    } catch (_) {')
    ..writeln('      for (final change in changes.reversed) {')
    ..writeln('        change.rollbackIfCurrent();')
    ..writeln('      }')
    ..writeln('      rethrow;')
    ..writeln('    }')
    ..writeln('    final target = byId[ids.first]!;')
    ..writeln('    return target.generatedAccess.generatedOrderAccess!')
    ..writeln('        .recordGeneratedExactOrder(')
    ..writeln('          changes: changes,')
    ..writeln('          command: ReorderOrderedCommand(')
    ..writeln('            orderedIds: ids,')
    ..writeln('            scopeBaseVersion: _engine.orderScopeVersionFor(')
    ..writeln('              target.generatedAccess.generatedOrderAccess!')
    ..writeln('                  .generatedOrderScopeKey,')
    ..writeln('            ),')
    ..writeln('          ),')
    ..writeln('        );')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> prepend($idType id) =>')
    ..writeln('      _moveInCanonicalOrder(')
    ..writeln('        id,')
    ..writeln('        placement: OrderedPlacement.first,')
    ..writeln('        beforeId: _firstOtherId(id),')
    ..writeln('      );')
    ..writeln()
    ..writeln('  Future<void> append($idType id) =>')
    ..writeln('      _moveInCanonicalOrder(')
    ..writeln('        id,')
    ..writeln('        placement: OrderedPlacement.last,')
    ..writeln('        afterId: _lastOtherId(id),')
    ..writeln('      );')
    ..writeln()
    ..writeln('  Future<void> moveBefore($idType id, $idType neighborId) {')
    ..writeln('    if (id == neighborId) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entity',")
    ..writeln("        field: 'order',")
    ..writeln("        message: 'An entity cannot be its own neighbor.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final items = _canonicalOrderedItems(id);')
    ..writeln('    final ids = items.map((entity) => entity.id).toList();')
    ..writeln('    final targetIndex = ids.indexOf(id);')
    ..writeln('    final neighborIndex = ids.indexOf(neighborId);')
    ..writeln(
      '    _validateOrderedMembers(targetIndex, neighborIndex: neighborIndex);',
    )
    ..writeln(
      '    if (targetIndex + 1 == neighborIndex) return Future.value();',
    )
    ..writeln('    ids.removeAt(targetIndex);')
    ..writeln('    final insertion = ids.indexOf(neighborId);')
    ..writeln('    final afterId = insertion == 0 ? null : ids[insertion - 1];')
    ..writeln(
      '    return _moveInCanonicalOrder(id, afterId: afterId, '
      'beforeId: neighborId, placement: OrderedPlacement.before, '
      'anchorId: neighborId);',
    )
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> moveAfter($idType id, $idType neighborId) {')
    ..writeln('    if (id == neighborId) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entity',")
    ..writeln("        field: 'order',")
    ..writeln("        message: 'An entity cannot be its own neighbor.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final items = _canonicalOrderedItems(id);')
    ..writeln('    final ids = items.map((entity) => entity.id).toList();')
    ..writeln('    final targetIndex = ids.indexOf(id);')
    ..writeln('    final neighborIndex = ids.indexOf(neighborId);')
    ..writeln(
      '    _validateOrderedMembers(targetIndex, neighborIndex: neighborIndex);',
    )
    ..writeln(
      '    if (neighborIndex + 1 == targetIndex) return Future.value();',
    )
    ..writeln('    ids.removeAt(targetIndex);')
    ..writeln('    final insertion = ids.indexOf(neighborId) + 1;')
    ..writeln(
      '    final beforeId = insertion == ids.length ? null : ids[insertion];',
    )
    ..writeln(
      '    return _moveInCanonicalOrder(id, afterId: neighborId, '
      'beforeId: beforeId, placement: OrderedPlacement.after, '
      'anchorId: neighborId);',
    )
    ..writeln('  }')
    ..writeln()
    ..writeln('  $idType? _firstOtherId($idType id) {')
    ..writeln('    final items = _canonicalOrderedItems(id);')
    ..writeln(
      '    final targetIndex = items.indexWhere((item) => item.id == id);',
    )
    ..writeln('    _validateOrderedMembers(targetIndex);')
    ..writeln('    if (targetIndex == 0) return null;')
    ..writeln('    return items.first.id;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  $idType? _lastOtherId($idType id) {')
    ..writeln('    final items = _canonicalOrderedItems(id);')
    ..writeln(
      '    final targetIndex = items.indexWhere((item) => item.id == id);',
    )
    ..writeln('    _validateOrderedMembers(targetIndex);')
    ..writeln('    if (targetIndex == items.length - 1) return null;')
    ..writeln('    return items.last.id;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  void _validateOrderedMembers(')
    ..writeln('    int targetIndex, {')
    ..writeln('    int? neighborIndex,')
    ..writeln('  }) {')
    ..writeln('    if (targetIndex >= 0 && (neighborIndex ?? 0) >= 0) return;')
    ..writeln('    throw const EntityValidationException(')
    ..writeln("      entityType: '$entity',")
    ..writeln("      field: 'order',")
    ..writeln(
      "      message: 'Ordered movement requires active canonical members.',",
    )
    ..writeln('    );')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> _moveInCanonicalOrder(')
    ..writeln('    $idType id, {')
    ..writeln('    required OrderedPlacement placement,')
    ..writeln('    $idType? anchorId,')
    ..writeln('    $idType? afterId,')
    ..writeln('    $idType? beforeId,')
    ..writeln('  }) async {')
    ..writeln('    if (afterId == null && beforeId == null) return;')
    ..writeln('    final items = _canonicalOrderedItems(id);')
    ..writeln('    final byId = <$idType, $entity>{')
    ..writeln('      for (final entity in items) entity.id: entity,')
    ..writeln('    };')
    ..writeln('    final target = byId[id];')
    ..writeln('    final after = afterId == null ? null : byId[afterId];')
    ..writeln('    final before = beforeId == null ? null : byId[beforeId];')
    ..writeln('    if (target == null ||')
    ..writeln('        (afterId != null && after == null) ||')
    ..writeln('        (beforeId != null && before == null)) {')
    ..writeln('      _validateOrderedMembers(-1);')
    ..writeln('    }')
    ..writeln('    final rank = GeneratedOrderRanks.between(')
    ..writeln(
      '      after: after?.generatedAccess.generatedOrderAccess!'
      '.generatedOrderRank,',
    )
    ..writeln(
      '      before: before?.generatedAccess.generatedOrderAccess!'
      '.generatedOrderRank,',
    )
    ..writeln('    );')
    ..writeln('    if (rank == null) {')
    ..writeln('      final ids = items.map((entity) => entity.id).toList();')
    ..writeln('      ids.remove(id);')
    ..writeln('      final insertion = switch (placement) {')
    ..writeln('        OrderedPlacement.first => 0,')
    ..writeln('        OrderedPlacement.last => ids.length,')
    ..writeln('        OrderedPlacement.before => ids.indexOf(anchorId!),')
    ..writeln('        OrderedPlacement.after => ids.indexOf(anchorId!) + 1,')
    ..writeln('      };')
    ..writeln('      ids.insert(insertion, id);')
    ..writeln('      await _recordExactOrder(items, ids);')
    ..writeln('      return;')
    ..writeln('    }')
    ..writeln(
      '    await target!.generatedAccess.generatedOrderAccess!'
      '.recordGeneratedOrderMove(',
    )
    ..writeln('      rank: rank,')
    ..writeln('      command: MoveOrderedCommand(')
    ..writeln('        placement: placement,')
    ..writeln('        anchorId: anchorId,')
    ..writeln(
      '        scopeBaseVersion: _engine.orderScopeVersionFor('
      'target.generatedAccess.generatedOrderAccess!.generatedOrderScopeKey),',
    )
    ..writeln('      ),')
    ..writeln('    );')
    ..writeln('  }');
}

void _emitOrderMove(StringBuffer buffer, EntitySpec spec) {
  final field = spec.orderRankField!;
  final updatePrincipals = spec.security.grants
      .where((grant) => grant.operation == RlsOperation.update)
      .map((grant) => grant.principal);
  buffer
    ..writeln('  @override')
    ..writeln(
      '  GeneratedOrderStateChange<${spec.className}>? '
      'prepareGeneratedOrderRank(OrderRank rank) {',
    );
  _emitDeletedMutationGuard(buffer, spec, fieldName: 'order');
  buffer
    ..writeln('    final oldRank = _${field.name}Store.value;')
    ..writeln('    if (oldRank == rank) return null;')
    ..writeln('    _mutationSink.validateMutationAuthorization(')
    ..writeln('      entity: this,')
    ..writeln('      operation: RlsOperation.update,')
    ..writeln('      principals: ${_principalListLiteral(updatePrincipals)},')
    ..writeln('    );')
    ..writeln('    final previousRevision = _localRevision;')
    ..writeln('    final mutationRevision = ++_localRevision;')
    ..writeln('    runInAction(() => _${field.name}Store.value = rank);')
    ..writeln(
      '    final localPatch = ${_fieldReference(spec, field)}.patch(rank);',
    )
    ..writeln('    return GeneratedOrderStateChange(')
    ..writeln('      entity: this,')
    ..writeln('      scopeKey: generatedOrderScopeKey,')
    ..writeln('      patch: localPatch,')
    ..writeln('      rollbackIfCurrent: () {')
    ..writeln('        if (_localRevision != mutationRevision) return;')
    ..writeln('        _localRevision = previousRevision;')
    ..writeln('        _${field.name}Store.value = oldRank;')
    ..writeln('      },')
    ..writeln(
      '      bindLocalCommit: (commit) => _generatedLocalCommit = commit,',
    )
    ..writeln('    );')
    ..writeln('  }')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Future<void> recordGeneratedOrderMove({')
    ..writeln('    required OrderRank rank,')
    ..writeln('    required MoveOrderedCommand<${spec.className}> command,')
    ..writeln('  }) {');
  _emitDeletedMutationGuard(buffer, spec, fieldName: 'order');
  buffer
    ..writeln('    final change = prepareGeneratedOrderRank(rank);')
    ..writeln('    if (change == null) return Future.value();')
    ..writeln(
      '    final commit = _mutationSink.recordEntityCommand<${spec.className}>(',
    )
    ..writeln('      entity: this,')
    ..writeln('      command: command,')
    ..writeln('      localPatch: change.patch,')
    ..writeln('      persistsEntityState: true,')
    ..writeln('      occurredAt: _clock.nowUtc(),')
    ..writeln('      rollbackIfCurrent: change.rollbackIfCurrent,')
    ..writeln('    );')
    ..writeln('    change.bindLocalCommit(commit);')
    ..writeln('    return _generatedMutationCompletion(commit);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Future<void> recordGeneratedExactOrder({')
    ..writeln(
      '    required List<GeneratedOrderStateChange<${spec.className}>> changes,',
    )
    ..writeln('    required ReorderOrderedCommand<${spec.className}> command,')
    ..writeln('  }) {')
    ..writeln('    if (changes.isEmpty) return Future.value();')
    ..writeln('    try {')
    ..writeln('      final commit = _mutationSink.recordEntityScopeCommand(')
    ..writeln('        entity: this,')
    ..writeln('        command: command,')
    ..writeln('        stateChanges: changes,')
    ..writeln('        scopeKey: generatedOrderScopeKey,')
    ..writeln('        occurredAt: _clock.nowUtc(),')
    ..writeln('      );')
    ..writeln('      for (final change in changes) {')
    ..writeln('        change.bindLocalCommit(commit);')
    ..writeln('      }')
    ..writeln('      return _generatedMutationCompletion(commit);')
    ..writeln('    } catch (_) {')
    ..writeln('      for (final change in changes.reversed) {')
    ..writeln('        change.rollbackIfCurrent();')
    ..writeln('      }')
    ..writeln('      rethrow;')
    ..writeln('    }')
    ..writeln('  }');
}

void _emitUniqueLookups(StringBuffer buffer, EntitySpec spec) {
  for (final index in spec.indexes.where(
    (candidate) =>
        candidate.unique &&
        candidate.fieldNames.every(
          (name) =>
              !spec.fields.singleWhere((field) => field.name == name).nullable,
        ),
  )) {
    final lookupFields = index.ownerScoped
        ? index.fieldNames
              .where((name) => name != spec.ownerField.name)
              .toList(growable: false)
        : index.fieldNames;
    final suffixFields = lookupFields.isEmpty ? index.fieldNames : lookupFields;
    final suffix = suffixFields.map(_upperCamelIdentifier).join('And');
    final methodName = 'by$suffix${index.ownerScoped ? 'ForOwner' : ''}';
    final fields = [
      for (final name in index.fieldNames)
        spec.fields.singleWhere((candidate) => candidate.name == name),
    ];
    final keyType = index.unordered
        ? 'UnorderedEntityPairKey<${fields.first.dartType}>'
        : '({${fields.map((field) => '${field.dartType} ${field.name}').join(', ')}})';
    final entityKey = index.unordered
        ? 'UnorderedEntityPairKey(entity.${fields.first.name}, '
              'entity.${fields.last.name})'
        : '(${fields.map((field) => '${field.name}: entity.${field.name}').join(', ')})';
    final argumentKey = index.unordered
        ? 'UnorderedEntityPairKey(${fields.first.name}, ${fields.last.name})'
        : '(${fields.map((field) => '${field.name}: ${field.name}').join(', ')})';
    final conditions = <String>[];
    if (index.activeOnly) {
      conditions.add('entity.${EntityConventions.deletedAtFieldName} == null');
    }
    if (index.condition case final condition?) {
      final field = spec.fields.singleWhere(
        (candidate) => candidate.name == condition.field,
      );
      final matches = condition.values
          .map(
            (value) =>
                'entity.${condition.field} == '
                '${_domainIndexConditionLiteral(field, value)}',
          )
          .join(' || ');
      conditions.add('($matches)');
    }

    buffer
      ..writeln(
        '  late final Computed<Map<$keyType, ${spec.className}>> '
        '_${methodName}Index = Computed(() => {',
      )
      ..writeln('    for (final entity in _engine.all)')
      ..writeln(
        conditions.isEmpty
            ? '      $entityKey: entity,'
            : '      if (${conditions.join(' && ')}) $entityKey: entity,',
      )
      ..writeln('  });')
      ..writeln('  ${spec.className}? $methodName({');
    for (final field in fields) {
      buffer.writeln('    required ${field.dartType} ${field.name},');
    }
    buffer.writeln('  }) => _${methodName}Index.value[$argumentKey];');
  }
}

String _upperCamelIdentifier(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';

String _domainIndexConditionLiteral(FieldSpec field, Object value) {
  if (!field.isEnum) return _dartLiteral(value);
  final index = field.enumWireValues.indexOf(value as String);
  if (index < 0) {
    throw StateError('Unknown `${field.name}` index-condition value `$value`.');
  }
  return '${field.dartType}.${field.enumValues[index]}';
}

void _emitCollaborationApi(StringBuffer buffer, EntitySpec spec) {
  final ownerField = spec.ownerField;
  buffer
    ..writeln(
      'extension ${spec.className}CollaborationApi on ${spec.className} {',
    )
    ..writeln('  Future<void> setCollaborator(')
    ..writeln('    ${ownerField.dartType} collaboratorId, {')
    ..writeln('    required bool active,')
    ..writeln('  }) =>')
    ..writeln('    generatedAccess.recordGeneratedCommand(')
    ..writeln(
      '      SetCollaboratorCommand<${spec.className}, '
      '${_entityIdArgument(ownerField.dartType)}>(',
    )
    ..writeln('        collaboratorId: collaboratorId, active: active,')
    ..writeln('      ),')
    ..writeln('    );')
    ..writeln('}')
    ..writeln();
}

void _emitRecordCollaborationApi(StringBuffer buffer, EntitySpec spec) {
  final ownerField = spec.ownerField;
  buffer
    ..writeln('  @override')
    ..writeln('  Future<void> setCollaborator(')
    ..writeln('    ${ownerField.dartType} collaboratorId, {')
    ..writeln('    required bool active,')
    ..writeln('  }) =>')
    ..writeln('    recordGeneratedCommand(')
    ..writeln(
      '      SetCollaboratorCommand<${spec.className}, '
      '${_entityIdArgument(ownerField.dartType)}>(',
    )
    ..writeln('        collaboratorId: collaboratorId, active: active,')
    ..writeln('      ),')
    ..writeln('    );');
}

String _decodeExpression(FieldSpec field, String source) {
  final nullableSuffix = field.nullable ? '?' : '!';
  final nonNullableType = field.dartType.replaceAll('?', '');
  if (field.isScalarValue) {
    final wire = _decodeScalarWireExpression(field, source);
    final decode = '$nonNullableType.fromScalar($wire)';
    return field.nullable ? '$source == null ? null : $decode' : decode;
  }
  if (field.isEnum) {
    final decode = [
      'switch ($source) {',
      for (final (index, value) in field.enumValues.indexed)
        "'${field.enumWireValues[index]}' => $nonNullableType.$value,",
      "_ => throw const FormatException('Invalid enum `${field.name}`.'),",
      '}',
    ].join(' ');
    return field.nullable ? '$source == null ? null : $decode' : decode;
  }
  if (field.name == EntityConventions.serverVersionFieldName) {
    return 'parseServerVersion($source)';
  }
  if (nonNullableType == 'OrderRank') {
    return field.nullable
        ? '$source == null ? null : OrderRank.parse($source as String)'
        : 'OrderRank.parse(($source)! as String)';
  }
  if (field.dartType.replaceAll('?', '').startsWith('LocalId<')) {
    final entityType = _entityIdArgument(field.dartType);
    return field.nullable
        ? '$source == null ? null : parseLocalId<$entityType>($source as String)'
        : 'parseLocalId<$entityType>(($source)! as String)';
  }
  return switch (nonNullableType) {
    'String' => field.nullable ? '$source as String?' : '($source)! as String',
    'bool' => field.nullable ? '$source as bool?' : '($source)! as bool',
    'int' =>
      field.nullable
          ? '$source == null ? null : ${_checkedIntegerExpression(field, source)}'
          : _checkedIntegerExpression(field, source),
    'double' =>
      field.nullable
          ? '$source == null ? null : ${_checkedRealExpression(field, source)}'
          : _checkedRealExpression(field, source),
    'LocalDate' =>
      field.nullable
          ? '$source == null ? null : LocalDate.parse($source as String)'
          : 'LocalDate.parse(($source)! as String)',
    'DateTime' =>
      field.nullable
          ? '$source == null ? null : DateTime.parse($source as String).toUtc()'
          : 'DateTime.parse(($source)! as String).toUtc()',
    _ => '($source)$nullableSuffix as $nonNullableType',
  };
}

String _checkedIntegerExpression(FieldSpec field, String source) =>
    "switch ($source) { final num value when value.isFinite && "
    "value == value.truncate() => value.toInt(), _ => throw const "
    "FormatException('Invalid integer `${field.name}`.'), }";

String _checkedRealExpression(FieldSpec field, String source) =>
    "switch ($source) { final num value when value.isFinite => "
    "value.toDouble(), _ => throw const "
    "FormatException('Invalid real `${field.name}`.'), }";

String _encodeExpression(FieldSpec field, String source) {
  final nonNullableType = field.dartType.replaceAll('?', '');
  if (field.isScalarValue) {
    return field.nullable ? '$source?.toScalar()' : '$source.toScalar()';
  }
  if (field.name == EntityConventions.serverVersionFieldName) {
    return '$source.value';
  }
  if (nonNullableType == 'OrderRank') {
    return field.nullable ? '$source?.value' : '$source.value';
  }
  if (field.isEnum) {
    final encoded = [
      'switch ($source) {',
      for (final (index, value) in field.enumValues.indexed)
        "$nonNullableType.$value => '${field.enumWireValues[index]}',",
      '}',
    ].join(' ');
    return field.nullable ? '$source == null ? null : $encoded' : encoded;
  }
  if (field.dartType.replaceAll('?', '').startsWith('LocalId<')) {
    return field.nullable ? '$source?.value' : '$source.value';
  }
  if (nonNullableType == 'LocalDate') {
    return field.nullable ? '$source?.value' : '$source.value';
  }
  if (nonNullableType == 'DateTime') {
    return field.nullable
        ? '$source?.toUtc().toIso8601String()'
        : '$source.toUtc().toIso8601String()';
  }
  return source;
}

String _decodeScalarWireExpression(FieldSpec field, String source) {
  return switch (field.scalarValue!.wireDartType) {
    'String' => '($source)! as String',
    'bool' => '($source)! as bool',
    'int' => _checkedIntegerExpression(field, source),
    'double' => _checkedRealExpression(field, source),
    _ => throw StateError(
      'Unsupported scalar value wire type for `${field.name}`.',
    ),
  };
}

String _entityIdArgument(String dartType) {
  final match = RegExp(r'LocalId<(.+)>').firstMatch(dartType);
  return match?.group(1) ?? 'Object';
}

String _fieldKind(FieldSpec field) => switch (field.sqlType) {
  SqlType.text => 'text',
  SqlType.uuid => 'uuid',
  SqlType.boolean => 'boolean',
  SqlType.integer => 'integer',
  SqlType.real => 'real',
  SqlType.date => 'date',
  SqlType.timestampWithTimeZone => 'timestamp',
};

String _queryFieldClass(FieldSpec field) {
  if (field.isScalarValue) {
    return field.nullable ? 'NullableEntityField' : 'EqualityEntityField';
  }
  if (field.isEnum) {
    return field.nullable ? 'NullableEntityField' : 'EqualityEntityField';
  }
  final comparable = switch (field.sqlType) {
    SqlType.text => !field.dartType.startsWith('LocalId<'),
    SqlType.integer ||
    SqlType.real ||
    SqlType.date ||
    SqlType.timestampWithTimeZone => true,
    SqlType.uuid || SqlType.boolean => false,
  };
  return switch ((field.nullable, comparable)) {
    (true, true) => 'NullableComparableEntityField',
    (true, false) => 'NullableEntityField',
    (false, true) => 'ComparableEntityField',
    (false, false) => 'EqualityEntityField',
  };
}

String _conflict(ConflictStrategy conflict) => switch (conflict) {
  ConflictStrategy.localWins => 'localWins',
  ConflictStrategy.serverWins => 'serverWins',
};

String _dartLiteral(Object? value) => switch (value) {
  null => 'null',
  final String value => "'${value.replaceAll("'", "\\'")}'",
  final bool value => value.toString(),
  final num value => value.toString(),
  final List<Object?> value => 'const [${value.map(_dartLiteral).join(', ')}]',
  _ => throw StateError('Unsupported Dart default: $value'),
};

String _domainDefaultLiteral(FieldSpec field) => domainDefaultLiteral(field);

String _sqliteDefaultLiteral(FieldSpec field) =>
    _dartLiteral(field.persistedDefaultValue);

String _sqlStringLiteral(String value) => "'${value.replaceAll("'", "''")}'";

String _generatedEntityImport(
  String inputImport, {
  bool privateOutput = false,
}) {
  final separator = inputImport.indexOf('/', 'package:'.length);
  final prefix = inputImport.substring(0, separator + 1);
  final relative = inputImport.substring(separator + 1);
  final generated = relative.replaceFirst(RegExp(r'\.dart$'), '.entity.g.dart');
  return privateOutput
      ? '${prefix}src/generated/entities/$generated'
      : '$prefix$generated';
}
