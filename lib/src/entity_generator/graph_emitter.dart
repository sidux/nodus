import 'package:dart_style/dart_style.dart';
import 'package:nodus/nodus.dart';

import 'model.dart';

String emitEntityGraph(
  EntityGraphSpec graph, {
  String? schemaFingerprint,
  bool privateEntityOutputs = false,
  String? partBaseName,
}) {
  final databaseName = '${graph.className}Database';
  final workTableName = '${graph.className}SyncWorkRows';
  final cursorTableName = '${graph.className}SyncCursorRows';
  final cursorGetter = _lowerCamel(cursorTableName);
  final hasCompositions = graph.entities.any(
    (entity) => entity.fields.any((field) => field.isComposition),
  );
  final usesSupabase = graph.syncTargets.any(
    (target) => target.wireName == 'supabase',
  );
  final usesManagedFlutterRuntime = privateEntityOutputs || usesSupabase;
  final canOpenSupabase = usesSupabase && graph.syncTargets.length == 1;
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Source: ${graph.inputImport}');
  if (schemaFingerprint != null) {
    buffer.writeln('// Schema fingerprint: $schemaFingerprint');
  }
  buffer
    ..writeln('// ignore_for_file: unused_field, type=lint')
    ..writeln()
    ..writeln("import 'dart:async';")
    ..writeln()
    ..writeln("import 'package:drift/drift.dart';");
  if (!usesManagedFlutterRuntime) {
    buffer.writeln("import 'package:drift/native.dart';");
  }
  if (usesManagedFlutterRuntime) {
    buffer.writeln("import 'package:nodus/nodus_flutter.dart';");
    if (canOpenSupabase) {
      buffer
        ..writeln("import 'package:nodus/nodus_supabase.dart';")
        ..writeln("import 'package:supabase/supabase.dart';");
    }
  } else {
    buffer.writeln("import 'package:nodus/nodus.dart';");
  }
  final publicImports = <String>{
    for (final entity in graph.entities) entity.inputImport,
    for (final entity in graph.entities)
      _generatedEntityImport(entity, privateOutput: privateEntityOutputs),
    for (final entity in graph.entities)
      ...entity.typeImports.where(
        (import) => import != 'package:nodus/nodus.dart',
      ),
  }.toList()..sort();
  final imports = <String>{
    for (final entity in graph.entities) entity.inputImport,
    for (final entity in graph.entities)
      _generatedEntityImport(entity, privateOutput: privateEntityOutputs),
    for (final entity in graph.entities)
      ...entity.typeImports.where(
        (import) => import != 'package:nodus/nodus.dart',
      ),
  }.toList()..sort();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer.writeln();
  for (final import in publicImports) {
    buffer.writeln("export '$import';");
  }
  buffer
    ..writeln()
    ..writeln("part '${partBaseName ?? graph.outputBaseName}.drift.dart';");
  if (graph.emitsSyncTargetEnum && graph.syncTargets.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('enum ${graph.className}SyncTarget {');
    for (final target in graph.syncTargets) {
      buffer.writeln('  ${target.valueName},');
    }
    buffer.writeln('}');
  }
  buffer
    ..writeln()
    ..writeln('@TableIndex.sql(')
    ..writeln('  "CREATE INDEX local_entity_push_patch_idx "')
    ..writeln(
      '  "ON local_entity_sync_work (sync_target, entity_type, entity_id, id) WHERE "',
    )
    ..writeln('  "direction = \'push\' AND kind = \'statePatch\' "')
    ..writeln('  "AND status = \'pending\'",')
    ..writeln(')')
    ..writeln('@TableIndex.sql(')
    ..writeln('  "CREATE INDEX local_entity_sync_ready_idx "')
    ..writeln('  "ON local_entity_sync_work "')
    ..writeln('  "(sync_target, status, next_attempt_at, direction, id)",')
    ..writeln(')')
    ..writeln('class $workTableName extends LocalEntitySyncWorkRows {}')
    ..writeln('class $cursorTableName extends LocalEntitySyncCursorRows {}')
    ..writeln()
    ..writeln('@DriftDatabase(tables: [');
  for (final entity in graph.entities) {
    buffer.writeln('  ${entity.className}Rows,');
  }
  buffer
    ..writeln('  $workTableName,')
    ..writeln('  $cursorTableName,')
    ..writeln('])')
    ..writeln('final class $databaseName extends _\$$databaseName {')
    ..writeln(
      '  $databaseName(super.executor, {MigrationStrategy? migrationOverride})',
    )
    ..writeln('      : _migrationOverride = migrationOverride;')
    ..writeln('  final MigrationStrategy? _migrationOverride;')
    ..writeln('  @override int get schemaVersion => ${graph.schemaVersion};')
    ..writeln('  @override MigrationStrategy get migration {')
    ..writeln('    final configured = _migrationOverride ?? MigrationStrategy(')
    ..writeln('        onCreate: (m) async {')
    ..writeln('          await m.createAll();');
  for (final target in graph.pullSyncTargets) {
    buffer
      ..writeln('          await into($cursorGetter).insert(')
      ..writeln('            const ${graph.className}SyncCursorRowsCompanion(')
      ..writeln(
        "              syncTarget: Value('${target.wireName}'), cursor: Value(0),",
      )
      ..writeln('            ),')
      ..writeln('            mode: InsertMode.insertOrIgnore,')
      ..writeln('          );');
  }
  buffer
    ..writeln('        },')
    ..writeln('        onUpgrade: (m, from, to) => throw StateError(')
    ..writeln(
      "          'Missing graph migration from schema version \$from to \$to.',",
    )
    ..writeln('        ),')
    ..writeln('      );')
    ..writeln('    return MigrationStrategy(');
  if (hasCompositions) {
    buffer
      ..writeln('      onCreate: (m) async {')
      ..writeln('        await configured.onCreate(m);')
      ..writeln('        await _installCompositionTriggers(replace: false);')
      ..writeln('      },')
      ..writeln('      onUpgrade: (m, from, to) async {')
      ..writeln('        await configured.onUpgrade(m, from, to);')
      ..writeln('        await _installCompositionTriggers(replace: true);')
      ..writeln('      },');
  } else {
    buffer
      ..writeln('      onCreate: configured.onCreate,')
      ..writeln('      onUpgrade: configured.onUpgrade,');
  }
  buffer
    ..writeln('      beforeOpen: (details) async {')
    ..writeln("        await customStatement('PRAGMA foreign_keys = ON');")
    ..writeln('        await configured.beforeOpen?.call(details);')
    ..writeln('      },')
    ..writeln('    );')
    ..writeln('  }');
  if (hasCompositions) {
    _emitLocalCompositionTriggerMethod(buffer, graph);
  }
  buffer
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class ${graph.className}Metadata {');
  for (final entity in graph.entities) {
    buffer.writeln(
      '  static const ${_lowerCamel(entity.className)}Descriptor = '
      '${entity.className}Descriptor();',
    );
  }
  for (final collection in graph.relationships) {
    final relationship = collection.relationship;
    buffer
      ..writeln(
        '  static const ${_lowerCamel(collection.linkEntity.className)}Relationship =',
      )
      ..writeln('      RelationshipDefinition(')
      ..writeln("        linkEntityType: '${collection.linkEntity.className}',")
      ..writeln(
        "        sourceEntityType: '${collection.sourceEntity.className}',",
      )
      ..writeln(
        "        targetEntityType: '${collection.targetEntity.className}',",
      )
      ..writeln(
        "        sourceFieldName: '${relationship.ownerReference.name}',",
      )
      ..writeln(
        "        targetFieldName: '${relationship.targetReference.name}',",
      )
      ..writeln("        activeFieldName: '${relationship.activeField.name}',")
      ..writeln(
        '        cardinalityResolution: '
        'RelationshipCardinalityResolution.'
        '${collection.cardinalityResolution.name},',
      )
      ..writeln(
        '        ordered: ${collection.linkEntity.hasOrderedCapability},',
      )
      ..writeln('      );');
  }
  for (final target in graph.syncTargets) {
    buffer
      ..writeln('  static const ${lowerCamelCase(target.wireName)}SyncTarget =')
      ..writeln('      SyncTargetId(')
      ..writeln("        typeIdentity: '${target.typeIdentity}',")
      ..writeln("        wireName: '${target.wireName}',")
      ..writeln('      );');
  }
  buffer
    ..writeln('  static final definition = EntityGraphDefinition(')
    ..writeln('    schemaVersion: ${graph.schemaVersion},')
    ..writeln('    descriptors: [');
  for (final entity in graph.entities) {
    buffer.writeln('      ${_lowerCamel(entity.className)}Descriptor,');
  }
  buffer
    ..writeln('    ],')
    ..writeln('    relationships: [');
  for (final collection in graph.relationships) {
    buffer.writeln(
      '      ${_lowerCamel(collection.linkEntity.className)}Relationship,',
    );
  }
  buffer
    ..writeln('    ],')
    ..writeln('    activityTrackings: [');
  for (final tracking in graph.activityTrackings) {
    buffer
      ..writeln('      ActivityTrackingDefinition(')
      ..writeln("        sourceEntityType: '${tracking.source.className}',")
      ..writeln("        activityEntityType: '${tracking.entry.className}',")
      ..writeln('      ),');
  }
  buffer
    ..writeln('    ],')
    ..writeln('    syncBindings: [');
  for (final binding in graph.syncBindings) {
    buffer
      ..writeln('      SyncBindingDefinition(')
      ..writeln("        entityType: '${binding.entity.className}',")
      ..writeln('        mode: SyncMode.${binding.mode.name},');
    if (binding.target case final target?) {
      buffer.writeln(
        '        target: ${lowerCamelCase(target.wireName)}SyncTarget,',
      );
    }
    buffer.writeln('      ),');
  }
  buffer
    ..writeln('    ],')
    ..writeln(
      "    pullRpcName: 'pull_${snakeCase(graph.className)}_graph_changes',",
    )
    ..writeln('  );');
  for (final target in graph.syncTargets) {
    final targetName = lowerCamelCase(target.wireName);
    buffer.writeln(
      '  static final ${targetName}SyncDefinition = '
      'definition.syncSubgraphFor(${targetName}SyncTarget);',
    );
  }
  buffer
    ..writeln('}')
    ..writeln();
  _emitSyncAdapters(buffer, graph);
  _emitEntityGraphRuntime(
    buffer,
    graph,
    databaseName,
    usesManagedFlutterRuntime: usesManagedFlutterRuntime,
  );
  _emitGraphLists(buffer, graph);
  _emitGraphLookups(buffer, graph);
  _emitGraphRelationships(buffer, graph);
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).format(buffer.toString());
}

String emitEntityGraphFacade(
  EntityGraphSpec graph, {
  required String schemaFingerprint,
  Iterable<String> routeExports = const [],
}) {
  final buffer = StringBuffer('''// GENERATED FILE. DO NOT EDIT.
// Source: ${graph.inputImport}
// Schema fingerprint: $schemaFingerprint

export 'package:nodus/nodus_flutter.dart';
export 'src/generated/nodus.runtime.g.dart';
''');
  for (final routeExport in routeExports) {
    buffer.writeln("export '$routeExport';");
  }
  return buffer.toString();
}

String emitEntityGraphTestHarness(EntityGraphSpec graph) {
  final graphName = '${graph.className}EntityGraph';
  final harnessName = '${graph.className}TestHarness';
  final accountType = graph.accountClassName;
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Test support for ${graph.inputImport}')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln("import 'package:nodus/nodus_testing.dart';")
    ..writeln("import 'package:${graph.packageName}/nodus.g.dart';")
    ..writeln()
    ..writeln('final class $harnessName {')
    ..writeln('  $harnessName._({')
    ..writeln('    required this.entityGraph,')
    ..writeln('    required this.clock,');
  for (final target in graph.syncTargets) {
    buffer.writeln('    required this.${lowerCamelCase(target.wireName)},');
  }
  buffer
    ..writeln('  });')
    ..writeln()
    ..writeln('  final $graphName entityGraph;')
    ..writeln('  final Clock clock;');
  for (final target in graph.syncTargets) {
    buffer.writeln(
      '  final InMemorySyncBackend ${lowerCamelCase(target.wireName)};',
    );
  }
  buffer
    ..writeln()
    ..writeln('  static Future<$harnessName> open({')
    ..writeln('    LocalId<$accountType>? accountId,')
    ..writeln('    Clock? clock,')
    ..writeln(
      '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
    )
    ..writeln(
      '    LocalEntityDiagnostics diagnostics = '
      'const NoopLocalEntityDiagnostics(),',
    );
  for (final target in graph.syncTargets) {
    buffer.writeln(
      '    InMemorySyncBackend? ${lowerCamelCase(target.wireName)},',
    );
  }
  buffer
    ..writeln('    bool autoSync = false,')
    ..writeln('  }) async {')
    ..writeln(
      "    final resolvedAccountId = accountId ?? LocalId<$accountType>('00000000-0000-0000-0000-000000000001');",
    )
    ..writeln('    final resolvedClock = clock ?? NodusTestClock();');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer
      ..writeln('    final resolved${_upperCamel(name)} =')
      ..writeln('        $name ?? InMemorySyncBackend.graph(')
      ..writeln(
        '          definition: ${graph.className}Metadata.${name}SyncDefinition,',
      )
      ..writeln('        );');
  }
  buffer
    ..writeln('    final entityGraph = await $graphName.openInMemory(')
    ..writeln('      accountId: resolvedAccountId,')
    ..writeln('      clock: resolvedClock,')
    ..writeln('      idGenerator: idGenerator,')
    ..writeln('      diagnostics: diagnostics,')
    ..writeln('      autoSync: autoSync,');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer.writeln('      ${name}Backend: resolved${_upperCamel(name)},');
  }
  buffer
    ..writeln('    );')
    ..writeln('    return $harnessName._(')
    ..writeln('      entityGraph: entityGraph,')
    ..writeln('      clock: resolvedClock,');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer.writeln('      $name: resolved${_upperCamel(name)},');
  }
  buffer
    ..writeln('    );')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Future<void> close() => entityGraph.close();')
    ..writeln('}');
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).format(buffer.toString());
}

void _emitSyncAdapters(StringBuffer buffer, EntityGraphSpec graph) {
  final className = '${graph.className}SyncAdapters';
  buffer.write('final class $className {\n  const $className(');
  if (graph.syncTargets.isEmpty) {
    buffer.writeln(');');
  } else {
    buffer.writeln('{');
    for (final target in graph.syncTargets) {
      buffer.writeln('    required this.${lowerCamelCase(target.wireName)},');
    }
    buffer.writeln('  });');
  }
  for (final target in graph.syncTargets) {
    final adapterType = _syncAdapterType(graph, target);
    buffer.writeln('  final $adapterType ${lowerCamelCase(target.wireName)};');
  }
  buffer
    ..writeln('  SyncAdapterRegistry bind() =>')
    ..writeln('      SyncAdapterRegistry(')
    ..writeln('        definition: ${graph.className}Metadata.definition,')
    ..writeln('        adapters: {');
  for (final target in graph.syncTargets) {
    buffer.writeln(
      '          ${graph.className}Metadata.'
      '${lowerCamelCase(target.wireName)}SyncTarget: '
      '${lowerCamelCase(target.wireName)},',
    );
  }
  buffer
    ..writeln('        },')
    ..writeln('      );')
    ..writeln('}')
    ..writeln();
}

String _syncAdapterType(EntityGraphSpec graph, SyncTargetSpec target) {
  final pushes = graph.pushSyncTargets.any(
    (candidate) => candidate.stableIdentity == target.stableIdentity,
  );
  final pulls = graph.pullSyncTargets.any(
    (candidate) => candidate.stableIdentity == target.stableIdentity,
  );
  return switch ((pushes, pulls)) {
    (true, true) => 'PushPullSyncAdapter',
    (true, false) => 'PushSyncAdapter',
    (false, true) => 'PullSyncAdapter',
    (false, false) => throw StateError(
      'Used sync target `${target.wireName}` has no sync direction.',
    ),
  };
}

void _emitGraphLists(StringBuffer buffer, EntityGraphSpec graph) {
  final entityGraphName = '${graph.className}EntityGraph';
  for (final entity in graph.entities) {
    final listName = '${entity.className}List';
    final ordered = entity.legacyOrderedCollection;
    final exhaustiveOrdering = entity.cardinality == Cardinality.bounded
        ? ordered
        : null;
    buffer
      ..writeln(
        'final class $listName extends EntityList<${entity.className}> {',
      )
      ..writeln('  $listName.all(')
      ..writeln('    $entityGraphName entityGraph, {')
      ..writeln('    EntityPredicate<${entity.className}>? where,')
      ..writeln('    EntityOrder<${entity.className}>? orderBy,')
      ..writeln(
        '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
      );
    _emitArchiveParameter(buffer, entity);
    buffer
      ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
      ..writeln(
        '  }) :${exhaustiveOrdering == null ? '' : ' _entityGraph = entityGraph,'}',
      )
      ..writeln('       super(entityGraph.${entity.setAccessor}.query(')
      ..writeln('         where: where,')
      ..writeln('         orderBy: ${_graphListOrderBy(entity)},')
      ..writeln('         tombstones: tombstones,')
      ..write(_archiveArgument(entity))
      ..writeln('         pageSize: pageSize,')
      ..writeln('       ));');

    if (entity.hasArchivableCapability) {
      _emitGraphArchiveConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        constructorName: 'active',
        visibility: 'exclude',
        retainEntityGraph: exhaustiveOrdering != null,
      );
      _emitGraphArchiveConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        constructorName: 'archived',
        visibility: 'only',
        retainEntityGraph: exhaustiveOrdering != null,
      );
    }

    if (entity.ownership == Ownership.separate) {
      _emitGraphOwnedListConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        retainEntityGraph: exhaustiveOrdering != null,
      );
      _emitGraphListSelectionConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        constructorName: 'forOwner',
        parameterName: 'ownerId',
        parameterType: entity.ownerField.dartType,
        predicate: '${entity.className}Fields.ownerId.equals(ownerId)',
        retainEntityGraph: exhaustiveOrdering != null,
      );

      if (entity.participantFields.isNotEmpty) {
        _emitGraphListSelectionConstructor(
          buffer,
          entity: entity,
          entityGraphName: entityGraphName,
          constructorName: 'visibleTo',
          parameterName: 'accountId',
          parameterType: entity.ownerField.dartType,
          predicate:
              '(${['${entity.className}Fields.ownerId.equals(accountId)', for (final field in entity.participantFields) '${entity.className}Fields.${field.name}.equals(accountId)'].join(' | ')})',
          retainEntityGraph: exhaustiveOrdering != null,
        );
      }
    }

    for (final field in entity.fields) {
      final reference = field.reference;
      final accessor =
          reference?.accessorName ??
          (field.isParticipant ? _idFieldAccessor(field.name) : null);
      if (accessor == null) continue;
      _emitGraphListSelectionConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        constructorName: 'for${_upperCamel(accessor)}',
        parameterName: field.name,
        parameterType: field.dartType.replaceAll('?', ''),
        predicate:
            '${entity.className}Fields.${field.name}.equals(${field.name})',
        retainEntityGraph: exhaustiveOrdering != null,
      );
    }

    if (entity.isActivityEntry) {
      final subject = entity.activitySubjectClassName!;
      final parameterName = '${_lowerCamel(subject)}Id';
      _emitGraphListSelectionConstructor(
        buffer,
        entity: entity,
        entityGraphName: entityGraphName,
        constructorName: 'for$subject',
        parameterName: parameterName,
        parameterType: 'LocalId<$subject>',
        predicate: '${entity.className}Fields.subjectId.equals($parameterName)',
        retainEntityGraph: exhaustiveOrdering != null,
      );
    }

    if (exhaustiveOrdering != null) {
      _emitOrderedCollection(
        buffer,
        entity: entity,
        ordered: exhaustiveOrdering,
        entityGraphName: entityGraphName,
      );
    }
    buffer
      ..writeln('}')
      ..writeln();
  }
}

void _emitGraphArchiveConstructor(
  StringBuffer buffer, {
  required EntitySpec entity,
  required String entityGraphName,
  required String constructorName,
  required String visibility,
  required bool retainEntityGraph,
}) {
  final listName = '${entity.className}List';
  buffer
    ..writeln('  $listName.$constructorName(')
    ..writeln('    $entityGraphName entityGraph, {')
    ..writeln('    EntityPredicate<${entity.className}>? where,')
    ..writeln('    EntityOrder<${entity.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    )
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln(
      '  }) :${retainEntityGraph ? ' _entityGraph = entityGraph,' : ''}',
    )
    ..writeln('       super(entityGraph.${entity.setAccessor}.query(')
    ..writeln('         where: where,')
    ..writeln('         orderBy: ${_graphListOrderBy(entity)},')
    ..writeln('         tombstones: tombstones,')
    ..writeln('         archives: ArchiveVisibility.$visibility,')
    ..writeln('         pageSize: pageSize,')
    ..writeln('       ));');
}

void _emitGraphLookups(StringBuffer buffer, EntityGraphSpec graph) {
  final entityGraphName = '${graph.className}EntityGraph';
  for (final entity in graph.entities.where(
    (candidate) => candidate.cardinality == Cardinality.unbounded,
  )) {
    final indexes = entity.indexes.where(
      (candidate) =>
          candidate.unique &&
          !candidate.unordered &&
          !candidate.activeOnly &&
          candidate.condition == null &&
          candidate.fieldNames.every(
            (name) => !entity.fields
                .singleWhere((field) => field.name == name)
                .nullable,
          ),
    );
    if (indexes.isEmpty) continue;

    final lookupName = '${entity.className}Lookup';
    buffer.writeln(
      'final class $lookupName extends EntityLookup<${entity.className}> {',
    );
    for (final index in indexes) {
      final fields = [
        for (final name in index.fieldNames)
          entity.fields.singleWhere((field) => field.name == name),
      ];
      final constructorName =
          'by${fields.map((field) => _upperCamel(_idFieldAccessor(field.name))).join('And')}';
      buffer
        ..writeln('  $lookupName.$constructorName(')
        ..writeln('    $entityGraphName entityGraph,')
        ..writeln(
          fields
              .map((field) => '    ${field.dartType} ${field.name},')
              .join('\n'),
        )
        ..writeln('    {')
        ..writeln(
          '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
        );
      _emitArchiveParameter(buffer, entity, defaultVisibility: 'include');
      buffer
        ..writeln('  }) : super(entityGraph.${entity.setAccessor}.query(')
        ..writeln(
          '         where: ${fields.map((field) => '${entity.className}Fields.${field.name}.equals(${field.name})').join(' & ')},',
        )
        ..writeln('         tombstones: tombstones,')
        ..write(_archiveArgument(entity))
        ..writeln('         pageSize: 1,')
        ..writeln('       ));');
    }
    buffer
      ..writeln('}')
      ..writeln();
  }
}

void _emitGraphOwnedListConstructor(
  StringBuffer buffer, {
  required EntitySpec entity,
  required String entityGraphName,
  required bool retainEntityGraph,
}) {
  final listName = '${entity.className}List';
  buffer
    ..writeln('  $listName.owned(')
    ..writeln('    $entityGraphName entityGraph, {')
    ..writeln('    EntityPredicate<${entity.className}>? where,')
    ..writeln('    EntityOrder<${entity.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  _emitArchiveParameter(buffer, entity);
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln(
      '  }) :${retainEntityGraph ? ' _entityGraph = entityGraph,' : ''}',
    )
    ..writeln('       super(entityGraph.${entity.setAccessor}.query(')
    ..writeln(
      '         where: ${entity.className}Fields.ownerId.equals('
      'entityGraph.accountId) &',
    )
    ..writeln(
      '             (where ?? EntityPredicate<${entity.className}>.all()),',
    )
    ..writeln('         orderBy: ${_graphListOrderBy(entity)},')
    ..writeln('         tombstones: tombstones,')
    ..write(_archiveArgument(entity))
    ..writeln('         pageSize: pageSize,')
    ..writeln('       ));');
}

void _emitGraphListSelectionConstructor(
  StringBuffer buffer, {
  required EntitySpec entity,
  required String entityGraphName,
  required String constructorName,
  required String parameterName,
  required String parameterType,
  required String predicate,
  required bool retainEntityGraph,
}) {
  final listName = '${entity.className}List';
  buffer
    ..writeln('  $listName.$constructorName(')
    ..writeln('    $entityGraphName entityGraph,')
    ..writeln('    $parameterType $parameterName, {')
    ..writeln('    EntityPredicate<${entity.className}>? where,')
    ..writeln('    EntityOrder<${entity.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  _emitArchiveParameter(buffer, entity);
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln(
      '  }) :${retainEntityGraph ? ' _entityGraph = entityGraph,' : ''}',
    )
    ..writeln('       super(entityGraph.${entity.setAccessor}.query(')
    ..writeln('         where: $predicate &')
    ..writeln(
      '             (where ?? EntityPredicate<${entity.className}>.all()),',
    )
    ..writeln('         orderBy: ${_graphListOrderBy(entity)},')
    ..writeln('         tombstones: tombstones,')
    ..write(_archiveArgument(entity))
    ..writeln('         pageSize: pageSize,')
    ..writeln('       ));');
}

void _emitArchiveParameter(
  StringBuffer buffer,
  EntitySpec entity, {
  String defaultVisibility = 'exclude',
}) {
  if (!entity.hasArchivableCapability) return;
  buffer.writeln(
    '    ArchiveVisibility archives = '
    'ArchiveVisibility.$defaultVisibility,',
  );
}

String _archiveArgument(EntitySpec entity, {String indent = '         '}) =>
    entity.hasArchivableCapability ? '${indent}archives: archives,\n' : '';

String _graphListOrderBy(EntitySpec entity) {
  if (entity.hasOrderedCapability) {
    return 'orderBy ?? entityGraph.${entity.setAccessor}.canonicalOrder';
  }
  if (entity.isActivityEntry) {
    return 'orderBy ?? ${entity.className}Fields.occurredAt.descending()';
  }
  final ordered = entity.legacyOrderedCollection;
  if (ordered == null) return 'orderBy';
  return 'orderBy ?? '
      '${entity.className}Fields.${ordered.orderField.name}.ascending()';
}

void _emitOrderedCollection(
  StringBuffer buffer, {
  required EntitySpec entity,
  required OrderedCollectionSpec ordered,
  required String entityGraphName,
}) {
  final entityName = entity.className;
  final orderField = ordered.orderField;
  final idType = entity.idField.dartType;
  buffer
    ..writeln('  final $entityGraphName _entityGraph;')
    ..writeln()
    ..writeln('  Future<void> reorder(Iterable<$idType> entityIds) async {')
    ..writeln('    final ordered = entityIds.toList(growable: false);')
    ..writeln('    if (ordered.toSet().length != ordered.length) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entityName',")
    ..writeln("        field: '${orderField.name}',")
    ..writeln("        message: 'An ordered entity may appear only once.',")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final entities = await loadAll();')
    ..writeln('    final byId = <$idType, $entityName>{')
    ..writeln('      for (final entity in entities) entity.id: entity,')
    ..writeln('    };')
    ..writeln('    if (byId.length != ordered.length ||')
    ..writeln('        !ordered.every(byId.containsKey)) {')
    ..writeln('      throw const EntityValidationException(')
    ..writeln("        entityType: '$entityName',")
    ..writeln("        field: '${orderField.name}',")
    ..writeln(
      "        message: 'The ordered identities must exactly match the collection.',",
    )
    ..writeln('      );')
    ..writeln('    }')
    ..writeln('    final unchanged = ordered.indexed.every(')
    ..writeln(
      '      (entry) => byId[entry.\$2]!.${orderField.name} == entry.\$1,',
    )
    ..writeln('    );')
    ..writeln('    if (unchanged) return;')
    ..writeln('    await _entityGraph.transaction(() {')
    ..writeln('      for (final (index, id) in ordered.indexed) {')
    ..writeln(
      '        unawaited(byId[id]!.${ordered.moveAction.methodName}(${orderField.name}: index));',
    )
    ..writeln('      }')
    ..writeln('    });')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  Future<$entityName> prepend($entityName Function() create) async {',
    )
    ..writeln('    final entities = await loadAll();')
    ..writeln('    late $entityName created;')
    ..writeln('    await _entityGraph.transaction(() {')
    ..writeln('      for (final entity in entities) {')
    ..writeln(
      '        unawaited(entity.${ordered.moveAction.methodName}(${orderField.name}: entity.${orderField.name} + 1));',
    )
    ..writeln('      }')
    ..writeln('      created = create();')
    ..writeln('      if (!spec.where.test(created)) {')
    ..writeln('        throw const EntityValidationException(')
    ..writeln("          entityType: '$entityName',")
    ..writeln("          field: '${orderField.name}',")
    ..writeln(
      "          message: 'The created entity must belong to the selected collection.',",
    )
    ..writeln('        );')
    ..writeln('      }')
    ..writeln(
      '      if (created.${orderField.name} != ${orderField.defaultValue}) {',
    )
    ..writeln('        throw const EntityValidationException(')
    ..writeln("          entityType: '$entityName',")
    ..writeln("          field: '${orderField.name}',")
    ..writeln(
      "          message: 'The prepended entity must use the default first position.',",
    )
    ..writeln('        );')
    ..writeln('      }')
    ..writeln('    });')
    ..writeln('    return created;')
    ..writeln('  }');
}

void _emitGraphRelationships(StringBuffer buffer, EntityGraphSpec graph) {
  final entityGraphName = '${graph.className}EntityGraph';
  for (final collection in graph.relationships) {
    _emitActiveRelationship(
      buffer,
      source: collection.linkEntity,
      relationship: collection.relationship,
      cardinalityResolution: collection.cardinalityResolution,
      entityGraphName: entityGraphName,
    );
  }
  for (final source in graph.entities) {
    for (final field in source.fields) {
      final reference = field.reference;
      if (reference == null) continue;
      final relationship = graph.relationshipFor(source)?.relationship;
      final isMutableRelationshipSource =
          relationship != null && field == relationship.ownerReference;
      final canCreateThroughReference =
          relationship == null &&
          source.canCreate &&
          field.persistedVariantName == null &&
          source.createParameters.contains(field);
      if (canCreateThroughReference) {
        _emitCreationRelationship(
          buffer,
          source: source,
          field: field,
          entityGraphName: entityGraphName,
        );
      }
      final returnType = isMutableRelationshipSource
          ? '${source.className}Relationship'
          : canCreateThroughReference
          ? generatedInverseCreationTypeName(field)
          : '${source.className}List';
      final extensionName =
          '${reference.targetClassName}${source.className}'
          '${pascalCase(snakeCase(field.name))}InverseRelationship';
      buffer
        ..writeln('extension $extensionName on ${reference.targetClassName} {')
        ..writeln('  $returnType ${reference.inverseName}(')
        ..writeln('    $entityGraphName entityGraph, {')
        ..writeln('    EntityPredicate<${source.className}>? where,')
        ..writeln('    EntityOrder<${source.className}>? orderBy,')
        ..write(
          isMutableRelationshipSource
              ? ''
              : '    TombstoneVisibility tombstones = '
                    'TombstoneVisibility.exclude,\n',
        );
      if (!isMutableRelationshipSource) {
        _emitArchiveParameter(buffer, source);
      }
      buffer
        ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
        ..writeln('  }) {')
        ..writeln(
          '    return ${isMutableRelationshipSource || canCreateThroughReference ? returnType : '${source.className}List.for${_upperCamel(reference.accessorName)}'}(',
        )
        ..writeln('      entityGraph,')
        ..writeln('      ${EntityConventions.idFieldName},')
        ..writeln('      where: where,')
        ..writeln('      orderBy: orderBy,')
        ..write(
          isMutableRelationshipSource ? '' : '      tombstones: tombstones,\n',
        )
        ..write(
          isMutableRelationshipSource
              ? ''
              : _archiveArgument(source, indent: '      '),
        )
        ..writeln('      pageSize: pageSize,')
        ..writeln('    );')
        ..writeln('  }')
        ..writeln('}')
        ..writeln();
    }
  }
}

/// Emits an inverse collection that binds its source reference for creation.
///
/// The entity set remains the only persistence implementation. This wrapper
/// only removes the already-known parent ID from the caller contract, so a
/// normalized child collection needs no handwritten factory or repository.
void _emitCreationRelationship(
  StringBuffer buffer, {
  required EntitySpec source,
  required FieldSpec field,
  required String entityGraphName,
}) {
  final className = generatedInverseCreationTypeName(field);
  final createParameters = source.createParameters
      .where(
        (candidate) =>
            candidate != field && candidate.persistedVariantName == null,
      )
      .toList(growable: false);
  final createVariants = source.persistedVariants
      .where(
        (variant) =>
            variant.storageFields.any(source.createParameters.contains),
      )
      .toList(growable: false);
  final boundType = field.dartType.replaceAll('?', '');
  buffer
    ..writeln(
      'final class $className extends EntityList<${source.className}> {',
    )
    ..writeln('  $className(')
    ..writeln('    $entityGraphName entityGraph,')
    ..writeln('    $boundType ${field.name}, {')
    ..writeln('    EntityPredicate<${source.className}>? where,')
    ..writeln('    EntityOrder<${source.className}>? orderBy,')
    ..writeln(
      '    TombstoneVisibility tombstones = TombstoneVisibility.exclude,',
    );
  _emitArchiveParameter(buffer, source);
  buffer
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln('  }) : _entityGraph = entityGraph,')
    ..writeln('       _${field.name} = ${field.name},')
    ..writeln('       super(entityGraph.${source.setAccessor}.query(')
    ..writeln(
      '         where: ${source.className}Fields.${field.name}.equals(${field.name}) &',
    )
    ..writeln(
      '             (where ?? EntityPredicate<${source.className}>.all()),',
    )
    ..writeln('         orderBy: ${_graphListOrderBy(source)},')
    ..writeln('         tombstones: tombstones,')
    ..write(_archiveArgument(source))
    ..writeln('         pageSize: pageSize,')
    ..writeln('       ));')
    ..writeln('  final $entityGraphName _entityGraph;')
    ..writeln('  final $boundType _${field.name};')
    ..writeln();

  final methods = source.hasOrderedCapability
      ? const [('create', 'create'), ('createFirst', 'createFirst')]
      : const [('create', 'create')];
  for (final (methodName, setMethod) in methods) {
    buffer
      ..writeln('  Future<${source.className}> $methodName({')
      ..writeln('    LocalId<${source.className}>? id,');
    _emitRelationshipCreateParameters(buffer, createParameters);
    _emitRelationshipVariantCreateParameters(buffer, createVariants);
    buffer
      ..writeln('  }) => _entityGraph.${source.setAccessor}.$setMethod(')
      ..writeln('    id: id,')
      ..writeln('    ${field.name}: _${field.name},');
    for (final parameter in createParameters) {
      buffer.writeln('    ${parameter.name}: ${parameter.name},');
    }
    for (final variant in createVariants) {
      buffer.writeln('    ${variant.name}: ${variant.name},');
    }
    buffer
      ..writeln('  );')
      ..writeln();
  }
  buffer
    ..writeln('}')
    ..writeln();
}

void _emitRelationshipVariantCreateParameters(
  StringBuffer buffer,
  List<PersistedVariantSpec> variants,
) {
  for (final variant in variants) {
    buffer.writeln(
      '    ${variant.nullable ? '' : 'required '}${variant.dartType} '
      '${variant.name},',
    );
  }
}

void _emitRelationshipCreateParameters(
  StringBuffer buffer,
  List<FieldSpec> fields,
) {
  for (final field in fields) {
    final required = !field.nullable && field.defaultValue == null;
    final defaultValue = field.defaultValue == null
        ? ''
        : ' = ${domainDefaultLiteral(field)}';
    buffer.writeln(
      '    ${required ? 'required ' : ''}${field.dartType} '
      '${field.name}$defaultValue,',
    );
  }
}

void _emitActiveRelationship(
  StringBuffer buffer, {
  required EntitySpec source,
  required ActiveRelationshipSpec relationship,
  required RelationshipCardinalityResolution cardinalityResolution,
  required String entityGraphName,
}) {
  final className = '${source.className}Relationship';
  final ownerField = relationship.ownerReference;
  final targetField = relationship.targetReference;
  final activeField = relationship.activeField;
  final targetIdType = targetField.dartType;
  final sourceEntityType = localIdTypeArgument(ownerField.dartType);
  final targetEntityType = localIdTypeArgument(targetField.dartType);
  final deletedAt = source.fields.singleWhere(
    (field) => field.name == EntityConventions.deletedAtFieldName,
  );
  final sourcePredicate =
      '${source.className}Fields.${ownerField.name}.equals(_${ownerField.name})';
  final activePredicate =
      '$sourcePredicate & '
      '${source.className}Fields.${deletedAt.name}.isNull';
  buffer
    ..writeln(
      'final class $className extends EntityList<${source.className}> {',
    )
    ..writeln('  $className(')
    ..writeln('    $entityGraphName entityGraph,')
    ..writeln('    ${ownerField.dartType} ${ownerField.name}, {')
    ..writeln('    EntityPredicate<${source.className}>? where,')
    ..writeln('    EntityOrder<${source.className}>? orderBy,')
    ..writeln('    int pageSize = EntityQuerySpec.defaultPageSize,')
    ..writeln('  }) : _entityGraph = entityGraph,')
    ..writeln('       _${ownerField.name} = ${ownerField.name},')
    ..writeln('       super(')
    ..writeln('         entityGraph.${source.setAccessor}.query(')
    ..writeln('           where:')
    ..writeln('               ${source.className}Fields.${ownerField.name}')
    ..writeln('                       .equals(${ownerField.name}) &')
    ..writeln(
      '                   ${source.className}Fields.${activeField.name}.equals(true) &',
    )
    ..writeln(
      '                   ${source.className}Fields.${deletedAt.name}.isNull &',
    )
    ..writeln(
      '                   (where ?? EntityPredicate<${source.className}>.all()),',
    )
    ..writeln(
      '           orderBy: ${source.hasOrderedCapability ? 'orderBy ?? entityGraph.${source.setAccessor}.canonicalOrder' : 'orderBy'},',
    )
    ..writeln('           pageSize: pageSize,')
    ..writeln('         ),')
    ..writeln('       );')
    ..writeln('  final $entityGraphName _entityGraph;')
    ..writeln('  final ${ownerField.dartType} _${ownerField.name};')
    ..writeln()
    ..writeln('  Future<void> link($targetIdType targetId) =>')
    ..writeln('      _useExisting(targetId, (existing) async {')
    ..writeln('        if (existing?.${activeField.name} == true) return;')
    ..writeln('        await _entityGraph.transaction(() async {')
    ..writeln('          if (existing == null) {')
    ..writeln('            await _entityGraph.${source.setAccessor}.create(')
    ..writeln('              ${ownerField.name}: _${ownerField.name},')
    ..writeln('              ${targetField.name}: targetId,')
    ..writeln('            );')
    ..writeln('          } else {')
    ..writeln('            await existing.activate();')
    ..writeln('          }')
    ..writeln('        });')
    ..writeln('      });')
    ..writeln()
    ..writeln('  Future<void> unlink($targetIdType targetId) =>')
    ..writeln('      _useExisting(targetId, (existing) async {')
    ..writeln(
      '        if (existing == null || !existing.${activeField.name}) return;',
    )
    ..writeln('        await _entityGraph.transaction(() async {')
    ..writeln('          await existing.deactivate();')
    ..writeln('        });')
    ..writeln('      });')
    ..writeln();
  if (cardinalityResolution.cardinality == Cardinality.bounded) {
    buffer
      ..writeln(
        '  Future<void> replace(Iterable<$targetIdType> targetIds) async {',
      )
      ..writeln('    final requested = targetIds.toList(growable: false);')
      ..writeln('    if (requested.toSet().length != requested.length) {')
      ..writeln('      throw const EntityValidationException(')
      ..writeln("        entityType: '${source.className}',")
      ..writeln("        field: '${targetField.name}',")
      ..writeln(
        "        message: 'A relationship target may appear only once.',",
      )
      ..writeln('      );')
      ..writeln('    }')
      ..writeln('    await _entityGraph.${source.setAccessor}')
      ..writeln('        .query(')
      ..writeln('          where:')
      ..writeln('              $activePredicate,')
      ..writeln('        )')
      ..writeln('        .useAll((existing) async {')
      ..writeln(
        '          final byTarget = <$targetIdType, ${source.className}>{};',
      )
      ..writeln('          for (final link in existing) {')
      ..writeln('            if (byTarget[link.${targetField.name}] != null) {')
      ..writeln('              throw StateError(')
      ..writeln(
        "                'Duplicate ${source.className} rows violate generated uniqueness.',",
      )
      ..writeln('              );')
      ..writeln('            }')
      ..writeln('            byTarget[link.${targetField.name}] = link;')
      ..writeln('          }')
      ..writeln(
        '          final baseActive = existing.where((link) => link.${activeField.name}).toList(growable: false);',
      );
    if (source.hasOrderedCapability) {
      buffer
        ..writeln('          if (baseActive.length == requested.length &&')
        ..writeln('              baseActive.indexed.every((entry) =>')
        ..writeln(
          '                  entry.\$2.${targetField.name} == requested[entry.\$1])) {',
        )
        ..writeln('            return;')
        ..writeln('          }');
    } else {
      buffer
        ..writeln(
          '          final activeTargets = baseActive.map((link) => link.${targetField.name}).toSet();',
        )
        ..writeln('          if (activeTargets.length == requested.length &&')
        ..writeln('              activeTargets.containsAll(requested)) {')
        ..writeln('            return;')
        ..writeln('          }');
    }
    buffer
      ..writeln('          late final List<${source.className}> active;')
      ..writeln(
        '          await _entityGraph._coordinator.replaceActiveRelationship(',
      )
      ..writeln('            applyLocalProjection: () async {')
      ..writeln('              active = <${source.className}>[];')
      ..writeln('            for (final targetId in requested) {')
      ..writeln('              final current = byTarget[targetId];')
      ..writeln('              if (current == null) {')
      ..writeln('                active.add(')
      ..writeln(
        '                  await _entityGraph.${source.setAccessor}.create(',
      )
      ..writeln('                    ${ownerField.name}: _${ownerField.name},')
      ..writeln('                    ${targetField.name}: targetId,')
      ..writeln('                  ),')
      ..writeln('                );')
      ..writeln('              } else {')
      ..writeln('                if (!current.${activeField.name}) {')
      ..writeln('                  await current.activate();')
      ..writeln('                }')
      ..writeln('                active.add(current);')
      ..writeln('              }')
      ..writeln('            }')
      ..writeln('            final requestedSet = requested.toSet();')
      ..writeln('            for (final current in existing) {')
      ..writeln('              if (current.${activeField.name} &&')
      ..writeln(
        '                  !requestedSet.contains(current.${targetField.name})) {',
      )
      ..writeln('                await current.deactivate();')
      ..writeln('              }')
      ..writeln('            }');
    if (source.hasOrderedCapability) {
      buffer
        ..writeln('            if (active.isNotEmpty) {')
        ..writeln('              final ranks = GeneratedOrderRanks.allocate(')
        ..writeln('                count: active.length,')
        ..writeln('              )!;')
        ..writeln(
          '              final changes = <GeneratedOrderStateChange<${source.className}>>[];',
        )
        ..writeln('              try {')
        ..writeln(
          '                for (final (index, link) in active.indexed) {',
        )
        ..writeln(
          '                  final change = link.generatedAccess.generatedOrderAccess!',
        )
        ..writeln(
          '                      .prepareGeneratedOrderRank(ranks[index]);',
        )
        ..writeln('                  if (change != null) changes.add(change);')
        ..writeln('                }')
        ..writeln('              } catch (_) {')
        ..writeln('                for (final change in changes.reversed) {')
        ..writeln('                  change.rollbackIfCurrent();')
        ..writeln('                }')
        ..writeln('                rethrow;')
        ..writeln('              }')
        ..writeln('              final target = active.first;')
        ..writeln(
          '              await target.generatedAccess.generatedOrderAccess!',
        )
        ..writeln('                  .recordGeneratedExactOrder(')
        ..writeln('                    changes: changes,')
        ..writeln('                    command: ReorderOrderedCommand(')
        ..writeln(
          '                      orderedIds: active.map((link) => link.id),',
        )
        ..writeln('                      scopeBaseVersion: _entityGraph')
        ..writeln(
          '                          ._${_lowerCamel(source.className)}Engine',
        )
        ..writeln('                          .orderScopeVersionFor(')
        ..writeln('                            target.generatedAccess')
        ..writeln('                                .generatedOrderAccess!')
        ..writeln('                                .generatedOrderScopeKey,')
        ..writeln('                          ),')
        ..writeln('                    ),')
        ..writeln('                  );')
        ..writeln('            }');
    }
    buffer
      ..writeln('            },')
      ..writeln('            recordSemanticCommand: () {')
      ..writeln(
        '              final anchor = active.firstOrNull ?? baseActive.first;',
      )
      ..writeln(
        '              return anchor.generatedAccess.recordGeneratedCommand(',
      )
      ..writeln(
        '                ReplaceActiveRelationshipCommand<${source.className}, $sourceEntityType, $targetEntityType>(',
      )
      ..writeln('                  sourceId: _${ownerField.name},')
      ..writeln(
        '                  baseActiveLinkIds: baseActive.map((link) => link.id),',
      )
      ..writeln('                  activeMembers: active.map(')
      ..writeln('                    (link) => ActiveRelationshipMember(')
      ..writeln('                      linkId: link.id,')
      ..writeln('                      targetId: link.${targetField.name},')
      ..writeln('                    ),')
      ..writeln('                  ),')
      ..writeln('                ),')
      ..writeln('              );')
      ..writeln('            },')
      ..writeln('          );')
      ..writeln('        });')
      ..writeln('  }')
      ..writeln();
  }
  if (source.hasOrderedCapability) {
    buffer
      ..writeln('  Future<void> moveFirst($targetIdType targetId) =>')
      ..writeln('      _useActive(targetId, (link) =>')
      ..writeln(
        '          _entityGraph.${source.setAccessor}.prepend(link.id));',
      )
      ..writeln()
      ..writeln('  Future<void> moveLast($targetIdType targetId) =>')
      ..writeln('      _useActive(targetId, (link) =>')
      ..writeln(
        '          _entityGraph.${source.setAccessor}.append(link.id));',
      )
      ..writeln()
      ..writeln('  Future<void> moveBefore(')
      ..writeln('    $targetIdType targetId,')
      ..writeln('    $targetIdType neighborTargetId,')
      ..writeln('  ) => _useActive(targetId, (link) =>')
      ..writeln('      _useActive(neighborTargetId, (neighbor) =>')
      ..writeln(
        '          _entityGraph.${source.setAccessor}.moveBefore(link.id, neighbor.id)));',
      )
      ..writeln()
      ..writeln('  Future<void> moveAfter(')
      ..writeln('    $targetIdType targetId,')
      ..writeln('    $targetIdType neighborTargetId,')
      ..writeln('  ) => _useActive(targetId, (link) =>')
      ..writeln('      _useActive(neighborTargetId, (neighbor) =>')
      ..writeln(
        '          _entityGraph.${source.setAccessor}.moveAfter(link.id, neighbor.id)));',
      )
      ..writeln();
  }
  if (source.hasOrderedCapability) {
    buffer
      ..writeln('  Future<R> _useActive<R>(')
      ..writeln('    $targetIdType targetId,')
      ..writeln('    Future<R> Function(${source.className} link) action,')
      ..writeln('  ) => _useExisting(targetId, (existing) {')
      ..writeln(
        '      if (existing == null || !existing.${activeField.name}) {',
      )
      ..writeln('        throw const EntityValidationException(')
      ..writeln("          entityType: '${source.className}',")
      ..writeln("          field: '${targetField.name}',")
      ..writeln(
        "          message: 'Ordered relationship movement requires an active link.',",
      )
      ..writeln('        );')
      ..writeln('      }')
      ..writeln('      return action(existing);')
      ..writeln('    });')
      ..writeln();
  }
  buffer
    ..writeln('  Future<R> _useExisting<R>(')
    ..writeln('    $targetIdType targetId,')
    ..writeln('    Future<R> Function(${source.className}? existing) action,')
    ..writeln('  ) =>')
    ..writeln('      _entityGraph.${source.setAccessor}')
    ..writeln('          .query(')
    ..writeln('            where:')
    ..writeln('                $activePredicate &')
    ..writeln(
      '                ${source.className}Fields.${targetField.name}.equals(targetId),',
    )
    ..writeln('            pageSize: 2,')
    ..writeln('          )')
    ..writeln('          .useAll((matches) async {')
    ..writeln('            if (matches.length > 1) {')
    ..writeln('              throw StateError(')
    ..writeln(
      "                'Duplicate ${source.className} rows violate generated uniqueness.',",
    )
    ..writeln('              );')
    ..writeln('            }')
    ..writeln(
      '            return action(matches.isEmpty ? null : matches.single);',
    )
    ..writeln('          });')
    ..writeln('}')
    ..writeln();
}

void _emitEntityGraphRuntime(
  StringBuffer buffer,
  EntityGraphSpec graph,
  String databaseName, {
  required bool usesManagedFlutterRuntime,
}) {
  final entityGraphName = '${graph.className}EntityGraph';
  final accountType = graph.accountClassName;
  buffer
    ..writeln('final class $entityGraphName {')
    ..write('  $entityGraphName._(this.accountId, this._coordinator');
  for (final entity in graph.entities) {
    buffer.write(', this._${_lowerCamel(entity.className)}Engine');
  }
  buffer.writeln(')');
  for (var index = 0; index < graph.entities.length; index++) {
    final entity = graph.entities[index];
    final prefix = index == 0 ? '      : ' : '        ';
    final suffix = index == graph.entities.length - 1 ? ',' : ',';
    buffer.writeln(
      '$prefix${entity.setAccessor} = '
      '${entity.className}Set(_${_lowerCamel(entity.className)}Engine)$suffix',
    );
  }
  buffer
    ..writeln('        syncQueue = _coordinator.syncQueue;')
    ..writeln('  final LocalId<$accountType> accountId;')
    ..writeln('  final LocalEntityGraphCoordinator _coordinator;');
  for (final entity in graph.entities) {
    buffer.writeln(
      '  final LocalEntityEngine<${entity.className}, '
      '${entity.className}Record> '
      '_${_lowerCamel(entity.className)}Engine;',
    );
  }
  for (final entity in graph.entities) {
    buffer.writeln('  final ${entity.className}Set ${entity.setAccessor};');
  }
  buffer
    ..writeln('  final SyncQueue syncQueue;')
    ..writeln('  Future<void>? _closeFuture;')
    ..writeln('  static Future<$entityGraphName> open({')
    ..writeln('    required LocalId<$accountType> accountId,')
    ..writeln('    required QueryExecutor executor,')
    ..writeln(
      graph.syncTargets.isEmpty
          ? '    ${graph.className}SyncAdapters syncAdapters = '
                'const ${graph.className}SyncAdapters(),'
          : '    required ${graph.className}SyncAdapters syncAdapters,',
    )
    ..writeln('    MigrationStrategy? migrationOverride,')
    ..writeln('    Clock clock = const SystemClock(),')
    ..writeln(
      '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
    )
    ..writeln(
      '    LocalEntityDiagnostics diagnostics = '
      'const NoopLocalEntityDiagnostics(),',
    )
    ..writeln('    bool autoSync = true,')
    ..writeln('  }) async {')
    ..writeln('    final adapterRegistry = syncAdapters.bind();')
    ..writeln('    final database = $databaseName(')
    ..writeln('      executor, migrationOverride: migrationOverride,')
    ..writeln('    );')
    ..writeln('    final coordinator = LocalEntityGraphCoordinator(')
    ..writeln('      database: database,')
    ..writeln('      adapters: adapterRegistry,')
    ..writeln('      definition: ${graph.className}Metadata.definition,')
    ..writeln('      authenticatedPrincipalId: accountId.value,')
    ..writeln('      autoSync: autoSync,')
    ..writeln('      clock: clock,')
    ..writeln('      idGenerator: idGenerator,')
    ..writeln('      diagnostics: diagnostics,')
    ..writeln('    );')
    ..writeln('    try {');
  for (final entity in graph.entities) {
    final lower = _lowerCamel(entity.className);
    buffer
      ..writeln(
        '      final ${lower}Engine = '
        'await LocalEntityEngine.openInGraph(',
      )
      ..writeln(
        '        descriptor: '
        '${graph.className}Metadata.${lower}Descriptor,',
      )
      ..writeln('        database: database,')
      ..writeln(
        "        backend: adapterRegistry.backendForEntity('${entity.className}'),",
      )
      ..writeln('        clock: clock,')
      ..writeln('        idGenerator: idGenerator,')
      ..writeln('        graphCoordinator: coordinator,')
      ..writeln('      );');
  }
  buffer
    ..writeln('      await coordinator.start();')
    ..write('      return $entityGraphName._(accountId, coordinator');
  for (final entity in graph.entities) {
    buffer.write(', ${_lowerCamel(entity.className)}Engine');
  }
  buffer
    ..writeln(');')
    ..writeln('    } catch (_) {')
    ..writeln('      await coordinator.close();')
    ..writeln('      rethrow;')
    ..writeln('    }')
    ..writeln('  }')
    ..writeln('  static Future<$entityGraphName> openInMemory({')
    ..writeln('    required LocalId<$accountType> accountId,');
  for (final target in graph.syncTargets) {
    buffer.writeln(
      '    InMemorySyncBackend? ${lowerCamelCase(target.wireName)}Backend,',
    );
  }
  buffer
    ..writeln('    MigrationStrategy? migrationOverride,')
    ..writeln('    Clock clock = const SystemClock(),')
    ..writeln(
      '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
    )
    ..writeln(
      '    LocalEntityDiagnostics diagnostics = '
      'const NoopLocalEntityDiagnostics(),',
    )
    ..writeln('    bool autoSync = false,')
    ..writeln('  }) {');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer
      ..writeln('    final resolved${_upperCamel(name)}Backend =')
      ..writeln('        ${name}Backend ?? InMemorySyncBackend.graph(')
      ..writeln(
        '          definition: ${graph.className}Metadata.${name}SyncDefinition,',
      )
      ..writeln('        );');
  }
  buffer
    ..writeln('    return open(')
    ..writeln('      accountId: accountId,')
    ..writeln(
      usesManagedFlutterRuntime
          ? '      executor: openNodusInMemoryExecutor(),'
          : '      executor: NativeDatabase.memory(),',
    )
    ..writeln('      syncAdapters: ${graph.className}SyncAdapters(');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer.writeln('        $name: resolved${_upperCamel(name)}Backend,');
  }
  buffer
    ..writeln('      ),')
    ..writeln('      migrationOverride: migrationOverride,')
    ..writeln('      clock: clock,')
    ..writeln('      idGenerator: idGenerator,')
    ..writeln('      diagnostics: diagnostics,')
    ..writeln('      autoSync: autoSync,')
    ..writeln('    );')
    ..writeln('  }');
  if (usesManagedFlutterRuntime && graph.syncTargets.isNotEmpty) {
    _emitManagedConnectorFactories(buffer, graph, entityGraphName, accountType);
  }
  final supabaseTargets = graph.syncTargets
      .where((target) => target.wireName == 'supabase')
      .toList(growable: false);
  if (supabaseTargets.length == 1 && graph.syncTargets.length == 1) {
    buffer
      ..writeln('  static Future<$entityGraphName> openSupabase({')
      ..writeln('    required LocalId<$accountType> accountId,')
      ..writeln('    required SupabaseClient client,')
      ..writeln(
        '    NodusLocalStore localStore = '
        'const ApplicationSupportNodusLocalStore(),',
      )
      ..writeln('    MigrationStrategy? migrationOverride,')
      ..writeln('    Clock clock = const SystemClock(),')
      ..writeln(
        '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
      )
      ..writeln(
        '    LocalEntityDiagnostics diagnostics = '
        'const NoopLocalEntityDiagnostics(),',
      )
      ..writeln('    bool autoSync = true,')
      ..writeln('  }) {')
      ..writeln('    return openWithConnectors(')
      ..writeln('      accountId: accountId,')
      ..writeln('      supabase: (context) => SupabaseSyncBackend.graph(')
      ..writeln('        client: client,')
      ..writeln('        definition: context.definition,')
      ..writeln('      ),')
      ..writeln('      localStore: localStore,')
      ..writeln('      migrationOverride: migrationOverride,')
      ..writeln('      clock: clock,')
      ..writeln('      idGenerator: idGenerator,')
      ..writeln('      diagnostics: diagnostics,')
      ..writeln('      autoSync: autoSync,')
      ..writeln('    );')
      ..writeln('  }');
  }
  buffer
    ..writeln(
      '  ReadOnlyObservableList<LocalPersistenceFailure> '
      'get persistenceFailures => _coordinator.persistenceFailures;',
    )
    ..writeln('  DateTime nowUtc() => _coordinator.clock.nowUtc();')
    ..writeln('  Future<void> flushLocal() => _coordinator.flushLocal();')
    ..writeln(
      '  Future<R> transaction<R>(FutureOr<R> Function() body) => '
      '_coordinator.transaction(body);',
    )
    ..writeln('  Future<void> sync() => _coordinator.sync();')
    ..writeln('  Future<void> close() => _closeFuture ??= _close();')
    ..writeln('  Future<void> _close() async {');
  for (final entity in graph.entities) {
    buffer.writeln('    ${entity.setAccessor}.dispose();');
  }
  buffer
    ..writeln('    await _coordinator.close();')
    ..writeln('  }')
    ..writeln('}');
}

void _emitManagedConnectorFactories(
  StringBuffer buffer,
  EntityGraphSpec graph,
  String entityGraphName,
  String accountType,
) {
  buffer
    ..writeln('  static Future<$entityGraphName> openWithConnectors({')
    ..writeln('    required LocalId<$accountType> accountId,');
  for (final target in graph.syncTargets) {
    buffer.writeln(
      '    required SyncConnector<${_syncAdapterType(graph, target)}> '
      '${lowerCamelCase(target.wireName)},',
    );
  }
  buffer
    ..writeln(
      '    NodusLocalStore localStore = '
      'const ApplicationSupportNodusLocalStore(),',
    )
    ..writeln('    MigrationStrategy? migrationOverride,')
    ..writeln('    Clock clock = const SystemClock(),')
    ..writeln(
      '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
    )
    ..writeln(
      '    LocalEntityDiagnostics diagnostics = '
      'const NoopLocalEntityDiagnostics(),',
    )
    ..writeln('    bool autoSync = true,')
    ..writeln('  }) async {');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer
      ..writeln('    final connected${_upperCamel(name)} = await $name(')
      ..writeln('      SyncConnectorContext(')
      ..writeln('        accountId: accountId.value,')
      ..writeln('        target: ${graph.className}Metadata.${name}SyncTarget,')
      ..writeln(
        '        definition: ${graph.className}Metadata.${name}SyncDefinition,',
      )
      ..writeln('      ),')
      ..writeln('    );');
  }
  buffer.writeln('    final syncAdapters = ${graph.className}SyncAdapters(');
  for (final target in graph.syncTargets) {
    final name = lowerCamelCase(target.wireName);
    buffer.writeln('      $name: connected${_upperCamel(name)},');
  }
  buffer
    ..writeln('    );')
    ..writeln('    syncAdapters.bind();')
    ..writeln('    final executor = await localStore.open(')
    ..writeln("      packageName: '${graph.packageName}',")
    ..writeln('      accountId: accountId.value,')
    ..writeln('    );')
    ..writeln('    return open(')
    ..writeln('      accountId: accountId,')
    ..writeln('      executor: executor,')
    ..writeln('      syncAdapters: syncAdapters,')
    ..writeln('      migrationOverride: migrationOverride,')
    ..writeln('      clock: clock,')
    ..writeln('      idGenerator: idGenerator,')
    ..writeln('      diagnostics: diagnostics,')
    ..writeln('      autoSync: autoSync,')
    ..writeln('    );')
    ..writeln('  }');

  if (graph.syncTargets.length != 1 ||
      graph.syncTargets.single.wireName == 'supabase') {
    return;
  }
  final target = graph.syncTargets.single;
  final name = lowerCamelCase(target.wireName);
  final methodName = 'open${_upperCamel(name)}';
  buffer
    ..writeln('  static Future<$entityGraphName> $methodName({')
    ..writeln('    required LocalId<$accountType> accountId,')
    ..writeln(
      '    required SyncConnector<${_syncAdapterType(graph, target)}> connector,',
    )
    ..writeln(
      '    NodusLocalStore localStore = '
      'const ApplicationSupportNodusLocalStore(),',
    )
    ..writeln('    MigrationStrategy? migrationOverride,')
    ..writeln('    Clock clock = const SystemClock(),')
    ..writeln(
      '    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),',
    )
    ..writeln(
      '    LocalEntityDiagnostics diagnostics = '
      'const NoopLocalEntityDiagnostics(),',
    )
    ..writeln('    bool autoSync = true,')
    ..writeln('  }) {')
    ..writeln('    return openWithConnectors(')
    ..writeln('      accountId: accountId,')
    ..writeln('      $name: connector,')
    ..writeln('      localStore: localStore,')
    ..writeln('      migrationOverride: migrationOverride,')
    ..writeln('      clock: clock,')
    ..writeln('      idGenerator: idGenerator,')
    ..writeln('      diagnostics: diagnostics,')
    ..writeln('      autoSync: autoSync,')
    ..writeln('    );')
    ..writeln('  }');
}

void _emitLocalCompositionTriggerMethod(
  StringBuffer buffer,
  EntityGraphSpec graph,
) {
  buffer
    ..writeln()
    ..writeln(
      '  Future<void> _installCompositionTriggers({required bool replace}) async {',
    );
  final byTarget = <String, List<(EntitySpec, FieldSpec)>>{};
  for (final aggregate in graph.entities) {
    for (final field in aggregate.fields.where(
      (field) => field.isComposition,
    )) {
      byTarget
          .putIfAbsent(
            field.reference!.targetClassName,
            () => <(EntitySpec, FieldSpec)>[],
          )
          .add((aggregate, field));
    }
  }
  for (final entry in byTarget.entries) {
    final component = graph.entities.singleWhere(
      (entity) => entity.className == entry.key,
    );
    final sources = entry.value;
    for (final (aggregate, field) in sources) {
      final base = '${aggregate.tableName}_${field.columnName}_composition';
      final existing = sources
          .map((source) {
            final stored =
                'SELECT 1 FROM ${source.$1.tableName} candidate '
                'WHERE candidate.${source.$2.columnName} = NEW.${field.columnName} '
                "AND NOT (candidate.${source.$1.idField.columnName} = NEW.${aggregate.idField.columnName} AND '${source.$1.tableName}' = '${aggregate.tableName}' AND '${source.$2.columnName}' = '${field.columnName}')";
            if (source.$1.className == aggregate.className &&
                source.$2.name != field.name) {
              return '$stored UNION ALL SELECT 1 '
                  'WHERE NEW.${source.$2.columnName} = NEW.${field.columnName}';
            }
            return stored;
          })
          .join(' UNION ALL ');
      final remaining = sources
          .map(
            (source) =>
                'SELECT 1 FROM ${source.$1.tableName} candidate '
                'WHERE candidate.${source.$2.columnName} = OLD.${field.columnName}',
          )
          .join(' UNION ALL ');
      final checks =
          '''
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM ${component.tableName} component
    WHERE component.${component.idField.columnName} = NEW.${field.columnName}
      AND component.${component.ownerField.columnName} = NEW.${aggregate.ownerField.columnName}
  ) THEN RAISE(ABORT, 'Composition component owner mismatch') END;
  SELECT CASE WHEN EXISTS ($existing)
    THEN RAISE(ABORT, 'Component identity already belongs to an aggregate') END;''';
      buffer
        ..writeln('    if (replace) {')
        ..writeln(
          "      await customStatement('DROP TRIGGER IF EXISTS ${base}_insert');",
        )
        ..writeln(
          "      await customStatement('DROP TRIGGER IF EXISTS ${base}_update');",
        )
        ..writeln(
          "      await customStatement('DROP TRIGGER IF EXISTS ${base}_cleanup');",
        )
        ..writeln('    }')
        ..writeln("    await customStatement(r'''CREATE TRIGGER ${base}_insert")
        ..writeln('BEFORE INSERT ON ${aggregate.tableName}')
        ..writeln('FOR EACH ROW BEGIN$checks')
        ..writeln("END''');")
        ..writeln("    await customStatement(r'''CREATE TRIGGER ${base}_update")
        ..writeln(
          'BEFORE UPDATE OF ${field.columnName} ON ${aggregate.tableName}',
        )
        ..writeln(
          'FOR EACH ROW WHEN NEW.${field.columnName} IS NOT OLD.${field.columnName} BEGIN$checks',
        )
        ..writeln("END''');")
        ..writeln(
          "    await customStatement(r'''CREATE TRIGGER ${base}_cleanup",
        )
        ..writeln('AFTER DELETE ON ${aggregate.tableName}')
        ..writeln('FOR EACH ROW BEGIN')
        ..writeln(
          '  DELETE FROM ${component.tableName} '
          'WHERE ${component.idField.columnName} = OLD.${field.columnName} '
          'AND NOT EXISTS ($remaining);',
        )
        ..writeln("END''');");
    }
  }
  buffer.writeln('  }');
}

String _generatedEntityImport(EntitySpec entity, {bool privateOutput = false}) {
  final prefix = 'package:${entity.packageName}/';
  final relative = entity.inputImport.substring(prefix.length);
  final generated = relative.replaceFirst(RegExp(r'\.dart$'), '.entity.g.dart');
  return privateOutput
      ? '${prefix}src/generated/entities/$generated'
      : '$prefix$generated';
}

String _lowerCamel(String value) =>
    value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';

String _upperCamel(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _idFieldAccessor(String value) =>
    value.endsWith('Id') && value.length > 2
    ? value.substring(0, value.length - 2)
    : value;
