import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:tasks_example/nodus.g.dart';

final class SyncCenterPage extends StatelessWidget {
  const SyncCenterPage(this.entityGraph, {super.key});

  final TasksExampleEntityGraph entityGraph;

  @override
  Widget build(BuildContext context) {
    final queue = entityGraph.syncQueue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync center'),
        actions: [
          IconButton(
            key: const Key('refreshQueueButton'),
            tooltip: 'Refresh queue',
            onPressed: queue.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Observer(
        builder: (_) {
          final syncState = queue.state.value;
          final syncing = syncState.phase == SyncPhase.syncing;
          return ListView(
            key: const Key('syncQueueList'),
            padding: const EdgeInsets.all(24),
            children: [
              _SyncSummary(state: syncState, itemCount: queue.items.length),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('syncNowButton'),
                onPressed: syncing ? null : queue.synchronize,
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Pull and retry now'),
              ),
              const SizedBox(height: 24),
              Text(
                'Durable work',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (queue.items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'The queue is empty. This device is caught up.',
                    ),
                  ),
                )
              else
                for (final item in queue.items) _SyncWorkCard(item: item),
            ],
          );
        },
      ),
    );
  }
}

final class _SyncSummary extends StatelessWidget {
  const _SyncSummary({required this.state, required this.itemCount});

  final SyncState state;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final label = switch (state.phase) {
      SyncPhase.idle => 'Idle',
      SyncPhase.syncing => 'Synchronizing',
      SyncPhase.waitingToRetry => 'Waiting to retry',
      SyncPhase.needsAttention => 'Needs attention',
      SyncPhase.failed => 'Local failure',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              state.phase == SyncPhase.idle
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_sync_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  Text(state.message ?? '$itemCount queue item(s)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SyncWorkCard extends StatelessWidget {
  const _SyncWorkCard({required this.item});

  final SyncWorkItem item;

  @override
  Widget build(BuildContext context) {
    final detail = switch (item) {
      PushSyncWorkItem(:final operation) =>
        'protocol ${operation.protocolVersion}',
      PullSyncWorkItem() => 'graph cursor',
    };
    final failure = switch (item.lastFailure) {
      null => '',
      RejectedSyncWorkFailure(:final category) =>
        ' · rejected: ${category.name}',
      ConflictSyncWorkFailure() => ' · version conflict',
      RetryableSyncWorkFailure(:final code) => ' · retryable: $code',
    };
    return Card(
      key: ValueKey('syncWork_${item.id}'),
      child: ListTile(
        leading: Icon(
          item.direction == SyncDirection.push
              ? Icons.upload_outlined
              : Icons.download_outlined,
        ),
        title: Text('${item.direction.name} · ${item.kind.name}'),
        subtitle: Text(
          '${item.status.name} · attempt ${item.attemptCount} · $detail$failure',
        ),
        trailing: item.nextAttemptAt == null
            ? null
            : Tooltip(
                message: 'Retry ${item.nextAttemptAt!.toLocal()}',
                child: const Icon(Icons.schedule),
              ),
      ),
    );
  }
}
