import 'dart:io';

import 'package:nodus/src/tool/initializer.dart';
import 'package:nodus/src/tool/migration_generator.dart';

Future<void> main(List<String> arguments) async {
  try {
    final command = arguments.isEmpty ? null : arguments.first;
    if (command == 'init') {
      final options = parseInitOptions(arguments.skip(1).toList());
      if (options.showHelp) {
        stdout.write(nodusInitUsage);
        return;
      }
      NodusInitializer(root: Directory.current).initialize(options);
      await NodusGenerator(
        root: Directory.current,
      ).generate(const NodusGenerationOptions());
      return;
    }
    final generator = NodusGenerator(root: Directory.current);
    if (command == null) {
      stdout.write(nodusGenerationUsage);
      return;
    }
    if (command == 'generate') {
      _requireNoArguments(command, arguments.skip(1).toList());
      await generator.generateFast();
      return;
    }
    if (command == 'watch') {
      _requireNoArguments(command, arguments.skip(1).toList());
      await generator.watch();
      return;
    }
    if (command == 'check') {
      _requireNoArguments(command, arguments.skip(1).toList());
      await generator.check();
      return;
    }
    if (command == 'explain') {
      final explanation = _explanationArguments(arguments.skip(1).toList());
      if (explanation.showHelp) {
        stdout.writeln('Usage: dart run nodus explain [ENTITY] [--json]');
        return;
      }
      stdout.writeln(
        await generator.explain(
          entity: explanation.entity,
          json: explanation.json,
        ),
      );
      return;
    }
    final generationArguments = command == 'migrate'
        ? _migrationArguments(arguments.skip(1).toList())
        : arguments;
    final options = parseGenerationOptions(generationArguments);
    if (options.showHelp) {
      stdout.write(nodusGenerationUsage);
      return;
    }
    await generator.generate(options);
  } on NodusToolUsageException catch (error) {
    stderr.writeln('nodus: ${error.message}');
    exitCode = 64;
  } on ProcessException catch (error) {
    stderr.writeln('nodus: ${error.message}');
    exitCode = error.errorCode == 0 ? 1 : error.errorCode;
  } on FormatException catch (error) {
    stderr.writeln('nodus: invalid generated schema: ${error.message}');
    exitCode = 65;
  }
}

void _requireNoArguments(String command, List<String> arguments) {
  if (arguments.isEmpty) return;
  if (arguments.length == 1 &&
      (arguments.single == '--help' || arguments.single == '-h')) {
    throw NodusToolUsageException(
      '`dart run nodus $command` does not require options.',
    );
  }
  throw NodusToolUsageException('Usage: dart run nodus $command');
}

({String? entity, bool json, bool showHelp}) _explanationArguments(
  List<String> arguments,
) {
  String? entity;
  var json = false;
  var showHelp = false;
  for (final argument in arguments) {
    switch (argument) {
      case '--json':
        json = true;
      case '--help' || '-h':
        showHelp = true;
      default:
        if (entity != null) {
          throw const NodusToolUsageException(
            'Usage: dart run nodus explain [ENTITY] [--json]',
          );
        }
        entity = argument;
    }
  }
  if (showHelp && arguments.length != 1) {
    throw const NodusToolUsageException(
      '--help must be used without other explain arguments.',
    );
  }
  return (entity: entity, json: json, showHelp: showHelp);
}

List<String> _migrationArguments(List<String> arguments) {
  if (arguments.length != 1) {
    throw const NodusToolUsageException(
      'Usage: dart run nodus migrate <lower_snake_case_name>',
    );
  }
  return ['--migration', arguments.single];
}
