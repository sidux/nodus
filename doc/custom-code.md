# Writing custom application code

Nodus generates repeatable entity mechanics. Application code still owns
business decisions, presentation, and external integrations that cannot be
derived from the entity graph.

The boundary is responsibility, not folder naming: use the generated API when
Nodus already knows the behavior, and keep genuinely custom behavior at the
narrowest place that owns its meaning.

## Choose the owner first

| Need | Preferred owner | Avoid |
| --- | --- | --- |
| Computed value or single-entity decision | Pure getter or method on the handwritten entity | View model or service that copies entity fields |
| Business name for a selection | Pure function that returns generated predicates or ordering | Repository that executes or caches the query |
| Create, edit, transition, relationship, or lifecycle mutation | Generated set, draft, entity, or relationship API | CRUD service, command handler, or DTO mapping |
| Ephemeral widget interaction | Local widget state or Flutter Hooks | Application-wide state for focus, forms, or animation |
| Account lifecycle or non-entity application state | Narrow injected composition boundary | Container that republishes entities or query state |
| Online-only API, device, payment, or file operation | Typed stateless client or gateway | Service locator, entity cache, or direct remote entity write |
| Another remote synchronization system | `SyncConnector` for one generated target contract | Feature-selected adapters or handwritten entity routing |

The complete decision rules are part of the
[normative architecture contract](Architecture.md#2-artifact-decision-rules).

## Keep business meaning on the entity

Handwritten getters and pure methods are inherited by the generated record, so
they operate on the same stable observable identity:

```dart
@Entity()
abstract class Task implements OwnedBy<Task, Account> {
  abstract final String title;

  @Persisted(defaultValue: TaskStatus.todo)
  abstract final TaskStatus status;

  @Persisted(maxLength: 1000)
  abstract final String? description;

  bool get isCompleted => status == TaskStatus.done;

  @Action(values: [ActionValue(#status, TaskStatus.done)])
  Future<void> complete();
}
```

Callers do not need a wrapper:

```dart
if (!task.isCompleted) {
  await task.complete();
}
```

Persisted fields remain immutable on the public entity. Change them through a
generated draft, action, relationship method, or lifecycle operation so local
durability and synchronization intent stay atomic.

## Name a query without owning its mechanics

A pure helper can add product vocabulary while the generated list continues to
own execution, paging, observation, and its cache lease:

```dart
EntityPredicate<Task> openTaskPredicate() =>
    TaskFields.status.equals(TaskStatus.todo);

final openTasks = TaskList.all(
  entityGraph,
  where: openTaskPredicate(),
);
```

Do not introduce a repository merely to forward that predicate or mirror its
results.

## Isolate an irreducible external operation

An online-only operation is not entity synchronization. Give it a small typed
boundary, inject it from the application composition root, and commit any
resulting entity change through Nodus:

```dart
abstract interface class TaskSummaryClient {
  Future<String> summarize(String text);
}

extension TaskSummarization on Task {
  Future<void> summarizeWith(TaskSummaryClient client) async {
    final source = description;
    if (source == null || source.trim().isEmpty) return;

    final summary = await client.summarize(source);
    final draft = beginEdit()..description = summary;
    await draft.save();
  }
}
```

A suitable feature layout is:

```text
features/tasks/
  domain/task.dart
  application/task_summarization.dart
  infrastructure/http_task_summary_client.dart
  presentation/...
```

The `application/` layer is present because an external request must be
coordinated. Ordinary entity operations do not need it. The HTTP adapter must
not load, cache, serialize, or synchronize `Task` itself.

If progress, retry, cancellation, audit, or offline execution is real product
state, model the work as an entity-owned process or projection instead of
hiding it inside a service.

## Add a synchronization target

A sync connector translates one generated target contract to a remote system:

```dart
final entityGraph = await ApplicationEntityGraph.openRestApi(
  accountId: accountId,
  connector: (context) => RestApiAdapter(
    client: restApiClient,
    definition: context.definition,
  ),
);
```

`ApplicationEntityGraph`, `openRestApi`, and `RestApiAdapter` are illustrative
names for an application's generated graph, declared target, and handwritten
transport adapter.

The generated target definition already supplies entity descriptors, codecs,
and routing. The adapter implements transport capabilities; it must not declare
application entities, choose their destination, or write directly around the
durable queue. See [Custom connectors](capabilities.md#custom-connectors) for
the complete contract.

## Review checklist

Before adding a custom abstraction, ask:

1. Can the behavior be derived from a field, relationship, capability, index,
   or declared action?
2. Does the code make a real business decision, or only rename generated
   mechanics?
3. Can the entity, its generated set, or its aggregate own the operation?
4. Does an external boundary remain stateless with respect to Nodus entities?
5. Does every entity change still pass through an awaited generated mutation?

If inference is missing or ambiguous, prefer improving the declaration or
compiler diagnostic over adding a parallel persistence or state layer.
