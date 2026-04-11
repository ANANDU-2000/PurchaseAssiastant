import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/contacts_hub_provider.dart';

final _categoryItemsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, category) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final r = contactsDefaultRange();
  return api.categoryItems(
    businessId: session.primaryBusiness.id,
    category: category,
    from: r.from,
    to: r.to,
  );
});

class CategoryItemsPage extends ConsumerWidget {
  const CategoryItemsPage({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_categoryItemsProvider(category));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text(category),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No line items in this category for the last $contactsLookbackDays days.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final row = rows[i];
              final name = row['item_name']?.toString() ?? '—';
              final profit = (row['total_profit'] as num?)?.toDouble() ?? 0;
              final qty = (row['total_qty'] as num?)?.toDouble() ?? 0;
              final lines = (row['line_count'] as num?)?.toInt() ?? 0;
              return Card(
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Lines: $lines · Qty: ${qty.toStringAsFixed(2)} · Profit: ${profit.toStringAsFixed(0)}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/item-analytics/${Uri.encodeComponent(name)}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
