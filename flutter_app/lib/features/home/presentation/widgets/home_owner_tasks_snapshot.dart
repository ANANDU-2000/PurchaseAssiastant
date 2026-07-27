import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/home_dashboard_provider.dart'
    show homeChecklistFetchEnabledProvider;
import '../../../../core/providers/operations_providers.dart';

/// Top incomplete owner checklist items.
class HomeOwnerTasksSnapshot extends ConsumerStatefulWidget {
  const HomeOwnerTasksSnapshot({super.key});

  @override
  ConsumerState<HomeOwnerTasksSnapshot> createState() =>
      _HomeOwnerTasksSnapshotState();
}

class _HomeOwnerTasksSnapshotState extends ConsumerState<HomeOwnerTasksSnapshot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeChecklistFetchEnabledProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(checklistTodayProvider).valueOrNull ?? const <String, dynamic>{};
    final tasks = [
      for (final e in (data['tasks'] as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final open = tasks.where((t) => t['completed'] != true).take(3).toList();
    if (open.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'My tasks',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/operations/owner-tasks'),
              child: const Text('View all'),
            ),
          ],
        ),
        ...open.map(
          (t) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.radio_button_unchecked, size: 20),
            title: Text(t['label']?.toString() ?? 'Task'),
          ),
        ),
      ],
    );
  }
}
