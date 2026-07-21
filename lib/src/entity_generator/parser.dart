import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

const _entityChecker = TypeChecker.typeNamed(Entity, inPackage: 'nodus');
const _persistedChecker = TypeChecker.typeNamed(Persisted, inPackage: 'nodus');
const _indexedChecker = TypeChecker.typeNamed(Indexed, inPackage: 'nodus');
const _referenceChecker = TypeChecker.typeNamed(Reference, inPackage: 'nodus');
const _compositionChecker = TypeChecker.typeNamed(
  Composition,
  inPackage: 'nodus',
);
const _accessParticipantChecker = TypeChecker.typeNamed(
  AccessParticipant,
  inPackage: 'nodus',
);
const _accessReferenceChecker = TypeChecker.typeNamed(
  AccessReference,
  inPackage: 'nodus',
);
const _accessTargetChecker = TypeChecker.typeNamed(
  AccessTarget,
  inPackage: 'nodus',
);
const _ownerReferenceChecker = TypeChecker.typeNamed(
  OwnerReference,
  inPackage: 'nodus',
);
const _syncCommandChecker = TypeChecker.typeNamed(
  SyncCommand,
  inPackage: 'nodus',
);
const _actionChecker = TypeChecker.typeNamed(Action, inPackage: 'nodus');
const _transientChecker = TypeChecker.typeNamed(Transient, inPackage: 'nodus');
const _ownedByChecker = TypeChecker.typeNamed(OwnedBy, inPackage: 'nodus');
const _softDeletableChecker = TypeChecker.typeNamed(
  SoftDeletable,
  inPackage: 'nodus',
);
const _orderedChecker = TypeChecker.fromUrl('package:nodus/nodus.dart#Ordered');
const _componentChecker = TypeChecker.fromUrl(
  'package:nodus/nodus.dart#Component',
);
const _persistedScalarValueChecker = TypeChecker.typeNamed(
  PersistedScalarValue,
  inPackage: 'nodus',
);

bool _isNodusCapability(InterfaceType type, String name) =>
    type.element.name == name &&
    type.element.library.uri.toString() == 'package:nodus/nodus.dart';

Future<EntitySpec?> parseEntity(BuildStep buildStep) async {
  return parseEntityAsset(buildStep, buildStep.inputId);
}

Future<EntitySpec?> parseEntityAsset(
  BuildStep buildStep,
  AssetId assetId,
) async {
  final library = LibraryReader(await buildStep.resolver.libraryFor(assetId));
  final annotated = library.annotatedWith(_entityChecker).toList();
  if (annotated.isEmpty) return null;
  if (annotated.length != 1 || annotated.single.element is! ClassElement) {
    throw InvalidGenerationSourceError(
      'Each entity declaration file must contain exactly one @Entity class.',
      element: annotated.first.element,
    );
  }

  final classElement = annotated.single.element as ClassElement;
  final hasOrderedCapability = classElement.allSupertypes.any(
    _orderedChecker.isExactlyType,
  );
  final hasArchivableCapability = classElement.allSupertypes.any(
    (type) => _isNodusCapability(type, 'Archivable'),
  );
  final hasActivityTrackedCapability = classElement.allSupertypes.any(
    (type) => _isNodusCapability(type, 'ActivityTracked'),
  );
  final activityEntryTypes = classElement.allSupertypes
      .where((type) => _isNodusCapability(type, 'ActivityOf'))
      .toList(growable: false);
  if (activityEntryTypes.length > 1) {
    throw InvalidGenerationSourceError(
      'An entity may implement ActivityOf exactly once.',
      element: classElement,
    );
  }
  final collaborativeTypes = classElement.allSupertypes
      .where((type) => _isNodusCapability(type, 'Collaborative'))
      .toList(growable: false);
  if (collaborativeTypes.length > 1) {
    throw InvalidGenerationSourceError(
      'An entity may implement Collaborative exactly once.',
      element: classElement,
    );
  }
  final isComponent = classElement.allSupertypes.any(
    _componentChecker.isExactlyType,
  );
  final hasActivatableCapability = classElement.allSupertypes.any(
    (type) =>
        type.element.name == 'Activatable' &&
        type.element.library.uri.toString() == 'package:nodus/nodus.dart',
  );
  if (activityEntryTypes.isNotEmpty &&
      (hasActivityTrackedCapability ||
          hasOrderedCapability ||
          hasArchivableCapability ||
          isComponent ||
          hasActivatableCapability ||
          collaborativeTypes.isNotEmpty ||
          classElement.allSupertypes.any(
            (type) => _softDeletableChecker.isExactlyType(type),
          ))) {
    throw InvalidGenerationSourceError(
      'An ActivityOf entry is immutable generated history and cannot compose '
      'lifecycle, ordering, collaboration, component, or tracking '
      'capabilities.',
      element: classElement,
    );
  }
  final unit = await buildStep.resolver.compilationUnitFor(assetId);
  final classNode = unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (node) => node.namePart.typeName.lexeme == classElement.name,
  );
  final initializers = <String, Expression?>{
    for (final declaration
        in classNode.body.members.whereType<FieldDeclaration>())
      for (final variable in declaration.fields.variables)
        variable.name.lexeme: variable.initializer,
  };
  final annotation = annotated.single.annotation;
  final ownedByType = classElement.allSupertypes
      .where((type) => _ownedByChecker.isExactlyType(type))
      .firstOrNull;
  if (ownedByType == null) {
    throw InvalidGenerationSourceError(
      '@Entity classes must implement OwnedBy<Self, Owner> so their nominal '
      'identity and authenticated owner types remain compile-time checked.',
      element: classElement,
    );
  }
  final tableName = annotation.peek('table')?.isNull ?? true
      ? pluralSnakeCase(classElement.name!)
      : annotation.read('table').stringValue;
  _validateSqlIdentifier(tableName, classElement, label: 'table');
  final setAccessor = annotation.peek('setAccessor')?.isNull ?? true
      ? null
      : annotation.read('setAccessor').stringValue;
  _validateSetAccessor(setAccessor ?? lowerCamelCase(tableName), classElement);
  final ownership = _readEnum(annotation.read('ownership'), Ownership.values);
  final cardinality = _readEnum(
    annotation.read('cardinality'),
    Cardinality.values,
  );
  final authenticatedReadSync = _readEnum(
    annotation.read('authenticatedReadSync'),
    AuthenticatedReadSync.values,
  );
  final syncReader = annotation.peek('sync');
  final syncMode = syncReader == null || syncReader.isNull
      ? null
      : _readEnum(syncReader, SyncMode.values);
  final syncTarget = _parseSyncTarget(
    annotation.peek('syncTarget'),
    classElement,
    label: 'Entity.syncTarget',
  );
  final fields = <FieldSpec>[];
  final typeImports = <String>{};
  List<FieldSpec> infrastructureTail = const [];
  final arguments = ownedByType.typeArguments;
  if (arguments.length != 2 ||
      arguments.first.getDisplayString() != classElement.name) {
    throw InvalidGenerationSourceError(
      'OwnedBy must use the declaring entity as its exact Self type.',
      element: classElement,
    );
  }
  final ownerType = arguments.last;
  String? activitySubjectClassName;
  String? activityActorClassName;
  if (activityEntryTypes case [final activityEntryType]) {
    final activityTypes = activityEntryType.typeArguments;
    if (activityTypes.length != 2) {
      throw InvalidGenerationSourceError(
        'ActivityOf must declare exact Subject and Actor types.',
        element: classElement,
      );
    }
    final subjectType = activityTypes.first;
    final actorType = activityTypes.last;
    activitySubjectClassName = subjectType.getDisplayString();
    activityActorClassName = actorType.getDisplayString();
    if (activityActorClassName != ownerType.getDisplayString()) {
      throw InvalidGenerationSourceError(
        'ActivityOf<Subject, Actor> must use the entity owner type '
        '`${ownerType.getDisplayString()}` as Actor.',
        element: classElement,
      );
    }
    _collectTypeImports(subjectType, typeImports);
    _collectTypeImports(actorType, typeImports);
  }
  if (hasActivityTrackedCapability) {
    final label = classElement.getGetter('activityLabel');
    if (label == null ||
        label.isAbstract ||
        label.returnType.getDisplayString() != 'String') {
      throw InvalidGenerationSourceError(
        'ActivityTracked requires one concrete, pure String '
        '`activityLabel` getter on the entity.',
        element: label ?? classElement,
      );
    }
  }
  if (collaborativeTypes case [final collaborativeType]) {
    final principalTypes = collaborativeType.typeArguments;
    if (principalTypes.length != 1 ||
        principalTypes.single.getDisplayString() !=
            ownerType.getDisplayString()) {
      throw InvalidGenerationSourceError(
        'Collaborative<Principal> must use the entity owner type '
        '`${ownerType.getDisplayString()}`.',
        element: classElement,
      );
    }
  }
  if (ownership == Ownership.identity &&
      ownerType.getDisplayString() != classElement.name) {
    throw InvalidGenerationSourceError(
      'Identity-owned entities must use the declaring entity as the exact '
      'OwnedBy Owner type.',
      element: classElement,
    );
  }
  _collectTypeImports(ownerType, typeImports);
  fields.add(
    _infrastructureField(
      name: EntityConventions.idFieldName,
      dartType: 'LocalId<${classElement.name}>',
      sqlType: SqlType.uuid,
    ),
  );
  if (ownership == Ownership.separate) {
    fields.add(
      _infrastructureField(
        name: EntityConventions.ownerFieldName,
        dartType: 'LocalId<${ownerType.getDisplayString()}>',
        sqlType: SqlType.uuid,
      ),
    );
  }
  infrastructureTail = [
    _infrastructureField(
      name: EntityConventions.deletedAtFieldName,
      dartType: 'DateTime?',
      sqlType: SqlType.timestampWithTimeZone,
      nullable: true,
    ),
    _infrastructureField(
      name: EntityConventions.serverVersionFieldName,
      dartType: 'ServerVersion',
      sqlType: SqlType.integer,
      defaultValue: 0,
    ),
  ];

  if (hasArchivableCapability) {
    final repeatedField = classElement.fields
        .where((field) => field.name == 'archivedAt')
        .firstOrNull;
    final repeatedAction = classElement.methods
        .where(
          (method) => method.name == 'archive' || method.name == 'unarchive',
        )
        .firstOrNull;
    if (repeatedField != null || repeatedAction != null) {
      throw InvalidGenerationSourceError(
        'Archivable supplies `archivedAt`, `archive`, and `unarchive`; '
        'remove the repeated lifecycle declaration.',
        element: repeatedField ?? repeatedAction ?? classElement,
      );
    }
  }
  if (activitySubjectClassName != null) {
    const suppliedMembers = {
      'subjectId',
      'actorId',
      'operation',
      'label',
      'sourceOperationId',
      'occurredAt',
    };
    final repeatedField = classElement.fields
        .where((field) => suppliedMembers.contains(field.name))
        .firstOrNull;
    if (repeatedField != null) {
      throw InvalidGenerationSourceError(
        'ActivityOf supplies its complete immutable activity-entry fields; '
        'remove `${repeatedField.name}`.',
        element: repeatedField,
      );
    }
    fields.addAll(
      _activityFields(
        subjectClassName: activitySubjectClassName,
        actorClassName: activityActorClassName!,
      ),
    );
  }

  for (final field in classElement.fields) {
    // Analyzer exposes getter/setter pairs as synthetic fields. They express
    // derived domain behavior, not stored state, so persistence is inferred
    // only from real field declarations. @Transient remains available for a
    // declared cache or other intentionally non-persistent field.
    if (field.isStatic ||
        field.isOriginGetterSetter ||
        _transientChecker.hasAnnotationOf(field)) {
      continue;
    }
    if (field.isPrivate) {
      throw InvalidGenerationSourceError(
        'Persisted entity fields must be public because generated records live '
        'in a separate library.',
        element: field,
      );
    }
    if (!field.isFinal) {
      throw InvalidGenerationSourceError(
        'Persisted entity field `${field.name}` must be declared final. '
        'Express durable changes through an @Action or an entity draft; '
        'Nodus does not generate asynchronous property setters.',
        element: field,
      );
    }
    if (const {
      EntityConventions.idFieldName,
      EntityConventions.ownerFieldName,
      EntityConventions.deletedAtFieldName,
      EntityConventions.serverVersionFieldName,
      EntityConventions.orderRankFieldName,
    }.contains(field.name)) {
      throw InvalidGenerationSourceError(
        '`${field.name}` is supplied by OwnedBy and must not be repeated.',
        element: field,
      );
    }
    final persistedAnnotation = _persistedChecker.firstAnnotationOf(field);
    final referenceObject = _referenceChecker.firstAnnotationOf(field);
    final compositionObject = _compositionChecker.firstAnnotationOf(field);
    if (referenceObject != null && compositionObject != null) {
      throw InvalidGenerationSourceError(
        '@Composition already declares the relationship; remove @Reference.',
        element: field,
      );
    }
    final isComposition = compositionObject != null;
    final isParticipant = _accessParticipantChecker.hasAnnotationOf(field);
    final accessReferenceObject = _accessReferenceChecker.firstAnnotationOf(
      field,
    );
    final accessTargetObject = _accessTargetChecker.firstAnnotationOf(field);
    final accessTargetTargetReader = accessTargetObject == null
        ? null
        : ConstantReader(accessTargetObject).peek('targetField');
    final accessTargetTargetField =
        accessTargetTargetReader == null || accessTargetTargetReader.isNull
        ? null
        : accessTargetTargetReader.objectValue.toSymbolValue();
    final ownerReferenceObject = _ownerReferenceChecker.firstAnnotationOf(
      field,
    );
    final isOwnerReference = ownerReferenceObject != null;
    final ownerReferenceTargetReader = ownerReferenceObject == null
        ? null
        : ConstantReader(ownerReferenceObject).peek('targetField');
    final ownerReferenceTargetField =
        ownerReferenceTargetReader == null || ownerReferenceTargetReader.isNull
        ? null
        : ownerReferenceTargetReader.objectValue.toSymbolValue();

    final persisted = persistedAnnotation == null
        ? null
        : ConstantReader(persistedAnnotation);
    final indexedObject = _indexedChecker.firstAnnotationOf(field);
    final indexed = indexedObject == null
        ? null
        : ConstantReader(indexedObject);
    final relationshipObject = referenceObject ?? compositionObject;
    final reference = relationshipObject == null
        ? null
        : _parseReference(
            field,
            classElement,
            ConstantReader(relationshipObject),
            ownerSetAccessor: setAccessor ?? lowerCamelCase(tableName),
            ownershipTargetField: ownerReferenceTargetField,
            composition: isComposition,
          );
    final accessTarget = accessTargetObject == null
        ? null
        : _resolveAccessTarget(
            field,
            classElement,
            reference: reference,
            targetField: accessTargetTargetField,
          );
    final dartType = field.type.getDisplayString();
    final collectionElementType = _isDartCoreList(field.type)
        ? (field.type as InterfaceType).typeArguments.single
        : null;
    if (collectionElementType != null) {
      throw InvalidGenerationSourceError(
        'Persisted collection field `${field.name}` is not supported. '
        'Normalize collection members as owned entities or relationships so '
        'identity, ordering, access, and synchronization stay explicit.',
        element: field,
      );
    }
    final scalarEnumElement = field.type.element is EnumElement
        ? field.type.element as EnumElement
        : null;
    final enumElement = scalarEnumElement;
    final enumValues = enumElement == null
        ? const <String>[]
        : enumElement.fields
              .where((candidate) => candidate.isEnumConstant)
              .map((candidate) => candidate.name!)
              .toList(growable: false);
    _collectTypeImports(field.type, typeImports);
    final scalarValue = enumElement == null
        ? _parseScalarValue(field.type, field)
        : null;
    final nullable = field.type.nullabilitySuffix == NullabilitySuffix.question;
    if (isComposition &&
        (indexedObject != null ||
            accessReferenceObject != null ||
            accessTargetObject != null ||
            ownerReferenceObject != null)) {
      throw InvalidGenerationSourceError(
        '@Composition derives uniqueness, access propagation, and ownership '
        'compatibility; remove @Indexed, @AccessReference, @AccessTarget, and '
        '@OwnerReference from `${field.name}`.',
        element: field,
      );
    }
    if (isParticipant) {
      _validateParticipantField(field, ownerType);
    }
    if (accessReferenceObject != null) {
      _validateAccessReferenceField(field, reference: reference);
    }
    final accessTargetOperations = accessTargetObject == null
        ? const <RlsOperation>[]
        : _parseAccessTargetOperations(
            field,
            ConstantReader(accessTargetObject),
            reference: accessTarget!.reference,
          );
    final accessTargetStates = accessTargetObject == null
        ? const _AccessTargetStates()
        : _parseAccessTargetStates(ConstantReader(accessTargetObject), field);
    if (isOwnerReference) {
      _validateOwnerReferenceField(
        field,
        reference: reference,
        ownerType: ownerType,
        ownership: ownership,
      );
    }
    final sqlType = enumElement == null
        ? scalarValue?.sqlType ?? _inferSqlType(dartType)
        : SqlType.text;

    final columnName = persisted?.peek('column')?.isNull ?? true
        ? snakeCase(field.name!)
        : persisted!.read('column').stringValue;
    _validateSqlIdentifier(columnName, field, label: 'column');
    final configuredDefault = _configuredDefaultValue(
      persisted,
      field,
      enumElement,
      scalarValue: scalarValue,
    );
    final transitions = _parseAllowedTransitions(
      persisted,
      field,
      scalarEnumElement,
    );
    final updatePrincipals = _parseFieldUpdatePrincipals(persisted, field);
    if (configuredDefault != null && enumElement == null) {
      _validateConfiguredDefault(
        field,
        configuredDefault,
        scalarValue: scalarValue,
      );
      if (scalarValue != null && !scalarValue.hasConstConstructor) {
        throw InvalidGenerationSourceError(
          '`${field.name}` has a scalar default, so '
          '`${field.type.getDisplayString().replaceAll('?', '')}.fromScalar` '
          'must be const for the generated optional parameter default.',
          element: field,
        );
      }
    }
    fields.add(
      FieldSpec(
        name: field.name!,
        columnName: columnName,
        dartType: dartType,
        sqlType: sqlType,
        nullable: nullable,
        isFinal: field.isFinal,
        defaultValue:
            configuredDefault ??
            _inferDefaultValue(field, initializers[field.name]),
        conflict: persisted == null
            ? ConflictStrategy.serverWins
            : _readEnum(persisted.read('conflict'), ConflictStrategy.values),
        authority: persisted == null
            ? FieldAuthority.client
            : _readEnum(persisted.read('authority'), FieldAuthority.values),
        minLength: persisted?.peek('minLength')?.isNull ?? true
            ? null
            : persisted!.read('minLength').intValue,
        maxLength: persisted?.peek('maxLength')?.isNull ?? true
            ? null
            : persisted!.read('maxLength').intValue,
        allowWhitespace: persisted?.peek('allowWhitespace')?.boolValue ?? false,
        minValue: persisted?.peek('minValue')?.isNull ?? true
            ? null
            : persisted!.read('minValue').intValue,
        maxValue: persisted?.peek('maxValue')?.isNull ?? true
            ? null
            : persisted!.read('maxValue').intValue,
        allowedValues: persisted == null
            ? const []
            : persisted
                  .read('allowedValues')
                  .listValue
                  .map((value) => value.toStringValue()!)
                  .toList(growable: false),
        greaterThan: persisted?.peek('greaterThan')?.isNull ?? true
            ? null
            : persisted!.read('greaterThan').objectValue.toSymbolValue(),
        greaterThanOrEqual:
            persisted?.peek('greaterThanOrEqual')?.isNull ?? true
            ? null
            : persisted!.read('greaterThanOrEqual').objectValue.toSymbolValue(),
        requires: persisted?.peek('requires')?.isNull ?? true
            ? null
            : persisted!.read('requires').objectValue.toSymbolValue(),
        notEqualTo: persisted?.peek('notEqualTo')?.isNull ?? true
            ? null
            : persisted!.read('notEqualTo').objectValue.toSymbolValue(),
        indexed:
            indexed != null ||
            reference != null ||
            isParticipant ||
            accessReferenceObject != null ||
            accessTargetObject != null ||
            isOwnerReference,
        unique: isComposition || (indexed?.read('unique').boolValue ?? false),
        indexScope: indexed == null
            ? IndexScope.field
            : _readEnum(indexed.read('scope'), IndexScope.values),
        enumValues: enumValues,
        enumTypeImport: enumElement?.library.uri.toString(),
        scalarValue: scalarValue,
        reference: reference,
        sinceProtocolVersion:
            persisted?.read('sinceProtocolVersion').intValue ?? 1,
        renamedFrom: persisted?.peek('renamedFrom')?.isNull ?? true
            ? null
            : persisted!.read('renamedFrom').stringValue,
        isParticipant: isParticipant,
        isAccessReference: accessReferenceObject != null,
        isAccessTarget: accessTargetObject != null || isComposition,
        isComposition: isComposition,
        accessTargetOperations: isComposition
            ? _compositionAccessOperations(reference!)
            : accessTargetOperations,
        accessTargetClassName: isComposition
            ? reference!.targetClassName
            : accessTarget?.reference.targetClassName,
        accessTargetInputImport: isComposition
            ? reference!.targetInputImport
            : accessTarget?.reference.targetInputImport,
        accessTargetTableName: isComposition
            ? reference!.targetTableName
            : accessTarget?.reference.targetTableName,
        accessTargetThroughColumnName: accessTarget?.throughColumnName,
        accessTargetActiveStates: accessTargetStates.values,
        accessTargetActiveStateEnumType: accessTargetStates.enumType,
        accessTargetActiveStateEnumImport: accessTargetStates.enumImport,
        isOwnerReference: isOwnerReference,
        transitions: transitions,
        updatePrincipals: updatePrincipals,
        draftEditableOverride: persisted?.peek('editable')?.isNull ?? true
            ? null
            : persisted!.read('editable').boolValue,
      ),
    );
  }
  if (hasActivatableCapability) {
    final repeatedField = classElement.fields
        .where((field) => field.name == 'active')
        .firstOrNull;
    final repeatedAction = classElement.methods
        .where(
          (method) => method.name == 'activate' || method.name == 'deactivate',
        )
        .firstOrNull;
    if (repeatedField != null || repeatedAction != null) {
      throw InvalidGenerationSourceError(
        'Activatable supplies `active`, `activate`, and `deactivate`; remove '
        'the repeated relationship lifecycle declaration.',
        element: repeatedField ?? repeatedAction ?? classElement,
      );
    }
    fields.add(_activatableField());
  }
  if (hasArchivableCapability) {
    final conventionalTimestampIndex = fields.indexWhere(
      (field) =>
          field.name == EntityConventions.createdAtFieldName ||
          field.name == EntityConventions.updatedAtFieldName,
    );
    fields.insert(
      conventionalTimestampIndex < 0
          ? fields.length
          : conventionalTimestampIndex,
      _archivableField(),
    );
  }
  if (hasOrderedCapability) {
    final obsoleteSortOrder = classElement.fields
        .where((field) => field.name == 'sortOrder')
        .firstOrNull;
    if (obsoleteSortOrder != null) {
      throw InvalidGenerationSourceError(
        'Ordered supplies an internal rank; remove the public `sortOrder` '
        'field and its persistence metadata.',
        element: obsoleteSortOrder,
      );
    }
    final obsoleteMove = classElement.methods
        .where((method) => method.name == 'moveTo')
        .firstOrNull;
    if (obsoleteMove != null) {
      throw InvalidGenerationSourceError(
        'Ordered movement belongs to the generated canonical collection; '
        'remove the entity-level `moveTo` method.',
        element: obsoleteMove,
      );
    }
    final capabilityProtocolVersion =
        <int>[
          1,
          ...fields.map((field) => field.sinceProtocolVersion),
        ].reduce((left, right) => left > right ? left : right) +
        1;
    fields.add(
      _infrastructureField(
        name: EntityConventions.orderRankFieldName,
        dartType: 'OrderRank',
        sqlType: SqlType.text,
        defaultValue: GeneratedOrderRanks.between()!.value,
        sinceProtocolVersion: capabilityProtocolVersion,
        generatedOnly: true,
      ),
    );
  }
  fields.addAll(infrastructureTail);

  _validateEntity(classElement, fields, ownership: ownership);
  final exclusiveFieldGroups = _parseExclusiveFieldGroups(
    annotation,
    classElement,
    fields,
  );
  _validateOwnerReferenceGroups(classElement, fields, exclusiveFieldGroups);
  _validateAccessReferenceGroups(classElement, fields, exclusiveFieldGroups);
  _validateAccessTargetFields(classElement, fields, exclusiveFieldGroups);
  final compoundIndexes = <CompoundIndexSpec>[
    ..._parseCompoundIndexes(
      annotation,
      classElement,
      fields,
      ownership: ownership,
    ),
  ];
  if (activitySubjectClassName != null) {
    compoundIndexes.addAll(const [
      CompoundIndexSpec(
        fields: ['subjectId', 'occurredAt'],
        unique: false,
        scope: IndexScope.field,
      ),
      CompoundIndexSpec(
        fields: ['occurredAt'],
        unique: false,
        scope: IndexScope.field,
      ),
      CompoundIndexSpec(
        fields: ['sourceOperationId'],
        unique: true,
        scope: IndexScope.field,
      ),
    ]);
  }
  final actions = [..._parseActions(classElement, fields)];
  if (hasActivatableCapability) {
    actions.addAll(_activatableActions);
  }
  if (hasArchivableCapability) {
    actions.addAll(_archivableActions);
  }
  final commands = _parseCommands(classElement, fields);
  final orderScopeFieldNames = _parseOrderScope(
    annotation,
    classElement,
    fields,
    actions: actions,
    commands: commands,
    hasOrderedCapability: hasOrderedCapability,
    ownership: ownership,
  );
  final isDeletable = classElement.allSupertypes.any(
    (type) => _softDeletableChecker.isExactlyType(type),
  );
  if (isComponent && isDeletable) {
    throw InvalidGenerationSourceError(
      'Component lifecycle belongs to its aggregate; remove SoftDeletable '
      'and delete the aggregate root instead.',
      element: classElement,
    );
  }
  if (isDeletable &&
      !commands.any((command) => command.methodName == 'remove')) {
    commands.add(
      const CommandSpec(
        methodName: 'remove',
        targetField: EntityConventions.deletedAtFieldName,
        parameterName: null,
        parameterType: null,
        value: SyncCommandValue.clockNow,
      ),
    );
  }
  if (isDeletable &&
      !commands.any((command) => command.methodName == 'restore')) {
    commands.add(
      const CommandSpec(
        methodName: 'restore',
        targetField: EntityConventions.deletedAtFieldName,
        parameterName: null,
        parameterType: null,
        value: SyncCommandValue.clear,
      ),
    );
  }
  final commandTargets = commands.map((command) => command.targetField).toSet();
  final commandMethods = commands.map((command) => command.methodName).toSet();
  for (final action in actions) {
    if (commandMethods.contains(action.methodName)) {
      throw InvalidGenerationSourceError(
        'Entity action `${action.methodName}` conflicts with a SyncCommand '
        'method of the same name.',
        element: classElement,
      );
    }
    final overlapping = action.targetFields
        .where(commandTargets.contains)
        .toList(growable: false);
    if (overlapping.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'Entity actions and SyncCommands cannot share target fields: '
        '${overlapping.join(', ')}.',
        element: classElement,
      );
    }
  }
  final inferredProtocolVersion = <int>[
    1,
    ...fields.map((field) => field.sinceProtocolVersion),
  ].reduce((left, right) => left > right ? left : right);
  final hasOrderScopeTransfer = actions.any(
    (action) => action.targetFields.any(
      (field) => orderScopeFieldNames?.contains(field) ?? false,
    ),
  );
  final protocolVersion = hasOrderScopeTransfer && inferredProtocolVersion < 3
      ? 3
      : inferredProtocolVersion;
  _validateProtocolEvolution(
    classElement,
    protocolVersion: protocolVersion,
    fields: fields,
  );
  _validateTransitionTargets(classElement, fields, actions);
  final security = _parseSecurity(
    annotation,
    classElement,
    ownership: ownership,
    fields: fields,
    commands: commands,
    actions: actions,
  );
  final relationshipGrants = security.grants
      .where((grant) => grant.principal == RlsPrincipal.relationship)
      .toList(growable: false);
  if (!isComponent && relationshipGrants.isNotEmpty) {
    throw InvalidGenerationSourceError(
      'RlsPrincipal.relationship is inferred only for Component entities.',
      element: classElement,
    );
  }
  if (isComponent &&
      !relationshipGrants.any(
        (grant) => grant.operation == RlsOperation.select,
      )) {
    throw InvalidGenerationSourceError(
      'A Component must grant relationship select access; omit explicit '
      'grants to use the inferred policy.',
      element: classElement,
    );
  }
  if (isComponent && security.collaboration != null) {
    throw InvalidGenerationSourceError(
      'A Component inherits aggregate access and cannot declare its own '
      'CollaborationAccess.',
      element: classElement,
    );
  }
  if (relationshipGrants.any(
    (grant) =>
        grant.operation == RlsOperation.insert ||
        grant.operation == RlsOperation.delete,
  )) {
    throw InvalidGenerationSourceError(
      'Component relationship access supports select and update only; '
      'creation and lifecycle belong to the aggregate transaction.',
      element: classElement,
    );
  }
  if (isComponent) {
    final invalidGrant = security.grants.where((grant) {
      final relationshipOperation =
          grant.principal == RlsPrincipal.relationship &&
          (grant.operation == RlsOperation.select ||
              grant.operation == RlsOperation.update);
      final dependencyInsert =
          grant.principal == RlsPrincipal.owner &&
          grant.operation == RlsOperation.insert;
      return !relationshipOperation && !dependencyInsert;
    }).firstOrNull;
    if (invalidGrant != null ||
        !security.grants.any(
          (grant) =>
              grant.principal == RlsPrincipal.owner &&
              grant.operation == RlsOperation.insert,
        )) {
      throw InvalidGenerationSourceError(
        'Component security permits only owner insert plus relationship '
        'select/update; omit explicit grants to use the inferred policy.',
        element: classElement,
      );
    }
  }
  _validateTransitionPrincipals(classElement, fields, security);
  _validateFieldUpdatePrincipals(classElement, fields, security, actions);
  _validateAndInferWorkflowMembership(
    classElement,
    tableName: tableName,
    fields: fields,
    actions: actions,
    security: security,
    compoundIndexes: compoundIndexes,
  );
  for (final command in commands) {
    if (!isDeletable) {
      throw InvalidGenerationSourceError(
        'Sync command `${command.methodName}` requires the entity to implement '
        'SoftDeletable.',
        element: classElement,
      );
    }
    if (!security.grants.any(
      (grant) => grant.operation == RlsOperation.delete,
    )) {
      throw InvalidGenerationSourceError(
        'Sync command `${command.methodName}` requires an explicit '
        'delete RLS grant.',
        element: classElement,
      );
    }
  }
  if (isDeletable &&
      !commands.any(
        (command) =>
            command.targetField == EntityConventions.deletedAtFieldName,
      )) {
    throw InvalidGenerationSourceError(
      'Tombstone entities must declare a delete SyncCommand targeting `deletedAt`.',
      element: classElement,
    );
  }
  if (security.grants.any(
        (grant) => grant.principal == RlsPrincipal.collaborator,
      ) &&
      security.collaboration == null) {
    throw InvalidGenerationSourceError(
      'A collaborator RLS grant requires CollaborationAccess metadata.',
      element: classElement,
    );
  }
  final hasParticipantGrant = security.grants.any(
    (grant) => grant.principal == RlsPrincipal.participant,
  );
  final hasParticipantField = fields.any((field) => field.isParticipant);
  if (hasParticipantGrant && !hasParticipantField) {
    throw InvalidGenerationSourceError(
      'A participant RLS grant requires at least one immutable '
      '@AccessParticipant LocalId<Owner> field.',
      element: classElement,
    );
  }
  if (hasParticipantField && !hasParticipantGrant) {
    throw InvalidGenerationSourceError(
      '@AccessParticipant has no effect without a participant RLS grant.',
      element: classElement,
    );
  }
  final referenceGrants = security.grants
      .where((grant) => grant.principal == RlsPrincipal.reference)
      .toList(growable: false);
  final hasReferenceGrant = referenceGrants.isNotEmpty;
  final hasAccessReference = fields.any((field) => field.isAccessReference);
  final hasOwnershipReference = fields.any((field) => field.isOwnerReference);
  final hasOwnerDerivedReferenceCreate =
      hasOwnershipReference &&
      referenceGrants.every((grant) => grant.operation == RlsOperation.insert);
  if (hasReferenceGrant &&
      !hasAccessReference &&
      !hasOwnerDerivedReferenceCreate) {
    throw InvalidGenerationSourceError(
      'A reference RLS grant requires at least one immutable '
      '@AccessReference entity reference, except an insert-only grant whose '
      'ownership is derived by @OwnerReference.',
      element: classElement,
    );
  }
  if (security.referenceAccessGuards.isNotEmpty && !hasAccessReference) {
    throw InvalidGenerationSourceError(
      '`referenceAccessGuards` requires at least one immutable '
      '@AccessReference entity reference.',
      element: classElement,
    );
  }
  final directlyGrantedOperations = security.grants
      .map((grant) => grant.operation)
      .toSet();
  final ungrantedReferenceGuards = security.referenceAccessGuards
      .where((operation) => !directlyGrantedOperations.contains(operation))
      .toList(growable: false);
  if (ungrantedReferenceGuards.isNotEmpty) {
    throw InvalidGenerationSourceError(
      '`referenceAccessGuards` may only guard directly granted operations. '
      'Missing grants: ${ungrantedReferenceGuards.map((operation) => operation.name).join(', ')}.',
      element: classElement,
    );
  }
  if (hasAccessReference &&
      !hasReferenceGrant &&
      security.referenceAccessGuards.isEmpty) {
    throw InvalidGenerationSourceError(
      '@AccessReference has no effect without a reference RLS grant or '
      '`referenceAccessGuards`.',
      element: classElement,
    );
  }
  if (security.collaboration?.isDirect == true &&
      (classElement.fields.any(
            (field) =>
                field.name == 'collaborators' ||
                field.name == 'setCollaborator',
          ) ||
          classElement.methods.any(
            (method) =>
                method.name == 'collaborators' ||
                method.name == 'setCollaborator',
          ))) {
    throw InvalidGenerationSourceError(
      '`setCollaborator` is reserved for the generated collaboration API and '
      'is supplied by Collaborative; remove the handwritten declaration.',
      element: classElement,
    );
  }
  if (security.grants.any(
    (grant) =>
        grant.operation == RlsOperation.insert &&
        grant.principal == RlsPrincipal.collaborator,
  )) {
    throw InvalidGenerationSourceError(
      'Collaborator inserts are not supported by the generated ownership '
      'protocol. Use an owner or authenticated insert grant.',
      element: classElement,
    );
  }
  if (security.grants.any(
    (grant) =>
        grant.operation == RlsOperation.insert &&
        grant.principal == RlsPrincipal.participant,
  )) {
    throw InvalidGenerationSourceError(
      'Participant inserts are not supported by the generated ownership '
      'protocol. The authenticated owner creates participant-scoped rows.',
      element: classElement,
    );
  }
  final grantedOperations = security.grants
      .map((grant) => grant.operation)
      .toSet();
  final hasAuthenticatedSelect = security.grants.any(
    (grant) =>
        grant.operation == RlsOperation.select &&
        grant.principal == RlsPrincipal.authenticated,
  );
  if (authenticatedReadSync != AuthenticatedReadSync.inferred &&
      !hasAuthenticatedSelect) {
    throw InvalidGenerationSourceError(
      '`authenticatedReadSync` is only meaningful with an authenticated '
      'select grant.',
      element: classElement,
    );
  }
  if (!grantedOperations.contains(RlsOperation.select)) {
    throw InvalidGenerationSourceError(
      'A synchronized entity requires an explicit select RLS grant.',
      element: classElement,
    );
  }
  if (grantedOperations.contains(RlsOperation.delete) && !isDeletable) {
    throw InvalidGenerationSourceError(
      'Delete RLS grants require SoftDeletable.',
      element: classElement,
    );
  }
  if (ownership == Ownership.identity &&
      grantedOperations.contains(RlsOperation.insert)) {
    throw InvalidGenerationSourceError(
      'Identity-owned entities are server-created and cannot grant client '
      'inserts.',
      element: classElement,
    );
  }
  final hasMutablePatch = fields.any(
    (field) =>
        (field.isMutable ||
            actions.any(
              (action) => action.targetFields.contains(field.name),
            )) &&
        !field.serverGenerated &&
        !commands.any((command) => command.targetField == field.name),
  );
  if (hasMutablePatch && !grantedOperations.contains(RlsOperation.update)) {
    throw InvalidGenerationSourceError(
      'Mutable synchronized fields require an explicit update RLS grant.',
      element: classElement,
    );
  }

  final packageName = assetId.package;
  final relativePath = assetId.path.substring('lib/'.length);
  final inputImport = 'package:$packageName/$relativePath';
  typeImports.remove(inputImport);
  typeImports.removeWhere((uri) => uri.startsWith('package:nodus/'));
  final spec = EntitySpec(
    className: classElement.name!,
    packageName: packageName,
    inputImport: inputImport,
    tableName: tableName,
    setAccessorOverride: setAccessor,
    ownership: ownership,
    cardinality: cardinality,
    authenticatedReadSync: authenticatedReadSync,
    hasOrderedCapability: hasOrderedCapability,
    hasArchivableCapability: hasArchivableCapability,
    hasActivityTrackedCapability: hasActivityTrackedCapability,
    activitySubjectClassName: activitySubjectClassName,
    activityActorClassName: activityActorClassName,
    isComponent: isComponent,
    protocolVersion: protocolVersion,
    relationshipAccessOperations: security.grants
        .where((grant) => grant.principal == RlsPrincipal.relationship)
        .map((grant) => grant.operation)
        .toList(growable: false),
    fields: fields,
    security: security,
    commands: commands,
    actions: actions,
    exclusiveFieldGroups: exclusiveFieldGroups,
    compoundIndexes: compoundIndexes,
    typeImports: typeImports.toList()..sort(),
    orderScopeFieldNames: orderScopeFieldNames,
    syncModeOverride: syncMode,
    syncTargetOverride: syncTarget,
  );
  final invalidDraftOverride = fields
      .where((field) => field.draftEditableOverride == true)
      .where((field) => !spec.isDraftEditable(field))
      .firstOrNull;
  if (invalidDraftOverride != null) {
    throw InvalidGenerationSourceError(
      '`${invalidDraftOverride.name}` cannot be draft-editable. Identity, '
      'ownership, infrastructure, lifecycle, transition, relationship, and '
      'action-owned fields must change through their generated capability or '
      'action.',
      element: classElement,
    );
  }
  return spec;
}

List<String>? _parseOrderScope(
  ConstantReader annotation,
  ClassElement element,
  List<FieldSpec> fields, {
  required List<ActionSpec> actions,
  required List<CommandSpec> commands,
  required bool hasOrderedCapability,
  required Ownership ownership,
}) {
  final reader = annotation.peek('orderScope');
  if (reader == null || reader.isNull) {
    if (hasOrderedCapability &&
        fields.any(
          (field) =>
              field.reference?.targetClassName == element.name &&
              field.name != EntityConventions.ownerFieldName,
        )) {
      throw InvalidGenerationSourceError(
        'Ordered cannot infer whether a self-reference forms one flat owner '
        'scope or independent sibling scopes. Set the smallest explicit '
        'Entity.orderScope tuple.',
        element: element,
      );
    }
    return null;
  }
  if (!hasOrderedCapability) {
    throw InvalidGenerationSourceError(
      'Entity.orderScope is valid only when the entity implements Ordered.',
      element: element,
    );
  }
  final names = reader.listValue
      .map((value) => value.toSymbolValue())
      .toList(growable: false);
  if (names.any((name) => name == null)) {
    throw InvalidGenerationSourceError(
      'Entity.orderScope entries must be persisted field symbols.',
      element: element,
    );
  }
  final declaredNames = names.cast<String>();
  if (declaredNames.toSet().length != declaredNames.length) {
    throw InvalidGenerationSourceError(
      'Entity.orderScope cannot repeat a field.',
      element: element,
    );
  }
  if (ownership == Ownership.separate &&
      declaredNames.contains(EntityConventions.ownerFieldName)) {
    throw InvalidGenerationSourceError(
      'A separately owned orderScope must omit inferred #ownerId.',
      element: element,
    );
  }
  final resolvedNames = [
    if (ownership == Ownership.separate) EntityConventions.ownerFieldName,
    ...declaredNames,
  ];
  final fieldsByName = {for (final field in fields) field.name: field};
  final actionTargets = {for (final action in actions) ...action.targetFields};
  final commandTargets = commands.map((command) => command.targetField).toSet();
  for (final name in resolvedNames) {
    final field = fieldsByName[name];
    if (field == null || field.generatedOnly) {
      throw InvalidGenerationSourceError(
        'Entity.orderScope field `$name` must be a persisted scalar field.',
        element: element,
      );
    }
    if (field.isMutable || commandTargets.contains(name)) {
      throw InvalidGenerationSourceError(
        'Entity.orderScope field `$name` must be an abstract final property. '
        'Only a generated action transfer may change its value.',
        element: element,
      );
    }
  }
  final transferActions = actions
      .where((action) => action.targetFields.any(resolvedNames.contains))
      .toList(growable: false);
  if (transferActions.length > 1) {
    throw InvalidGenerationSourceError(
      'An Ordered entity may declare only one action that transfers its scope.',
      element: element,
    );
  }
  if (transferActions case [final action]) {
    final transferableNames = resolvedNames
        .where((name) => name != EntityConventions.ownerFieldName)
        .toSet();
    final recursiveTransferFields = action.targetFields.where(
      (name) => fieldsByName[name]?.reference?.targetClassName == element.name,
    );
    if (recursiveTransferFields.length > 1) {
      throw InvalidGenerationSourceError(
        'An ordered hierarchy transfer supports exactly one recursive scope '
        'reference; multiple ancestry axes are ambiguous.',
        element: element,
      );
    }
    if (transferableNames.isEmpty ||
        action.assignments.isNotEmpty ||
        action.targetFields.toSet().length != transferableNames.length ||
        !action.targetFields.toSet().containsAll(transferableNames)) {
      throw InvalidGenerationSourceError(
        'The generated ordering-scope transfer action must contain exactly '
        'one required parameter for every non-owner scope field and no other '
        'mutation.',
        element: element,
      );
    }
  } else if (actionTargets.any(resolvedNames.contains)) {
    throw StateError(
      'Ordering-scope transfer classification was inconsistent.',
    );
  }
  return List<String>.unmodifiable(resolvedNames);
}

void _validateAndInferWorkflowMembership(
  ClassElement element, {
  required String tableName,
  required List<FieldSpec> fields,
  required List<ActionSpec> actions,
  required SecuritySpec security,
  required List<CompoundIndexSpec> compoundIndexes,
}) {
  final targetReferences = fields
      .where(
        (field) => field.reference?.targetCollaboration?.isWorkflow ?? false,
      )
      .where(
        (field) =>
            field.reference!.targetCollaboration!.membershipTable == tableName,
      )
      .toList(growable: false);
  if (targetReferences.isEmpty) return;
  if (targetReferences.length != 1) {
    throw InvalidGenerationSourceError(
      'A workflow membership entity must reference exactly one collaboration '
      'target whose inferred membership table is `$tableName`.',
      element: element,
    );
  }
  final targetField = targetReferences.single;
  final reference = targetField.reference!;
  final collaboration = reference.targetCollaboration!;
  if (targetField.columnName != collaboration.entityForeignKey) {
    throw InvalidGenerationSourceError(
      'Workflow target `${targetField.name}` must map to inferred column '
      '`${collaboration.entityForeignKey}`.',
      element: element,
    );
  }
  final participants = fields
      .where((field) => field.isParticipant)
      .toList(growable: false);
  if (participants.length != 1 ||
      participants.single.columnName != collaboration.userForeignKey) {
    throw InvalidGenerationSourceError(
      'Workflow membership `$tableName` requires exactly one '
      '@AccessParticipant field mapped to `${collaboration.userForeignKey}`.',
      element: element,
    );
  }
  final ownerFields = fields
      .where((field) => field.name == EntityConventions.ownerFieldName)
      .toList(growable: false);
  if (ownerFields.length != 1) {
    throw InvalidGenerationSourceError(
      'Workflow membership entities must use separate ownership.',
      element: element,
    );
  }
  final ownerField = ownerFields.single;
  if (ownerField.dartType != reference.targetOwnerDartType) {
    throw InvalidGenerationSourceError(
      'Workflow membership and `${reference.targetClassName}` must use the '
      'same nominal Owner type.',
      element: element,
    );
  }
  final statuses = fields
      .where((field) => field.columnName == collaboration.statusField)
      .toList(growable: false);
  final status = statuses.length == 1 ? statuses.single : null;
  final accepted = collaboration.acceptedValue!;
  if (status == null ||
      !status.isEnum ||
      (!status.isMutable &&
          !actions.any(
            (action) => action.targetFields.contains(status.name),
          )) ||
      !status.enumWireValues.contains(accepted) ||
      status.transitions.isEmpty ||
      status.persistedDefaultValue == accepted ||
      collaboration.additionalReadableValues.any(
        (value) => !status.enumWireValues.contains(value),
      ) ||
      (collaboration.acceptedEnumType != null &&
          (status.dartType != collaboration.acceptedEnumType ||
              status.enumTypeImport != collaboration.acceptedEnumImport)) ||
      (collaboration.readableEnumType != null &&
          (status.dartType != collaboration.readableEnumType ||
              status.enumTypeImport != collaboration.readableEnumImport))) {
    throw InvalidGenerationSourceError(
      'Workflow membership `$tableName` requires an immutable enum '
      '`${collaboration.statusField}` targeted by Actions, with non-accepted '
      'default, an `$accepted` value, matching readable states, and declared '
      'transitions.',
      element: element,
    );
  }
  final updatePrincipals = security.grants
      .where((grant) => grant.operation == RlsOperation.update)
      .map((grant) => grant.principal)
      .toSet();
  Set<RlsPrincipal> actors(ValueTransitionSpec transition) =>
      transition.principals.isEmpty
      ? updatePrincipals
      : transition.principals.toSet();
  final acceptanceEdges = status.transitions.where(
    (transition) => transition.toWire == accepted,
  );
  if (acceptanceEdges.isEmpty ||
      acceptanceEdges.any(
        (transition) =>
            !actors(transition).contains(RlsPrincipal.participant) ||
            actors(transition).contains(RlsPrincipal.owner),
      )) {
    throw InvalidGenerationSourceError(
      'Workflow acceptance transitions must be explicitly controlled by the '
      'participant, not the owner.',
      element: element,
    );
  }
  final revocationEdges = status.transitions.where(
    (transition) =>
        transition.fromWire == accepted && transition.toWire != accepted,
  );
  if (revocationEdges.isEmpty ||
      revocationEdges.every(
        (transition) =>
            !actors(transition).contains(RlsPrincipal.owner) &&
            !actors(transition).contains(RlsPrincipal.participant),
      )) {
    throw InvalidGenerationSourceError(
      'Workflow membership must allow an owner or participant to leave the '
      'accepted state.',
      element: element,
    );
  }
  final participant = participants.single;
  final inferredFields = [targetField.name, participant.name];
  compoundIndexes.removeWhere(
    (index) =>
        index.scope == IndexScope.field &&
        index.fields.length == inferredFields.length &&
        index.fields.indexed.every(
          (entry) => entry.$2 == inferredFields[entry.$1],
        ),
  );
  compoundIndexes.add(
    CompoundIndexSpec(
      fields: inferredFields,
      unique: true,
      scope: IndexScope.field,
    ),
  );
}

List<ValueTransitionSpec> _parseAllowedTransitions(
  ConstantReader? persisted,
  FieldElement field,
  EnumElement? enumElement,
) {
  if (persisted == null) return const [];
  final values = persisted.read('transitions').listValue;
  if (values.isEmpty) return const [];
  if (enumElement == null ||
      field.type.nullabilitySuffix == NullabilitySuffix.question) {
    throw InvalidGenerationSourceError(
      'Persisted transitions require a non-null enum field.',
      element: field,
    );
  }
  final enumValues = enumElement.fields
      .where((candidate) => candidate.isEnumConstant)
      .map((candidate) => candidate.name!)
      .toSet();
  final transitions = <ValueTransitionSpec>[];
  final identities = <String>{};
  for (final value in values) {
    final transition = ConstantReader(value);
    final fromObject = transition.read('from').objectValue;
    final toObject = transition.read('to').objectValue;
    final fromVariable = fromObject.variable;
    final toVariable = toObject.variable;
    final from = fromVariable?.name;
    final to = toVariable?.name;
    if (from == null ||
        to == null ||
        fromVariable?.enclosingElement != enumElement ||
        toVariable?.enclosingElement != enumElement ||
        !enumValues.contains(from) ||
        !enumValues.contains(to)) {
      throw InvalidGenerationSourceError(
        'Persisted transitions must use values from `${enumElement.name}`.',
        element: field,
      );
    }
    if (from == to) {
      throw InvalidGenerationSourceError(
        'Persisted transitions cannot declare a no-op `$from -> $to` edge.',
        element: field,
      );
    }
    if (!identities.add('$from->$to')) {
      throw InvalidGenerationSourceError(
        'Persisted transitions cannot repeat the `$from -> $to` edge.',
        element: field,
      );
    }
    final principals = transition
        .read('by')
        .listValue
        .map((value) => _readEnum(ConstantReader(value), RlsPrincipal.values))
        .toList(growable: false);
    if (principals.toSet().length != principals.length) {
      throw InvalidGenerationSourceError(
        'Persisted transition principals must be unique for `$from -> $to`.',
        element: field,
      );
    }
    transitions.add(
      ValueTransitionSpec(from: from, to: to, principals: principals),
    );
  }
  return List.unmodifiable(transitions);
}

List<RlsPrincipal> _parseFieldUpdatePrincipals(
  ConstantReader? persisted,
  FieldElement field,
) {
  if (persisted == null) return const [];
  final principals = persisted
      .read('updateBy')
      .listValue
      .map((value) => _readEnum(ConstantReader(value), RlsPrincipal.values))
      .toList(growable: false);
  if (principals.toSet().length != principals.length) {
    throw InvalidGenerationSourceError(
      'Persisted update principals must be unique.',
      element: field,
    );
  }
  return List.unmodifiable(principals);
}

void _validateTransitionPrincipals(
  ClassElement element,
  List<FieldSpec> fields,
  SecuritySpec security,
) {
  final updatePrincipals = security.grants
      .where((grant) => grant.operation == RlsOperation.update)
      .map((grant) => grant.principal)
      .toSet();
  for (final field in fields) {
    for (final transition in field.transitions) {
      final ungranted = transition.principals
          .where((principal) => !updatePrincipals.contains(principal))
          .toList(growable: false);
      if (ungranted.isNotEmpty) {
        throw InvalidGenerationSourceError(
          '`${field.name}` transition `${transition.from} -> '
          '${transition.to}` names ${ungranted.map((value) => value.name).join(', ')} '
          'without a matching update RLS grant.',
          element: element,
        );
      }
    }
  }
}

void _validateFieldUpdatePrincipals(
  ClassElement element,
  List<FieldSpec> fields,
  SecuritySpec security,
  List<ActionSpec> actions,
) {
  final updatePrincipals = security.grants
      .where((grant) => grant.operation == RlsOperation.update)
      .map((grant) => grant.principal)
      .toSet();
  final actionTargets = actions.expand((action) => action.targetFields).toSet();
  for (final field in fields.where(
    (candidate) => candidate.updatePrincipals.isNotEmpty,
  )) {
    final ordinaryDraftField =
        field.draftEditableOverride != false &&
        field.inCreatePayload &&
        field.reference == null &&
        field.transitions.isEmpty &&
        !const {
          EntityConventions.idFieldName,
          EntityConventions.ownerFieldName,
          EntityConventions.deletedAtFieldName,
          EntityConventions.archivedAtFieldName,
          EntityConventions.orderRankFieldName,
        }.contains(field.name);
    if ((!ordinaryDraftField && !actionTargets.contains(field.name)) ||
        field.serverGenerated ||
        field.isServerManaged) {
      throw InvalidGenerationSourceError(
        '`${field.name}` declares update principals but is not a '
        'client-updatable field or entity-action target.',
        element: element,
      );
    }
    final ungranted = field.updatePrincipals
        .where((principal) => !updatePrincipals.contains(principal))
        .toList(growable: false);
    if (ungranted.isNotEmpty) {
      throw InvalidGenerationSourceError(
        '`${field.name}` names ${ungranted.map((value) => value.name).join(', ')} '
        'without a matching update RLS grant.',
        element: element,
      );
    }
  }
}

void _validateParticipantField(FieldElement field, DartType ownerType) {
  final type = field.type;
  if (type.nullabilitySuffix == NullabilitySuffix.question || !field.isFinal) {
    throw InvalidGenerationSourceError(
      '@AccessParticipant requires an immutable, non-null LocalId<Owner> field.',
      element: field,
    );
  }
  if (type is! InterfaceType ||
      type.element.name != 'LocalId' ||
      type.typeArguments.length != 1 ||
      type.typeArguments.single.getDisplayString() !=
          ownerType.getDisplayString()) {
    throw InvalidGenerationSourceError(
      '@AccessParticipant requires LocalId<${ownerType.getDisplayString()}>.',
      element: field,
    );
  }
}

void _validateAccessReferenceField(
  FieldElement field, {
  required ReferenceSpec? reference,
}) {
  if (reference == null || !field.isFinal) {
    throw InvalidGenerationSourceError(
      '@AccessReference requires an immutable @Reference LocalId<T> '
      'field.',
      element: field,
    );
  }
  if (reference.targetClassName == field.enclosingElement.name) {
    throw InvalidGenerationSourceError(
      '@AccessReference cannot authorize through a self-reference.',
      element: field,
    );
  }
}

void _validateAccessReferenceGroups(
  ClassElement element,
  List<FieldSpec> fields,
  List<ExclusiveFieldGroupSpec> exclusiveFieldGroups,
) {
  final accessFields = fields
      .where((field) => field.isAccessReference)
      .toList(growable: false);
  for (final field in accessFields.where((candidate) => candidate.nullable)) {
    final matching = exclusiveFieldGroups.where(
      (group) => group.fields.contains(field.name),
    );
    final valid = matching.any(
      (group) =>
          !group.allowNone &&
          group.fields.every(
            (name) => accessFields.any((candidate) => candidate.name == name),
          ),
    );
    if (!valid) {
      throw InvalidGenerationSourceError(
        'Nullable @AccessReference `${field.name}` must belong to an '
        'exactly-one ExclusiveFieldGroup containing only access references.',
        element: element,
      );
    }
  }
}

final class _ResolvedAccessTarget {
  const _ResolvedAccessTarget({
    required this.reference,
    this.throughColumnName,
  });

  final ReferenceSpec reference;
  final String? throughColumnName;
}

_ResolvedAccessTarget _resolveAccessTarget(
  FieldElement field,
  ClassElement relationship, {
  required ReferenceSpec? reference,
  required String? targetField,
}) {
  if (reference == null || !field.isFinal) {
    throw InvalidGenerationSourceError(
      '@AccessTarget requires an immutable @Reference LocalId<T> field. '
      'Nullable targets must form one exactly-one group.',
      element: field,
    );
  }
  if (targetField == null) {
    return _ResolvedAccessTarget(reference: reference);
  }

  final outerType = field.type as InterfaceType;
  final bridge = outerType.typeArguments.single.element as ClassElement;
  final candidates = bridge.fields.where(
    (candidate) => candidate.name == targetField,
  );
  if (candidates.length != 1) {
    throw InvalidGenerationSourceError(
      '@AccessTarget.targetField must name one declared field on '
      '`${bridge.name}`.',
      element: field,
    );
  }
  final through = candidates.single;
  final throughReferenceObject = _referenceChecker.firstAnnotationOf(through);
  if (throughReferenceObject == null ||
      through.isStatic ||
      through.isOriginGetterSetter ||
      _transientChecker.hasAnnotationOf(through) ||
      !through.isFinal ||
      through.type.nullabilitySuffix == NullabilitySuffix.question) {
    throw InvalidGenerationSourceError(
      '@AccessTarget.targetField must be an immutable, non-null '
      '@Reference LocalId<T> field.',
      element: field,
    );
  }

  final bridgeAnnotation = ConstantReader(
    _entityChecker.firstAnnotationOf(bridge)!,
  );
  final bridgeTableName = bridgeAnnotation.peek('table')?.isNull ?? true
      ? pluralSnakeCase(bridge.name!)
      : bridgeAnnotation.read('table').stringValue;
  final bridgeSetAccessor = bridgeAnnotation.peek('setAccessor')?.isNull ?? true
      ? lowerCamelCase(bridgeTableName)
      : bridgeAnnotation.read('setAccessor').stringValue;
  final targetReference = _parseReference(
    through,
    bridge,
    ConstantReader(throughReferenceObject),
    ownerSetAccessor: bridgeSetAccessor,
  );
  if (targetReference.targetClassName == relationship.name) {
    throw InvalidGenerationSourceError(
      '@AccessTarget.targetField cannot authorize the relationship itself.',
      element: field,
    );
  }
  final persistedObject = _persistedChecker.firstAnnotationOf(through);
  final persisted = persistedObject == null
      ? null
      : ConstantReader(persistedObject);
  final throughColumnName = persisted?.peek('column')?.isNull ?? true
      ? snakeCase(targetField)
      : persisted!.read('column').stringValue;
  return _ResolvedAccessTarget(
    reference: targetReference,
    throughColumnName: throughColumnName,
  );
}

List<RlsOperation> _parseAccessTargetOperations(
  FieldElement field,
  ConstantReader annotation, {
  required ReferenceSpec? reference,
}) {
  if (reference == null || !field.isFinal) {
    throw InvalidGenerationSourceError(
      '@AccessTarget requires an immutable @Reference LocalId<T> field. '
      'Nullable targets must form one exactly-one group.',
      element: field,
    );
  }
  if (reference.targetClassName == field.enclosingElement.name) {
    throw InvalidGenerationSourceError(
      '@AccessTarget cannot authorize a self-reference.',
      element: field,
    );
  }
  if (_accessReferenceChecker.hasAnnotationOf(field) ||
      _accessParticipantChecker.hasAnnotationOf(field)) {
    throw InvalidGenerationSourceError(
      '@AccessTarget is an authorization destination and cannot also be an '
      'access source or participant. It may be the ownership source when a '
      'different @AccessReference supplies the finite audience.',
      element: field,
    );
  }

  final configured = annotation.peek('operations');
  final operations = configured == null || configured.isNull
      ? reference.targetOwnerOperations
            .where((operation) => operation != RlsOperation.insert)
            .toList(growable: false)
      : configured.listValue
            .map(
              (value) => _readEnum(ConstantReader(value), RlsOperation.values),
            )
            .toList(growable: false);
  final unique = operations.toSet();
  if (operations.isEmpty || unique.length != operations.length) {
    throw InvalidGenerationSourceError(
      '@AccessTarget operations must be a non-empty unique list.',
      element: field,
    );
  }
  if (unique.contains(RlsOperation.insert)) {
    throw InvalidGenerationSourceError(
      '@AccessTarget cannot grant insert access to an existing referenced row.',
      element: field,
    );
  }
  if (!unique.contains(RlsOperation.select)) {
    throw InvalidGenerationSourceError(
      '@AccessTarget update or delete access requires select access.',
      element: field,
    );
  }
  final unsupported = unique.difference(
    reference.targetOwnerOperations.toSet(),
  );
  if (unsupported.isNotEmpty) {
    throw InvalidGenerationSourceError(
      '@AccessTarget cannot grant operations the target owner does not have: '
      '${unsupported.map((operation) => operation.name).join(', ')}.',
      element: field,
    );
  }
  return List.unmodifiable(operations);
}

List<RlsOperation> _compositionAccessOperations(ReferenceSpec reference) =>
    reference.targetRelationshipAccessOperations;

final class _AccessTargetStates {
  const _AccessTargetStates({
    this.values = const [],
    this.enumType,
    this.enumImport,
  });

  final List<String> values;
  final String? enumType;
  final String? enumImport;
}

_AccessTargetStates _parseAccessTargetStates(
  ConstantReader annotation,
  FieldElement field,
) {
  final values = annotation.read('activeStates').listValue;
  if (values.isEmpty) return const _AccessTargetStates();
  String? enumType;
  String? enumImport;
  final names = <String>[];
  for (final value in values) {
    final variable = value.variable;
    final declaringEnum = variable?.enclosingElement;
    final name = variable?.name;
    if (declaringEnum is! EnumElement || name == null) {
      throw InvalidGenerationSourceError(
        '@AccessTarget.activeStates must contain enum constants.',
        element: field,
      );
    }
    final candidateType = declaringEnum.name!;
    final candidateImport = declaringEnum.library.uri.toString();
    enumType ??= candidateType;
    enumImport ??= candidateImport;
    if (enumType != candidateType || enumImport != candidateImport) {
      throw InvalidGenerationSourceError(
        '@AccessTarget.activeStates must use one enum type.',
        element: field,
      );
    }
    names.add(name);
  }
  if (names.toSet().length != names.length) {
    throw InvalidGenerationSourceError(
      '@AccessTarget.activeStates must be unique.',
      element: field,
    );
  }
  return _AccessTargetStates(
    values: List.unmodifiable(names),
    enumType: enumType,
    enumImport: enumImport,
  );
}

void _validateAccessTargetFields(
  ClassElement element,
  List<FieldSpec> fields,
  List<ExclusiveFieldGroupSpec> exclusiveFieldGroups,
) {
  final targets = fields
      .where((field) => field.isAccessTarget)
      .toList(growable: false);
  for (final field in targets.where((candidate) => candidate.nullable)) {
    final valid = exclusiveFieldGroups.any(
      (group) =>
          !group.allowNone &&
          group.fields.contains(field.name) &&
          group.fields.every(
            (name) => targets.any((candidate) => candidate.name == name),
          ),
    );
    if (!valid) {
      throw InvalidGenerationSourceError(
        'Nullable @AccessTarget `${field.name}` must belong to an exactly-one '
        'ExclusiveFieldGroup containing only access targets.',
        element: element,
      );
    }
  }
  final activeField = fields
      .where(
        (field) =>
            field.name == 'active' &&
            field.dartType == 'bool' &&
            !field.nullable,
      )
      .firstOrNull;
  final status = fields.where((field) => field.name == 'status').firstOrNull;
  for (final target in targets.where(
    (field) => field.accessTargetActiveStates.isNotEmpty,
  )) {
    if (activeField != null) {
      throw InvalidGenerationSourceError(
        '@AccessTarget.activeStates cannot be combined with a conventional '
        '`active` field.',
        element: element,
      );
    }
    if (status == null ||
        !status.isEnum ||
        status.dartType != target.accessTargetActiveStateEnumType ||
        status.enumTypeImport != target.accessTargetActiveStateEnumImport ||
        !target.accessTargetActiveStates.every(status.enumValues.contains)) {
      throw InvalidGenerationSourceError(
        '@AccessTarget.activeStates must use constants from the entity\'s '
        'persisted enum `status` field.',
        element: element,
      );
    }
  }
}

void _validateOwnerReferenceField(
  FieldElement field, {
  required ReferenceSpec? reference,
  required DartType ownerType,
  required Ownership ownership,
}) {
  if (reference == null || !field.isFinal) {
    throw InvalidGenerationSourceError(
      '@OwnerReference requires an immutable @Reference LocalId<T> '
      'field. Nullable ownership references must form one exactly-one group.',
      element: field,
    );
  }
  if (ownership != Ownership.separate) {
    throw InvalidGenerationSourceError(
      '@OwnerReference requires separate entity ownership.',
      element: field,
    );
  }
  final expectedOwnerType = 'LocalId<${ownerType.getDisplayString()}>';
  if (reference.ownershipSourceDartType != expectedOwnerType) {
    throw InvalidGenerationSourceError(
      '@OwnerReference requires its referenced ownership source to use the '
      'same `$expectedOwnerType` owner.',
      element: field,
    );
  }
}

void _validateOwnerReferenceGroups(
  ClassElement element,
  List<FieldSpec> fields,
  List<ExclusiveFieldGroupSpec> exclusiveFieldGroups,
) {
  final ownershipReferences = fields
      .where((field) => field.isOwnerReference)
      .toList(growable: false);
  if (ownershipReferences.isEmpty) return;
  if (ownershipReferences.length == 1 && !ownershipReferences.single.nullable) {
    return;
  }
  if (ownershipReferences.any((field) => !field.nullable)) {
    throw InvalidGenerationSourceError(
      'Multiple @OwnerReference fields must all be nullable alternatives.',
      element: element,
    );
  }
  final ownershipNames = ownershipReferences.map((field) => field.name).toSet();
  final matching = exclusiveFieldGroups.where(
    (group) =>
        !group.allowNone && group.fields.toSet().containsAll(ownershipNames),
  );
  final valid = matching.any(
    (group) => group.fields.toSet().length == ownershipNames.length,
  );
  if (!valid) {
    throw InvalidGenerationSourceError(
      'Nullable @OwnerReference fields must be every member of one '
      'exactly-one ExclusiveFieldGroup.',
      element: element,
    );
  }
}

List<CompoundIndexSpec> _parseCompoundIndexes(
  ConstantReader annotation,
  ClassElement element,
  List<FieldSpec> fields, {
  required Ownership ownership,
}) {
  final persistedByName = {for (final field in fields) field.name: field};
  final identities = <String>{
    for (final field in fields.where((field) => field.indexed))
      [
        if (field.indexScope == IndexScope.owner)
          EntityConventions.ownerFieldName,
        field.name,
      ].join('|'),
  };
  final indexes = <CompoundIndexSpec>[];
  for (final indexValue in annotation.read('indexes').listValue) {
    final reader = ConstantReader(indexValue);
    final keyset = reader.read('keyset').boolValue;
    final unordered = reader.read('unordered').boolValue;
    final conditionReader = reader.peek('condition');
    IndexConditionSpec? condition;
    if (conditionReader != null && !conditionReader.isNull) {
      if (keyset) {
        throw InvalidGenerationSourceError(
          'CompoundIndex.query cannot be conditional because generated keyset '
          'queries do not imply a partial-index predicate.',
          element: element,
        );
      }
      if (unordered) {
        throw InvalidGenerationSourceError(
          'CompoundIndex.unorderedWithOwner cannot be conditional.',
          element: element,
        );
      }
      final fieldName = conditionReader
          .read('field')
          .objectValue
          .toSymbolValue();
      final field = fieldName == null ? null : persistedByName[fieldName];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'IndexCondition field must be a persisted field symbol.',
          element: element,
        );
      }
      if (field.nullable) {
        throw InvalidGenerationSourceError(
          'IndexCondition field `$fieldName` must be a non-null scalar value.',
          element: element,
        );
      }
      final values = conditionReader
          .read('values')
          .listValue
          .map((value) => _indexConditionValue(value, field, element))
          .toList(growable: false);
      if (values.isEmpty || values.toSet().length != values.length) {
        throw InvalidGenerationSourceError(
          'IndexCondition values must be a non-empty set of unique constants.',
          element: element,
        );
      }
      condition = IndexConditionSpec(
        field: fieldName!,
        values: List.unmodifiable(values),
      );
    }
    final names = unordered
        ? [reader.read('unorderedWithOwnerField').objectValue.toSymbolValue()]
        : reader
              .read('fields')
              .listValue
              .map((value) => value.toSymbolValue())
              .toList(growable: false);
    if (names.any((name) => name == null)) {
      throw InvalidGenerationSourceError(
        'CompoundIndex fields must be symbols.',
        element: element,
      );
    }
    final minimumFields = keyset || condition != null || unordered ? 1 : 2;
    if (names.length < minimumFields) {
      throw InvalidGenerationSourceError(
        keyset
            ? 'CompoundIndex.query requires at least one field symbol.'
            : condition != null
            ? 'A conditional CompoundIndex requires at least one field symbol.'
            : 'CompoundIndex requires at least two field symbols.',
        element: element,
      );
    }
    final resolved = names.cast<String>();
    if (resolved.toSet().length != resolved.length) {
      throw InvalidGenerationSourceError(
        'CompoundIndex cannot repeat a field.',
        element: element,
      );
    }
    for (final name in resolved) {
      final field = persistedByName[name];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'CompoundIndex field `$name` is not persisted.',
          element: element,
        );
      }
    }
    if (keyset && resolved.contains(EntityConventions.idFieldName)) {
      throw InvalidGenerationSourceError(
        'CompoundIndex.query appends the inferred `${EntityConventions.idFieldName}` '
        'tie-breaker; do not declare it explicitly.',
        element: element,
      );
    }
    final scope = _readEnum(reader.read('scope'), IndexScope.values);
    if (scope == IndexScope.owner) {
      if (ownership != Ownership.separate) {
        throw InvalidGenerationSourceError(
          'A CompoundIndex cannot use owner scope when entity ownership is '
          'identity-based.',
          element: element,
        );
      }
      if (resolved.contains(EntityConventions.ownerFieldName)) {
        throw InvalidGenerationSourceError(
          'A CompoundIndex with owner scope must not repeat the inferred '
          '`${EntityConventions.ownerFieldName}` field.',
          element: element,
        );
      }
    }
    if (unordered) {
      if (ownership != Ownership.separate ||
          scope != IndexScope.owner ||
          !reader.read('unique').boolValue ||
          keyset ||
          resolved.length != 1) {
        throw InvalidGenerationSourceError(
          'CompoundIndex.unorderedWithOwner requires one immutable, non-null '
          'LocalId<Owner> field on a separately owned entity.',
          element: element,
        );
      }
      final owner = persistedByName[EntityConventions.ownerFieldName]!;
      final other = persistedByName[resolved.single]!;
      if (other.nullable ||
          !other.isFinal ||
          other.sqlType != SqlType.uuid ||
          other.dartType != owner.dartType) {
        throw InvalidGenerationSourceError(
          'CompoundIndex.unorderedWithOwner requires one immutable, non-null '
          'LocalId<Owner> field on a separately owned entity.',
          element: element,
        );
      }
    }
    final identity = [
      if (unordered) 'unordered',
      if (scope == IndexScope.owner) EntityConventions.ownerFieldName,
      ...resolved,
      if (keyset) EntityConventions.idFieldName,
      if (condition != null) ...[
        'where',
        condition.field,
        ...condition.values.map((value) => value.toString()),
      ],
    ].join('|');
    if (!identities.add(identity)) {
      throw InvalidGenerationSourceError(
        'Duplicate generated index declaration for `${resolved.join(', ')}`.',
        element: element,
      );
    }
    indexes.add(
      CompoundIndexSpec(
        fields: List.unmodifiable(resolved),
        unique: reader.read('unique').boolValue,
        scope: scope,
        keyset: keyset,
        condition: condition,
        unordered: unordered,
      ),
    );
  }
  return List.unmodifiable(indexes);
}

Object _indexConditionValue(
  DartObject value,
  FieldSpec field,
  ClassElement element,
) {
  if (field.isEnum) {
    final variable = value.variable;
    final enumElement = variable?.enclosingElement;
    final name = variable?.name;
    if (enumElement is EnumElement &&
        enumElement.name == field.dartType &&
        enumElement.library.uri.toString() == field.enumTypeImport &&
        name != null &&
        field.enumValues.contains(name)) {
      return snakeCase(name);
    }
  } else {
    final decoded = switch (field.dartType) {
      'String' => value.toStringValue(),
      'bool' => value.toBoolValue(),
      'int' => value.toIntValue(),
      _ => null,
    };
    if (decoded != null) return decoded;
  }
  throw InvalidGenerationSourceError(
    'IndexCondition values for `${field.name}` must be constants of its exact '
    'persisted type.',
    element: element,
  );
}

List<ExclusiveFieldGroupSpec> _parseExclusiveFieldGroups(
  ConstantReader annotation,
  ClassElement element,
  List<FieldSpec> fields,
) {
  final persistedByName = {for (final field in fields) field.name: field};
  final groups = <ExclusiveFieldGroupSpec>[];
  final identities = <String>{};
  for (final groupValue in annotation.read('exclusiveFieldGroups').listValue) {
    final names = ConstantReader(groupValue)
        .read('fields')
        .listValue
        .map((value) => value.toSymbolValue())
        .toList(growable: false);
    if (names.length < 2 || names.any((name) => name == null)) {
      throw InvalidGenerationSourceError(
        'ExclusiveFieldGroup requires at least two field symbols.',
        element: element,
      );
    }
    final resolved = names.cast<String>();
    if (resolved.toSet().length != resolved.length) {
      throw InvalidGenerationSourceError(
        'ExclusiveFieldGroup cannot repeat a field.',
        element: element,
      );
    }
    for (final name in resolved) {
      final field = persistedByName[name];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'ExclusiveFieldGroup field `$name` is not persisted.',
          element: element,
        );
      }
      if (!field.nullable) {
        throw InvalidGenerationSourceError(
          'ExclusiveFieldGroup field `$name` must be nullable.',
          element: element,
        );
      }
    }
    final identity = [...resolved]..sort();
    if (!identities.add(identity.join('|'))) {
      throw InvalidGenerationSourceError(
        'Duplicate ExclusiveFieldGroup declaration.',
        element: element,
      );
    }
    groups.add(
      ExclusiveFieldGroupSpec(
        fields: List.unmodifiable(resolved),
        allowNone: ConstantReader(groupValue).read('allowNone').boolValue,
      ),
    );
  }
  return List.unmodifiable(groups);
}

void _collectTypeImports(DartType type, Set<String> imports) {
  if (type is! InterfaceType) return;
  final uri = type.element.library.uri;
  if (uri.scheme == 'package') imports.add(uri.toString());
  for (final argument in type.typeArguments) {
    _collectTypeImports(argument, imports);
  }
}

/// Discovers the package graph without a handwritten Dart graph root.
Future<EntityGraphSpec> parseInferredEntityGraph(
  BuildStep buildStep, {
  required String className,
  required int schemaVersion,
  required String defaultTarget,
}) async {
  final entities = await _discoverGraphEntities(buildStep);
  if (entities.isEmpty) {
    throw InvalidGenerationSourceError(
      'Nodus discovered no @Entity declarations under lib/.',
    );
  }
  final packageName = buildStep.inputId.package;
  final packagePrefix = 'package:$packageName/';
  final firstEntityAsset = AssetId(
    packageName,
    'lib/${entities.first.inputImport.substring(packagePrefix.length)}',
  );
  final library = await buildStep.resolver.libraryFor(firstEntityAsset);
  final element = library.classes.firstWhere(_entityChecker.hasAnnotationOf);
  final target = SyncTargetSpec(
    enumType: '${className}SyncTarget',
    enumImport: 'package:$packageName/nodus.g.dart',
    valueName: lowerCamelCase(defaultTarget),
    wireName: defaultTarget,
  );
  return _resolveEntityGraph(
    className: className,
    packageName: packageName,
    inputImport: 'package:$packageName/nodus.lock',
    schemaVersion: schemaVersion,
    entities: entities,
    defaultSyncTarget: target,
    element: element,
    outputBaseName: 'nodus.g',
    emitsSyncTargetEnum: true,
  );
}

Future<List<EntitySpec>> _discoverGraphEntities(BuildStep buildStep) async {
  final entities = <EntitySpec>[];
  await for (final asset in buildStep.findAssets(Glob('lib/**.dart'))) {
    if (!await buildStep.resolver.isLibrary(asset)) {
      continue;
    }
    final entity = await parseEntityAsset(buildStep, asset);
    if (entity != null) entities.add(entity);
  }
  entities.sort((left, right) => left.inputImport.compareTo(right.inputImport));
  return List.unmodifiable(entities);
}

EntityGraphSpec _resolveEntityGraph({
  required String className,
  required String packageName,
  required String inputImport,
  required int schemaVersion,
  required List<EntitySpec> entities,
  required SyncTargetSpec? defaultSyncTarget,
  required Element element,
  String outputBaseName = 'nodus.g',
  bool emitsSyncTargetEnum = false,
}) {
  if (entities.isEmpty) {
    throw InvalidGenerationSourceError(
      'An entity graph must discover at least one @Entity declaration.',
      element: element,
    );
  }
  _validateGraphEntities(entities, element);
  final relationshipOperations = <String, Set<RlsOperation>>{};
  for (final relationship in entities) {
    for (final field in relationship.accessTargetFields) {
      if (field.accessTargetThroughColumnName != null) {
        relationshipOperations
            .putIfAbsent(
              field.reference!.targetClassName,
              () => <RlsOperation>{},
            )
            .add(RlsOperation.select);
      }
      relationshipOperations
          .putIfAbsent(field.accessTargetClassName!, () => <RlsOperation>{})
          .addAll(field.accessTargetOperations);
    }
  }
  final resolvedEntities = [
    for (final entity in entities)
      entity.withGraphAccess(relationshipOperations),
  ];
  late final List<SyncBindingSpec> syncBindings;
  try {
    syncBindings = resolveEntitySyncBindings(
      entities: resolvedEntities,
      defaultTarget: defaultSyncTarget,
    );
  } on StateError catch (error) {
    throw InvalidGenerationSourceError(error.message, element: element);
  }
  final syncByEntity = {
    for (final binding in syncBindings) binding.entity.className: binding,
  };
  for (final tracking in resolveActivityTrackings(resolvedEntities)) {
    final sourceBinding = syncByEntity[tracking.source.className]!;
    final entryBinding = syncByEntity[tracking.entry.className]!;
    if (sourceBinding.mode != entryBinding.mode ||
        sourceBinding.target?.stableIdentity !=
            entryBinding.target?.stableIdentity) {
      throw InvalidGenerationSourceError(
        '${tracking.source.className} and its activity entry '
        '`${tracking.entry.className}` must use the same sync mode and target.',
        element: element,
      );
    }
  }
  for (final aggregate in resolvedEntities) {
    for (final field in aggregate.fields.where(
      (field) => field.isComposition,
    )) {
      final aggregateBinding = syncByEntity[aggregate.className]!;
      final componentBinding = syncByEntity[field.reference!.targetClassName]!;
      if (aggregateBinding.mode != componentBinding.mode ||
          aggregateBinding.target?.stableIdentity !=
              componentBinding.target?.stableIdentity) {
        throw InvalidGenerationSourceError(
          '${aggregate.className}.${field.name} and its Component '
          '`${componentBinding.entity.className}` must use the same sync mode '
          'and target.',
          element: element,
        );
      }
    }
  }
  return EntityGraphSpec(
    className: className,
    packageName: packageName,
    inputImport: inputImport,
    schemaVersion: schemaVersion,
    entities: List<EntitySpec>.unmodifiable(resolvedEntities),
    defaultSyncTarget: defaultSyncTarget,
    syncBindings: syncBindings,
    outputBaseName: outputBaseName,
    emitsSyncTargetEnum: emitsSyncTargetEnum,
  );
}

SyncTargetSpec? _parseSyncTarget(
  ConstantReader? reader,
  Element element, {
  required String label,
}) {
  if (reader == null || reader.isNull) return null;
  final variable = reader.objectValue.variable;
  final enumElement = variable?.enclosingElement;
  final valueName = variable?.name;
  if (valueName == null ||
      enumElement is! EnumElement ||
      !enumElement.fields.any(
        (field) => field == variable && field.isEnumConstant,
      )) {
    throw InvalidGenerationSourceError(
      '$label must be one public enum constant.',
      element: element,
    );
  }
  final enumType = enumElement.name;
  if (enumType == null ||
      enumType.startsWith('_') ||
      valueName.startsWith('_')) {
    throw InvalidGenerationSourceError(
      '$label must use a public enum type and constant.',
      element: element,
    );
  }
  final enumImport = enumElement.library.uri.toString();
  if (!enumImport.startsWith('package:')) {
    throw InvalidGenerationSourceError(
      '$label must use an application-owned package enum.',
      element: element,
    );
  }
  return SyncTargetSpec(
    enumType: enumType,
    enumImport: enumImport,
    valueName: valueName,
    wireName: snakeCase(valueName),
  );
}

void _validateGraphEntities(List<EntitySpec> entities, Element element) {
  final separatelyOwned = entities.where(
    (entity) => entity.ownership == Ownership.separate,
  );
  final ownerTypes = (separatelyOwned.isEmpty ? entities : separatelyOwned)
      .map((entity) => entity.ownerClassName)
      .toSet();
  if (ownerTypes.length != 1) {
    throw InvalidGenerationSourceError(
      'Every separately owned entity in one graph must use the same '
      'OwnedBy Owner type so '
      'the generated entity graph has one nominal authenticated account '
      'identity. '
      'Found: ${ownerTypes.toList()..sort()}.',
      element: element,
    );
  }
  final classNames = <String>{};
  final tableNames = <String>{};
  final setAccessors = <String>{};
  for (final entity in entities) {
    if (!classNames.add(entity.className)) {
      throw InvalidGenerationSourceError(
        'Duplicate entity class `${entity.className}` in the graph.',
        element: element,
      );
    }
    if (!tableNames.add(entity.tableName)) {
      throw InvalidGenerationSourceError(
        'Duplicate entity table `${entity.tableName}` in the graph.',
        element: element,
      );
    }
    if (_generatedEntityGraphMemberNames.contains(entity.setAccessor)) {
      throw InvalidGenerationSourceError(
        'Entity-set accessor `${entity.setAccessor}` conflicts with a '
        'generated entity-graph member. Set `Entity.setAccessor` to an '
        'unambiguous lowerCamelCase name.',
        element: element,
      );
    }
    if (!setAccessors.add(entity.setAccessor)) {
      throw InvalidGenerationSourceError(
        'Duplicate entity-set accessor `${entity.setAccessor}` in the '
        'graph. Set `Entity.setAccessor` on one declaration.',
        element: element,
      );
    }
  }
  for (final entity in entities) {
    final listName = '${entity.className}List';
    if (classNames.contains(listName)) {
      throw InvalidGenerationSourceError(
        'Generated collection type `$listName` conflicts with an entity class '
        'in the graph. Rename the conflicting entity so every inferred '
        'collection has an unambiguous Dart type.',
        element: element,
      );
    }
  }
  for (final entity in entities) {
    final collaboration = entity.security.collaboration;
    if (collaboration?.isDirect == true &&
        !tableNames.add(collaboration!.membershipTable)) {
      throw InvalidGenerationSourceError(
        'Duplicate entity or collaboration table '
        '`${collaboration.membershipTable}` in the graph.',
        element: element,
      );
    }
  }
  final entitiesByClass = {
    for (final entity in entities) entity.className: entity,
  };
  final activityEntriesBySubject = <String, List<EntitySpec>>{};
  for (final entry in entities.where((entity) => entity.isActivityEntry)) {
    (activityEntriesBySubject[entry.activitySubjectClassName!] ??= []).add(
      entry,
    );
  }
  for (final source in entities.where(
    (entity) => entity.hasActivityTrackedCapability,
  )) {
    final entries = activityEntriesBySubject[source.className] ?? const [];
    if (entries.length != 1) {
      throw InvalidGenerationSourceError(
        '${source.className} implements ActivityTracked and requires exactly '
        'one @Entity implementing ActivityOf<${source.className}, '
        '${source.ownerClassName}> in the same graph.',
        element: element,
      );
    }
  }
  for (final entry in entities.where((entity) => entity.isActivityEntry)) {
    final source = entitiesByClass[entry.activitySubjectClassName];
    if (source == null || !source.hasActivityTrackedCapability) {
      throw InvalidGenerationSourceError(
        '${entry.className} declares ActivityOf<'
        '${entry.activitySubjectClassName}, ${entry.activityActorClassName}> '
        'but its subject is not an ActivityTracked entity in this graph.',
        element: element,
      );
    }
    if (entry.ownerClassName != source.ownerClassName ||
        entry.activityActorClassName != source.ownerClassName) {
      throw InvalidGenerationSourceError(
        '${entry.className} and ${source.className} must use the same '
        'authenticated owner/actor type.',
        element: element,
      );
    }
  }
  final inverseNamesByTarget = <String, Set<String>>{};
  final reservedGeneratedTypeNames = <String>{
    for (final entity in entities) ...[
      entity.className,
      '${entity.className}Rows',
      '${entity.className}Descriptor',
      '${entity.className}Record',
      '${entity.className}Fields',
      '${entity.className}Set',
      '${entity.className}List',
      '${entity.className}Lookup',
      '${entity.className}EditDraft',
      '${entity.className}Relationship',
      '${entity.className}Collaborators',
    ],
  };
  final inverseCreationTypes = <String, String>{};
  final composedTargets = <String>{};
  for (final entity in entities) {
    final explicitAccessTargets = entity.accessTargetFields
        .where((field) => !field.isComposition)
        .toList(growable: false);
    if (explicitAccessTargets.isNotEmpty &&
        entity.accessReferenceFields.isEmpty &&
        entity.participantFields.isEmpty) {
      throw InvalidGenerationSourceError(
        '`${entity.className}` declares @AccessTarget but has no '
        '@AccessReference or @AccessParticipant source.',
        element: element,
      );
    }
    for (final source in entity.accessReferenceFields.where(
      (field) => !field.isAccessTarget,
    )) {
      if (entity.accessTargetFields.isNotEmpty &&
          source.reference!.targetSelectPrincipals.contains(
            RlsPrincipal.authenticated,
          )) {
        throw InvalidGenerationSourceError(
          '@AccessTarget requires a finite source audience; broad '
          'authenticated access cannot publish deterministic snapshots and '
          'revocations.',
          element: element,
        );
      }
    }
    for (final field in entity.fields) {
      final reference = field.reference;
      if (reference == null) continue;
      final target = entitiesByClass[reference.targetClassName];
      if (target == null || target.inputImport != reference.targetInputImport) {
        throw InvalidGenerationSourceError(
          '${entity.className}.${field.name} references '
          '`${reference.targetClassName}`, which is not in this entity graph.',
          element: element,
        );
      }
      if (target.tableName != reference.targetTableName) {
        throw InvalidGenerationSourceError(
          'Reference metadata for ${entity.className}.${field.name} does not '
          'match the target entity declaration.',
          element: element,
        );
      }
      if (field.isAccessTarget) {
        final accessTarget = entitiesByClass[field.accessTargetClassName];
        if (accessTarget == null ||
            accessTarget.inputImport != field.accessTargetInputImport ||
            accessTarget.tableName != field.accessTargetTableName) {
          throw InvalidGenerationSourceError(
            'Access-target metadata for ${entity.className}.${field.name} '
            'does not match an entity in this graph.',
            element: element,
          );
        }
      }
      if (field.isComposition) {
        if (!target.isComponent) {
          throw InvalidGenerationSourceError(
            '@Composition target `${target.className}` must implement '
            'Component.',
            element: element,
          );
        }
        composedTargets.add(target.className);
      }
      if (field.isAccessReference &&
          target.security.grants.any(
            (grant) =>
                grant.operation == RlsOperation.select &&
                grant.principal == RlsPrincipal.reference,
          )) {
        throw InvalidGenerationSourceError(
          '@AccessReference cannot target another reference-authorized '
          'entity. Declare access through a stable owner, participant, '
          'collaborator, or authenticated endpoint.',
          element: element,
        );
      }
      final inverseNames = inverseNamesByTarget.putIfAbsent(
        reference.targetClassName,
        () => <String>{},
      );
      if (!inverseNames.add(reference.inverseName)) {
        throw InvalidGenerationSourceError(
          'Duplicate inverse relationship `${reference.targetClassName}.'
          '${reference.inverseName}` in the entity graph.',
          element: element,
        );
      }
      final generatesCreationRelationship =
          entity.activeRelationship == null &&
          entity.canCreate &&
          entity.createParameters.contains(field);
      if (generatesCreationRelationship) {
        final typeName = generatedInverseCreationTypeName(field);
        final origin = '${entity.className}.${field.name}';
        final previous = inverseCreationTypes[typeName];
        if (reservedGeneratedTypeNames.contains(typeName) || previous != null) {
          throw InvalidGenerationSourceError(
            'Generated inverse creation type `$typeName` for `$origin` '
            'conflicts with ${previous == null ? 'another generated/entity type' : '`$previous`'}. '
            'Set a more specific `Reference.inverse` name.',
            element: element,
          );
        }
        inverseCreationTypes[typeName] = origin;
      }
    }
  }
  for (final component in entities.where((entity) => entity.isComponent)) {
    if (!composedTargets.contains(component.className)) {
      throw InvalidGenerationSourceError(
        'Component `${component.className}` is not owned by any '
        '@Composition field in this entity graph.',
        element: element,
      );
    }
  }
  _validateRelationshipAccessGraph(entities, element);
  for (final target in entities.where(
    (entity) => entity.security.collaboration?.isWorkflow ?? false,
  )) {
    final collaboration = target.security.collaboration!;
    final memberships = entities
        .where((entity) => entity.tableName == collaboration.membershipTable)
        .toList(growable: false);
    final membership = memberships.length == 1 ? memberships.single : null;
    final workflow = membership?.workflowMembership;
    if (membership == null ||
        workflow == null ||
        workflow.targetClassName != target.className ||
        workflow.targetTableName != target.tableName) {
      throw InvalidGenerationSourceError(
        '`${target.className}` workflow collaboration requires one synchronized '
        '`${collaboration.membershipTable}` entity with its conventional target '
        'reference, participant, and status contract.',
        element: element,
      );
    }
  }
  final visiting = <String>{};
  final visited = <String>{};
  void visit(EntitySpec entity) {
    if (visited.contains(entity.className)) return;
    if (!visiting.add(entity.className)) {
      throw InvalidGenerationSourceError(
        'Cyclic entity references cannot be independently pushed or emitted '
        'as ordered inline foreign keys.',
        element: element,
      );
    }
    for (final field in entity.fields) {
      final target = field.reference?.targetClassName;
      if (target != null && target != entity.className) {
        visit(entitiesByClass[target]!);
      }
    }
    visiting.remove(entity.className);
    visited.add(entity.className);
  }

  for (final entity in entities) {
    visit(entity);
  }
}

void _validateRelationshipAccessGraph(
  List<EntitySpec> entities,
  Element element,
) {
  final edges = <String, Set<String>>{};
  for (final relationship in entities) {
    final sources = <String>{
      ...relationship.accessReferenceFields.map(
        (field) => field.reference!.targetClassName,
      ),
      if (relationship.accessTargetFields.any((field) => field.isComposition))
        relationship.className,
    };
    final targets = relationship.accessTargetFields
        .expand(
          (field) => {
            field.accessTargetClassName!,
            if (field.accessTargetThroughColumnName != null)
              field.reference!.targetClassName,
          },
        )
        .toSet();
    for (final source in sources) {
      edges.putIfAbsent(source, () => <String>{}).addAll(targets);
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  final path = <String>[];

  void visit(String entity) {
    if (visited.contains(entity)) return;
    final cycleStart = path.indexOf(entity);
    if (cycleStart >= 0) {
      final cycle = [...path.sublist(cycleStart), entity].join(' -> ');
      throw InvalidGenerationSourceError(
        'Relationship-derived access graph is cyclic: $cycle. '
        '@AccessReference/@AccessTarget paths must form a directed acyclic '
        'graph so authorization and change publication terminate.',
        element: element,
      );
    }
    if (!visiting.add(entity)) return;
    path.add(entity);
    for (final target in edges[entity] ?? const <String>{}) {
      visit(target);
    }
    path.removeLast();
    visiting.remove(entity);
    visited.add(entity);
  }

  for (final entity in edges.keys) {
    visit(entity);
  }
}

const _generatedEntityGraphMemberNames = <String>{
  'open',
  'syncQueue',
  'persistenceFailures',
  'nowUtc',
  'flushLocal',
  'transaction',
  'sync',
  'close',
  'runtimeType',
  'hashCode',
  'toString',
  'noSuchMethod',
};

void _validateSetAccessor(String value, Element element) {
  if (!_isLowerCamelDartIdentifier(value)) {
    throw InvalidGenerationSourceError(
      'Invalid entity-set accessor `$value`. Use a lowerCamelCase Dart identifier.',
      element: element,
    );
  }
}

ReferenceSpec _parseReference(
  FieldElement field,
  ClassElement owner,
  ConstantReader annotation, {
  required String ownerSetAccessor,
  String? ownershipTargetField,
  bool composition = false,
}) {
  final annotationName = composition ? '@Composition' : '@Reference';
  final fieldName = field.name!;
  if (!fieldName.endsWith('Id') || fieldName.length == 2) {
    throw InvalidGenerationSourceError(
      '$annotationName fields must use the `...Id` convention so the typed '
      'relationship accessor is deterministic.',
      element: field,
    );
  }
  final nonNullableType = field.type is InterfaceType
      ? field.type as InterfaceType
      : null;
  if (nonNullableType == null ||
      nonNullableType.element.name != 'LocalId' ||
      nonNullableType.typeArguments.length != 1) {
    throw InvalidGenerationSourceError(
      '$annotationName fields must have nominal type `LocalId<T>` or '
      '`LocalId<T>?`.',
      element: field,
    );
  }
  final targetType = nonNullableType.typeArguments.single;
  if (targetType is! InterfaceType || targetType.element is! ClassElement) {
    throw InvalidGenerationSourceError(
      'The LocalId type argument of $annotationName must be an entity class.',
      element: field,
    );
  }
  final target = targetType.element as ClassElement;
  if (composition &&
      !target.allSupertypes.any(_componentChecker.isExactlyType)) {
    throw InvalidGenerationSourceError(
      '@Composition target `${target.name}` must implement Component.',
      element: field,
    );
  }
  final targetAnnotationObject = _entityChecker.firstAnnotationOf(target);
  if (targetAnnotationObject == null) {
    throw InvalidGenerationSourceError(
      '`${target.name}` is not annotated with @Entity.',
      element: field,
    );
  }
  final targetAnnotation = ConstantReader(targetAnnotationObject);
  final targetOwnership = _readEnum(
    targetAnnotation.read('ownership'),
    Ownership.values,
  );
  final targetSecurity = _parseSecurity(
    targetAnnotation,
    target,
    ownership: targetOwnership,
  );
  final targetHasClientMutation = _hasClientMutationSurface(target);
  final targetOwnedByType = target.allSupertypes
      .where((type) => _ownedByChecker.isExactlyType(type))
      .firstOrNull;
  if (targetOwnedByType == null) {
    throw InvalidGenerationSourceError(
      'Referenced entity `${target.name}` must implement '
      'OwnedBy<${target.name}, Owner> so its identity contract is known.',
      element: field,
    );
  }
  if (composition) {
    if (!field.isFinal ||
        field.type.nullabilitySuffix == NullabilitySuffix.question) {
      throw InvalidGenerationSourceError(
        '@Composition requires an immutable, non-null LocalId<Component> '
        'field.',
        element: field,
      );
    }
    final sourceOwnedByType = owner.allSupertypes
        .where((type) => _ownedByChecker.isExactlyType(type))
        .firstOrNull;
    if (sourceOwnedByType == null ||
        sourceOwnedByType.typeArguments.last.getDisplayString() !=
            targetOwnedByType.typeArguments.last.getDisplayString()) {
      throw InvalidGenerationSourceError(
        '@Composition aggregate and component must use the same nominal '
        'OwnedBy owner type.',
        element: field,
      );
    }
  }
  final targetOwnerDartType = targetOwnership == Ownership.identity
      ? 'LocalId<${target.name}>'
      : 'LocalId<${targetOwnedByType.typeArguments.last.getDisplayString()}>';
  final targetOwnerFieldName = targetOwnership == Ownership.identity
      ? EntityConventions.idFieldName
      : EntityConventions.ownerFieldName;
  final targetOwnerColumnName = targetOwnership == Ownership.identity
      ? EntityConventions.idColumnName
      : EntityConventions.ownerColumnName;
  var ownershipSourceFieldName = targetOwnerFieldName;
  var ownershipSourceColumnName = targetOwnerColumnName;
  var ownershipSourceDartType = targetOwnerDartType;
  if (ownershipTargetField != null) {
    final candidates = target.fields.where(
      (candidate) => candidate.name == ownershipTargetField,
    );
    if (candidates.length != 1) {
      throw InvalidGenerationSourceError(
        '@OwnerReference.targetField must name one declared field on '
        '`${target.name}`.',
        element: field,
      );
    }
    final source = candidates.single;
    if (source.isStatic ||
        source.isOriginGetterSetter ||
        _transientChecker.hasAnnotationOf(source) ||
        !source.isFinal ||
        source.type.nullabilitySuffix == NullabilitySuffix.question) {
      throw InvalidGenerationSourceError(
        '@OwnerReference.targetField must be an immutable, non-null '
        'persisted field.',
        element: field,
      );
    }
    ownershipSourceDartType = source.type.getDisplayString();
    if (ownershipSourceDartType != targetOwnerDartType) {
      throw InvalidGenerationSourceError(
        '@OwnerReference.targetField must have the referenced entity owner '
        'type `$targetOwnerDartType`.',
        element: field,
      );
    }
    final persistedObject = _persistedChecker.firstAnnotationOf(source);
    final persisted = persistedObject == null
        ? null
        : ConstantReader(persistedObject);
    ownershipSourceFieldName = ownershipTargetField;
    ownershipSourceColumnName = persisted?.peek('column')?.isNull ?? true
        ? snakeCase(ownershipTargetField)
        : persisted!.read('column').stringValue;
  }
  final onDelete = composition
      ? ReferenceDeleteAction.restrict
      : _readEnum(annotation.read('onDelete'), ReferenceDeleteAction.values);
  final nullable = field.type.nullabilitySuffix == NullabilitySuffix.question;
  if (onDelete == ReferenceDeleteAction.setNull && !nullable) {
    throw InvalidGenerationSourceError(
      'ReferenceDeleteAction.setNull requires a nullable LocalId field.',
      element: field,
    );
  }
  final accessorName = fieldName.substring(0, fieldName.length - 2);
  if (owner.fields.any((candidate) => candidate.name == accessorName) ||
      owner.methods.any((candidate) => candidate.name == accessorName)) {
    throw InvalidGenerationSourceError(
      '`$accessorName` is reserved for the generated relationship accessor.',
      element: field,
    );
  }
  final inverseName = annotation.peek('inverse')?.isNull ?? true
      ? ownerSetAccessor
      : annotation.read('inverse').stringValue;
  if (!_isLowerCamelDartIdentifier(inverseName)) {
    throw InvalidGenerationSourceError(
      'Reference.inverse must be a lowerCamelCase Dart identifier.',
      element: field,
    );
  }
  if (target.fields.any((candidate) => candidate.name == inverseName) ||
      target.methods.any((candidate) => candidate.name == inverseName)) {
    throw InvalidGenerationSourceError(
      '`${target.name}.$inverseName` is reserved for the generated inverse '
      'relationship query.',
      element: field,
    );
  }
  return ReferenceSpec(
    targetClassName: target.name!,
    targetInputImport: target.library.uri.toString(),
    targetTableName: targetAnnotation.peek('table')?.isNull ?? true
        ? pluralSnakeCase(target.name!)
        : targetAnnotation.read('table').stringValue,
    accessorName: accessorName,
    inverseName: inverseName,
    onDelete: onDelete,
    targetSelectPrincipals:
        targetSecurity.grants
            .where((grant) => grant.operation == RlsOperation.select)
            .map((grant) => grant.principal)
            .toSet()
            .toList()
          ..sort((left, right) => left.index.compareTo(right.index)),
    targetOwnerOperations:
        targetSecurity.grants
            .where((grant) => grant.principal == RlsPrincipal.owner)
            .map((grant) => grant.operation)
            .toSet()
            .toList()
          ..sort((left, right) => left.index.compareTo(right.index)),
    targetOwnerDartType: targetOwnerDartType,
    targetOwnerColumnName: targetOwnerColumnName,
    ownershipSourceFieldName: ownershipSourceFieldName,
    ownershipSourceColumnName: ownershipSourceColumnName,
    ownershipSourceDartType: ownershipSourceDartType,
    targetCollaboration: targetSecurity.collaboration,
    targetRelationshipAccessOperations: targetSecurity.grants
        .where((grant) => grant.principal == RlsPrincipal.relationship)
        .map((grant) => grant.operation)
        .where(
          (operation) =>
              operation != RlsOperation.update || targetHasClientMutation,
        )
        .toList(growable: false),
  );
}

bool _hasClientMutationSurface(ClassElement target) {
  if (target.methods.any(_actionChecker.hasAnnotationOf)) return true;
  if (target.allSupertypes.any(
    (type) => _isNodusCapability(type, 'ActivityOf'),
  )) {
    return false;
  }
  return target.fields.any((field) {
    if (field.isStatic ||
        field.isOriginGetterSetter ||
        _transientChecker.hasAnnotationOf(field) ||
        !field.isFinal ||
        _referenceChecker.hasAnnotationOf(field) ||
        _compositionChecker.hasAnnotationOf(field) ||
        const {
          EntityConventions.idFieldName,
          EntityConventions.ownerFieldName,
          EntityConventions.createdAtFieldName,
          EntityConventions.updatedAtFieldName,
          EntityConventions.deletedAtFieldName,
          EntityConventions.archivedAtFieldName,
          EntityConventions.orderRankFieldName,
          EntityConventions.serverVersionFieldName,
        }.contains(field.name)) {
      return false;
    }
    final object = _persistedChecker.firstAnnotationOf(field);
    if (object == null) return true;
    final persisted = ConstantReader(object);
    final editable = persisted.peek('editable');
    if (editable != null && !editable.isNull && !editable.boolValue) {
      return false;
    }
    if (_readEnum(persisted.read('authority'), FieldAuthority.values) ==
        FieldAuthority.server) {
      return false;
    }
    return persisted.read('transitions').listValue.isEmpty;
  });
}

bool _isLowerCamelDartIdentifier(String value) =>
    RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(value) &&
    Keyword.keywords[value]?.isReservedWord != true;

List<ActionSpec> _parseActions(
  ClassElement classElement,
  List<FieldSpec> fields,
) {
  final fieldsByName = {for (final field in fields) field.name: field};
  final declarationsByName = {
    for (final field in classElement.fields) field.name: field,
  };
  final reservedBeginEdit = classElement.methods
      .where((method) => method.name == 'beginEdit')
      .firstOrNull;
  if (reservedBeginEdit != null) {
    throw InvalidGenerationSourceError(
      '`beginEdit` is reserved for the generated typed edit draft.',
      element: reservedBeginEdit,
    );
  }
  final actions = <ActionSpec>[];
  for (final method in classElement.methods) {
    final object = _actionChecker.firstAnnotationOf(method);
    if (object == null) continue;
    if (method.name == 'edit') {
      throw InvalidGenerationSourceError(
        '`edit` is not a semantic action name. Use the generated `beginEdit` '
        'draft for ordinary fields, or name the action for its domain meaning.',
        element: method,
      );
    }
    if (method.isStatic ||
        method.isPrivate ||
        !method.isAbstract ||
        method.returnType.getDisplayString() != 'Future<void>' ||
        method.typeParameters.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'An entity action must be an abstract, non-generic '
        'Future<void> method.',
        element: method,
      );
    }
    if (_syncCommandChecker.hasAnnotationOf(method)) {
      throw InvalidGenerationSourceError(
        'A method cannot be both an Action and a SyncCommand.',
        element: method,
      );
    }
    final parameters = <ActionParameterSpec>[];
    final targets = <String>{};
    for (final parameter in method.formalParameters) {
      if (!parameter.isRequiredNamed && !parameter.isRequiredPositional) {
        throw InvalidGenerationSourceError(
          'Entity action parameters must be required so omission cannot be '
          'confused with a persisted value.',
          element: parameter,
        );
      }
      final name = parameter.name!;
      final field = fieldsByName[name];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'Entity action parameter `$name` must match a persisted field.',
          element: parameter,
        );
      }
      final parameterType = parameter.type.getDisplayString();
      final safelyNarrowsNullableField =
          field.nullable &&
          parameterType ==
              field.dartType.substring(0, field.dartType.length - 1);
      if (parameterType != field.dartType && !safelyNarrowsNullableField) {
        throw InvalidGenerationSourceError(
          'Entity action parameter `$name` type `$parameterType` must match '
          'persisted field type `${field.dartType}` or safely narrow its '
          'nullability.',
          element: parameter,
        );
      }
      _validateActionTarget(
        field,
        method,
        isAbstract: declarationsByName[name]?.isAbstract ?? false,
      );
      targets.add(name);
      parameters.add(
        ActionParameterSpec(
          name: name,
          dartType: parameterType,
          named: parameter.isRequiredNamed,
        ),
      );
    }

    final assignments = <ActionAssignmentSpec>[];
    final annotation = ConstantReader(object);
    for (final assignmentObject in annotation.read('values').listValue) {
      final assignment = ConstantReader(assignmentObject);
      final fieldName = assignment.read('field').objectValue.toSymbolValue();
      final field = fieldName == null ? null : fieldsByName[fieldName];
      if (field == null) {
        throw InvalidGenerationSourceError(
          'Entity action values must target persisted field symbols.',
          element: method,
        );
      }
      if (!targets.add(fieldName!)) {
        throw InvalidGenerationSourceError(
          'Entity action `${method.name}` assigns `$fieldName` more than once.',
          element: method,
        );
      }
      _validateActionTarget(
        field,
        method,
        isAbstract: declarationsByName[fieldName]?.isAbstract ?? false,
      );
      final kind = _readEnum(assignment.read('kind'), ActionValueKind.values);
      final literal = switch (kind) {
        ActionValueKind.literal => _parseActionLiteral(
          assignment.read('value').objectValue,
          field,
          method,
        ),
        ActionValueKind.clockNow => _validateActionClock(field, method),
        ActionValueKind.clear => _validateActionClear(field, method),
      };
      assignments.add(
        ActionAssignmentSpec(
          fieldName: fieldName,
          kind: kind,
          literal: literal,
        ),
      );
    }
    if (targets.isEmpty) {
      throw InvalidGenerationSourceError(
        'Entity action `${method.name}` must mutate at least one field.',
        element: method,
      );
    }
    actions.add(
      ActionSpec(
        methodName: method.name!,
        parameters: List.unmodifiable(parameters),
        assignments: List.unmodifiable(assignments),
      ),
    );
  }
  return List.unmodifiable(actions);
}

void _validateActionTarget(
  FieldSpec field,
  Element element, {
  required bool isAbstract,
}) {
  if (!isAbstract ||
      !field.isFinal ||
      field.isId ||
      field.serverGenerated ||
      field.autoUpdated ||
      field.isServerManaged ||
      field.name == EntityConventions.ownerFieldName ||
      field.name == EntityConventions.deletedAtFieldName ||
      field.name == EntityConventions.serverVersionFieldName) {
    throw InvalidGenerationSourceError(
      'Entity action target `${field.name}` must be an abstract final, '
      'client-authoritative domain field.',
      element: element,
    );
  }
}

Object _parseActionLiteral(DartObject value, FieldSpec field, Element element) {
  if (value.isNull) {
    throw InvalidGenerationSourceError(
      'Use ActionValue.clear(#${field.name}) for a null assignment.',
      element: element,
    );
  }
  if (field.isEnum) {
    final variable = value.variable;
    final declaringEnum = variable?.enclosingElement;
    final name = variable?.name;
    if (name == null ||
        declaringEnum is! EnumElement ||
        declaringEnum.name != field.dartType.replaceAll('?', '') ||
        declaringEnum.library.uri.toString() != field.enumTypeImport ||
        !field.enumValues.contains(name)) {
      throw InvalidGenerationSourceError(
        'Entity action value for `${field.name}` must use its enum type '
        '`${field.dartType}`.',
        element: element,
      );
    }
    return name;
  }
  final literal = switch (field.dartType.replaceAll('?', '')) {
    'String' => value.toStringValue(),
    'bool' => value.toBoolValue(),
    'int' => value.toIntValue(),
    'double' => value.toDoubleValue() ?? value.toIntValue()?.toDouble(),
    _ => null,
  };
  if (literal == null) {
    throw InvalidGenerationSourceError(
      'Entity action literal values support String, bool, int, double, and enum '
      'fields. Use a typed method parameter for `${field.name}`.',
      element: element,
    );
  }
  _validateActionLiteralBounds(field, literal, element);
  return literal;
}

void _validateActionLiteralBounds(
  FieldSpec field,
  Object literal,
  Element element,
) {
  if (literal is String &&
      ((field.minLength != null && literal.trim().length < field.minLength!) ||
          (field.maxLength != null && literal.length > field.maxLength!) ||
          (field.allowedValues.isNotEmpty &&
              !field.allowedValues.contains(literal)))) {
    throw InvalidGenerationSourceError(
      'Entity action literal for `${field.name}` violates its validation '
      'constraints.',
      element: element,
    );
  }
  if (literal is num &&
      ((field.minValue != null && literal < field.minValue!) ||
          (field.maxValue != null && literal > field.maxValue!))) {
    throw InvalidGenerationSourceError(
      'Entity action literal for `${field.name}` violates its numeric bounds.',
      element: element,
    );
  }
}

Object? _validateActionClock(FieldSpec field, Element element) {
  if (field.dartType.replaceAll('?', '') != 'DateTime') {
    throw InvalidGenerationSourceError(
      'ActionValue.clockNow requires a DateTime field.',
      element: element,
    );
  }
  return null;
}

Object? _validateActionClear(FieldSpec field, Element element) {
  if (!field.nullable) {
    throw InvalidGenerationSourceError(
      'ActionValue.clear requires a nullable field.',
      element: element,
    );
  }
  return null;
}

void _validateTransitionTargets(
  ClassElement element,
  List<FieldSpec> fields,
  List<ActionSpec> actions,
) {
  final actionTargets = actions.expand((action) => action.targetFields).toSet();
  for (final field in fields.where((field) => field.transitions.isNotEmpty)) {
    if (!field.isMutable && !actionTargets.contains(field.name)) {
      throw InvalidGenerationSourceError(
        'Transitioned enum `${field.name}` must be mutable or targeted by an '
        'Action.',
        element: element,
      );
    }
  }
}

List<CommandSpec> _parseCommands(
  ClassElement classElement,
  List<FieldSpec> fields,
) {
  final commands = <CommandSpec>[];
  for (final method in classElement.methods) {
    final object = _syncCommandChecker.firstAnnotationOf(method);
    final conventionalRemove =
        object == null &&
        method.name == 'remove' &&
        method.isAbstract &&
        method.formalParameters.isEmpty &&
        method.returnType.getDisplayString() == 'Future<void>' &&
        fields.any(
          (field) => field.name == EntityConventions.deletedAtFieldName,
        );
    final conventionalRestore =
        object == null &&
        method.name == 'restore' &&
        method.isAbstract &&
        method.formalParameters.isEmpty &&
        method.returnType.getDisplayString() == 'Future<void>' &&
        fields.any(
          (field) => field.name == EntityConventions.deletedAtFieldName,
        );
    if (object == null && !conventionalRemove && !conventionalRestore) {
      continue;
    }
    final annotation = object == null ? null : ConstantReader(object);
    final targetField = conventionalRemove || conventionalRestore
        ? EntityConventions.deletedAtFieldName
        : annotation!.read('targetField').stringValue;
    final value = conventionalRemove
        ? SyncCommandValue.clockNow
        : conventionalRestore
        ? SyncCommandValue.clear
        : _readEnum(annotation!.read('value'), SyncCommandValue.values);
    final field = fields
        .where((field) => field.name == targetField)
        .firstOrNull;
    if (field == null) {
      throw InvalidGenerationSourceError(
        'Sync command targetField `$targetField` is not persisted.',
        element: method,
      );
    }
    if (!method.isAbstract) {
      throw InvalidGenerationSourceError(
        'A field sync command must be abstract.',
        element: method,
      );
    }
    if (method.returnType.getDisplayString() != 'Future<void>' ||
        method.typeParameters.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'A field sync command must be a non-generic Future<void> method.',
        element: method,
      );
    }
    String? parameterName;
    String? parameterType;
    switch (value) {
      case SyncCommandValue.parameter:
        if (method.formalParameters.length != 1) {
          throw InvalidGenerationSourceError(
            'A parameter-valued sync command must declare exactly one parameter.',
            element: method,
          );
        }
        final parameter = method.formalParameters.single;
        if (!parameter.isRequiredPositional) {
          throw InvalidGenerationSourceError(
            'A parameter-valued sync command must use one required positional '
            'parameter.',
            element: method,
          );
        }
        parameterName = parameter.name;
        parameterType = parameter.type.getDisplayString();
        if (parameterType != field.dartType.replaceAll('?', '')) {
          throw InvalidGenerationSourceError(
            '`${method.name}` parameter type `$parameterType` must match the '
            'non-null target field type `${field.dartType.replaceAll('?', '')}`.',
            element: method,
          );
        }
      case SyncCommandValue.clockNow:
        if (method.formalParameters.isNotEmpty ||
            field.sqlType != SqlType.timestampWithTimeZone) {
          throw InvalidGenerationSourceError(
            'A clock-valued sync command must declare no parameters and target '
            'a timestamp field.',
            element: method,
          );
        }
      case SyncCommandValue.clear:
        if (method.formalParameters.isNotEmpty || !field.nullable) {
          throw InvalidGenerationSourceError(
            'A clear-valued sync command must declare no parameters and target '
            'a nullable field.',
            element: method,
          );
        }
    }
    if (field.serverGenerated || field.isServerManaged) {
      throw InvalidGenerationSourceError(
        'A sync command cannot target server-authoritative `${field.name}`.',
        element: method,
      );
    }
    if (field.isMutable) {
      throw InvalidGenerationSourceError(
        'A sync command target `${field.name}` must be read-only. The generated '
        'command is the field\'s only public transition.',
        element: method,
      );
    }
    commands.add(
      CommandSpec(
        methodName: method.name!,
        targetField: targetField,
        parameterName: parameterName,
        parameterType: parameterType,
        value: value,
      ),
    );
  }
  return commands;
}

void _validateProtocolEvolution(
  ClassElement element, {
  required int protocolVersion,
  required List<FieldSpec> fields,
}) {
  final currentFieldNames = fields.map((field) => field.name).toSet();
  final historicalNames = <String>{};
  for (final field in fields) {
    if (field.sinceProtocolVersion < 1 ||
        field.sinceProtocolVersion > protocolVersion) {
      throw InvalidGenerationSourceError(
        '`${field.name}` sinceProtocolVersion must be between 1 and '
        'the entity protocolVersion ($protocolVersion).',
        element: element,
      );
    }
    final renamedFrom = field.renamedFrom;
    if (renamedFrom != null) {
      if (field.sinceProtocolVersion == 1 ||
          !RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(renamedFrom) ||
          currentFieldNames.contains(renamedFrom) ||
          !historicalNames.add(renamedFrom)) {
        throw InvalidGenerationSourceError(
          '`${field.name}` renamedFrom must be a unique historical lowerCamelCase '
          'key on a field introduced after protocol version 1.',
          element: element,
        );
      }
    }
    if (field.sinceProtocolVersion > 1 &&
        field.inCreatePayload &&
        field.defaultValue == null &&
        !field.nullable &&
        !field.isId) {
      throw InvalidGenerationSourceError(
        '`${field.name}` needs a defaultValue (or must be nullable) so retained '
        'create operations can be upcast deterministically.',
        element: element,
      );
    }
  }
}

void _validateEntity(
  ClassElement element,
  List<FieldSpec> fields, {
  required Ownership ownership,
}) {
  if (fields.where((field) => field.isId).length != 1) {
    throw InvalidGenerationSourceError(
      'A local entity must have exactly one conventional `id` field.',
      element: element,
    );
  }
  if (!fields.any(
    (field) =>
        field.name == EntityConventions.serverVersionFieldName &&
        field.serverGenerated,
  )) {
    throw InvalidGenerationSourceError(
      'A synchronized entity must declare a server-generated `serverVersion` field.',
      element: element,
    );
  }
  final idField = fields.singleWhere((field) => field.isId);
  for (final field in fields) {
    if (field.transitions.isNotEmpty && field.defaultValue == null) {
      throw InvalidGenerationSourceError(
        'Transitioned enum `${field.name}` must declare its single initial '
        'state as a field initializer or Persisted.defaultValue.',
        element: element,
      );
    }
    if (field.indexScope == IndexScope.owner &&
        ownership != Ownership.separate) {
      throw InvalidGenerationSourceError(
        '`${field.name}` cannot use an owner-scoped index when entity '
        'ownership is identity-based.',
        element: element,
      );
    }
  }
  if (idField.dartType != 'LocalId<${element.name}>') {
    throw InvalidGenerationSourceError(
      'Entity IDs must use the exact nominal `LocalId<${element.name}>` type.',
      element: element,
    );
  }
  if (!idField.isFinal || idField.nullable || idField.sqlType != SqlType.uuid) {
    throw InvalidGenerationSourceError(
      'Entity IDs must be immutable, non-null UUID fields.',
      element: element,
    );
  }
  final serverVersion = fields.singleWhere(
    (field) =>
        field.name == EntityConventions.serverVersionFieldName &&
        field.serverGenerated,
  );
  if (serverVersion.dartType != 'ServerVersion' || !serverVersion.isFinal) {
    throw InvalidGenerationSourceError(
      '`serverVersion` must be an immutable, server-generated ServerVersion.',
      element: element,
    );
  }
  if (serverVersion.sqlType != SqlType.integer || serverVersion.nullable) {
    throw InvalidGenerationSourceError(
      '`serverVersion` must be a non-null integer column.',
      element: element,
    );
  }
  final tombstone = fields
      .where((field) => field.name == EntityConventions.deletedAtFieldName)
      .firstOrNull;
  if (tombstone != null &&
      (tombstone.dartType != 'DateTime?' ||
          tombstone.sqlType != SqlType.timestampWithTimeZone ||
          !tombstone.isFinal ||
          tombstone.serverGenerated)) {
    throw InvalidGenerationSourceError(
      '`deletedAt` must be an immutable, nullable, client-commanded DateTime.',
      element: element,
    );
  }
  final createdAt = fields
      .where((field) => field.name == EntityConventions.createdAtFieldName)
      .firstOrNull;
  if (createdAt != null &&
      (createdAt.dartType != 'DateTime' ||
          !createdAt.isFinal ||
          !createdAt.serverGenerated)) {
    throw InvalidGenerationSourceError(
      '`createdAt` is conventionally an immutable, non-null, server-generated DateTime.',
      element: element,
    );
  }
  final updatedAt = fields
      .where((field) => field.name == EntityConventions.updatedAtFieldName)
      .firstOrNull;
  if (updatedAt != null && !updatedAt.autoUpdated) {
    throw InvalidGenerationSourceError(
      '`updatedAt` is conventionally an immutable, non-null, automatically '
      'maintained DateTime.',
      element: element,
    );
  }
  final columnNames = fields.map((field) => field.columnName).toList();
  if (columnNames.toSet().length != columnNames.length) {
    throw InvalidGenerationSourceError(
      'Persisted SQL column names must be unique within an entity.',
      element: element,
    );
  }
  for (final field in fields) {
    if (field.isServerManaged) {
      if (!field.isFinal) {
        throw InvalidGenerationSourceError(
          'Server-authoritative `${field.name}` must be final so domain code '
          'cannot mutate it.',
          element: element,
        );
      }
      if (field.conflict != ConflictStrategy.serverWins) {
        throw InvalidGenerationSourceError(
          'Server-authoritative `${field.name}` must use serverWins conflict '
          'resolution.',
          element: element,
        );
      }
      if (field.serverGenerated || field.autoUpdated || field.isId) {
        throw InvalidGenerationSourceError(
          '`${field.name}` already has conventional infrastructure authority '
          'and must not repeat it with FieldAuthority.server.',
          element: element,
        );
      }
      if (!field.nullable && field.defaultValue == null) {
        throw InvalidGenerationSourceError(
          'Non-null server-authoritative `${field.name}` needs a local and SQL '
          'default.',
          element: element,
        );
      }
    }
    if (field.serverGenerated && field.isMutable) {
      throw InvalidGenerationSourceError(
        '`${field.name}` is server-generated and cannot have a public setter.',
        element: element,
      );
    }
    if (field.minLength != null &&
        ((field.dartType.replaceAll('?', '') != 'String' &&
                field.scalarValue?.wireDartType != 'String') ||
            field.minLength! < 1)) {
      throw InvalidGenerationSourceError(
        '`minLength` is only valid for String fields and must be positive.',
        element: element,
      );
    }
    if (field.maxLength != null &&
        ((field.dartType.replaceAll('?', '') != 'String' &&
                field.scalarValue?.wireDartType != 'String') ||
            field.maxLength! < 1 ||
            (field.minLength != null && field.maxLength! < field.minLength!))) {
      throw InvalidGenerationSourceError(
        '`maxLength` is only valid for String fields, must be '
        'positive, and cannot be less than `minLength`.',
        element: element,
      );
    }
    if (field.minValue != null &&
        field.sqlType != SqlType.integer &&
        field.sqlType != SqlType.real) {
      throw InvalidGenerationSourceError(
        '`minValue` is only valid for numeric fields.',
        element: element,
      );
    }
    if (field.maxValue != null &&
        ((field.sqlType != SqlType.integer && field.sqlType != SqlType.real) ||
            (field.minValue != null && field.maxValue! < field.minValue!))) {
      throw InvalidGenerationSourceError(
        '`maxValue` is only valid for numeric fields and cannot be less than '
        '`minValue`.',
        element: element,
      );
    }
    if (field.allowedValues.isNotEmpty) {
      if (field.dartType.replaceAll('?', '') != 'String' &&
          field.scalarValue?.wireDartType != 'String') {
        throw InvalidGenerationSourceError(
          '`allowedValues` is only valid for String fields.',
          element: element,
        );
      }
      if (field.allowedValues.toSet().length != field.allowedValues.length) {
        throw InvalidGenerationSourceError(
          '`allowedValues` must not contain duplicates.',
          element: element,
        );
      }
      for (final value in field.allowedValues) {
        if ((field.minLength != null &&
                value.trim().length < field.minLength!) ||
            (field.maxLength != null && value.length > field.maxLength!)) {
          throw InvalidGenerationSourceError(
            'Every `${field.name}.allowedValues` entry must satisfy its '
            'length bounds.',
            element: element,
          );
        }
      }
      if (field.defaultValue case final String defaultValue
          when !field.allowedValues.contains(defaultValue)) {
        throw InvalidGenerationSourceError(
          'The default for `${field.name}` must be in `allowedValues`.',
          element: element,
        );
      }
    }
    if (field.greaterThan case final otherName?) {
      final other = fields.where((candidate) => candidate.name == otherName);
      if (other.length != 1 || otherName == field.name) {
        throw InvalidGenerationSourceError(
          '`${field.name}.greaterThan` must name another persisted field.',
          element: element,
        );
      }
      final fieldType = field.dartType.replaceAll('?', '');
      final otherType = other.single.dartType.replaceAll('?', '');
      if ((fieldType != 'int' && fieldType != 'double') ||
          otherType != fieldType) {
        throw InvalidGenerationSourceError(
          '`greaterThan` is only valid between fields of the same numeric type.',
          element: element,
        );
      }
    }
    if (field.greaterThanOrEqual case final otherName?) {
      final other = fields.where((candidate) => candidate.name == otherName);
      if (other.length != 1 || otherName == field.name) {
        throw InvalidGenerationSourceError(
          '`${field.name}.greaterThanOrEqual` must name another persisted field.',
          element: element,
        );
      }
      final fieldType = field.dartType.replaceAll('?', '');
      final otherType = other.single.dartType.replaceAll('?', '');
      if ((fieldType != 'int' && fieldType != 'double') ||
          otherType != fieldType) {
        throw InvalidGenerationSourceError(
          '`greaterThanOrEqual` is only valid between fields of the same numeric type.',
          element: element,
        );
      }
    }
    if (field.requires case final otherName?) {
      final other = fields.where((candidate) => candidate.name == otherName);
      if (other.length != 1 || otherName == field.name) {
        throw InvalidGenerationSourceError(
          '`${field.name}.requires` must name another persisted field.',
          element: element,
        );
      }
      if (!field.nullable || !other.single.nullable) {
        throw InvalidGenerationSourceError(
          '`requires` is only meaningful between nullable fields.',
          element: element,
        );
      }
    }
    if (field.notEqualTo case final otherName?) {
      final other = fields.where((candidate) => candidate.name == otherName);
      if (other.length != 1 || otherName == field.name) {
        throw InvalidGenerationSourceError(
          '`${field.name}.notEqualTo` must name another persisted field.',
          element: element,
        );
      }
      final fieldType = field.dartType.replaceAll('?', '');
      final otherType = other.single.dartType.replaceAll('?', '');
      if (fieldType != otherType) {
        throw InvalidGenerationSourceError(
          '`notEqualTo` requires two scalar fields with the same Dart type.',
          element: element,
        );
      }
    }
    final defaultValue = field.defaultValue;
    if (defaultValue is num &&
        ((field.minValue != null && defaultValue < field.minValue!) ||
            (field.maxValue != null && defaultValue > field.maxValue!))) {
      throw InvalidGenerationSourceError(
        'The default for `${field.name}` must satisfy its numeric bounds.',
        element: element,
      );
    }
  }
}

SecuritySpec _parseSecurity(
  ConstantReader annotation,
  ClassElement element, {
  required Ownership ownership,
  List<FieldSpec>? fields,
  List<CommandSpec>? commands,
  List<ActionSpec>? actions,
}) {
  final collaborationReader = annotation.peek('collaboration');
  final hasCollaborativeCapability = element.allSupertypes.any(
    (type) => _isNodusCapability(type, 'Collaborative'),
  );
  final hasExplicitCollaboration =
      collaborationReader != null && !collaborationReader.isNull;
  final hasCollaboration =
      hasCollaborativeCapability || hasExplicitCollaboration;
  final configuredGrants = annotation.peek('grants');
  final hasAccessReference =
      fields?.any((field) => field.isAccessReference) ??
      element.fields.any(_accessReferenceChecker.hasAnnotationOf);
  final isComponent = element.allSupertypes.any(
    _componentChecker.isExactlyType,
  );
  final isActivityEntry = element.allSupertypes.any(
    (type) => _isNodusCapability(type, 'ActivityOf'),
  );
  final grants = configuredGrants == null || configuredGrants.isNull
      ? _inferSecurityGrants(
          ownership: ownership,
          fields: fields,
          commands: commands,
          actions: actions,
          hasCollaboration: hasCollaboration,
          hasAccessReference: hasAccessReference,
          isComponent: isComponent,
          isActivityEntry: isActivityEntry,
        )
      : configuredGrants.listValue
            .map((object) {
              final grant = ConstantReader(object);
              return GrantSpec(
                operation: _readEnum(
                  grant.read('operation'),
                  RlsOperation.values,
                ),
                principal: _readEnum(
                  grant.read('principal'),
                  RlsPrincipal.values,
                ),
              );
            })
            .toList(growable: false);
  final grantKeys = grants
      .map((grant) => '${grant.operation.name}:${grant.principal.name}')
      .toSet();
  if (grantKeys.length != grants.length) {
    throw InvalidGenerationSourceError(
      'RLS grants must be unique within an entity.',
      element: element,
    );
  }
  final referenceAccessGuards = annotation
      .read('referenceAccessGuards')
      .listValue
      .map(
        (operation) =>
            _readEnum(ConstantReader(operation), RlsOperation.values),
      )
      .toList(growable: false);
  if (referenceAccessGuards.toSet().length != referenceAccessGuards.length) {
    throw InvalidGenerationSourceError(
      '`referenceAccessGuards` operations must be unique.',
      element: element,
    );
  }
  if (referenceAccessGuards.any(
    (operation) =>
        operation == RlsOperation.select || operation == RlsOperation.insert,
  )) {
    throw InvalidGenerationSourceError(
      '`referenceAccessGuards` supports update and delete only. Declare read '
      'visibility with an RLS reference grant; create reference access is '
      'already inferred.',
      element: element,
    );
  }

  CollaborationSpec? collaboration;
  if (hasCollaboration) {
    final lifecycle = hasExplicitCollaboration
        ? _readEnum(
            collaborationReader.read('lifecycle'),
            CollaborationLifecycle.values,
          )
        : CollaborationLifecycle.direct;
    if (hasCollaborativeCapability &&
        lifecycle != CollaborationLifecycle.direct) {
      throw InvalidGenerationSourceError(
        'Collaborative<Principal> declares direct collaborator mutation and '
        'cannot use workflow collaboration.',
        element: element,
      );
    }
    final entityBase = snakeCase(element.name!);
    final membershipTable =
        !hasExplicitCollaboration ||
            (collaborationReader.peek('membershipTable')?.isNull ?? true)
        ? '${entityBase}_members'
        : collaborationReader.read('membershipTable').stringValue;
    final entityForeignKey =
        !hasExplicitCollaboration ||
            (collaborationReader.peek('entityForeignKey')?.isNull ?? true)
        ? '${entityBase}_id'
        : collaborationReader.read('entityForeignKey').stringValue;
    final userForeignKey =
        !hasExplicitCollaboration ||
            (collaborationReader.peek('userForeignKey')?.isNull ?? true)
        ? lifecycle == CollaborationLifecycle.direct
              ? 'user_id'
              : 'member_id'
        : collaborationReader.read('userForeignKey').stringValue;
    final activeField = lifecycle == CollaborationLifecycle.direct
        ? !hasExplicitCollaboration ||
                  (collaborationReader.peek('activeField')?.isNull ?? true)
              ? 'active'
              : collaborationReader.read('activeField').stringValue
        : null;
    final statusField = lifecycle == CollaborationLifecycle.workflow
        ? !hasExplicitCollaboration ||
                  (collaborationReader.peek('statusField')?.isNull ?? true)
              ? 'status'
              : collaborationReader.read('statusField').stringValue
        : null;
    final acceptedState = hasExplicitCollaboration
        ? collaborationReader.peek('acceptedState')
        : null;
    String? acceptedValue;
    String? acceptedEnumType;
    String? acceptedEnumImport;
    final additionalReadableValues = <String>[];
    String? readableEnumType;
    String? readableEnumImport;
    if (lifecycle == CollaborationLifecycle.workflow) {
      if (acceptedState == null || acceptedState.isNull) {
        acceptedValue = 'accepted';
      } else {
        final variable = acceptedState.objectValue.variable;
        final enumElement = variable?.enclosingElement;
        final name = variable?.name;
        if (name == null ||
            enumElement is! EnumElement ||
            !enumElement.fields.any(
              (field) => field == variable && field.isEnumConstant,
            )) {
          throw InvalidGenerationSourceError(
            'CollaborationAccess.workflow acceptedState must be an enum '
            'constant.',
            element: element,
          );
        }
        acceptedValue = snakeCase(name);
        acceptedEnumType = enumElement.name;
        acceptedEnumImport = enumElement.library.uri.toString();
      }
      for (final state
          in collaborationReader!.read('additionalReadableStates').listValue) {
        final variable = state.variable;
        final enumElement = variable?.enclosingElement;
        final name = variable?.name;
        if (name == null ||
            enumElement is! EnumElement ||
            !enumElement.fields.any(
              (field) => field == variable && field.isEnumConstant,
            )) {
          throw InvalidGenerationSourceError(
            'CollaborationAccess.workflow additionalReadableStates must '
            'contain enum constants.',
            element: element,
          );
        }
        final value = snakeCase(name);
        if (value == acceptedValue ||
            additionalReadableValues.contains(value)) {
          throw InvalidGenerationSourceError(
            'CollaborationAccess.workflow additionalReadableStates must be '
            'unique and must not repeat the accepted state.',
            element: element,
          );
        }
        additionalReadableValues.add(value);
        final enumType = enumElement.name;
        final enumImport = enumElement.library.uri.toString();
        if (readableEnumType != null &&
            (readableEnumType != enumType ||
                readableEnumImport != enumImport)) {
          throw InvalidGenerationSourceError(
            'CollaborationAccess.workflow additionalReadableStates must use '
            'one enum type.',
            element: element,
          );
        }
        readableEnumType = enumType;
        readableEnumImport = enumImport;
      }
    }
    _validateSqlIdentifier(membershipTable, element, label: 'membership table');
    _validateSqlIdentifier(
      entityForeignKey,
      element,
      label: 'entity foreign key',
    );
    _validateSqlIdentifier(userForeignKey, element, label: 'user foreign key');
    if (activeField != null) {
      _validateSqlIdentifier(activeField, element, label: 'active field');
    }
    if (statusField != null) {
      _validateSqlIdentifier(statusField, element, label: 'status field');
    }
    collaboration = CollaborationSpec(
      lifecycle: lifecycle,
      membershipTable: membershipTable,
      entityForeignKey: entityForeignKey,
      userForeignKey: userForeignKey,
      activeField: activeField,
      statusField: statusField,
      acceptedValue: acceptedValue,
      acceptedEnumType: acceptedEnumType,
      acceptedEnumImport: acceptedEnumImport,
      additionalReadableValues: additionalReadableValues,
      readableEnumType: readableEnumType,
      readableEnumImport: readableEnumImport,
    );
  }

  return SecuritySpec(
    grants: grants,
    collaboration: collaboration,
    referenceAccessGuards: referenceAccessGuards,
  );
}

List<GrantSpec> _inferSecurityGrants({
  required Ownership ownership,
  required List<FieldSpec>? fields,
  required List<CommandSpec>? commands,
  required List<ActionSpec>? actions,
  required bool hasCollaboration,
  required bool hasAccessReference,
  required bool isComponent,
  required bool isActivityEntry,
}) {
  final actionTargets =
      actions?.expand((action) => action.targetFields).toSet() ??
      const <String>{};
  final commandTargets =
      commands?.map((command) => command.targetField).toSet() ??
      const <String>{};
  final hasMutableFields =
      !isActivityEntry &&
      (fields?.any(
            (field) =>
                !field.isId &&
                !field.generatedOnly &&
                field.name != EntityConventions.ownerFieldName &&
                field.name != EntityConventions.deletedAtFieldName &&
                field.name != EntityConventions.archivedAtFieldName &&
                field.name != EntityConventions.orderRankFieldName &&
                field.inCreatePayload &&
                !field.isServerManaged &&
                (actionTargets.contains(field.name) ||
                    (field.draftEditableOverride != false &&
                        field.reference == null &&
                        field.transitions.isEmpty &&
                        !commandTargets.contains(field.name) &&
                        !actionTargets.contains(field.name))),
          ) ??
          true);
  if (isComponent) {
    return [
      const GrantSpec(
        operation: RlsOperation.insert,
        principal: RlsPrincipal.owner,
      ),
      const GrantSpec(
        operation: RlsOperation.select,
        principal: RlsPrincipal.relationship,
      ),
      if (hasMutableFields)
        const GrantSpec(
          operation: RlsOperation.update,
          principal: RlsPrincipal.relationship,
        ),
    ];
  }
  final grants = <GrantSpec>[
    const GrantSpec(
      operation: RlsOperation.select,
      principal: RlsPrincipal.owner,
    ),
    if (ownership == Ownership.separate)
      const GrantSpec(
        operation: RlsOperation.insert,
        principal: RlsPrincipal.owner,
      ),
  ];
  if (hasMutableFields) {
    grants.add(
      const GrantSpec(
        operation: RlsOperation.update,
        principal: RlsPrincipal.owner,
      ),
    );
  }
  if (commands?.isNotEmpty ?? true) {
    grants.add(
      const GrantSpec(
        operation: RlsOperation.delete,
        principal: RlsPrincipal.owner,
      ),
    );
  }
  if (hasCollaboration) {
    grants.add(
      const GrantSpec(
        operation: RlsOperation.select,
        principal: RlsPrincipal.collaborator,
      ),
    );
    if (hasMutableFields) {
      grants.add(
        const GrantSpec(
          operation: RlsOperation.update,
          principal: RlsPrincipal.collaborator,
        ),
      );
    }
  }
  if (hasAccessReference) {
    grants.addAll([
      for (final grant
          in grants
              .where((grant) => grant.principal == RlsPrincipal.owner)
              .toList(growable: false))
        GrantSpec(
          operation: grant.operation,
          principal: RlsPrincipal.reference,
        ),
    ]);
  }
  return grants;
}

void _validateSqlIdentifier(
  String value,
  Element element, {
  required String label,
}) {
  if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(value)) {
    throw InvalidGenerationSourceError(
      'Invalid $label identifier `$value`. Use lowercase snake_case only.',
      element: element,
    );
  }
}

T _readEnum<T extends Enum>(ConstantReader reader, List<T> values) {
  final name = reader.objectValue.variable?.name;
  return values.singleWhere(
    (value) => value.name == name,
    orElse: () => throw FormatException('Unsupported enum value: $name'),
  );
}

SqlType _inferSqlType(String dartType) {
  final nonNullable = dartType.replaceAll('?', '');
  if (nonNullable.startsWith('LocalId<')) return SqlType.uuid;
  return switch (nonNullable) {
    'String' => SqlType.text,
    'bool' => SqlType.boolean,
    'int' => SqlType.integer,
    'double' => SqlType.real,
    'LocalDate' => SqlType.date,
    'DateTime' => SqlType.timestampWithTimeZone,
    _ => throw InvalidGenerationSourceError(
      'Unsupported persisted type `$dartType`. Implement '
      'PersistedScalarValue<String|bool|int|double> for an immutable atomic '
      'domain value, or model structure as native fields and relationships.',
    ),
  };
}

ScalarValueSpec? _parseScalarValue(DartType type, FieldElement field) {
  if (type is! InterfaceType || type.element is! ClassElement) return null;
  final element = type.element as ClassElement;
  final contracts = element.allSupertypes
      .where(
        (candidate) => _persistedScalarValueChecker.isExactlyType(candidate),
      )
      .toList(growable: false);
  if (contracts.isEmpty) return null;
  _validatePersistedValueClass(element, type, field);
  if (contracts.length != 1 || contracts.single.typeArguments.length != 1) {
    throw InvalidGenerationSourceError(
      '`${field.name}` must implement exactly one PersistedScalarValue '
      'contract.',
      element: field,
    );
  }

  final wireType = contracts.single.typeArguments.single;
  final wireDartType = wireType.getDisplayString();
  final sqlType = switch (wireDartType) {
    'String' => SqlType.text,
    'bool' => SqlType.boolean,
    'int' => SqlType.integer,
    'double' => SqlType.real,
    _ => throw InvalidGenerationSourceError(
      '`${field.name}` has unsupported PersistedScalarValue wire type '
      '`$wireDartType`. Use String, bool, int, or double.',
      element: field,
    ),
  };
  final constructors = element.constructors
      .where((candidate) => candidate.name == 'fromScalar')
      .toList(growable: false);
  if (constructors.length != 1) {
    throw InvalidGenerationSourceError(
      '`${type.getDisplayString()}` must expose exactly one named `fromScalar` '
      'constructor.',
      element: field,
    );
  }
  final constructor = constructors.single;
  if (constructor.formalParameters.length != 1 ||
      !constructor.formalParameters.single.isRequiredPositional ||
      constructor.formalParameters.single.type.getDisplayString() !=
          wireDartType) {
    throw InvalidGenerationSourceError(
      '`${type.getDisplayString()}.fromScalar` must accept one required '
      'positional `$wireDartType` value.',
      element: field,
    );
  }
  return ScalarValueSpec(
    wireDartType: wireDartType,
    sqlType: sqlType,
    hasConstConstructor: constructor.isConst,
  );
}

void _validatePersistedValueClass(
  ClassElement element,
  DartType type,
  FieldElement field,
) {
  final mutableFields = element.fields
      .where(
        (candidate) =>
            !candidate.isStatic &&
            candidate.isOriginDeclaration &&
            !candidate.isFinal,
      )
      .toList(growable: false);
  if (!element.isFinal || element.isAbstract || mutableFields.isNotEmpty) {
    throw InvalidGenerationSourceError(
      '`${type.getDisplayString()}` must be a concrete final value type with '
      'only final instance fields.',
      element: field,
    );
  }
}

FieldSpec _infrastructureField({
  required String name,
  required String dartType,
  required SqlType sqlType,
  bool nullable = false,
  Object? defaultValue,
  int sinceProtocolVersion = 1,
  String? renamedFrom,
  bool generatedOnly = false,
}) {
  return FieldSpec(
    name: name,
    columnName: snakeCase(name),
    dartType: dartType,
    sqlType: sqlType,
    nullable: nullable,
    isFinal: true,
    defaultValue: defaultValue,
    conflict: ConflictStrategy.serverWins,
    minLength: null,
    maxLength: null,
    minValue: null,
    maxValue: null,
    greaterThan: null,
    requires: null,
    notEqualTo: null,
    indexed: false,
    unique: false,
    sinceProtocolVersion: sinceProtocolVersion,
    renamedFrom: renamedFrom,
    generatedOnly: generatedOnly,
  );
}

FieldSpec _activatableField() => const FieldSpec(
  name: 'active',
  columnName: 'active',
  dartType: 'bool',
  sqlType: SqlType.boolean,
  nullable: false,
  isFinal: true,
  defaultValue: true,
  conflict: ConflictStrategy.localWins,
  minLength: null,
  maxLength: null,
  minValue: null,
  maxValue: null,
  greaterThan: null,
  requires: null,
  notEqualTo: null,
  indexed: false,
  unique: false,
);

FieldSpec _archivableField() => const FieldSpec(
  name: 'archivedAt',
  columnName: 'archived_at',
  dartType: 'DateTime?',
  sqlType: SqlType.timestampWithTimeZone,
  nullable: true,
  isFinal: true,
  defaultValue: null,
  conflict: ConflictStrategy.localWins,
  minLength: null,
  maxLength: null,
  minValue: null,
  maxValue: null,
  greaterThan: null,
  requires: null,
  notEqualTo: null,
  indexed: true,
  unique: false,
  indexScope: IndexScope.owner,
);

List<FieldSpec> _activityFields({
  required String subjectClassName,
  required String actorClassName,
}) => [
  FieldSpec(
    name: 'subjectId',
    columnName: 'subject_id',
    dartType: 'LocalId<$subjectClassName>',
    sqlType: SqlType.uuid,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: null,
    maxLength: null,
    indexed: false,
    unique: false,
  ),
  FieldSpec(
    name: 'actorId',
    columnName: 'actor_id',
    dartType: 'LocalId<$actorClassName>',
    sqlType: SqlType.uuid,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: null,
    maxLength: null,
    indexed: false,
    unique: false,
  ),
  const FieldSpec(
    name: 'operation',
    columnName: 'operation',
    dartType: 'ActivityOperation',
    sqlType: SqlType.text,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: 1,
    maxLength: 160,
    indexed: false,
    unique: false,
    scalarValue: ScalarValueSpec(
      wireDartType: 'String',
      sqlType: SqlType.text,
      hasConstConstructor: false,
    ),
  ),
  const FieldSpec(
    name: 'label',
    columnName: 'label',
    dartType: 'String',
    sqlType: SqlType.text,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: 1,
    maxLength: 240,
    indexed: false,
    unique: false,
  ),
  const FieldSpec(
    name: 'sourceOperationId',
    columnName: 'source_operation_id',
    dartType: 'String',
    sqlType: SqlType.text,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: 1,
    maxLength: 64,
    indexed: false,
    unique: false,
  ),
  const FieldSpec(
    name: 'occurredAt',
    columnName: 'occurred_at',
    dartType: 'DateTime',
    sqlType: SqlType.timestampWithTimeZone,
    nullable: false,
    isFinal: true,
    defaultValue: null,
    conflict: ConflictStrategy.localWins,
    minLength: null,
    maxLength: null,
    indexed: false,
    unique: false,
  ),
];

const _activatableActions = [
  ActionSpec(
    methodName: 'activate',
    parameters: [],
    assignments: [
      ActionAssignmentSpec(
        fieldName: 'active',
        kind: ActionValueKind.literal,
        literal: true,
      ),
    ],
  ),
  ActionSpec(
    methodName: 'deactivate',
    parameters: [],
    assignments: [
      ActionAssignmentSpec(
        fieldName: 'active',
        kind: ActionValueKind.literal,
        literal: false,
      ),
    ],
  ),
];

const _archivableActions = [
  ActionSpec(
    methodName: 'archive',
    parameters: [],
    assignments: [
      ActionAssignmentSpec(
        fieldName: 'archivedAt',
        kind: ActionValueKind.clockNow,
      ),
    ],
  ),
  ActionSpec(
    methodName: 'unarchive',
    parameters: [],
    assignments: [
      ActionAssignmentSpec(
        fieldName: 'archivedAt',
        kind: ActionValueKind.clear,
      ),
    ],
  ),
];

Object? _inferDefaultValue(FieldElement field, Expression? initializer) {
  if (_isDartCoreList(field.type)) {
    final elementType = (field.type as InterfaceType).typeArguments.single;
    if (initializer is ListLiteral) {
      if (initializer.constKeyword == null) {
        throw InvalidGenerationSourceError(
          '`${field.name}` collection defaults must be const list literals.',
          element: field,
        );
      }
      return List<Object?>.unmodifiable(
        initializer.elements.map(
          (element) => _collectionInitializerValue(element, elementType, field),
        ),
      );
    }
    final values = field.computeConstantValue()?.toListValue();
    if (values == null) return null;
    return List<Object?>.unmodifiable(
      values.map(
        (value) => _collectionConstantValue(value, elementType, field),
      ),
    );
  }
  if (field.type.element is EnumElement) {
    return switch (initializer) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.name == field.type.element?.name =>
        identifier.name,
      _ => field.computeConstantValue()?.variable?.name,
    };
  }
  final value = switch (initializer) {
    BooleanLiteral(:final value) => value,
    IntegerLiteral(:final value) => value,
    DoubleLiteral(:final value) => value,
    SimpleStringLiteral(:final value) => value,
    _ => null,
  };
  if (value != null) return value;
  if (field.name == EntityConventions.serverVersionFieldName &&
      field.isFinal &&
      field.type.getDisplayString() == 'ServerVersion') {
    return 0;
  }
  return null;
}

Object _collectionInitializerValue(
  CollectionElement element,
  DartType elementType,
  FieldElement field,
) {
  final enumElement = elementType.element;
  if (enumElement is EnumElement && element is PrefixedIdentifier) {
    final value = element.identifier.name;
    if (element.prefix.name == enumElement.name &&
        enumElement.fields.any(
          (candidate) => candidate.isEnumConstant && candidate.name == value,
        )) {
      return value;
    }
  }

  final Object? value;
  if (element is SimpleStringLiteral) {
    value = element.value;
  } else if (element is BooleanLiteral) {
    value = element.value;
  } else if (element is IntegerLiteral) {
    value = element.value;
  } else if (element is PrefixExpression &&
      element.operator.lexeme == '-' &&
      element.operand is IntegerLiteral) {
    final integer = (element.operand as IntegerLiteral).value;
    value = integer == null ? null : -integer;
  } else {
    value = null;
  }
  final valid = switch (elementType.getDisplayString()) {
    'String' => value is String,
    'bool' => value is bool,
    'int' => value is int,
    _ => false,
  };
  if (valid) return value!;

  throw InvalidGenerationSourceError(
    '`${field.name}` has an unsupported const collection default element for '
    '`${elementType.getDisplayString()}`.',
    element: field,
  );
}

Object? _configuredDefaultValue(
  ConstantReader? persisted,
  FieldElement field,
  EnumElement? enumElement, {
  ScalarValueSpec? scalarValue,
}) {
  final reader = persisted?.peek('defaultValue');
  if (reader == null || reader.isNull) return null;
  if (_isDartCoreList(field.type)) {
    final elementType = (field.type as InterfaceType).typeArguments.single;
    final values = reader.objectValue.toListValue();
    if (values == null) {
      throw InvalidGenerationSourceError(
        'A collection default must be a const List value.',
        element: field,
      );
    }
    return List<Object?>.unmodifiable(
      values.map(
        (value) => _collectionConstantValue(value, elementType, field),
      ),
    );
  }
  if (enumElement == null) {
    final expectedType =
        scalarValue?.wireDartType ??
        field.type.getDisplayString().replaceAll('?', '');
    return switch (expectedType) {
      'double' =>
        reader.objectValue.toDoubleValue() ??
            reader.objectValue.toIntValue()?.toDouble() ??
            (reader.literalValue as num?)?.toDouble(),
      _ => reader.literalValue,
    };
  }
  final variable = reader.objectValue.variable;
  if (variable == null || variable.enclosingElement != enumElement) {
    throw InvalidGenerationSourceError(
      'An enum default must be a value of `${enumElement.name}`.',
      element: field,
    );
  }
  return variable.name;
}

bool _isDartCoreList(DartType type) =>
    type is InterfaceType &&
    type.element.name == 'List' &&
    type.element.library.uri.toString() == 'dart:core';

Object? _collectionConstantValue(
  DartObject value,
  DartType elementType,
  FieldElement field,
) {
  final enumElement = elementType.element;
  if (enumElement is EnumElement) {
    final variable = value.variable;
    if (variable?.enclosingElement == enumElement) return variable!.name;
  } else {
    final type = elementType.getDisplayString();
    final decoded = switch (type) {
      'String' => value.toStringValue(),
      'bool' => value.toBoolValue(),
      'int' => value.toIntValue(),
      _ => null,
    };
    if (decoded != null) return decoded;
  }
  throw InvalidGenerationSourceError(
    '`${field.name}` has an unsupported collection default element for '
    '`${elementType.getDisplayString()}`.',
    element: field,
  );
}

void _validateConfiguredDefault(
  FieldElement field,
  Object value, {
  ScalarValueSpec? scalarValue,
}) {
  final expectedType =
      scalarValue?.wireDartType ??
      field.type.getDisplayString().replaceAll('?', '');
  final matches = switch (expectedType) {
    'String' => value is String,
    'bool' => value is bool,
    'int' => value is int,
    'double' => value is double,
    _ => false,
  };
  if (!matches) {
    throw InvalidGenerationSourceError(
      '`${field.name}` defaultValue must be a `$expectedType` constant. '
      'Nominal IDs and timestamps do not accept stringly defaults.',
      element: field,
    );
  }
}
