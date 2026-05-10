import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hexa_purchase_assistant/core/maintenance/maintenance_month_record.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_repository.dart';
import 'package:hexa_purchase_assistant/core/providers/prefs_provider.dart';
import 'package:hexa_purchase_assistant/core/router/navigation_ext.dart';
import 'package:hexa_purchase_assistant/core/theme/hexa_colors.dart';
import 'package:hexa_purchase_assistant/core/theme/theme_context_ext.dart';

class MaintenanceHistoryPage extends ConsumerWidget {
  const MaintenanceHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final prefs = ref.watch(sharedPreferencesProvider);
    final repo = MaintenancePaymentRepository(prefs);
    final rows = repo.allRowsNewestFirst();

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Maintenance history', style: tt.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: rows.isEmpty
          ? const Center(
              child: Text('No records yet. Open the app to create this month.',
                  textAlign: TextAlign.center),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                return Card(
                  color: context.adaptiveCard,
                  child: ListTile(
                    title: Text(r.month, style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    )),
                    subtitle: Text(
                      '₹${r.amount} · ${r.isPaid ? "Paid" : "Unpaid"}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _detail(context, r),
                  ),
                );
              },
            ),
    );
  }
}

void _detail(BuildContext context, MaintenanceMonthRecord r) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(r.month),
      content: Text(
        r.isPaid
            ? 'Status: paid\n'
                'Amount: ₹${r.amount}\n'
                'Paid: ${r.paidAt != null ? DateFormat.yMMMd().add_jm().format(r.paidAt!) : "—"}'
            : 'Status: unpaid\nAmount: ₹${r.amount}',
        style: TextStyle(height: 1.35, color: HexaColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
