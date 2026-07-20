/// Build Runner entry points registered by Nodus's package-owned builders.
///
/// Applications do not import this library directly; `build.yaml` selects the
/// inferred builders automatically.
library;

import 'package:build/build.dart';

import 'src/entity_generator/entity_graph_builder.dart';
import 'src/entity_generator/local_entity_builder.dart';
import 'src/route_generator/file_routes_builder.dart';

/// Builds one generated implementation for each discovered entity library.
Builder localEntityBuilder(BuilderOptions options) => LocalEntityBuilder();

/// Builds entity implementations using package-owned discovery conventions.
Builder inferredLocalEntityBuilder(BuilderOptions options) =>
    InferredLocalEntityBuilder();

/// Builds the package-wide entity graph using inferred configuration.
Builder inferredEntityGraphBuilder(BuilderOptions options) =>
    InferredEntityGraphBuilder();

/// Builds a package-wide entity graph with explicit builder options.
Builder entityGraphBuilder(BuilderOptions options) => EntityGraphBuilder();

/// Builds typed file routes with explicit builder options.
Builder fileRoutesBuilder(BuilderOptions options) => FileRoutesBuilder();

/// Builds typed file routes using the package filesystem conventions.
Builder inferredFileRoutesBuilder(BuilderOptions options) =>
    InferredFileRoutesBuilder();
