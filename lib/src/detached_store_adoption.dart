part of '../nodus.dart';

/// Gives an entity the identity it must have once its store belongs to
/// another account, or null to keep its own.
///
/// [record] holds the entity's persisted fields by name, with every identity
/// already renamed for the adopting account, including its owner. Only an
/// identity the application derives from owner-scoped values, such as one
/// shared by every device of an account, needs a new one.
typedef DetachedIdentityRename =
    String? Function(String entityType, JsonMap record);

enum DetachedStoreAdoptionRefusal {
  /// The adopting account's store already holds entities or queued work, so
  /// adopting would mix two accounts' data.
  targetNotEmpty,
}

final class DetachedStoreAdoptionException implements Exception {
  const DetachedStoreAdoptionException(this.refusal);

  final DetachedStoreAdoptionRefusal refusal;

  @override
  String toString() => 'DetachedStoreAdoptionException(${refusal.name})';
}

final RegExp _identityPattern = RegExp(
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);

/// Moves everything a detached graph's store holds into the empty store of
/// the account [intoAccountId], in one transaction, so it synchronizes as
/// that account's own.
///
/// A detached store has never synchronized: each entity it holds is a
/// queued create, and its identity roots stand at version zero below the
/// roots the server provisions. Renaming [fromAccountId] to [intoAccountId]
/// wherever it appears, in owner and member columns and inside queued work,
/// therefore makes the same work valid for the adopting account; the
/// identity roots it pulls next rebase the edits made while detached.
///
/// Both stores are opened through [openDatabase], which applies the reviewed
/// migrations, and neither may belong to an open graph. A target that holds
/// any entity or queued work refuses adoption with
/// [DetachedStoreAdoptionRefusal.targetNotEmpty]. The detached store is left
/// as it was; the caller erases it once adoption returns.
Future<void> adoptDetachedLocalStore({
  required EntityGraphDefinition definition,
  required Future<GeneratedDatabase> Function(String accountId) openDatabase,
  required String fromAccountId,
  required String intoAccountId,
  DetachedIdentityRename? renameIdentity,
}) async {
  // One database class may have one open instance at a time, so the
  // detached store is read whole and closed before the target opens.
  final source = await openDatabase(fromAccountId);
  final Map<String, List<Map<String, Object?>>> rowsByTable;
  final Map<String, String> renames;
  try {
    renames = await _detachedIdentityRenames(
      source,
      definition,
      fromAccountId: fromAccountId,
      intoAccountId: intoAccountId,
      renameIdentity: renameIdentity,
    );
    final importedTables = {
      for (final descriptor in definition.descriptors)
        if (definition.syncBindingFor(descriptor.entityType).mode ==
            SyncMode.imported)
          descriptor.tableName,
    };
    final order = {
      for (final (index, descriptor) in _inReferenceOrder(
        definition.descriptors,
      ).indexed)
        descriptor.tableName: index,
    };
    final tables =
        source.allTables
            .map((table) => table.actualTableName)
            .where((name) => name != _syncCursorTable)
            // Imported rows were computed on the device; the account's own
            // source sends its own.
            .where((name) => !importedTables.contains(name))
            .toList()
          ..sort(
            (a, b) =>
                (order[a] ?? order.length).compareTo(order[b] ?? order.length),
          );
    rowsByTable = {
      for (final table in tables)
        table: [
          for (final row
              in await source
                  .customSelect(
                    table == _syncWorkTable
                        ? "select * from $table where direction <> 'pull' "
                              'order by id'
                        : 'select * from $table',
                  )
                  .get())
            row.data,
        ],
    };
  } finally {
    await source.close();
  }
  Object? renamed(Object? value) => value is String
      ? value.replaceAllMapped(
          _identityPattern,
          (match) => renames[match[0]] ?? match[0]!,
        )
      : value;
  final target = await openDatabase(intoAccountId);
  try {
    await target.transaction(() async {
      await _requireEmptyStore(target, definition);
      // A hierarchy can list a child before its parent.
      await target.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final MapEntry(key: table, value: rows) in rowsByTable.entries) {
        for (final row in rows) {
          final columns = row.keys.toList(growable: false);
          await target.customStatement(
            'insert into $table (${columns.join(', ')}) '
            'values (${List.filled(columns.length, '?').join(', ')})',
            [for (final column in columns) renamed(row[column])],
          );
        }
      }
    });
  } finally {
    await target.close();
  }
}

const _syncWorkTable = 'local_entity_sync_work';
const _syncCursorTable = 'local_entity_sync_cursor';

Future<void> _requireEmptyStore(
  GeneratedDatabase store,
  EntityGraphDefinition definition,
) async {
  for (final descriptor in definition.descriptors) {
    final row = await store
        .customSelect('select 1 from ${descriptor.tableName} limit 1')
        .getSingleOrNull();
    if (row != null) {
      throw const DetachedStoreAdoptionException(
        DetachedStoreAdoptionRefusal.targetNotEmpty,
      );
    }
  }
  final work = await store
      .customSelect(
        "select 1 from $_syncWorkTable where direction <> 'pull' limit 1",
      )
      .getSingleOrNull();
  if (work != null) {
    throw const DetachedStoreAdoptionException(
      DetachedStoreAdoptionRefusal.targetNotEmpty,
    );
  }
}

/// The identities to rename: the account itself, then each identity
/// [renameIdentity] derives anew, visiting referenced entities first so a
/// derived identity can build on its renamed references.
Future<Map<String, String>> _detachedIdentityRenames(
  GeneratedDatabase source,
  EntityGraphDefinition definition, {
  required String fromAccountId,
  required String intoAccountId,
  DetachedIdentityRename? renameIdentity,
}) async {
  final renames = {fromAccountId: intoAccountId};
  if (renameIdentity == null) return renames;
  for (final descriptor in _inReferenceOrder(definition.descriptors)) {
    final rows = await source
        .customSelect('select * from ${descriptor.tableName}')
        .get();
    for (final row in rows) {
      final record = <String, Object?>{
        for (final field in descriptor.fields)
          field.name: switch (field.fromDatabase(row.data[field.columnName])) {
            final String value => value.replaceAllMapped(
              _identityPattern,
              (match) => renames[match[0]] ?? match[0]!,
            ),
            final value => value,
          },
      };
      final id = row.data[EntityConventions.idColumnName] as String;
      final renamed = renameIdentity(descriptor.entityType, record);
      if (renamed != null && renamed != record[EntityConventions.idFieldName]) {
        renames[id] = renamed;
      }
    }
  }
  return renames;
}

/// [descriptors] with each entity after every entity it references.
List<EntityDescriptorBase> _inReferenceOrder(
  List<EntityDescriptorBase> descriptors,
) {
  final byType = {
    for (final descriptor in descriptors) descriptor.entityType: descriptor,
  };
  final ordered = <EntityDescriptorBase>[];
  final placed = <String>{};
  final visiting = <String>{};
  void place(EntityDescriptorBase descriptor) {
    if (placed.contains(descriptor.entityType) ||
        !visiting.add(descriptor.entityType)) {
      return;
    }
    for (final field in descriptor.fields) {
      final target = byType[field.reference?.targetEntityType];
      if (target != null) place(target);
    }
    visiting.remove(descriptor.entityType);
    placed.add(descriptor.entityType);
    ordered.add(descriptor);
  }

  descriptors.forEach(place);
  return ordered;
}
