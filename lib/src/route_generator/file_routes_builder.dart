import 'package:build/build.dart';

import 'emitter.dart';
import 'parser.dart';

final class FileRoutesBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/features/{{}}/presentation/pages/not_found.dart': [
      'lib/features/{{}}/presentation/pages/not_found.routes.g.dart',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final spec = await parseFileRouter(buildStep);
    await buildStep.writeAsString(
      buildStep.allowedOutputs.single,
      emitFileRouter(spec),
    );
  }
}

final class InferredFileRoutesBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/features/{{}}/presentation/pages/not_found.dart': [
      'lib/src/generated/routes/{{}}/not_found.routes.g.dart',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final spec = await parseFileRouter(buildStep);
    await buildStep.writeAsString(
      buildStep.allowedOutputs.single,
      emitFileRouter(spec),
    );
  }
}
