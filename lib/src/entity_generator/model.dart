import 'package:nodus/nodus.dart';

enum SqlType { text, uuid, boolean, integer, real, date, timestampWithTimeZone }

final class EntitySpec {
  const EntitySpec({
    required this.className,
    required this.packageName,
    required this.inputImport,
    required this.tableName,
    required this.ownership,
    required this.cardinality,
    required this.authenticatedReadSync,
    this.hasOrderedCapability = false,
    this.hasArchivableCapability = false,
    this.hasActivityTrackedCapability = false,
    this.activitySubjectClassName,
    this.activityActorClassName,
    this.isComponent = false,
    required this.fields,
    required this.security,
    required this.commands,
    this.actions = const [],
    this.persistedVariants = const [],
    this.exclusiveFieldGroups = const [],
    this.compoundIndexes = const [],
    this.typeImports = const [],
    this.protocolVersion = 1,
    this.setAccessorOverride,
    this.relationshipAccessOperations = const [],
    this.orderScopeFieldNames,
    this.syncModeOverride,
    this.syncTargetOverride,
  });

  final String className;
  final String packageName;
  final String inputImport;
  final String tableName;
  final String? setAccessorOverride;
  final Ownership ownership;
  final Cardinality cardinality;
  final AuthenticatedReadSync authenticatedReadSync;
  final bool hasOrderedCapability;
  final bool hasArchivableCapability;
  final bool hasActivityTrackedCapability;
  final String? activitySubjectClassName;
  final String? activityActorClassName;
  final bool isComponent;
  final int protocolVersion;
  final List<FieldSpec> fields;
  final SecuritySpec security;
  final List<CommandSpec> commands;
  final List<ActionSpec> actions;
  final List<PersistedVariantSpec> persistedVariants;
  final List<ExclusiveFieldGroupSpec> exclusiveFieldGroups;
  final List<CompoundIndexSpec> compoundIndexes;
  final List<String> typeImports;
  final List<RlsOperation> relationshipAccessOperations;
  final List<String>? orderScopeFieldNames;
  final SyncMode? syncModeOverride;
  final SyncTargetSpec? syncTargetOverride;

  String get sourceBaseName =>
      inputImport.split('/').last.replaceFirst(RegExp(r'\.dart$'), '');

  String get setAccessor => setAccessorOverride ?? lowerCamelCase(tableName);

  FieldSpec get idField => fields.singleWhere((field) => field.isId);

  FieldSpec get serverVersionField => fields.singleWhere(
    (field) =>
        field.serverGenerated &&
        field.name == EntityConventions.serverVersionFieldName,
  );

  FieldSpec? get orderRankField => hasOrderedCapability
      ? fields.singleWhere(
          (field) => field.name == EntityConventions.orderRankFieldName,
        )
      : null;

  FieldSpec get ownerField => switch (ownership) {
    Ownership.separate => fields.singleWhere(
      (field) => field.name == EntityConventions.ownerFieldName,
    ),
    Ownership.identity => idField,
  };

  String get ownerClassName => localIdTypeArgument(ownerField.dartType);

  bool get canCreate =>
      security.grants.any((grant) => grant.operation == RlsOperation.insert);

  bool get canCreatePublicly => canCreate && !isActivityEntry;

  bool get isActivityEntry => activitySubjectClassName != null;

  bool get canDelete =>
      security.grants.any((grant) => grant.operation == RlsOperation.delete);

  bool get canUpdate =>
      security.grants.any((grant) => grant.operation == RlsOperation.update);

  bool get canCollaborate =>
      security.collaboration?.lifecycle == CollaborationLifecycle.direct;

  bool get canCommand => canCollaborate || hasOrderedCapability;

  bool get hasStateMutations => canUpdate || canDelete;

  bool get syncAuthenticatedReads => switch (authenticatedReadSync) {
    AuthenticatedReadSync.inferred => cardinality == Cardinality.bounded,
    AuthenticatedReadSync.onDemand => false,
    AuthenticatedReadSync.graph => true,
  };

  bool isCommandOnly(FieldSpec field) =>
      commands.any((command) => command.targetField == field.name);

  PersistedVariantSpec? persistedVariantForField(FieldSpec field) =>
      persistedVariants
          .where((variant) => variant.storageFields.contains(field))
          .firstOrNull;

  bool isPersistedVariantField(FieldSpec field) =>
      persistedVariantForField(field) != null;

  bool isActionTarget(FieldSpec field) =>
      actions.any((action) => action.targetFields.contains(field.name));

  ActionSpec? get orderScopeTransferAction {
    if (!hasOrderedCapability) return null;
    final scopeNames = orderScopeFields.map((field) => field.name).toSet();
    return actions
        .where((action) => action.targetFields.any(scopeNames.contains))
        .firstOrNull;
  }

  bool isOrderScopeTransferAction(ActionSpec action) =>
      identical(action, orderScopeTransferAction);

  bool isOrderScopeTransferTarget(FieldSpec field) =>
      orderScopeTransferAction?.targetFields.contains(field.name) ?? false;

  List<FieldSpec> get orderScopeTransferFields {
    final action = orderScopeTransferAction;
    if (action == null) return const [];
    return [
      for (final name in action.targetFields)
        fields.singleWhere((field) => field.name == name),
    ];
  }

  List<ActionSpec> get ordinaryActions => [
    for (final action in actions)
      if (!isOrderScopeTransferAction(action)) action,
  ];

  bool isFixedActionTarget(FieldSpec field) => actions.any(
    (action) => action.assignments.any(
      (assignment) => assignment.fieldName == field.name,
    ),
  );

  /// Declared actions whose atomic shape includes at least one field that
  /// cannot be changed through the ordinary mutation draft.
  List<ActionSpec> get guardedActions => [
    for (final action in ordinaryActions)
      if (action.targetFields.any((name) {
        final field = fields.singleWhere((field) => field.name == name);
        return !isDraftEditable(field);
      }))
        action,
  ];

  /// The action targets that activate semantic action-shape enforcement.
  List<String> guardedActionFields(ActionSpec action) => [
    for (final name in action.targetFields)
      if (!isDraftEditable(fields.singleWhere((field) => field.name == name)))
        name,
  ];

  /// Ordinary scalar fields edited by the generated mutation draft.
  ///
  /// Domain transitions, fixed action assignments, and relationships stay
  /// behind their generated actions. Ordinary action parameters remain
  /// editable so a compound operation does not require a duplicate catch-all
  /// action for normal form editing.
  /// An explicit `editable: false` keeps a creation-time fact immutable without
  /// requiring a no-op semantic action merely to communicate that policy.
  List<FieldSpec> get draftEditableFields {
    if (!canUpdate || isActivityEntry) return const [];
    return fields.where(isDraftEditable).toList(growable: false);
  }

  List<PersistedVariantSpec> get draftEditableVariants =>
      canUpdate && !isActivityEntry ? persistedVariants : const [];

  bool isDraftEditable(FieldSpec field) {
    if (!canUpdate || isActivityEntry) return false;
    if (isPersistedVariantField(field)) return false;
    if (field.draftEditableOverride == false) return false;
    return !field.isId &&
        !field.generatedOnly &&
        field != ownerField &&
        field.inCreatePayload &&
        field.reference == null &&
        field.transitions.isEmpty &&
        !isCommandOnly(field) &&
        !isFixedActionTarget(field) &&
        field.name != EntityConventions.deletedAtFieldName &&
        field.name != EntityConventions.archivedAtFieldName &&
        field.name != EntityConventions.orderRankFieldName;
  }

  /// Persisted fields initialized by generated set creation.
  ///
  /// Keeping this derivation on the entity specification lets graph-level
  /// relationship constructors expose the exact same creation contract as the
  /// generated set without duplicating generator policy.
  List<FieldSpec> get createFields => fields
      .where(
        (field) =>
            !field.isId && field.inCreatePayload && !isCommandOnly(field),
      )
      .toList(growable: false);

  /// Caller-supplied parameters of generated creation APIs.
  List<FieldSpec> get createParameters => createFields
      .where(
        (field) =>
            !field.generatedOnly &&
            field != ownerField &&
            field.transitions.isEmpty &&
            !hasInferredActionInitialValue(field),
      )
      .toList(growable: false);

  bool hasInferredActionInitialValue(FieldSpec field) =>
      isFixedActionTarget(field) &&
      (field.nullable || field.defaultValue != null);

  /// Whether a client state patch may contain this field.
  ///
  /// Publicly mutable fields expose a setter. Action targets are read-only in
  /// the domain API and can only be patched by their generated atomic method.
  bool isPatchable(FieldSpec field) =>
      !isCommandOnly(field) &&
      !isOrderScopeTransferTarget(field) &&
      (isDraftEditable(field) ||
          (canUpdate && isPersistedVariantField(field)) ||
          isActionTarget(field));

  /// The canonical ordering scope derived once for every generated adapter.
  ///
  /// Relationship ordering belongs to its source endpoint. Ordinary entities
  /// are owner-scoped, while identity-owned entities use one complete root.
  List<FieldSpec> get orderScopeFields {
    if (!hasOrderedCapability) return const [];
    final explicit = orderScopeFieldNames;
    if (explicit != null) {
      return [
        for (final name in explicit)
          fields.singleWhere((field) => field.name == name),
      ];
    }
    final inferred =
        activeRelationship?.ownerReference ??
        (ownership == Ownership.separate ? ownerField : null);
    return [?inferred];
  }

  List<(FieldSpec, Object?)> get orderMembershipConditions {
    if (!hasOrderedCapability) return const [];
    final relationship = activeRelationship;
    return [
      (deletedAtField!, null),
      if (relationship != null) (relationship.activeField, true),
    ];
  }

  bool get hasRootOrderScope =>
      hasOrderedCapability && orderScopeFields.isEmpty;

  bool get usesEncodedOrderScopeKey =>
      orderScopeFields.length > 1 ||
      (orderScopeFields.length == 1 && orderScopeFields.first.nullable);

  List<String> _orderedCompoundScope(
    CompoundIndexSpec index, {
    required bool includeAccountOwnerScope,
  }) {
    if (!hasOrderedCapability || !index.keyset) return const [];
    return [
      for (final scope in orderScopeFields)
        if (!(!includeAccountOwnerScope && scope == ownerField) &&
            !(index.scope == IndexScope.owner && scope == ownerField) &&
            !index.fields.contains(scope.name))
          scope.name,
    ];
  }

  List<IndexSpec> _declaredIndexes({required bool includeAccountOwnerScope}) =>
      [
        for (final field in fields)
          if (field.indexed)
            IndexSpec(
              fieldNames: [
                if (field.indexScope == IndexScope.owner) ownerField.name,
                field.name,
              ],
              unique: field.unique,
              ownerScoped: field.indexScope == IndexScope.owner,
              unordered: false,
              activeOnly: false,
            ),
        for (final index in compoundIndexes)
          IndexSpec(
            fieldNames: [
              if (index.scope == IndexScope.owner &&
                  (!hasOrderedCapability ||
                      !index.keyset ||
                      includeAccountOwnerScope))
                ownerField.name,
              ..._orderedCompoundScope(
                index,
                includeAccountOwnerScope: includeAccountOwnerScope,
              ),
              ...index.fields,
              if (index.keyset) idField.name,
            ],
            unique: index.unique,
            ownerScoped: index.scope == IndexScope.owner,
            unordered: index.unordered,
            activeOnly: index.unordered && canDelete,
            condition: index.condition,
          ),
      ];

  IndexSpec? _orderIndex({required bool includeAccountOwnerScope}) {
    final rank = orderRankField;
    if (rank == null) return null;
    return IndexSpec(
      fieldNames: [
        for (final scope in orderScopeFields)
          if (includeAccountOwnerScope || scope != ownerField) scope.name,
        for (final (field, _) in orderMembershipConditions) field.name,
        rank.name,
        idField.name,
      ],
      unique: false,
      ownerScoped: false,
      unordered: false,
      activeOnly: false,
    );
  }

  /// Indexes for the account-scoped local projection.
  ///
  /// The authenticated owner is invariant for one local graph and is omitted;
  /// relationship sources remain physical scope prefixes.
  List<IndexSpec> get indexes => [
    ?_orderIndex(includeAccountOwnerScope: false),
    ..._declaredIndexes(includeAccountOwnerScope: false),
  ];

  /// Indexes for the multi-tenant PostgreSQL projection.
  List<IndexSpec> get postgresIndexes => [
    ?_orderIndex(includeAccountOwnerScope: true),
    ..._declaredIndexes(includeAccountOwnerScope: true),
  ];

  List<String> indexColumns(IndexSpec index) => [
    for (final name in index.fieldNames)
      fields.singleWhere((field) => field.name == name).columnName,
  ];

  String indexName(IndexSpec index) => generatedIndexName(
    tableName: tableName,
    columns: [
      if (index.unordered) 'unordered',
      ...indexColumns(index),
      if (index.activeOnly) 'active',
      if (index.condition case final condition?) ...[
        'where',
        fields.singleWhere((field) => field.name == condition.field).columnName,
        _generatedIndexConditionToken(condition.values),
      ],
    ],
  );

  List<FieldSpec> get participantFields =>
      fields.where((field) => field.isParticipant).toList(growable: false);

  List<FieldSpec> get accessReferenceFields =>
      fields.where((field) => field.isAccessReference).toList(growable: false);

  /// Reference authorization clauses, AND-composed across groups and
  /// OR-composed within an inferred exactly-one alternative group.
  List<List<FieldSpec>> get accessReferenceGroups {
    final accessFields = accessReferenceFields;
    final alternativeByField = <String, List<FieldSpec>>{};
    for (final group in exclusiveFieldGroups.where(
      (candidate) => !candidate.allowNone,
    )) {
      final alternatives = [
        for (final name in group.fields)
          ...accessFields.where((field) => field.name == name),
      ];
      if (alternatives.length != group.fields.length) continue;
      for (final field in alternatives) {
        alternativeByField[field.name] = alternatives;
      }
    }
    final result = <List<FieldSpec>>[];
    final emittedFields = <String>{};
    for (final field in accessFields) {
      if (!emittedFields.add(field.name)) continue;
      final alternatives = alternativeByField[field.name];
      if (alternatives == null) {
        result.add([field]);
      } else {
        result.add(alternatives);
        emittedFields.addAll(alternatives.map((candidate) => candidate.name));
      }
    }
    return result;
  }

  List<FieldSpec> get accessTargetFields =>
      fields.where((field) => field.isAccessTarget).toList(growable: false);

  FieldSpec? get activeField => fields
      .where(
        (field) =>
            field.name == 'active' &&
            field.sqlType == SqlType.boolean &&
            !field.nullable,
      )
      .firstOrNull;

  FieldSpec? get deletedAtField => fields
      .where(
        (field) =>
            field.name == EntityConventions.deletedAtFieldName &&
            field.sqlType == SqlType.timestampWithTimeZone,
      )
      .firstOrNull;

  FieldSpec? get archivedAtField => !hasArchivableCapability
      ? null
      : fields.singleWhere((field) => field.name == 'archivedAt');

  EntitySpec withGraphAccess(
    Map<String, Set<RlsOperation>> relationshipOperations,
  ) {
    final normalized = <RlsOperation>{
      ...relationshipAccessOperations,
      ...?relationshipOperations[className],
    }.toList()..sort((left, right) => left.index.compareTo(right.index));
    final resolvedFields = [
      for (final field in fields)
        if (field.reference case final reference?)
          field.withReference(
            reference.withTargetRelationshipAccess(
              relationshipOperations[reference.targetClassName] ?? const {},
            ),
          )
        else
          field,
    ];
    return EntitySpec(
      className: className,
      packageName: packageName,
      inputImport: inputImport,
      tableName: tableName,
      ownership: ownership,
      cardinality: cardinality,
      authenticatedReadSync: authenticatedReadSync,
      hasOrderedCapability: hasOrderedCapability,
      hasArchivableCapability: hasArchivableCapability,
      hasActivityTrackedCapability: hasActivityTrackedCapability,
      activitySubjectClassName: activitySubjectClassName,
      activityActorClassName: activityActorClassName,
      isComponent: isComponent,
      fields: resolvedFields,
      security: security,
      commands: commands,
      actions: actions,
      persistedVariants: [
        for (final variant in persistedVariants)
          PersistedVariantSpec(
            name: variant.name,
            dartType: variant.dartType,
            nullable: variant.nullable,
            cases: [
              for (final variantCase in variant.cases)
                PersistedVariantCaseSpec(
                  className: variantCase.className,
                  fields: [
                    for (final field in variantCase.fields)
                      resolvedFields.singleWhere(
                        (candidate) => candidate.name == field.name,
                      ),
                  ],
                  constructorParameters: variantCase.constructorParameters,
                ),
            ],
          ),
      ],
      exclusiveFieldGroups: exclusiveFieldGroups,
      compoundIndexes: compoundIndexes,
      typeImports: typeImports,
      protocolVersion: protocolVersion,
      setAccessorOverride: setAccessorOverride,
      relationshipAccessOperations: List.unmodifiable(normalized),
      orderScopeFieldNames: orderScopeFieldNames,
      syncModeOverride: syncModeOverride,
      syncTargetOverride: syncTargetOverride,
    );
  }

  List<FieldSpec> get ownershipReferenceFields =>
      fields.where((field) => field.isOwnerReference).toList(growable: false);

  bool get hasOwnershipReference => ownershipReferenceFields.isNotEmpty;

  OrderedCollectionSpec? get legacyOrderedCollection {
    final orderField = fields
        .where(
          (field) =>
              field.name == 'sortOrder' &&
              field.dartType == 'int' &&
              !field.nullable &&
              field.defaultValue == 0 &&
              field.minValue == 0,
        )
        .firstOrNull;
    if (orderField == null) return null;
    final moveAction = actions
        .where(
          (action) =>
              action.methodName == 'moveTo' &&
              action.parameters.length == 1 &&
              action.parameters.single.name == orderField.name &&
              action.parameters.single.dartType == orderField.dartType &&
              action.parameters.single.named &&
              action.assignments.isEmpty,
        )
        .firstOrNull;
    if (moveAction == null) return null;
    return OrderedCollectionSpec(
      orderField: orderField,
      moveAction: moveAction,
    );
  }

  ActiveRelationshipSpec? get activeRelationship {
    if (!canCreate || !canUpdate || ownershipReferenceFields.length != 1) {
      return null;
    }
    final references = fields
        .where((field) => field.reference != null && !field.nullable)
        .toList(growable: false);
    if (references.length != 2) return null;
    final ownerReference = ownershipReferenceFields.single;
    if (!references.contains(ownerReference)) return null;
    final targetReference = references.singleWhere(
      (field) => field != ownerReference,
    );
    final referenceNames = references.map((field) => field.name).toSet();
    final hasUniquePair = compoundIndexes.any(
      (index) =>
          index.unique &&
          index.scope != IndexScope.owner &&
          index.condition == null &&
          index.fields.toSet().length == referenceNames.length &&
          index.fields.toSet().containsAll(referenceNames),
    );
    if (!hasUniquePair) return null;
    final activeField = fields
        .where(
          (field) =>
              field.name == 'active' &&
              field.dartType == 'bool' &&
              !field.nullable &&
              field.defaultValue == true,
        )
        .firstOrNull;
    if (activeField == null) return null;

    bool isBooleanAction(String methodName, bool value) => actions.any(
      (action) =>
          action.methodName == methodName &&
          action.parameters.isEmpty &&
          action.assignments.length == 1 &&
          action.assignments.single.fieldName == activeField.name &&
          action.assignments.single.kind == ActionValueKind.literal &&
          action.assignments.single.literal == value,
    );

    if (!isBooleanAction('activate', true) ||
        !isBooleanAction('deactivate', false)) {
      return null;
    }
    final structuralFields = {
      idField.name,
      ownerField.name,
      ownerReference.name,
      targetReference.name,
      activeField.name,
      EntityConventions.deletedAtFieldName,
    };
    final hasRequiredRelationshipPayload = fields.any(
      (field) =>
          field.inCreatePayload &&
          !structuralFields.contains(field.name) &&
          !field.nullable &&
          field.defaultValue == null,
    );
    if (hasRequiredRelationshipPayload) return null;
    return ActiveRelationshipSpec(
      ownerReference: ownerReference,
      targetReference: targetReference,
      activeField: activeField,
    );
  }

  WorkflowMembershipSpec? get workflowMembership {
    final target = fields
        .where(
          (field) => field.reference?.targetCollaboration?.isWorkflow ?? false,
        )
        .where(
          (field) =>
              field.reference!.targetCollaboration!.membershipTable ==
              tableName,
        )
        .firstOrNull;
    if (target == null) return null;
    final collaboration = target.reference!.targetCollaboration!;
    return WorkflowMembershipSpec(
      targetReference: target,
      participant: fields.singleWhere(
        (field) =>
            field.isParticipant &&
            field.columnName == collaboration.userForeignKey,
      ),
      status: fields.singleWhere(
        (field) => field.columnName == collaboration.statusField,
      ),
    );
  }
}

final class OrderedCollectionSpec {
  const OrderedCollectionSpec({
    required this.orderField,
    required this.moveAction,
  });

  final FieldSpec orderField;
  final ActionSpec moveAction;
}

final class ActiveRelationshipSpec {
  const ActiveRelationshipSpec({
    required this.ownerReference,
    required this.targetReference,
    required this.activeField,
  });

  final FieldSpec ownerReference;
  final FieldSpec targetReference;
  final FieldSpec activeField;
}

final class WorkflowMembershipSpec {
  const WorkflowMembershipSpec({
    required this.targetReference,
    required this.participant,
    required this.status,
  });

  final FieldSpec targetReference;
  final FieldSpec participant;
  final FieldSpec status;

  String get targetClassName => targetReference.reference!.targetClassName;
  String get targetTableName => targetReference.reference!.targetTableName;
}

final class ExclusiveFieldGroupSpec {
  const ExclusiveFieldGroupSpec({
    required this.fields,
    required this.allowNone,
  });

  final List<String> fields;
  final bool allowNone;
}

final class PersistedVariantSpec {
  const PersistedVariantSpec({
    required this.name,
    required this.dartType,
    required this.nullable,
    required this.cases,
  });

  final String name;
  final String dartType;
  final bool nullable;
  final List<PersistedVariantCaseSpec> cases;

  String get capitalizedName => '${name[0].toUpperCase()}${name.substring(1)}';

  List<FieldSpec> get storageFields => [
    for (final variantCase in cases) ...variantCase.fields,
  ];

  PersistedVariantCaseSpec? get emptyCase =>
      cases.where((variantCase) => variantCase.fields.isEmpty).firstOrNull;
}

final class PersistedVariantCaseSpec {
  const PersistedVariantCaseSpec({
    required this.className,
    required this.fields,
    required this.constructorParameters,
  });

  final String className;
  final List<FieldSpec> fields;
  final List<PersistedVariantParameterSpec> constructorParameters;

  FieldSpec? get presenceField => fields.where((field) {
    final parameter = constructorParameters
        .where((candidate) => candidate.fieldName == field.name)
        .firstOrNull;
    return parameter != null &&
        parameter.required &&
        field.persistedVariantComponentNullable == false;
  }).firstOrNull;
}

final class PersistedVariantParameterSpec {
  const PersistedVariantParameterSpec({
    required this.fieldName,
    required this.named,
    required this.required,
  });

  final String fieldName;
  final bool named;
  final bool required;
}

final class CompoundIndexSpec {
  const CompoundIndexSpec({
    required this.fields,
    required this.unique,
    required this.scope,
    this.keyset = false,
    this.condition,
    this.unordered = false,
  });

  final List<String> fields;
  final bool unique;
  final IndexScope scope;
  final bool keyset;
  final IndexConditionSpec? condition;
  final bool unordered;
}

final class IndexSpec {
  const IndexSpec({
    required this.fieldNames,
    required this.unique,
    this.ownerScoped = false,
    this.condition,
    this.unordered = false,
    this.activeOnly = false,
  });

  final List<String> fieldNames;
  final bool unique;
  final bool ownerScoped;
  final IndexConditionSpec? condition;
  final bool unordered;
  final bool activeOnly;
}

final class IndexConditionSpec {
  const IndexConditionSpec({required this.field, required this.values});

  final String field;
  final List<Object> values;
}

/// Derives one stable SQLite/PostgreSQL index identifier.
///
/// PostgreSQL limits identifiers to 63 ASCII bytes. Persisted identifiers are
/// validated as lowercase ASCII snake_case, so character length is byte length.
/// Long names retain a readable prefix and a deterministic 64-bit FNV-1a suffix
/// instead of relying on PostgreSQL's backend-only truncation.
String generatedIndexName({
  required String tableName,
  required List<String> columns,
}) {
  final source = '${tableName}_${columns.join('_')}_idx';
  const maxLength = 63;
  if (source.length <= maxLength) return source;

  final fingerprint = _fnv1a64(source.codeUnits);
  final suffix = '_${fingerprint}_idx';
  return '${source.substring(0, maxLength - suffix.length)}$suffix';
}

String _generatedIndexConditionToken(List<Object> values) {
  final bytes = <int>[];
  for (final value in values) {
    final source = '${value.runtimeType}:$value;';
    bytes.addAll(source.codeUnits);
  }
  return 'values_${_fnv1a64(bytes)}';
}

String _fnv1a64(Iterable<int> bytes) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in bytes) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Emits the domain-level Dart literal for a generated field default.
///
/// Set creation and relationship-bound creation share this single policy so
/// their signatures cannot drift when new persisted scalar kinds are added.
String domainDefaultLiteral(FieldSpec field) {
  if (field.defaultValue == null) return 'null';
  if (field.isScalarValue) {
    return 'const ${field.dartType.replaceAll('?', '')}.fromScalar('
        '${dartLiteral(field.defaultValue)})';
  }
  if (field.isEnum) {
    return '${field.dartType.replaceAll('?', '')}.${field.defaultValue}';
  }
  if (field.dartType.replaceAll('?', '') == 'OrderRank') {
    return 'OrderRank.parse(${dartLiteral(field.defaultValue)})';
  }
  return dartLiteral(field.defaultValue);
}

String dartLiteral(Object? value) => switch (value) {
  null => 'null',
  final String value => "'${value.replaceAll("'", "\\'")}'",
  final bool value => value.toString(),
  final num value => value.toString(),
  final List<Object?> value => 'const [${value.map(dartLiteral).join(', ')}]',
  _ => throw StateError('Unsupported Dart default: $value'),
};

/// Concise public type name for a create-capable inverse relationship.
///
/// An inverse such as `goalMembers` on `Goal` becomes `GoalMembers`, while an
/// unrelated inverse such as `subgoals` remains `GoalSubgoals`.
String generatedInverseCreationTypeName(FieldSpec field) {
  final reference = field.reference!;
  final targetName = reference.targetClassName;
  final targetPrefix = lowerCamelCase(targetName);
  final inverseName = reference.inverseName;
  final suffixStart = targetPrefix.length;
  final repeatsTarget =
      inverseName.startsWith(targetPrefix) &&
      inverseName.length > suffixStart &&
      _isAsciiUpperCase(inverseName.codeUnitAt(suffixStart));
  final suffix = repeatsTarget
      ? inverseName.substring(suffixStart)
      : pascalCase(snakeCase(inverseName));
  return '$targetName$suffix';
}

bool _isAsciiUpperCase(int codeUnit) => codeUnit >= 65 && codeUnit <= 90;

final class EntityGraphSpec {
  EntityGraphSpec({
    required this.className,
    required this.packageName,
    required this.inputImport,
    required this.schemaVersion,
    required List<EntitySpec> entities,
    this.defaultSyncTarget,
    List<SyncBindingSpec>? syncBindings,
    this.outputBaseName = 'nodus.g',
    this.emitsSyncTargetEnum = false,
  }) : entities = List.unmodifiable(entities),
       syncBindings = List.unmodifiable(
         syncBindings ??
             [
               for (final entity in entities)
                 SyncBindingSpec(entity: entity, mode: SyncMode.localOnly),
             ],
       ),
       relationships = List.unmodifiable(
         _resolveActiveRelationshipCollections(entities),
       ),
       activityTrackings = List.unmodifiable(
         resolveActivityTrackings(entities),
       );

  final String className;
  final String packageName;
  final String inputImport;
  final int schemaVersion;
  final List<EntitySpec> entities;
  final SyncTargetSpec? defaultSyncTarget;
  final List<SyncBindingSpec> syncBindings;
  final String outputBaseName;
  final bool emitsSyncTargetEnum;
  final List<ActiveRelationshipCollectionSpec> relationships;
  final List<ActivityTrackingSpec> activityTrackings;

  List<SyncTargetSpec> get syncTargets {
    final targets = <String, SyncTargetSpec>{};
    for (final binding in syncBindings) {
      final target = binding.target;
      if (target != null) targets[target.stableIdentity] = target;
    }
    final result = targets.values.toList(growable: false)
      ..sort((left, right) => left.wireName.compareTo(right.wireName));
    return List.unmodifiable(result);
  }

  List<SyncTargetSpec> get pullSyncTargets =>
      _syncTargetsForModes({SyncMode.replicated, SyncMode.imported});

  List<SyncTargetSpec> get pushSyncTargets =>
      _syncTargetsForModes({SyncMode.replicated, SyncMode.exported});

  List<SyncTargetSpec> _syncTargetsForModes(Set<SyncMode> modes) {
    final targets = <String, SyncTargetSpec>{};
    for (final binding in syncBindings.where(
      (binding) => modes.contains(binding.mode),
    )) {
      final target = binding.target!;
      targets[target.stableIdentity] = target;
    }
    final result = targets.values.toList(growable: false)
      ..sort((left, right) => left.wireName.compareTo(right.wireName));
    return List.unmodifiable(result);
  }

  /// Returns the exact compiler graph owned by one remote target.
  ///
  /// Generation has already rejected remote constraints that cross this
  /// boundary, so target emitters never need unrelated local or remote
  /// entities to reconstruct their schema or protocol.
  EntityGraphSpec syncSubgraphFor(SyncTargetSpec target) {
    final selectedBindings = [
      for (final binding in syncBindings)
        if (binding.target?.stableIdentity == target.stableIdentity) binding,
    ];
    if (selectedBindings.isEmpty) {
      throw ArgumentError.value(
        target.wireName,
        'target',
        'The target is not used by this entity graph.',
      );
    }
    final selectedTypes = {
      for (final binding in selectedBindings) binding.entity.className,
    };
    return EntityGraphSpec(
      className: className,
      packageName: packageName,
      inputImport: inputImport,
      schemaVersion: schemaVersion,
      entities: [
        for (final entity in entities)
          if (selectedTypes.contains(entity.className)) entity,
      ],
      defaultSyncTarget: target,
      syncBindings: selectedBindings,
      outputBaseName: outputBaseName,
      emitsSyncTargetEnum: emitsSyncTargetEnum,
    );
  }

  ActiveRelationshipCollectionSpec? relationshipFor(EntitySpec entity) =>
      relationships
          .where(
            (relationship) =>
                relationship.linkEntity.className == entity.className,
          )
          .firstOrNull;

  String get accountClassName {
    final separatelyOwned = entities.where(
      (entity) => entity.ownership == Ownership.separate,
    );
    return separatelyOwned.isEmpty
        ? entities.first.ownerClassName
        : separatelyOwned.first.ownerClassName;
  }

  String get sourceBaseName =>
      inputImport.split('/').last.replaceFirst(RegExp(r'\.dart$'), '');
}

final class ActivityTrackingSpec {
  const ActivityTrackingSpec({required this.source, required this.entry});

  final EntitySpec source;
  final EntitySpec entry;
}

List<ActivityTrackingSpec> resolveActivityTrackings(List<EntitySpec> entities) {
  final entriesBySubject = <String, List<EntitySpec>>{};
  for (final entry in entities.where((entity) => entity.isActivityEntry)) {
    (entriesBySubject[entry.activitySubjectClassName!] ??= []).add(entry);
  }
  return [
    for (final source in entities.where(
      (entity) => entity.hasActivityTrackedCapability,
    ))
      for (final entry in entriesBySubject[source.className] ?? const [])
        ActivityTrackingSpec(source: source, entry: entry),
  ];
}

final class SyncTargetSpec {
  const SyncTargetSpec({
    required this.enumType,
    required this.enumImport,
    required this.valueName,
    required this.wireName,
  });

  final String enumType;
  final String enumImport;
  final String valueName;
  final String wireName;

  String get typeIdentity => '$enumImport#$enumType';
  String get stableIdentity => '$typeIdentity.$valueName';
  String get expression => '$enumType.$valueName';
}

final class SyncBindingSpec {
  const SyncBindingSpec({
    required this.entity,
    required this.mode,
    this.target,
  });

  final EntitySpec entity;
  final SyncMode mode;
  final SyncTargetSpec? target;
}

List<SyncBindingSpec> resolveEntitySyncBindings({
  required List<EntitySpec> entities,
  required SyncTargetSpec? defaultTarget,
}) {
  final targetTypes = <String>{
    if (defaultTarget != null) defaultTarget.typeIdentity,
    for (final entity in entities)
      if (entity.syncTargetOverride case final target?) target.typeIdentity,
  };
  if (targetTypes.length > 1) {
    throw StateError(
      'One entity graph must use exactly one sync-target enum type. Found: '
      '${targetTypes.toList()..sort()}.',
    );
  }
  final targetsByWire = <String, String>{};
  for (final target in [
    ?defaultTarget,
    for (final entity in entities) ?entity.syncTargetOverride,
  ]) {
    final previous = targetsByWire.putIfAbsent(
      target.wireName,
      () => target.stableIdentity,
    );
    if (previous != target.stableIdentity) {
      throw StateError(
        'Sync-target enum values `$previous` and `${target.stableIdentity}` '
        'resolve to the same durable wire name `${target.wireName}`.',
      );
    }
  }

  final bindings = <SyncBindingSpec>[];
  for (final entity in entities) {
    final explicitMode = entity.syncModeOverride;
    final explicitTarget = entity.syncTargetOverride;
    if (explicitMode == SyncMode.localOnly && explicitTarget != null) {
      throw StateError(
        '${entity.className} cannot select a sync target in localOnly mode.',
      );
    }
    final inferredTarget = explicitMode == SyncMode.localOnly
        ? null
        : explicitTarget ?? defaultTarget;
    final mode =
        explicitMode ??
        (inferredTarget == null ? SyncMode.localOnly : SyncMode.replicated);
    if (mode != SyncMode.localOnly && inferredTarget == null) {
      throw StateError(
        '${entity.className} uses ${mode.name} sync but no target can be '
        'inferred. Select an entity target or a graph default.',
      );
    }
    if (mode == SyncMode.imported &&
        (entity.canCreate ||
            entity.canUpdate ||
            entity.canDelete ||
            entity.actions.isNotEmpty ||
            entity.commands.isNotEmpty ||
            entity.hasOrderedCapability)) {
      throw StateError(
        '${entity.className} is imported and must be a read-only projection. '
        'Remove local mutation grants, actions, commands, and Ordered.',
      );
    }
    bindings.add(
      SyncBindingSpec(entity: entity, mode: mode, target: inferredTarget),
    );
  }
  final bindingByEntity = {
    for (final binding in bindings) binding.entity.className: binding,
  };
  for (final source in bindings) {
    for (final field in source.entity.fields) {
      final reference = field.reference;
      if (reference == null) continue;
      final target = bindingByEntity[reference.targetClassName];
      if (target == null) continue;
      final sourceTarget = source.target;
      final targetTarget = target.target;
      final crossesRemoteTargets =
          sourceTarget != null &&
          targetTarget != null &&
          sourceTarget.stableIdentity != targetTarget.stableIdentity;
      final remoteDependsOnLocalOnly =
          sourceTarget != null && targetTarget == null;
      final localAccessDependsOnRemote =
          sourceTarget == null &&
          targetTarget != null &&
          (field.isAccessReference || field.isAccessTarget);
      if (crossesRemoteTargets ||
          remoteDependsOnLocalOnly ||
          localAccessDependsOnRemote) {
        throw StateError(
          '${source.entity.className}.${field.name} cannot constrain '
          '${target.entity.className} across '
          '`${sourceTarget?.wireName ?? 'localOnly'}` and '
          '`${targetTarget?.wireName ?? 'localOnly'}`. Cross-target '
          'relationships require an '
          'explicit transport contract, which is not yet declared.',
        );
      }
    }
  }
  return List.unmodifiable(bindings);
}

List<ActiveRelationshipCollectionSpec> _resolveActiveRelationshipCollections(
  List<EntitySpec> entities,
) {
  final byClassName = {for (final entity in entities) entity.className: entity};
  return [
    for (final linkEntity in entities)
      if (linkEntity.activeRelationship case final relationship?)
        ActiveRelationshipCollectionSpec(
          linkEntity: linkEntity,
          sourceEntity:
              byClassName[relationship
                  .ownerReference
                  .reference!
                  .targetClassName]!,
          targetEntity:
              byClassName[relationship
                  .targetReference
                  .reference!
                  .targetClassName]!,
          relationship: relationship,
          cardinalityResolution: linkEntity.cardinality == Cardinality.bounded
              ? RelationshipCardinalityResolution.boundedByLinkEntity
              : byClassName[relationship
                            .targetReference
                            .reference!
                            .targetClassName]!
                        .cardinality ==
                    Cardinality.bounded
              ? RelationshipCardinalityResolution.boundedByTargetEntity
              : RelationshipCardinalityResolution.unboundedByDefault,
        ),
  ];
}

final class ActiveRelationshipCollectionSpec {
  const ActiveRelationshipCollectionSpec({
    required this.linkEntity,
    required this.sourceEntity,
    required this.targetEntity,
    required this.relationship,
    required this.cardinalityResolution,
  });

  final EntitySpec linkEntity;
  final EntitySpec sourceEntity;
  final EntitySpec targetEntity;
  final ActiveRelationshipSpec relationship;
  final RelationshipCardinalityResolution cardinalityResolution;

  Cardinality get cardinality => cardinalityResolution.cardinality;
}

String localIdTypeArgument(String dartType) {
  final match = RegExp(r'^LocalId<(.+)>$').firstMatch(dartType);
  if (match == null) {
    throw StateError('Expected a nominal LocalId type, got `$dartType`.');
  }
  return match.group(1)!;
}

final class CommandSpec {
  const CommandSpec({
    required this.methodName,
    required this.targetField,
    required this.parameterName,
    required this.parameterType,
    required this.value,
  });

  final String methodName;
  final String targetField;
  final String? parameterName;
  final String? parameterType;
  final SyncCommandValue value;
}

final class ActionSpec {
  const ActionSpec({
    required this.methodName,
    required this.parameters,
    required this.assignments,
  });

  final String methodName;
  final List<ActionParameterSpec> parameters;
  final List<ActionAssignmentSpec> assignments;

  List<String> get targetFields => [
    ...parameters.map((parameter) => parameter.fieldName),
    ...assignments.map((assignment) => assignment.fieldName),
  ];
}

final class ActionParameterSpec {
  const ActionParameterSpec({
    required this.name,
    required this.dartType,
    required this.named,
  });

  final String name;
  final String dartType;
  final bool named;
  String get fieldName => name;
}

final class ActionAssignmentSpec {
  const ActionAssignmentSpec({
    required this.fieldName,
    required this.kind,
    this.literal,
  });

  final String fieldName;
  final ActionValueKind kind;

  /// Canonical Dart value: primitives retain their value and enums store the
  /// declaring constant name.
  final Object? literal;
}

final class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.columnName,
    required this.dartType,
    required this.sqlType,
    required this.nullable,
    required this.isFinal,
    required this.defaultValue,
    required this.conflict,
    required this.minLength,
    required this.maxLength,
    this.allowWhitespace = false,
    required this.indexed,
    required this.unique,
    this.authority = FieldAuthority.client,
    this.indexScope = IndexScope.field,
    this.minValue,
    this.maxValue,
    this.allowedValues = const [],
    this.greaterThan,
    this.greaterThanOrEqual,
    this.requires,
    this.notEqualTo,
    this.enumValues = const [],
    this.reference,
    this.sinceProtocolVersion = 1,
    this.renamedFrom,
    this.isParticipant = false,
    this.isAccessReference = false,
    this.isAccessTarget = false,
    this.isComposition = false,
    this.accessTargetOperations = const [],
    this.accessTargetClassName,
    this.accessTargetInputImport,
    this.accessTargetTableName,
    this.accessTargetThroughColumnName,
    this.accessTargetActiveStates = const [],
    this.accessTargetActiveStateEnumType,
    this.accessTargetActiveStateEnumImport,
    this.isOwnerReference = false,
    this.transitions = const [],
    this.updatePrincipals = const [],
    this.enumTypeImport,
    this.scalarValue,
    this.generatedOnly = false,
    this.draftEditableOverride,
    this.persistedVariantName,
    this.persistedVariantComponentNullable,
  });

  final String name;
  final String columnName;
  final String dartType;
  final SqlType sqlType;
  final bool nullable;
  final bool isFinal;
  final Object? defaultValue;
  final ConflictStrategy conflict;
  final FieldAuthority authority;
  final int? minLength;
  final int? maxLength;
  final bool allowWhitespace;
  final int? minValue;
  final int? maxValue;
  final List<String> allowedValues;
  final String? greaterThan;
  final String? greaterThanOrEqual;
  final String? requires;
  final String? notEqualTo;
  final bool indexed;
  final bool unique;
  final IndexScope indexScope;
  final List<String> enumValues;
  final ReferenceSpec? reference;
  final int sinceProtocolVersion;
  final String? renamedFrom;
  final bool isParticipant;
  final bool isAccessReference;
  final bool isAccessTarget;
  final bool isComposition;
  final List<RlsOperation> accessTargetOperations;
  final String? accessTargetClassName;
  final String? accessTargetInputImport;
  final String? accessTargetTableName;

  /// Column on the referenced bridge containing the ultimate target identity.
  /// Null means this field directly references the access target.
  final String? accessTargetThroughColumnName;
  final List<String> accessTargetActiveStates;
  final String? accessTargetActiveStateEnumType;
  final String? accessTargetActiveStateEnumImport;
  final bool isOwnerReference;
  final List<ValueTransitionSpec> transitions;
  final List<RlsPrincipal> updatePrincipals;
  final String? enumTypeImport;
  final ScalarValueSpec? scalarValue;
  final bool generatedOnly;
  final bool? draftEditableOverride;
  final String? persistedVariantName;
  final bool? persistedVariantComponentNullable;

  FieldSpec withReference(ReferenceSpec value) => FieldSpec(
    name: name,
    columnName: columnName,
    dartType: dartType,
    sqlType: sqlType,
    nullable: nullable,
    isFinal: isFinal,
    defaultValue: defaultValue,
    conflict: conflict,
    authority: authority,
    minLength: minLength,
    maxLength: maxLength,
    allowWhitespace: allowWhitespace,
    minValue: minValue,
    maxValue: maxValue,
    allowedValues: allowedValues,
    greaterThan: greaterThan,
    greaterThanOrEqual: greaterThanOrEqual,
    requires: requires,
    notEqualTo: notEqualTo,
    indexed: indexed,
    unique: unique,
    indexScope: indexScope,
    enumValues: enumValues,
    reference: value,
    sinceProtocolVersion: sinceProtocolVersion,
    renamedFrom: renamedFrom,
    isParticipant: isParticipant,
    isAccessReference: isAccessReference,
    isAccessTarget: isAccessTarget,
    isComposition: isComposition,
    accessTargetOperations: accessTargetOperations,
    accessTargetClassName: accessTargetClassName,
    accessTargetInputImport: accessTargetInputImport,
    accessTargetTableName: accessTargetTableName,
    accessTargetThroughColumnName: accessTargetThroughColumnName,
    accessTargetActiveStates: accessTargetActiveStates,
    accessTargetActiveStateEnumType: accessTargetActiveStateEnumType,
    accessTargetActiveStateEnumImport: accessTargetActiveStateEnumImport,
    isOwnerReference: isOwnerReference,
    transitions: transitions,
    updatePrincipals: updatePrincipals,
    enumTypeImport: enumTypeImport,
    scalarValue: scalarValue,
    generatedOnly: generatedOnly,
    draftEditableOverride: draftEditableOverride,
    persistedVariantName: persistedVariantName,
    persistedVariantComponentNullable: persistedVariantComponentNullable,
  );

  bool get isServerManaged => authority == FieldAuthority.server;
  bool get isMutable => !isFinal && !serverGenerated && !isServerManaged;
  bool get isScalarValue => scalarValue != null;
  bool get isEnum => enumValues.isNotEmpty;
  List<String> get enumWireValues => [
    for (final value in enumValues) snakeCase(value),
  ];
  Object? get persistedDefaultValue {
    if (isEnum && defaultValue is String) {
      return snakeCase(defaultValue! as String);
    }
    return defaultValue;
  }

  bool get isId => name == EntityConventions.idFieldName;
  String get capitalizedName => '${name[0].toUpperCase()}${name.substring(1)}';
  bool get serverGenerated =>
      (isFinal &&
          !nullable &&
          name == EntityConventions.createdAtFieldName &&
          dartType == 'DateTime') ||
      (isFinal &&
          !nullable &&
          name == EntityConventions.serverVersionFieldName &&
          dartType == 'ServerVersion');
  bool get autoUpdated =>
      isFinal &&
      !nullable &&
      name == EntityConventions.updatedAtFieldName &&
      dartType == 'DateTime';
  bool get inCreatePayload =>
      !serverGenerated && !autoUpdated && !isServerManaged;
}

final class ScalarValueSpec {
  const ScalarValueSpec({
    required this.wireDartType,
    required this.sqlType,
    required this.hasConstConstructor,
  });

  final String wireDartType;
  final SqlType sqlType;
  final bool hasConstConstructor;
}

final class ValueTransitionSpec {
  const ValueTransitionSpec({
    required this.from,
    required this.to,
    this.principals = const [],
  });

  final String from;
  final String to;
  final List<RlsPrincipal> principals;

  String get fromWire => snakeCase(from);
  String get toWire => snakeCase(to);
}

final class ReferenceSpec {
  const ReferenceSpec({
    required this.targetClassName,
    required this.targetInputImport,
    required this.targetTableName,
    required this.accessorName,
    required this.inverseName,
    required this.onDelete,
    required this.targetSelectPrincipals,
    required this.targetOwnerOperations,
    required this.targetOwnerDartType,
    required this.targetOwnerColumnName,
    required this.ownershipSourceFieldName,
    required this.ownershipSourceColumnName,
    required this.ownershipSourceDartType,
    required this.targetCollaboration,
    this.targetRelationshipAccessOperations = const [],
  });

  final String targetClassName;
  final String targetInputImport;
  final String targetTableName;
  final String accessorName;
  final String inverseName;
  final ReferenceDeleteAction onDelete;
  final List<RlsPrincipal> targetSelectPrincipals;
  final List<RlsOperation> targetOwnerOperations;
  final String targetOwnerDartType;
  final String targetOwnerColumnName;
  final String ownershipSourceFieldName;
  final String ownershipSourceColumnName;
  final String ownershipSourceDartType;
  final CollaborationSpec? targetCollaboration;
  final List<RlsOperation> targetRelationshipAccessOperations;

  bool get targetReadableByRelationship =>
      targetRelationshipAccessOperations.contains(RlsOperation.select);

  ReferenceSpec withTargetRelationshipAccess(
    Iterable<RlsOperation> operations,
  ) {
    final normalized = <RlsOperation>{
      ...targetRelationshipAccessOperations,
      ...operations,
    }.toList()..sort((left, right) => left.index.compareTo(right.index));
    return ReferenceSpec(
      targetClassName: targetClassName,
      targetInputImport: targetInputImport,
      targetTableName: targetTableName,
      accessorName: accessorName,
      inverseName: inverseName,
      onDelete: onDelete,
      targetSelectPrincipals: targetSelectPrincipals,
      targetOwnerOperations: targetOwnerOperations,
      targetOwnerDartType: targetOwnerDartType,
      targetOwnerColumnName: targetOwnerColumnName,
      ownershipSourceFieldName: ownershipSourceFieldName,
      ownershipSourceColumnName: ownershipSourceColumnName,
      ownershipSourceDartType: ownershipSourceDartType,
      targetCollaboration: targetCollaboration,
      targetRelationshipAccessOperations: List.unmodifiable(normalized),
    );
  }
}

final class SecuritySpec {
  const SecuritySpec({
    required this.grants,
    required this.collaboration,
    this.referenceAccessGuards = const [],
  });

  final List<GrantSpec> grants;
  final CollaborationSpec? collaboration;
  final List<RlsOperation> referenceAccessGuards;

  bool guardsWithReferenceAccess(RlsOperation operation) =>
      referenceAccessGuards.contains(operation);
}

final class GrantSpec {
  const GrantSpec({required this.operation, required this.principal});

  final RlsOperation operation;
  final RlsPrincipal principal;
}

final class CollaborationSpec {
  const CollaborationSpec({
    required this.lifecycle,
    required this.membershipTable,
    required this.entityForeignKey,
    required this.userForeignKey,
    this.activeField,
    this.statusField,
    this.acceptedValue,
    this.acceptedEnumType,
    this.acceptedEnumImport,
    this.additionalReadableValues = const [],
    this.readableEnumType,
    this.readableEnumImport,
  });

  final CollaborationLifecycle lifecycle;
  final String membershipTable;
  final String entityForeignKey;
  final String userForeignKey;
  final String? activeField;
  final String? statusField;
  final String? acceptedValue;
  final String? acceptedEnumType;
  final String? acceptedEnumImport;
  final List<String> additionalReadableValues;
  final String? readableEnumType;
  final String? readableEnumImport;

  bool get isDirect => lifecycle == CollaborationLifecycle.direct;
  bool get isWorkflow => lifecycle == CollaborationLifecycle.workflow;
  bool get hasAdditionalReadableStates => additionalReadableValues.isNotEmpty;
  List<String> get readableValues {
    final value = acceptedValue;
    return value == null
        ? additionalReadableValues
        : [value, ...additionalReadableValues];
  }
}

String snakeCase(String input) {
  return input
      .replaceAllMapped(
        RegExp('([A-Z]+)([A-Z][a-z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp('([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
}

String pluralSnakeCase(String className) => _pluralize(snakeCase(className));

String lowerCamelCase(String snakeCaseValue) {
  final pascal = pascalCase(snakeCaseValue);
  if (pascal.isEmpty) return '';
  return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
}

String _pluralize(String value) {
  if (RegExp(r'[^aeiou]y$', caseSensitive: false).hasMatch(value)) {
    return '${value.substring(0, value.length - 1)}ies';
  }
  if (RegExp(r'(s|x|z|ch|sh)$', caseSensitive: false).hasMatch(value)) {
    return '${value}es';
  }
  return '${value}s';
}

String pascalCase(String input) => input
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();
