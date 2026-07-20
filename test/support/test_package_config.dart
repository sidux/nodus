import 'dart:convert';
import 'dart:io';

import 'package:build_runner/src/internal.dart';

/// Supplies package resolution explicitly because Flutter's AOT test isolate
/// does not expose `Isolate.packageConfig` on every supported toolchain.
void initializeBuildTestEnvironment() {
  final file = File('.dart_tool/package_config.json').absolute;
  buildProcessState.deserializeAndSet(
    jsonEncode(<String, Object?>{'packageConfigUri': file.uri.toString()}),
  );
}
