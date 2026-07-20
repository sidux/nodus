import 'package:nodus/nodus.dart';

final class TestDescriptor<E>
    implements
        EntityDescriptorBase,
        EntityIdentityDescriptor<E>,
        EntityUniqueConstraintDescriptor,
        ActionPolicyProvider {
  const TestDescriptor({
    this.entityType = 'Note',
    this.tableName = 'notes',
    this.collaborationTableName,
    this.cardinality = Cardinality.unbounded,
    this.uniqueConstraints = const [],
    this.actionPolicy = const ActionPolicy(actions: []),
    this.fields = _defaultTestFields,
  });

  @override
  final String entityType;

  @override
  int get protocolVersion => 3;

  @override
  EntityIdentity<E> parseIdentity(String source) =>
      EntityIdentity(descriptor: this, id: parseLocalId<E>(source));

  @override
  final Cardinality cardinality;

  @override
  final String tableName;

  @override
  final String? collaborationTableName;

  @override
  final List<EntityUniqueConstraint> uniqueConstraints;

  @override
  final ActionPolicy actionPolicy;

  @override
  final List<EntityFieldDescriptor> fields;

  @override
  EntitySemanticCommand<dynamic> decodeSemanticCommand(
    String name,
    JsonMap payload,
  ) => throw const RejectedSyncException.validation(
    code: 'unsupported_command',
    message: 'Test entity has no commands.',
  );

  @override
  GeneratedEntityRecord instantiate({
    required EntityMutationSink mutationSink,
    required Clock clock,
    required JsonMap fields,
    required int localRevision,
  }) => throw UnsupportedError('Not needed by protocol model tests.');
}

const _defaultTestFields = [
  EntityFieldDescriptor(
    name: 'id',
    columnName: 'id',
    kind: EntityFieldKind.uuid,
    nullable: false,
    mutable: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
  ),
  EntityFieldDescriptor(
    name: 'isActive',
    columnName: 'is_active',
    kind: EntityFieldKind.boolean,
    nullable: false,
    mutable: true,
    conflictPolicy: FieldConflictPolicy.localWins,
  ),
  EntityFieldDescriptor(
    name: 'serverVersion',
    columnName: 'server_version',
    kind: EntityFieldKind.integer,
    nullable: false,
    mutable: false,
    conflictPolicy: FieldConflictPolicy.serverWins,
  ),
];
