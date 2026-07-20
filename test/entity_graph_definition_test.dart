import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

import 'support/test_descriptor.dart';

void main() {
  test(
    'connector context carries one exact generated target subgraph',
    () async {
      const descriptor = TestDescriptor<_FirstEntity>();
      final definition = EntityGraphDefinition.single(descriptor);
      final targetDefinition = definition.syncSubgraphFor(
        SyncTargetId.testOnly,
      );
      final context = SyncConnectorContext(
        accountId: 'account-1',
        target: SyncTargetId.testOnly,
        definition: targetDefinition,
      );
      Future<PushPullSyncAdapter> connector(
        SyncConnectorContext context,
      ) async => InMemorySyncBackend.graph(definition: context.definition);

      final adapter = await connector(context);

      expect(context.accountId, 'account-1');
      expect(context.target, SyncTargetId.testOnly);
      expect(adapter.definition, same(targetDefinition));
      expect(
        () => SyncConnectorContext(
          accountId: '',
          target: SyncTargetId.testOnly,
          definition: targetDefinition,
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncConnectorContext(
          accountId: 'account-1',
          target: const SyncTargetId(
            typeIdentity: 'package:nodus/testing.dart#TestSyncTarget',
            wireName: 'other',
          ),
          definition: targetDefinition,
        ),
        throwsArgumentError,
      );
    },
  );

  test('graph definition freezes descriptors and derives protocol version', () {
    final source = <EntityDescriptorBase>[
      const TestDescriptor<_FirstEntity>(),
      const TestDescriptor<_SecondEntity>(
        entityType: 'SecondEntity',
        tableName: 'second_entities',
      ),
    ];

    final definition = EntityGraphDefinition(
      schemaVersion: 2,
      descriptors: source,
      relationships: const [],
      syncBindings: [
        for (final descriptor in source)
          SyncBindingDefinition(
            entityType: descriptor.entityType,
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
      ],
      pullRpcName: 'pull_test_graph_changes',
    );
    source.clear();

    expect(definition.descriptors, hasLength(2));
    expect(definition.syncBindings, hasLength(2));
    expect(definition.protocolVersion, 3);
    expect(
      () => definition.descriptors.add(const TestDescriptor<_FirstEntity>()),
      throwsUnsupportedError,
    );
    expect(
      () => definition.syncBindings.add(
        const SyncBindingDefinition(
          entityType: 'Other',
          mode: SyncMode.localOnly,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      definition.isTransportCompatibleWith(
        EntityGraphDefinition(
          schemaVersion: 99,
          descriptors: const [
            TestDescriptor<_FirstEntity>(),
            TestDescriptor<_SecondEntity>(
              entityType: 'SecondEntity',
              tableName: 'second_entities',
            ),
          ],
          relationships: const [],
          syncBindings: const [
            SyncBindingDefinition(
              entityType: 'Note',
              mode: SyncMode.replicated,
              target: SyncTargetId.testOnly,
            ),
            SyncBindingDefinition(
              entityType: 'SecondEntity',
              mode: SyncMode.replicated,
              target: SyncTargetId.testOnly,
            ),
          ],
          pullRpcName: 'pull_test_graph_changes',
        ),
      ),
      isTrue,
    );
    expect(
      () => definition.validateBackend(
        InMemorySyncBackend(descriptor: const TestDescriptor<_FirstEntity>()),
      ),
      throwsArgumentError,
    );
    expect(
      () => definition.validateBackend(
        InMemorySyncBackend.graph(definition: definition),
      ),
      returnsNormally,
    );
  });

  test('graph definition owns resolved relationship cardinality', () {
    const relationship = RelationshipDefinition(
      linkEntityType: 'Membership',
      sourceEntityType: 'Source',
      targetEntityType: 'Target',
      sourceFieldName: 'sourceId',
      targetFieldName: 'targetId',
      activeFieldName: 'active',
      cardinalityResolution:
          RelationshipCardinalityResolution.boundedByTargetEntity,
      ordered: false,
    );
    const descriptors = <EntityDescriptorBase>[
      TestDescriptor<_SourceEntity>(entityType: 'Source', tableName: 'sources'),
      TestDescriptor<_TargetEntity>(
        entityType: 'Target',
        tableName: 'targets',
        cardinality: Cardinality.bounded,
      ),
      TestDescriptor<_MembershipEntity>(
        entityType: 'Membership',
        tableName: 'memberships',
        uniqueConstraints: [
          EntityUniqueConstraint(
            name: 'memberships_source_target_key',
            fieldNames: ['sourceId', 'targetId'],
          ),
        ],
        fields: [
          EntityFieldDescriptor(
            name: 'id',
            columnName: 'id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
          ),
          EntityFieldDescriptor(
            name: 'sourceId',
            columnName: 'source_id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
            reference: EntityReferenceDescriptor(
              targetEntityType: 'Source',
              onDelete: ReferenceDeleteAction.cascade,
            ),
          ),
          EntityFieldDescriptor(
            name: 'targetId',
            columnName: 'target_id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
            reference: EntityReferenceDescriptor(
              targetEntityType: 'Target',
              onDelete: ReferenceDeleteAction.cascade,
            ),
          ),
          EntityFieldDescriptor(
            name: 'active',
            columnName: 'active',
            kind: EntityFieldKind.boolean,
            nullable: false,
            mutable: false,
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
        ],
      ),
    ];

    final definition = EntityGraphDefinition(
      schemaVersion: 1,
      descriptors: descriptors,
      relationships: const [relationship],
      syncBindings: const [
        SyncBindingDefinition(
          entityType: 'Source',
          mode: SyncMode.replicated,
          target: SyncTargetId.testOnly,
        ),
        SyncBindingDefinition(
          entityType: 'Target',
          mode: SyncMode.replicated,
          target: SyncTargetId.testOnly,
        ),
        SyncBindingDefinition(
          entityType: 'Membership',
          mode: SyncMode.replicated,
          target: SyncTargetId.testOnly,
        ),
      ],
      pullRpcName: 'pull_relationship_graph_changes',
    );

    expect(definition.relationships, const [relationship]);
    expect(
      () => definition.relationships.add(relationship),
      throwsUnsupportedError,
    );
    expect(definition.relationships.single.cardinality, Cardinality.bounded);
    expect(
      () => EntityGraphDefinition(
        schemaVersion: 1,
        descriptors: descriptors,
        relationships: const [
          RelationshipDefinition(
            linkEntityType: 'Membership',
            sourceEntityType: 'Source',
            targetEntityType: 'Target',
            sourceFieldName: 'sourceId',
            targetFieldName: 'targetId',
            activeFieldName: 'active',
            cardinalityResolution:
                RelationshipCardinalityResolution.unboundedByDefault,
            ordered: false,
          ),
        ],
        syncBindings: const [
          SyncBindingDefinition(
            entityType: 'Source',
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
          SyncBindingDefinition(
            entityType: 'Target',
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
          SyncBindingDefinition(
            entityType: 'Membership',
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
        ],
        pullRpcName: 'pull_relationship_graph_changes',
      ),
      throwsArgumentError,
    );
  });

  test('graph definition derives composition edges from field metadata', () {
    const descriptors = <EntityDescriptorBase>[
      TestDescriptor<_SourceEntity>(
        entityType: 'Aggregate',
        tableName: 'aggregates',
        fields: [
          EntityFieldDescriptor(
            name: 'documentId',
            columnName: 'document_id',
            kind: EntityFieldKind.uuid,
            nullable: false,
            mutable: false,
            conflictPolicy: FieldConflictPolicy.serverWins,
            reference: EntityReferenceDescriptor(
              targetEntityType: 'Document',
              onDelete: ReferenceDeleteAction.cascade,
              composition: true,
            ),
          ),
        ],
      ),
      TestDescriptor<_TargetEntity>(
        entityType: 'Document',
        tableName: 'documents',
      ),
    ];
    final definition = EntityGraphDefinition(
      schemaVersion: 1,
      descriptors: descriptors,
      relationships: const [],
      syncBindings: const [
        SyncBindingDefinition(
          entityType: 'Aggregate',
          mode: SyncMode.localOnly,
        ),
        SyncBindingDefinition(entityType: 'Document', mode: SyncMode.localOnly),
      ],
      pullRpcName: 'pull_composition_graph_changes',
    );

    expect(definition.compositions, const [
      CompositionDefinition(
        aggregateEntityType: 'Aggregate',
        fieldName: 'documentId',
        componentEntityType: 'Document',
      ),
    ]);
    expect(
      () => definition.compositions.add(
        const CompositionDefinition(
          aggregateEntityType: 'Other',
          fieldName: 'documentId',
          componentEntityType: 'Document',
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => EntityGraphDefinition(
        schemaVersion: 1,
        descriptors: const [
          TestDescriptor<_SourceEntity>(
            entityType: 'Aggregate',
            tableName: 'aggregates',
            fields: [
              EntityFieldDescriptor(
                name: 'documentId',
                columnName: 'document_id',
                kind: EntityFieldKind.uuid,
                nullable: false,
                mutable: false,
                conflictPolicy: FieldConflictPolicy.serverWins,
                reference: EntityReferenceDescriptor(
                  targetEntityType: 'MissingDocument',
                  onDelete: ReferenceDeleteAction.cascade,
                  composition: true,
                ),
              ),
            ],
          ),
        ],
        relationships: const [],
        syncBindings: const [
          SyncBindingDefinition(
            entityType: 'Aggregate',
            mode: SyncMode.localOnly,
          ),
        ],
        pullRpcName: 'pull_invalid_composition_graph_changes',
      ),
      throwsArgumentError,
    );
  });

  test('adapter registry binds exact generated target subgraphs', () {
    const descriptors = <EntityDescriptorBase>[
      TestDescriptor<_FirstEntity>(),
      TestDescriptor<_SecondEntity>(
        entityType: 'SecondEntity',
        tableName: 'second_entities',
      ),
    ];
    final definition = EntityGraphDefinition(
      schemaVersion: 1,
      descriptors: descriptors,
      relationships: const [],
      syncBindings: const [
        SyncBindingDefinition(
          entityType: 'Note',
          mode: SyncMode.replicated,
          target: SyncTargetId.testOnly,
        ),
        SyncBindingDefinition(
          entityType: 'SecondEntity',
          mode: SyncMode.localOnly,
        ),
      ],
      pullRpcName: 'pull_test_graph_changes',
    );
    final targetDefinition = definition.syncSubgraphFor(SyncTargetId.testOnly);

    expect(targetDefinition.descriptors.map((value) => value.entityType), [
      'Note',
    ]);
    expect(targetDefinition.syncBindings, hasLength(1));
    expect(definition.syncTargets, {SyncTargetId.testOnly});
    expect(definition.pullSyncTargets, {SyncTargetId.testOnly});
    expect(definition.pushSyncTargets, {SyncTargetId.testOnly});
    expect(
      () => SyncAdapterRegistry(
        definition: definition,
        adapters: {
          SyncTargetId.testOnly: InMemorySyncBackend.graph(
            definition: targetDefinition,
          ),
        },
      ),
      returnsNormally,
    );
    expect(
      () => SyncAdapterRegistry(
        definition: definition,
        adapters: {
          SyncTargetId.testOnly: InMemorySyncBackend.graph(
            definition: definition,
          ),
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => SyncAdapterRegistry(definition: definition, adapters: const {}),
      throwsArgumentError,
    );
  });

  test('graph definition rejects ambiguous or malformed contracts', () {
    EntityGraphDefinition create({
      int schemaVersion = 1,
      String pullRpcName = 'pull_test_graph_changes',
      Iterable<EntityDescriptorBase> descriptors = const [
        TestDescriptor<_FirstEntity>(),
      ],
    }) => EntityGraphDefinition(
      schemaVersion: schemaVersion,
      descriptors: descriptors,
      relationships: const [],
      syncBindings: [
        for (final descriptor in descriptors)
          SyncBindingDefinition(
            entityType: descriptor.entityType,
            mode: SyncMode.replicated,
            target: SyncTargetId.testOnly,
          ),
      ],
      pullRpcName: pullRpcName,
    );

    expect(() => create(schemaVersion: 0), throwsArgumentError);
    expect(() => create(pullRpcName: 'Pull Invalid'), throwsArgumentError);
    expect(() => create(descriptors: const []), throwsArgumentError);
    expect(
      () => create(
        descriptors: const [
          TestDescriptor<_FirstEntity>(),
          TestDescriptor<_SecondEntity>(),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => EntityGraphDefinition(
        schemaVersion: 1,
        descriptors: const [TestDescriptor<_FirstEntity>()],
        relationships: const [],
        syncBindings: const [],
        pullRpcName: 'pull_test_graph_changes',
      ),
      throwsArgumentError,
    );
    expect(
      () => EntityGraphDefinition(
        schemaVersion: 1,
        descriptors: const [TestDescriptor<_FirstEntity>()],
        relationships: const [],
        syncBindings: const [
          SyncBindingDefinition(
            entityType: 'Note',
            mode: SyncMode.localOnly,
            target: SyncTargetId.testOnly,
          ),
        ],
        pullRpcName: 'pull_test_graph_changes',
      ),
      throwsArgumentError,
    );
  });
}

final class _FirstEntity {}

final class _SecondEntity {}

final class _SourceEntity {}

final class _TargetEntity {}

final class _MembershipEntity {}
