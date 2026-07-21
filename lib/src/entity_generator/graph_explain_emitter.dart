import 'dart:convert';

import '../annotations.dart';
import 'model.dart';

String emitEntityGraphExplanation(EntityGraphSpec graph) {
  final bindings = {
    for (final binding in graph.syncBindings) binding.entity.className: binding,
  };
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({
    'graph': graph.className,
    'package': graph.packageName,
    'schemaVersion': graph.schemaVersion,
    'targets': [for (final target in graph.syncTargets) target.wireName],
    'durableWork': [
      for (final binding in graph.durableWorkBindings) {
          'name': binding.name,
          'kind': binding.kind.name,
          'sources': [
            for (final source in binding.sources) {'entity': source.entityClassName, 'fields': source.fieldNames},
          ],
          'generatedInstall': binding.installMethodName,
          'generatedTrigger': binding.kind == DurableWorkBindingKind.projection ? binding.triggerMethodName : null,
        },
    ],
    'entities': [
      for (final entity in graph.entities) {
          'name': entity.className,
          'source': entity.inputImport,
          'table': entity.tableName,
          'ownership': entity.ownership.name,
          'cardinality': entity.cardinality.name,
          'coIdentityWith': entity.coIdentityClassNames,
          'sync': {'mode': bindings[entity.className]!.mode.name, 'target': bindings[entity.className]!.target?.wireName},
          'capabilities': {'archivable': entity.hasArchivableCapability, 'ordered': entity.hasOrderedCapability, 'collaborative': entity.canCollaborate, 'activityTracked': graph.activityTrackings.any((tracking) => tracking.source.className == entity.className), 'component': entity.isComponent},
          'fields': [
            for (final field in entity.fields) {'name': field.name, 'type': field.dartType, 'column': field.columnName, 'nullable': field.nullable, 'default': field.defaultValue?.toString(), 'generated': field.generatedOnly, 'mutable': entity.isPatchable(field), 'normalization': field.normalization.name, 'reference': field.reference?.targetClassName, 'inverseCardinality': field.reference == null ? null : entity.inverseCardinalityFor(field).name, 'hierarchy': field.reference?.hierarchy ?? false, 'source': field.generatedOnly ? 'generated convention or capability' : 'entity declaration'},
          ],
          'indexes': [
            for (final index in entity.compoundIndexes) {'fields': index.fields, 'unique': index.unique, 'scope': index.scope.name, 'keyset': index.keyset, 'activeOnly': index.activeOnly, 'exactLookup': index.exactLookup},
          ],
          'actions': [
            for (final action in entity.actions) {
                'name': action.methodName,
                'bulk': action.bulk,
                'parameters': [
                  for (final parameter in action.parameters) {'name': parameter.name, 'type': parameter.dartType, 'named': parameter.named},
                ],
                'fields': action.targetFields,
              },
          ],
          'generatedApi': {'set': '${entity.className}Set', 'setAccessor': entity.setAccessor, 'list': '${entity.className}List', 'boundedListConstructors': _boundedListConstructors(entity), 'draft': '${entity.className}MutationDraft', 'create': entity.canCreatePublicly},
        },
    ],
  })}\n';
}

List<String> _boundedListConstructors(EntitySpec entity) {
  final constructors = <String>{};
  for (final field in entity.fields) {
    final reference = field.reference;
    final accessor =
        reference?.accessorName ??
        (field.isParticipant ? _idFieldAccessor(field.name) : null);
    if (accessor == null || reference == null) continue;
    if (entity.inverseCardinalityFor(field) == Cardinality.bounded) {
      constructors.add('for${_upperCamel(accessor)}');
    }
  }
  if (entity.ownership == Ownership.separate &&
      entity.ownerField.reference != null &&
      entity.inverseCardinalityFor(entity.ownerField) == Cardinality.bounded) {
    constructors
      ..add('owned')
      ..add('forOwner');
  }
  return constructors.toList(growable: false)..sort();
}

String _idFieldAccessor(String fieldName) => fieldName.endsWith('Id')
    ? fieldName.substring(0, fieldName.length - 2)
    : fieldName;

String _upperCamel(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
