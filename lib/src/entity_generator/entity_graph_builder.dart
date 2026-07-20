import 'package:build/build.dart';
import 'package:glob/glob.dart';

import '../configuration.dart';
import 'graph_emitter.dart';
import 'graph_explain_emitter.dart';
import 'graph_sql_emitter.dart';
import 'model.dart';
import 'parser.dart';
import 'schema_fingerprint.dart';

/// Default package builder: one inferred graph rooted in `nodus.lock`.
final class InferredEntityGraphBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [
      'lib/nodus.g.dart',
      'lib/src/generated/nodus.runtime.g.dart',
      'lib/src/generated/nodus.explain.g.json',
      'test/nodus_test_harness.g.dart',
      'supabase/nodus/schema.sql',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final lockAsset = AssetId(buildStep.inputId.package, 'nodus.lock');
    if (!await buildStep.canRead(lockAsset)) return;
    final lock = NodusLock.decode(await buildStep.readAsString(lockAsset));
    if (lock.packageName != buildStep.inputId.package) {
      throw StateError(
        'nodus.lock belongs to `${lock.packageName}`, but build_runner is '
        'building `${buildStep.inputId.package}`. Run `dart run nodus init` '
        'from the application package.',
      );
    }
    final graph = await parseInferredEntityGraph(
      buildStep,
      className: lock.graphName,
      schemaVersion: lock.schemaVersion,
      defaultTarget: lock.defaultTarget!,
    );
    final fingerprint = entityGraphSchemaFingerprint(graph);
    final routeExports = await _generatedRouteExports(buildStep);
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('/nodus.g.dart'),
      ),
      emitEntityGraphFacade(
        graph,
        schemaFingerprint: fingerprint,
        routeExports: routeExports,
      ),
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('/nodus.runtime.g.dart'),
      ),
      emitEntityGraph(
        graph,
        schemaFingerprint: fingerprint,
        privateEntityOutputs: true,
        partBaseName: 'nodus.runtime.g',
      ),
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('/nodus_test_harness.g.dart'),
      ),
      emitEntityGraphTestHarness(graph),
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('/nodus.explain.g.json'),
      ),
      emitEntityGraphExplanation(graph),
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('.sql'),
      ),
      _emitConventionalSupabaseSql(graph),
    );
  }
}

Future<List<String>> _generatedRouteExports(BuildStep buildStep) async {
  const prefix = 'lib/features/';
  const suffix = '/presentation/pages/not_found.dart';
  final exports = <String>[];
  await for (final asset in buildStep.findAssets(
    Glob('lib/features/**/presentation/pages/not_found.dart'),
  )) {
    final path = asset.path;
    if (!path.startsWith(prefix) || !path.endsWith(suffix)) continue;
    final feature = path.substring(prefix.length, path.length - suffix.length);
    exports.add('src/generated/routes/$feature/not_found.routes.g.dart');
  }
  exports.sort();
  return List.unmodifiable(exports);
}

/// Compatibility builder used by compiler fixtures that still provide an
/// explicit graph source. Applications use [InferredEntityGraphBuilder].
final class EntityGraphBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    'lib/entity_graph.dart': [
      'lib/entity_graph.runtime.g.dart',
      'supabase/nodus/schema.sql',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final graph = await parseEntityGraph(buildStep);
    if (graph == null) return;
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('.dart'),
      ),
      emitEntityGraph(graph),
    );
    await buildStep.writeAsString(
      buildStep.allowedOutputs.singleWhere(
        (output) => output.path.endsWith('.sql'),
      ),
      _emitConventionalSupabaseSql(graph),
    );
  }
}

String _emitConventionalSupabaseSql(EntityGraphSpec graph) {
  final targets = graph.syncTargets
      .where((target) => target.wireName == 'supabase')
      .toList(growable: false);
  if (targets.isEmpty) {
    return '''-- GENERATED FILE. DO NOT EDIT.
-- Source: ${graph.inputImport}
-- No sync target named `supabase`; no Supabase schema is generated.
''';
  }
  if (targets.length != 1) {
    throw StateError('A graph cannot declare duplicate `supabase` targets.');
  }
  return emitEntityGraphSupabaseSql(graph.syncSubgraphFor(targets.single));
}
