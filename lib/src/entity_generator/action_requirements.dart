import 'package:source_gen/source_gen.dart';

import 'check_ins.dart';
import 'model.dart';

/// One [RequireLinkedSpec] checked against its link and target entities.
final class ResolvedRequirement {
  ResolvedRequirement._({
    required this.spec,
    required this.link,
    required this.source,
    required this.target,
    required this.targetReference,
    required this.checkIns,
  });

  factory ResolvedRequirement.of(
    EntitySpec entity,
    RequireLinkedSpec spec,
    EntityGraphSpec graph,
  ) {
    final link =
        graph.entities
            .where((candidate) => candidate.className == spec.linkClassName)
            .firstOrNull ??
        (throw InvalidGenerationSourceError(
          'RequireLinked names ${spec.linkClassName}, which is not an entity.',
        ));
    if (link.activeField == null) {
      throw InvalidGenerationSourceError(
        'RequireLinked needs an Activatable link: ${link.className}.',
      );
    }
    final references = [
      for (final field in link.fields)
        if (field.reference != null && !field.nullable) field,
    ];
    final source = references
        .where((field) => field.reference!.targetClassName == entity.className)
        .firstOrNull;
    final targetReference = references
        .where((field) => field != source)
        .firstOrNull;
    if (source == null || targetReference == null || references.length != 2) {
      throw InvalidGenerationSourceError(
        '${link.className} must link ${entity.className} to one other entity.',
      );
    }
    final target = graph.entities.singleWhere(
      (candidate) =>
          candidate.className == targetReference.reference!.targetClassName,
    );
    for (final name in [...spec.done.keys, ...spec.counting.keys]) {
      final field = target.fields.where((field) => field.name == name);
      if (field.isEmpty || !field.single.isEnum) {
        throw InvalidGenerationSourceError(
          'RequireLinked reads `$name`, which is not an enum field of '
          '${target.className}.',
        );
      }
    }
    ResolvedCheckIns? checkIns;
    if (spec.checkedIn) {
      final log = graph.entities
          .where(
            (candidate) =>
                candidate.checkIns != null &&
                ResolvedCheckIns.of(candidate, graph).subject.className ==
                    target.className,
          )
          .firstOrNull;
      if (log == null) {
        throw InvalidGenerationSourceError(
          'RequireLinked.checkedIn needs CheckIns for ${target.className}.',
        );
      }
      checkIns = ResolvedCheckIns.of(log, graph);
    }
    return ResolvedRequirement._(
      spec: spec,
      link: link,
      source: source,
      target: target,
      targetReference: targetReference,
      checkIns: checkIns,
    );
  }

  final RequireLinkedSpec spec;
  final EntitySpec link;
  final FieldSpec source;
  final EntitySpec target;
  final FieldSpec targetReference;
  final ResolvedCheckIns? checkIns;

  FieldSpec field(String name) =>
      target.fields.singleWhere((field) => field.name == name);
}

/// The action's requirements, resolved, with the names both targets use.
final class ResolvedActionRequirements {
  ResolvedActionRequirements(this.entity, this.action, EntityGraphSpec graph)
    : requirements = [
        for (final spec in action.requirements)
          ResolvedRequirement.of(entity, spec, graph),
      ];

  final EntitySpec entity;
  final ActionSpec action;
  final List<ResolvedRequirement> requirements;

  String get dartMethod =>
      'require${action.methodName[0].toUpperCase()}${action.methodName.substring(1)}';
  String get sqlFunction =>
      'public.${entity.tableName}_${snakeCase(action.methodName)}_unfinished';

  String get verb => snakeCase(action.methodName).replaceAll('_', ' ');
  String get noun => snakeCase(entity.className).replaceAll('_', ' ');

  /// The refusal for unfinished work called [kind].
  String message(String kind) =>
      'Cannot $verb $noun with incomplete $kind. '
      '${verb[0].toUpperCase()}${verb.substring(1)} all linked $kind first.';
}

List<ResolvedActionRequirements> _all(EntityGraphSpec graph) => [
  for (final entity in graph.entities)
    for (final action in entity.actions)
      if (action.requirements.isNotEmpty)
        ResolvedActionRequirements(entity, action, graph),
];

/// Generated `require<Action>` checks on each entity whose actions declare
/// requirements.
String emitActionRequirementsDart(
  EntityGraphSpec graph,
  String entityGraphName,
) {
  final byEntity = <String, List<ResolvedActionRequirements>>{};
  for (final resolved in _all(graph)) {
    byEntity.putIfAbsent(resolved.entity.className, () => []).add(resolved);
  }
  final buffer = StringBuffer();
  for (final MapEntry(key: className, value: actions) in byEntity.entries) {
    buffer
      ..writeln()
      ..writeln('extension ${className}ActionRequirements on $className {');
    for (final resolved in actions) {
      final field = resolved.action.targetFields.first;
      buffer
        ..writeln(
          '  /// Refuses `${resolved.action.methodName}` while linked work is '
          'unfinished.',
        )
        ..writeln(
          '  Future<void> ${resolved.dartMethod}($entityGraphName entityGraph) async {',
        )
        ..writeln('    final unfinished = <String>[];');
      if (resolved.requirements.any((each) => each.checkIns != null)) {
        buffer.writeln(
          '    final today = LocalDate.fromDateTime(entityGraph.nowUtc().toLocal());',
        );
      }
      for (final requirement in resolved.requirements) {
        final link = requirement.link.className;
        final target = requirement.target.className;
        String matches(Map<String, List<String>> values) => [
          for (final MapEntry(key: name, value: constants) in values.entries)
            'const {${[for (final constant in constants) '${requirement.field(name).dartType.replaceAll('?', '')}.$constant'].join(', ')}}.contains(row.$name)',
        ].join(' && ');
        buffer
          ..writeln('    {')
          ..writeln('      final ids = await ${link}List.all(')
          ..writeln('        entityGraph,')
          ..writeln(
            '        where: ${link}Fields.${requirement.source.name}.equals(id) & '
            '${link}Fields.${requirement.link.activeField!.name}.equals(true),',
          )
          ..writeln(
            '      ).useAll((rows) => {for (final row in rows) row.${requirement.targetReference.name}});',
          )
          ..writeln('      final rows = ids.isEmpty')
          ..writeln('          ? const <$target>[]')
          ..writeln(
            '          : await ${target}List.all(entityGraph, where: ${target}Fields.id.isIn(ids))'
            '.useAll((rows) => List.of(rows));',
          )
          ..writeln('      for (final row in rows) {');
        if (requirement.spec.counting.isNotEmpty) {
          buffer.writeln(
            '        if (!(${matches(requirement.spec.counting)})) continue;',
          );
        }
        if (requirement.spec.done.isNotEmpty) {
          buffer.writeln(
            '        if (${matches(requirement.spec.done)}) continue;',
          );
        }
        if (requirement.checkIns != null) {
          buffer.writeln(
            '        if (!await row.owesCheckInOn(entityGraph, today)) continue;',
          );
        }
        buffer
          ..writeln(
            "        unfinished.add(${dartLiteral(requirement.spec.label)});",
          )
          ..writeln('        break;')
          ..writeln('      }')
          ..writeln('    }');
      }
      buffer
        ..writeln('    if (unfinished.isEmpty) return;')
        ..writeln(
          "    final kind = unfinished.length == 1 ? unfinished.single : 'items';",
        )
        ..writeln('    throw EntityValidationException(')
        ..writeln("      entityType: '$className',")
        ..writeln("      field: '$field',")
        ..writeln(
          "      message: '${resolved.message(r'$kind').replaceAll("'", r"\'")}',",
        )
        ..writeln('    );')
        ..writeln('  }');
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

/// Functions listing the labels of a row's unfinished linked work, which an
/// action's agent tool checks before it runs.
String emitActionRequirementsSql(EntityGraphSpec graph) {
  final buffer = StringBuffer();
  for (final resolved in _all(graph)) {
    final zone = resolved.requirements
        .map((each) => each.checkIns)
        .whereType<ResolvedCheckIns>()
        .firstOrNull;
    final checks = <String>[];
    for (final requirement in resolved.requirements) {
      final link = requirement.link;
      final target = requirement.target;
      String matches(Map<String, List<String>> values) => [
        for (final MapEntry(key: name, value: constants) in values.entries)
          'target.${requirement.field(name).columnName} in (${[for (final constant in constants) _quote(snakeCase(constant))].join(', ')})',
      ].join(' and ');
      final done = [
        if (requirement.spec.done.isNotEmpty) matches(requirement.spec.done),
        if (requirement.checkIns case final checkIns?)
          'not ${checkIns.owesFunction}(target.id, today)',
      ];
      final conditions = [
        'link.${requirement.source.columnName} = p_id',
        'link.${link.activeField!.columnName}',
        if (link.hasSoftDeletableCapability) 'link.deleted_at is null',
        if (target.hasSoftDeletableCapability) 'target.deleted_at is null',
        if (target.hasArchivableCapability) 'target.archived_at is null',
        if (requirement.spec.counting.isNotEmpty)
          matches(requirement.spec.counting),
        if (done.isNotEmpty) 'not (${done.join(' or ')})',
      ];
      checks.add('''
  if exists (
    select 1 from public.${link.tableName} link
    join public.${target.tableName} target on target.id = link.${requirement.targetReference.columnName}
    where ${conditions.join('\n      and ')}
  ) then
    unfinished := unfinished || ${_quote(requirement.spec.label)}::text;
  end if;''');
    }
    buffer.writeln('''
create or replace function ${resolved.sqlFunction}(p_id uuid)
returns text[]
language plpgsql
stable
set search_path = ''
as \$\$
declare
  unfinished text[] := '{}';
${zone == null ? '' : '''  today date := (now() at time zone coalesce(
    (select profile.${zone.timezone.columnName} from public.${zone.owner.tableName} profile where profile.id = auth.uid()),
    'UTC'
  ))::date;'''}
begin
${checks.join('\n')}
  return unfinished;
end;
\$\$;

revoke all on function ${resolved.sqlFunction}(uuid) from public, anon, authenticated, service_role;
grant execute on function ${resolved.sqlFunction}(uuid) to authenticated;
''');
  }
  return buffer.toString();
}

String _quote(String value) => "'${value.replaceAll("'", "''")}'";
