import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Purchase tab: recent trade purchases + entry point for the wizard.
class PurchaseHomePage extends ConsumerWidget {
  const PurchaseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final rows = ref.watch(tradePurchasesListProvider);
    final inr = NumberFormat.currency(
        locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(tradePurchasesListProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in to record purchases.'))
          : rows.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => FriendlyLoadError(
                onRetry: () => ref.invalidate(tradePurchasesListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'No trade purchases yet.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap New purchase to add your first PUR document.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = items[i];
                    final hid = r['human_id']?.toString() ?? '';
                    final date = r['purchase_date']?.toString() ?? '';
                    final total = (r['total_amount'] as num?)?.toDouble() ?? 0;
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      child: ListTile(
                        title: Text(
                          hid,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(date),
                        trailing: Text(
                          inr.format(total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: HexaColors.primaryMid,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: session == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/purchase/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New purchase'),
            ),
    );
  }
}
