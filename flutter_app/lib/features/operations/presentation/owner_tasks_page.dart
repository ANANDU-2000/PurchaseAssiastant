import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/operations_providers.dart';

final ownerChecklistSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider);
  if (s == null) return {};
  return ref.read(hexaApiProvider).getChecklistSummary(
        businessId: s.primaryBusiness.id,
      );
});

class OwnerTasksPage extends ConsumerWidget {
  const OwnerTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(checklistTodayProvider);
    final summary = ref.watch(ownerChecklistSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Owner Tasks')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          summary.when(
            data: (s) => Card(
              child: ListTile(
                title: Text('Completion ${((s['completion_pct'] as num?) ?? 0).toString()}%'),
                subtitle: Text(
                  'Completed ${(s['tasks_completed'] as num?)?.toInt() ?? 0} / ${(s['tasks_total'] as num?)?.toInt() ?? 0}',
                ),
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Text('Today checklist', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          todayAsync.when(
            data: (d) {
              final tasks = [
                for (final e in (d['tasks'] as List? ?? const []))
                  if (e is Map) Map<String, dynamic>.from(e),
              ];
              if (tasks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No tasks for today'),
                );
              }
              return Column(
                children: [
                  for (final t in tasks)
                    CheckboxListTile(
                      value: t['completed'] == true,
                      onChanged: null,
                      title: Text(t['label']?.toString() ?? 'Task'),
                      subtitle: Text((t['slot']?.toString() ?? '').toUpperCase()),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Could not load tasks'),
          ),
        ],
      ),
    );
  }
}

