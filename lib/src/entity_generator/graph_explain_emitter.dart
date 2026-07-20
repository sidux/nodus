import 'dart:convert';

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
    'entities': [
      for (final entity in graph.entities) {
          'name': entity.className,
          'source': entity.inputImport,
          'table': entity.tableName,
          'ownership': entity.ownership.name,
          'cardinality': entity.cardinality.name,
          'sync': {'mode': bindings[entity.className]!.mode.name, 'target': bindings[entity.className]!.target?.wireName},
          'capabilities': {'archivable': entity.hasArchivableCapability, 'ordered': entity.hasOrderedCapability, 'collaborative': entity.canCollaborate, 'activityTracked': graph.activityTrackings.any((tracking) => tracking.source.className == entity.className), 'component': entity.isComponent},
          'fields': [
            for (final field in entity.fields) {'name': field.name, 'type': field.dartType, 'column': field.columnName, 'nullable': field.nullable, 'default': field.defaultValue?.toString(), 'generated': field.generatedOnly, 'mutable': entity.isPatchable(field), 'reference': field.reference?.targetClassName, 'source': field.generatedOnly ? 'generated convention or capability' : 'entity declaration'},
          ],
          'indexes': [
            for (final index in entity.compoundIndexes) {'fields': index.fields, 'unique': index.unique, 'scope': index.scope.name, 'keyset': index.keyset},
          ],
          'actions': [
            for (final action in entity.actions) {
                'name': action.methodName,
                'parameters': [
                  for (final parameter in action.parameters) {'name': parameter.name, 'type': parameter.dartType, 'named': parameter.named},
                ],
                'fields': action.targetFields,
              },
          ],
          'generatedApi': {'set': '${entity.className}Set', 'list': '${entity.className}List', 'draft': '${entity.className}MutationDraft', 'create': entity.canCreatePublicly},
        },
    ],
  })}\n';
}
