import 'package:build/build.dart';

import 'dart_emitter.dart';
import 'parser.dart';

final class LocalEntityBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/{{}}.dart': ['lib/{{}}.entity.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final spec = await parseEntity(buildStep);
    if (spec == null) return;
    final dartOutput = buildStep.allowedOutputs.single;
    await buildStep.writeAsString(dartOutput, emitDart(spec));
  }
}

/// Application builder that keeps compiler implementation files below
/// `lib/src/generated`; consumers import only `package:app/nodus.g.dart`.
final class InferredLocalEntityBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/{{}}.dart': ['lib/src/generated/entities/{{}}.entity.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final spec = await parseEntity(buildStep);
    if (spec == null) return;
    await buildStep.writeAsString(
      buildStep.allowedOutputs.single,
      emitDart(spec, privateEntityOutputs: true),
    );
  }
}
