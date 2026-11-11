import 'package:nodus/nodus.dart';
import 'package:source_gen/source_gen.dart';

import 'model.dart';

/// An [AcyclicSpec] checked against its link entity and the entity it links.
final class ResolvedAcyclic {
  ResolvedAcyclic._(this.link, this.target, this.from, this.to);

  factory ResolvedAcyclic.of(EntitySpec link, EntityGraphSpec graph) {
    final spec = link.acyclic!;
    FieldSpec field(String name) =>
        link.fields.where((field) => field.name == name).firstOrNull ??
        (throw InvalidGenerationSourceError(
          'Acyclic names `$name`, which is not a field of ${link.className}.',
        ));
    final from = field(spec.fromFieldName);
    final to = field(spec.toFieldName);
    final targetClass = from.reference?.targetClassName;
    if (targetClass == null || to.reference?.targetClassName != targetClass) {
      throw InvalidGenerationSourceError(
        'Acyclic links two references to the same entity: '
        '${link.className}.${from.name} and ${to.name}.',
      );
    }
    if (link.activeField == null) {
      throw InvalidGenerationSourceError(
        'Acyclic needs an Activatable link: ${link.className}.',
      );
    }
    final target = graph.entities.singleWhere(
      (entity) => entity.className == targetClass,
    );
    if (spec.hierarchyMessage != null && target.hierarchyParentField == null) {
      throw InvalidGenerationSourceError(
        'Acyclic.hierarchy needs a hierarchy on $targetClass.',
      );
    }
    return ResolvedAcyclic._(link, target, from, to);
  }

  final EntitySpec link;
  final EntitySpec target;
  final FieldSpec from;
  final FieldSpec to;

  AcyclicSpec get spec => link.acyclic!;
  FieldSpec get active => link.activeField!;
  FieldSpec? get parent =>
      spec.hierarchyMessage == null ? null : target.hierarchyParentField;
  String get table => 'public.${link.tableName}';
  String get function => 'public.${link.tableName}_acyclic';
}

/// Generated `require<Link>` checks for every [Acyclic] link entity.
String emitAcyclicDart(EntityGraphSpec graph, String entityGraphName) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (entity.acyclic == null) continue;
    final rule = ResolvedAcyclic.of(entity, graph);
    final link = rule.link.className;
    final idType = 'LocalId<${rule.target.className}>';
    final from = rule.from.name;
    final to = rule.to.name;
    String refuse(String field, String message) =>
        'throw const EntityValidationException('
        "entityType: '$link', field: '$field', "
        'message: ${dartLiteral(message)});';
    buffer
      ..writeln()
      ..writeln('extension ${link}Rules on $entityGraphName {')
      ..writeln(
        '  /// Refuses a $link from [$from] to [$to] that the declared rule',
      )
      ..writeln('  /// forbids, before the target refuses it.')
      ..writeln(
        '  Future<void> require$link($idType $from, $idType $to) async {',
      );
    final parent = rule.parent;
    if (parent != null) {
      buffer
        ..writeln('    Future<Set<$idType>> ancestorsOf($idType id) async {')
        ..writeln('      final found = <$idType>{};')
        ..writeln('      $idType? next = id;')
        ..writeln('      while (true) {')
        ..writeln(
          '        next = await ${rule.target.setAccessor}.loadPresentById(next!)'
          '.use<$idType?>((row) => row.${parent.name}, ifAbsent: () => null);',
        )
        ..writeln('        if (next == null || !found.add(next)) return found;')
        ..writeln('      }')
        ..writeln('    }')
        ..writeln(
          '    if ((await ancestorsOf($from)).contains($to) || '
          '(await ancestorsOf($to)).contains($from)) {',
        )
        ..writeln('      ${refuse(to, rule.spec.hierarchyMessage!)}')
        ..writeln('    }');
    }
    buffer
      ..writeln('    final visited = <$idType>{$to};')
      ..writeln('    var frontier = {$to};')
      ..writeln('    while (frontier.isNotEmpty) {')
      ..writeln('      final next = await ${link}List.all(')
      ..writeln('        this,')
      ..writeln(
        '        where: ${link}Fields.$from.isIn(frontier) & '
        '${link}Fields.${rule.active.name}.equals(true),',
      )
      ..writeln(
        '      ).useAll((links) => {for (final link in links) link.$to});',
      )
      ..writeln('      if (next.contains($from)) {')
      ..writeln('        ${refuse(to, rule.spec.cycleMessage)}')
      ..writeln('      }')
      ..writeln('      frontier = next.difference(visited);')
      ..writeln('      visited.addAll(frontier);')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln('}');
  }
  return buffer.toString();
}

/// Trigger enforcing every [Acyclic] rule on each write that activates or
/// moves a link. It reads past row-level security, since a cycle may run
/// through links the writer cannot see, and only ever refuses.
String emitAcyclicSql(EntityGraphSpec graph) {
  final buffer = StringBuffer();
  for (final entity in graph.entities) {
    if (entity.acyclic == null) continue;
    final rule = ResolvedAcyclic.of(entity, graph);
    final from = rule.from.columnName;
    final to = rule.to.columnName;
    final active = rule.active.columnName;
    final live = rule.link.hasSoftDeletableCapability
        ? ' and link.deleted_at is null'
        : '';
    final parent = rule.parent;
    final targetTable = 'public.${rule.target.tableName}';
    String ancestors(String start, String sought) =>
        '''
exists (
    with recursive up(id) as (
      select row.${parent!.columnName} from $targetTable row where row.id = new.$start
      union
      select row.${parent.columnName} from $targetTable row join up on row.id = up.id
    )
    select 1 from up where up.id = new.$sought
  )''';
    final hierarchy = parent == null
        ? ''
        : '''
  if ${ancestors(from, to)} or ${ancestors(to, from)} then
    raise exception ${_quote(rule.spec.hierarchyMessage!)} using errcode = '23514';
  end if;
''';
    final trigger = '${rule.link.tableName}_acyclic';
    buffer.writeln('''
create or replace function ${rule.function}()
returns trigger
language plpgsql
security definer
set search_path = ''
as \$\$
begin
  if not new.$active${rule.link.hasSoftDeletableCapability ? ' or new.deleted_at is not null' : ''} then
    return new;
  end if;
$hierarchy  if exists (
    with recursive reach(id) as (
      select link.$to from ${rule.table} link
      where link.$from = new.$to and link.$active and link.id <> new.id$live
      union
      select link.$to from ${rule.table} link join reach on link.$from = reach.id
      where link.$active and link.id <> new.id$live
    )
    select 1 from reach where reach.id = new.$from
  ) then
    raise exception ${_quote(rule.spec.cycleMessage)} using errcode = '23514';
  end if;
  return new;
end;
\$\$;

revoke all on function ${rule.function}() from public, anon, authenticated, service_role;
drop trigger if exists $trigger on ${rule.table};
create trigger $trigger before insert or update of $active, $from, $to on ${rule.table} for each row execute function ${rule.function}();
''');
  }
  return buffer.toString();
}

String _quote(String value) => "'${value.replaceAll("'", "''")}'";
