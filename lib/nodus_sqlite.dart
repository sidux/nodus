/// SQLite functions that Nodus queries rely on.
///
/// Nodus installs them on the databases it opens. An application that opens
/// its own database, or runs SQLite in a web worker it compiles itself,
/// installs them there, for example with
/// `WasmDatabase.workerMainForOpen(setupAllDatabases: installNodusSqlFunctions)`.
library;

import 'package:sqlite3/common.dart';

import 'nodus.dart';

/// Registers [nodusTextFoldFunctionName] on [database].
void installNodusSqlFunctions(CommonDatabase database) {
  database.createFunction(
    functionName: nodusTextFoldFunctionName,
    argumentCount: const AllowedArgumentCount(1),
    deterministic: true,
    function: (arguments) => switch (arguments[0]) {
      final String text => foldTextForMatching(text),
      final value => value,
    },
  );
}
