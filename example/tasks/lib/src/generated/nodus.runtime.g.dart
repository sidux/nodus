// GENERATED FILE. DO NOT EDIT.
// Source: package:tasks_example/nodus.lock
// Schema fingerprint: 7334f12ec59899f4b251b9f440b7f3c19e93e49767c73eb47cf4936620984f32
// ignore_for_file: unused_field, type=lint

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' hide Table;
import 'package:nodus/nodus_flutter.dart';
import 'package:nodus/nodus_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:tasks_example/features/accounts/domain/account.dart';
import 'package:tasks_example/features/tasks/domain/task.dart';
import 'package:tasks_example/features/tasks/domain/task_activity.dart';
import 'package:tasks_example/features/tasks/domain/task_project.dart';
import 'package:tasks_example/src/generated/entities/features/tasks/domain/task.entity.g.dart';
import 'package:tasks_example/src/generated/entities/features/tasks/domain/task_activity.entity.g.dart';
import 'package:tasks_example/src/generated/entities/features/tasks/domain/task_project.entity.g.dart';

export 'package:tasks_example/features/accounts/domain/account.dart';
export 'package:tasks_example/features/tasks/domain/task.dart';
export 'package:tasks_example/features/tasks/domain/task_activity.dart';
export 'package:tasks_example/features/tasks/domain/task_project.dart';
export 'package:tasks_example/src/generated/entities/features/tasks/domain/task.entity.g.dart';
export 'package:tasks_example/src/generated/entities/features/tasks/domain/task_activity.entity.g.dart';
export 'package:tasks_example/src/generated/entities/features/tasks/domain/task_project.entity.g.dart';

part 'nodus.runtime.g.drift.dart';

enum TasksExampleSyncTarget { supabase }

@TableIndex.sql(
  "CREATE INDEX local_entity_push_patch_idx "
  "ON local_entity_sync_work (sync_target, entity_type, entity_id, id) WHERE "
  "direction = 'push' AND kind = 'statePatch' "
  "AND status = 'pending'",
)
@TableIndex.sql(
  "CREATE INDEX local_entity_sync_ready_idx "
  "ON local_entity_sync_work "
  "(sync_target, status, next_attempt_at, direction, id)",
)
class TasksExampleSyncWorkRows extends LocalEntitySyncWorkRows {}

class TasksExampleSyncCursorRows extends LocalEntitySyncCursorRows {}

@DriftDatabase(
  tables: [
    TaskRows,
    TaskActivityRows,
    TaskProjectRows,
    TasksExampleSyncWorkRows,
    TasksExampleSyncCursorRows,
  ],
)
final class TasksExampleDatabase extends _$TasksExampleDatabase {
  TasksExampleDatabase(super.executor, {MigrationStrategy? migrationOverride})
    : _migrationOverride = migrationOverride;
  final MigrationStrategy? _migrationOverride;
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration {
    final configured =
        _migrationOverride ??
        MigrationStrategy(
          onCreate: (m) async {
            await m.createAll();
            await into(tasksExampleSyncCursorRows).insert(
              const TasksExampleSyncCursorRowsCompanion(
                syncTarget: Value('supabase'),
                cursor: Value(0),
              ),
              mode: InsertMode.insertOrIgnore,
            );
          },
          onUpgrade: (m, from, to) => throw StateError(
            'Missing graph migration from schema version $from to $to.',
          ),
        );
    return MigrationStrategy(
      onCreate: configured.onCreate,
      onUpgrade: configured.onUpgrade,
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await configured.beforeOpen?.call(details);
      },
    );
  }
}

abstract final class TasksExampleMetadata {
  static const taskDescriptor = TaskDescriptor();
  static const taskActivityDescriptor = TaskActivityDescriptor();
  static const taskProjectDescriptor = TaskProjectDescriptor();
  static const supabaseSyncTarget = SyncTargetId(
    typeIdentity: 'package:tasks_example/nodus.g.dart#TasksExampleSyncTarget',
    wireName: 'supabase',
  );
  static final definition = EntityGraphDefinition(
    schemaVersion: 1,
    descriptors: [
      taskDescriptor,
      taskActivityDescriptor,
      taskProjectDescriptor,
    ],
    relationships: [],
    activityTrackings: [
      ActivityTrackingDefinition(
        sourceEntityType: 'Task',
        activityEntityType: 'TaskActivity',
      ),
    ],
    syncBindings: [
      SyncBindingDefinition(
        entityType: 'Task',
        mode: SyncMode.replicated,
        target: supabaseSyncTarget,
      ),
      SyncBindingDefinition(
        entityType: 'TaskActivity',
        mode: SyncMode.replicated,
        target: supabaseSyncTarget,
      ),
      SyncBindingDefinition(
        entityType: 'TaskProject',
        mode: SyncMode.replicated,
        target: supabaseSyncTarget,
      ),
    ],
    pullRpcName: 'pull_tasks_example_graph_changes',
  );
  static final supabaseSyncDefinition = definition.syncSubgraphFor(
    supabaseSyncTarget,
  );
}

final class TasksExampleSyncAdapters {
  const TasksExampleSyncAdapters({required this.supabase});
  final PushPullSyncAdapter supabase;
  SyncAdapterRegistry bind() => SyncAdapterRegistry(
    definition: TasksExampleMetadata.definition,
    adapters: {TasksExampleMetadata.supabaseSyncTarget: supabase},
  );
}

final class TasksExampleEntityGraph {
  TasksExampleEntityGraph._(
    this.accountId,
    this._coordinator,
    this._taskEngine,
    this._taskActivityEngine,
    this._taskProjectEngine,
  ) : tasks = TaskSet(_taskEngine),
      taskActivities = TaskActivitySet(_taskActivityEngine),
      taskProjects = TaskProjectSet(_taskProjectEngine),
      syncQueue = _coordinator.syncQueue;
  final LocalId<Account> accountId;
  final LocalEntityGraphCoordinator _coordinator;
  final LocalEntityEngine<Task, TaskRecord> _taskEngine;
  final LocalEntityEngine<TaskActivity, TaskActivityRecord> _taskActivityEngine;
  final LocalEntityEngine<TaskProject, TaskProjectRecord> _taskProjectEngine;
  final TaskSet tasks;
  final TaskActivitySet taskActivities;
  final TaskProjectSet taskProjects;
  final SyncQueue syncQueue;
  Future<void>? _closeFuture;
  static Future<TasksExampleEntityGraph> open({
    required LocalId<Account> accountId,
    required QueryExecutor executor,
    required TasksExampleSyncAdapters syncAdapters,
    MigrationStrategy? migrationOverride,
    Clock clock = const SystemClock(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    LocalEntityDiagnostics diagnostics = const NoopLocalEntityDiagnostics(),
    bool autoSync = true,
  }) async {
    final adapterRegistry = syncAdapters.bind();
    final database = TasksExampleDatabase(
      executor,
      migrationOverride: migrationOverride,
    );
    final coordinator = LocalEntityGraphCoordinator(
      database: database,
      adapters: adapterRegistry,
      definition: TasksExampleMetadata.definition,
      authenticatedPrincipalId: accountId.value,
      autoSync: autoSync,
      clock: clock,
      idGenerator: idGenerator,
      diagnostics: diagnostics,
    );
    try {
      final taskEngine = await LocalEntityEngine.openInGraph(
        descriptor: TasksExampleMetadata.taskDescriptor,
        database: database,
        backend: adapterRegistry.backendForEntity('Task'),
        clock: clock,
        idGenerator: idGenerator,
        graphCoordinator: coordinator,
      );
      final taskActivityEngine = await LocalEntityEngine.openInGraph(
        descriptor: TasksExampleMetadata.taskActivityDescriptor,
        database: database,
        backend: adapterRegistry.backendForEntity('TaskActivity'),
        clock: clock,
        idGenerator: idGenerator,
        graphCoordinator: coordinator,
      );
      final taskProjectEngine = await LocalEntityEngine.openInGraph(
        descriptor: TasksExampleMetadata.taskProjectDescriptor,
        database: database,
        backend: adapterRegistry.backendForEntity('TaskProject'),
        clock: clock,
        idGenerator: idGenerator,
        graphCoordinator: coordinator,
      );
      await coordinator.start();
      return TasksExampleEntityGraph._(
        accountId,
        coordinator,
        taskEngine,
        taskActivityEngine,
        taskProjectEngine,
      );
    } catch (_) {
      await coordinator.close();
      rethrow;
    }
  }

  static Future<TasksExampleEntityGraph> openInMemory({
    required LocalId<Account> accountId,
    InMemorySyncBackend? supabaseBackend,
    MigrationStrategy? migrationOverride,
    Clock clock = const SystemClock(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    LocalEntityDiagnostics diagnostics = const NoopLocalEntityDiagnostics(),
    bool autoSync = false,
  }) {
    final resolvedSupabaseBackend =
        supabaseBackend ??
        InMemorySyncBackend.graph(
          definition: TasksExampleMetadata.supabaseSyncDefinition,
        );
    return open(
      accountId: accountId,
      executor: openNodusInMemoryExecutor(),
      syncAdapters: TasksExampleSyncAdapters(supabase: resolvedSupabaseBackend),
      migrationOverride: migrationOverride,
      clock: clock,
      idGenerator: idGenerator,
      diagnostics: diagnostics,
      autoSync: autoSync,
    );
  }

  static Future<TasksExampleEntityGraph> openWithConnectors({
    required LocalId<Account> accountId,
    required SyncConnector<PushPullSyncAdapter> supabase,
    NodusLocalStore localStore = const ApplicationSupportNodusLocalStore(),
    MigrationStrategy? migrationOverride,
    Clock clock = const SystemClock(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    LocalEntityDiagnostics diagnostics = const NoopLocalEntityDiagnostics(),
    bool autoSync = true,
  }) async {
    final connectedSupabase = await supabase(
      SyncConnectorContext(
        accountId: accountId.value,
        target: TasksExampleMetadata.supabaseSyncTarget,
        definition: TasksExampleMetadata.supabaseSyncDefinition,
      ),
    );
    final syncAdapters = TasksExampleSyncAdapters(supabase: connectedSupabase);
    syncAdapters.bind();
    final executor = await localStore.open(
      packageName: 'tasks_example',
      accountId: accountId.value,
    );
    return open(
      accountId: accountId,
      executor: executor,
      syncAdapters: syncAdapters,
      migrationOverride: migrationOverride,
      clock: clock,
      idGenerator: idGenerator,
      diagnostics: diagnostics,
      autoSync: autoSync,
    );
  }

  static Future<TasksExampleEntityGraph> openSupabase({
    required LocalId<Account> accountId,
    required SupabaseClient client,
    NodusLocalStore localStore = const ApplicationSupportNodusLocalStore(),
    MigrationStrategy? migrationOverride,
    Clock clock = const SystemClock(),
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    LocalEntityDiagnostics diagnostics = const NoopLocalEntityDiagnostics(),
    bool autoSync = true,
  }) {
    return openWithConnectors(
      accountId: accountId,
      supabase: (context) => SupabaseSyncBackend.graph(
        client: client,
        definition: context.definition,
      ),
      localStore: localStore,
      migrationOverride: migrationOverride,
      clock: clock,
      idGenerator: idGenerator,
      diagnostics: diagnostics,
      autoSync: autoSync,
    );
  }

  ReadOnlyObservableList<LocalPersistenceFailure> get persistenceFailures =>
      _coordinator.persistenceFailures;
  DateTime nowUtc() => _coordinator.clock.nowUtc();
  Future<void> flushLocal() => _coordinator.flushLocal();
  Future<R> transaction<R>(FutureOr<R> Function() body) =>
      _coordinator.transaction(body);
  Future<void> sync() => _coordinator.sync();
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    tasks.dispose();
    taskActivities.dispose();
    taskProjects.dispose();
    await _coordinator.close();
  }
}

final class TasksExampleEntityGraphScope extends StatelessWidget {
  const TasksExampleEntityGraphScope({
    required this.session,
    required this.child,
    super.key,
  });
  final AccountEntityGraphSession<TasksExampleEntityGraph, Account> session;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AccountEntityGraphScope<TasksExampleEntityGraph, Account>(
        session: session,
        child: child,
      );
}

extension TasksExampleEntityGraphBuildContext on BuildContext {
  AccountEntityGraphSessionState<TasksExampleEntityGraph, Account>
  get tasksExampleEntityGraphState =>
      AccountEntityGraphScope.stateOf<TasksExampleEntityGraph, Account>(this);
  AccountEntityGraphReady<TasksExampleEntityGraph, Account>?
  get tasksExampleEntityGraphReady =>
      AccountEntityGraphScope.maybeReadyOf<TasksExampleEntityGraph, Account>(
        this,
      );
  AccountEntityGraphSession<TasksExampleEntityGraph, Account>
  get tasksExampleEntityGraphSession =>
      AccountEntityGraphScope.sessionOf<TasksExampleEntityGraph, Account>(this);
}

final class TaskList extends EntityList<Task> {
  TaskList.all(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where: where,
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: archives,
           pageSize: pageSize,
         ),
       );
  TaskList.active(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where: where,
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: ArchiveVisibility.exclude,
           pageSize: pageSize,
         ),
       );
  TaskList.archived(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where: where,
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: ArchiveVisibility.only,
           pageSize: pageSize,
         ),
       );
  TaskList.owned(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where:
               TaskFields.ownerId.equals(entityGraph.accountId) &
               (where ?? EntityPredicate<Task>.all()),
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: archives,
           pageSize: pageSize,
         ),
       );
  TaskList.forOwner(
    TasksExampleEntityGraph entityGraph,
    LocalId<Account> ownerId, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where:
               TaskFields.ownerId.equals(ownerId) &
               (where ?? EntityPredicate<Task>.all()),
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: archives,
           pageSize: pageSize,
         ),
       );
  TaskList.forProject(
    TasksExampleEntityGraph entityGraph,
    LocalId<TaskProject> projectId, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.tasks.query(
           where:
               TaskFields.projectId.equals(projectId) &
               (where ?? EntityPredicate<Task>.all()),
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: archives,
           pageSize: pageSize,
         ),
       );
  final TasksExampleEntityGraph _entityGraph;

  Future<EntityBulkMutationResult> removeAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.remove();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);

  Future<EntityBulkMutationResult> restoreAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.restore();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);

  Future<EntityBulkMutationResult> archiveAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.archive();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);

  Future<EntityBulkMutationResult> unarchiveAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.unarchive();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);
}

final class TaskActivityList extends EntityList<TaskActivity> {
  TaskActivityList.all(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : super(
         entityGraph.taskActivities.query(
           where: where,
           orderBy: orderBy ?? TaskActivityFields.occurredAt.descending(),
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  TaskActivityList.owned(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : super(
         entityGraph.taskActivities.query(
           where:
               TaskActivityFields.ownerId.equals(entityGraph.accountId) &
               (where ?? EntityPredicate<TaskActivity>.all()),
           orderBy: orderBy ?? TaskActivityFields.occurredAt.descending(),
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  TaskActivityList.forOwner(
    TasksExampleEntityGraph entityGraph,
    LocalId<Account> ownerId, {
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : super(
         entityGraph.taskActivities.query(
           where:
               TaskActivityFields.ownerId.equals(ownerId) &
               (where ?? EntityPredicate<TaskActivity>.all()),
           orderBy: orderBy ?? TaskActivityFields.occurredAt.descending(),
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  TaskActivityList.forTask(
    TasksExampleEntityGraph entityGraph,
    LocalId<Task> taskId, {
    EntityPredicate<TaskActivity>? where,
    EntityOrder<TaskActivity>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : super(
         entityGraph.taskActivities.query(
           where:
               TaskActivityFields.subjectId.equals(taskId) &
               (where ?? EntityPredicate<TaskActivity>.all()),
           orderBy: orderBy ?? TaskActivityFields.occurredAt.descending(),
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
}

final class TaskProjectList extends EntityList<TaskProject> {
  TaskProjectList.all(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.taskProjects.query(
           where: where,
           orderBy: orderBy ?? entityGraph.taskProjects.canonicalOrder,
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  TaskProjectList.owned(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.taskProjects.query(
           where:
               TaskProjectFields.ownerId.equals(entityGraph.accountId) &
               (where ?? EntityPredicate<TaskProject>.all()),
           orderBy: orderBy ?? entityGraph.taskProjects.canonicalOrder,
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  TaskProjectList.forOwner(
    TasksExampleEntityGraph entityGraph,
    LocalId<Account> ownerId, {
    EntityPredicate<TaskProject>? where,
    EntityOrder<TaskProject>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       super(
         entityGraph.taskProjects.query(
           where:
               TaskProjectFields.ownerId.equals(ownerId) &
               (where ?? EntityPredicate<TaskProject>.all()),
           orderBy: orderBy ?? entityGraph.taskProjects.canonicalOrder,
           tombstones: tombstones,
           pageSize: pageSize,
         ),
       );
  final TasksExampleEntityGraph _entityGraph;

  Future<EntityBulkMutationResult> removeAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.remove();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);

  Future<EntityBulkMutationResult> restoreAll() =>
      runGeneratedBulkAction((entity) async {
        final before = entity.generatedAccess.generatedLocalRevision;
        await entity.restore();
        return entity.generatedAccess.generatedLocalRevision != before;
      }, runTransaction: _entityGraph.transaction);
}

final class TaskActivityLookup extends EntityLookup<TaskActivity> {
  TaskActivityLookup.bySourceOperation(
    TasksExampleEntityGraph entityGraph,
    String sourceOperationId, {
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
  }) : super(
         entityGraph.taskActivities.query(
           where: TaskActivityFields.sourceOperationId.equals(
             sourceOperationId,
           ),
           tombstones: tombstones,
           pageSize: 1,
         ),
       );
}

final class TaskProjectTasks extends EntityList<Task> {
  TaskProjectTasks(
    TasksExampleEntityGraph entityGraph,
    LocalId<TaskProject> projectId, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) : _entityGraph = entityGraph,
       _projectId = projectId,
       super(
         entityGraph.tasks.query(
           where:
               TaskFields.projectId.equals(projectId) &
               (where ?? EntityPredicate<Task>.all()),
           orderBy: orderBy ?? entityGraph.tasks.canonicalOrder,
           tombstones: tombstones,
           archives: archives,
           pageSize: pageSize,
         ),
       );
  final TasksExampleEntityGraph _entityGraph;
  final LocalId<TaskProject> _projectId;

  Future<Task> create({
    LocalId<Task>? id,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) => _entityGraph.tasks.create(
    id: id,
    projectId: _projectId,
    title: title,
    description: description,
    priority: priority,
    dueAt: dueAt,
  );

  Future<Task> createFirst({
    LocalId<Task>? id,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) => _entityGraph.tasks.createFirst(
    id: id,
    projectId: _projectId,
    title: title,
    description: description,
    priority: priority,
    dueAt: dueAt,
  );
}

extension TaskProjectTaskProjectIdInverseRelationship on TaskProject {
  TaskProjectTasks tasks(
    TasksExampleEntityGraph entityGraph, {
    EntityPredicate<Task>? where,
    EntityOrder<Task>? orderBy,
    TombstoneVisibility tombstones = TombstoneVisibility.exclude,
    ArchiveVisibility archives = ArchiveVisibility.exclude,
    int pageSize = EntityQuerySpec.defaultPageSize,
  }) {
    return TaskProjectTasks(
      entityGraph,
      id,
      where: where,
      orderBy: orderBy,
      tombstones: tombstones,
      archives: archives,
      pageSize: pageSize,
    );
  }
}
