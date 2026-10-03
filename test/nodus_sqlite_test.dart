import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:nodus/nodus.dart';
import 'package:nodus/nodus_sqlite.dart';

void main() {
  test('SQLite folds text the way Nodus matches it in memory', () async {
    final database = _Database(
      NativeDatabase.memory(setup: installNodusSqlFunctions),
    );
    addTearDown(database.close);

    final row = await database
        .customSelect(
          "select $nodusTextFoldFunctionName('École Über ΆΣ') as folded, "
          "$nodusTextFoldFunctionName(null) as missing",
        )
        .getSingle();

    expect(row.read<String>('folded'), foldTextForMatching('École Über ΆΣ'));
    expect(row.read<String>('folded'), 'ecole uber ασ');
    expect(row.readNullable<String>('missing'), isNull);
  });
}

final class _Database extends GeneratedDatabase {
  _Database(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}
