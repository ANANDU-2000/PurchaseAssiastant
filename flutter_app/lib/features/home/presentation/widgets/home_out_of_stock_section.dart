import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/section_inline_error.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;

/// Out-of-stock items with Buy Now CTA.
class HomeOutOfStockSection extends ConsumerWidget {
  const HomeOutOfStockSection({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider);
    if (session == null) {
      return const HomeSectionSkeleton(rows: 2);
    }
    final listAsync = ref.watch(homeOutOfStockListProvider);

    return listAsync.when(
      loading: () => const HomeSectionSkeleton(rows: 2),
      error: (_, __) => SectionInlineError(
        message: 'Could not load out-of-stock items',
        onRetry: () => ref.invalidate(homeOutOfStockListProvider),
      ),
      data: (payload) {
        final raw = payload['items'];
        final rows = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        final out = rows
            .where((r) => (r['stock_status']?.toString() ?? '') == 'out')
            .take(dense ? 3 : 5)
            .toList();
        if (out.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Out of stock',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: dense ? 13 : null,
                  ),
            ),
            SizedBox(height: dense ? 4 : 8),
            ...out.map(
              (r) => Card(
                margin: EdgeInsets.only(bottom: dense ? 4 : 6),
                child: ListTile(
                  dense: dense,
                  visualDensity:
                      dense ? VisualDensity.compact : VisualDensity.standard,
                  title: Text(
                    r['name']?.toString() ?? 'Item',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 13 : 14,
                    ),
                  ),
                  trailing: FilledButton(
                    onPressed: () {
                      final id = r['id']?.toString();
                      if (id != null && id.isNotEmpty) {
                        context.push('/purchase/new?catalog_item_id=$id');
                      } else {
                        context.push('/purchase/new');
                      }
                    },
                    child: const Text('Buy now'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
