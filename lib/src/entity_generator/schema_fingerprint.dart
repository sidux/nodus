import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'graph_sql_emitter.dart';
import 'model.dart';

/// Fingerprints the resolved physical local and remote schema.
///
/// Migration-only schema versions and generated Dart API formatting are
/// deliberately excluded. A compiler refactor therefore does not create a
/// fake migration, while every resolved table, column, constraint, index,
/// relationship, security rule, protocol, or target change does.
String entityGraphSchemaFingerprint(EntityGraphSpec graph) {
  final material = <String, Object?>{
    'graph': graph.className,
    'entities': [for (final entity in graph.entities) _entitySchema(entity)],
    'bindings': [
      for (final binding in graph.syncBindings)
        {
          'entity': binding.entity.className,
          'mode': binding.mode.name,
          'target': binding.target?.wireName,
        },
    ],
    'remoteSchemas': {
      for (final target in graph.syncTargets)
        target.wireName: target.wireName == 'supabase'
            ? emitEntityGraphSupabaseSql(
                graph.syncSubgraphFor(target),
              ).replaceFirst(RegExp(r'^-- Source:.*\n', multiLine: true), '')
            : null,
    },
  };
  return sha256.convert(utf8.encode(jsonEncode(material))).toString();
}

Map<String, Object?> _entitySchema(EntitySpec entity) => {
  'type': entity.className,
  'table': entity.tableName,
  'ownership': entity.ownership.name,
  'cardinality': entity.cardinality.name,
  'authenticatedReadSync': entity.authenticatedReadSync.name,
  'protocolVersion': entity.protocolVersion,
  'component': entity.isComponent,
  'ordered': entity.hasOrderedCapability,
  'archivable': entity.hasArchivableCapability,
  'activityTracked': entity.hasActivityTrackedCapability,
  'activitySubject': entity.activitySubjectClassName,
  'activityActor': entity.activityActorClassName,
  'fields': [
    for (final field in entity.fields)
      {
        'name': field.name,
        'column': field.columnName,
        'dartType': field.dartType,
        'sqlType': field.sqlType.name,
        'nullable': field.nullable,
        'final': field.isFinal,
        'default': field.persistedDefaultValue,
        'authority': field.authority.name,
        'minLength': field.minLength,
        'maxLength': field.maxLength,
        'allowWhitespace': field.allowWhitespace,
        'normalization': field.normalization.name,
        'minValue': field.minValue,
        'maxValue': field.maxValue,
        'allowedValues': field.allowedValues,
        'greaterThan': field.greaterThan,
        'greaterThanOrEqual': field.greaterThanOrEqual,
        'requires': field.requires,
        'notEqualTo': field.notEqualTo,
        'indexed': field.indexed,
        'unique': field.unique,
        'indexScope': field.indexScope.name,
        'enumValues': field.enumWireValues,
        'scalarSqlType': field.scalarValue?.sqlType.name,
        'sinceProtocolVersion': field.sinceProtocolVersion,
        'renamedFrom': field.renamedFrom,
        'participant': field.isParticipant,
        'accessReference': field.isAccessReference,
        'accessTarget': field.isAccessTarget,
        'composition': field.isComposition,
        'ownerReference': field.isOwnerReference,
        'reference': switch (field.reference) {
          final reference? => {
            'targetType': reference.targetClassName,
            'targetTable': reference.targetTableName,
            'onDelete': reference.onDelete.name,
            'hierarchy': reference.hierarchy,
            'targetOwnerColumn': reference.targetOwnerColumnName,
            'ownershipSourceColumn': reference.ownershipSourceColumnName,
            'targetRelationshipAccess': [
              for (final operation
                  in reference.targetRelationshipAccessOperations)
                operation.name,
            ],
          },
          null => null,
        },
        'accessTargetOperations': [
          for (final operation in field.accessTargetOperations) operation.name,
        ],
        'accessTargetType': field.accessTargetClassName,
        'accessTargetTable': field.accessTargetTableName,
        'accessTargetThroughColumn': field.accessTargetThroughColumnName,
        'accessTargetActiveStates': field.accessTargetActiveStates,
        'transitions': [
          for (final transition in field.transitions)
            {
              'from': transition.fromWire,
              'to': transition.toWire,
              'principals': [
                for (final principal in transition.principals) principal.name,
              ],
            },
        ],
        'updatePrincipals': [
          for (final principal in field.updatePrincipals) principal.name,
        ],
      },
  ],
  'indexes': [for (final index in entity.indexes) _indexSchema(entity, index)],
  'postgresIndexes': [
    for (final index in entity.postgresIndexes) _indexSchema(entity, index),
  ],
  'exclusiveGroups': [
    for (final group in entity.exclusiveFieldGroups)
      {'fields': group.fields, 'allowNone': group.allowNone},
  ],
  'security': {
    'grants': [
      for (final grant in entity.security.grants)
        {'operation': grant.operation.name, 'principal': grant.principal.name},
    ],
    'referenceGuards': [
      for (final operation in entity.security.referenceAccessGuards)
        operation.name,
    ],
    'relationshipAccess': [
      for (final operation in entity.relationshipAccessOperations)
        operation.name,
    ],
    'collaboration': switch (entity.security.collaboration) {
      final collaboration? => {
        'lifecycle': collaboration.lifecycle.name,
        'table': collaboration.membershipTable,
        'entityForeignKey': collaboration.entityForeignKey,
        'userForeignKey': collaboration.userForeignKey,
        'activeField': collaboration.activeField,
        'statusField': collaboration.statusField,
        'acceptedValue': collaboration.acceptedValue,
        'readableValues': collaboration.readableValues,
      },
      null => null,
    },
  },
};

Map<String, Object?> _indexSchema(EntitySpec entity, IndexSpec index) => {
  'name': entity.indexName(index),
  'columns': entity.indexColumns(index),
  'unique': index.unique,
  'ownerScoped': index.ownerScoped,
  'unordered': index.unordered,
  'activeOnly': index.activeOnly,
  'exactLookup': index.exactLookup,
  'condition': switch (index.condition) {
    final condition? => {'field': condition.field, 'values': condition.values},
    null => null,
  },
};
