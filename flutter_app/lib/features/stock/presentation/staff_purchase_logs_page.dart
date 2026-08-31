import 'package:flutter/material.dart';

import '../../../shared/widgets/desktop_page_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/json_coerce.dart';
import '../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../core/utils/unit_utils.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

final staffPurchaseLogsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref
      .read(hexaApiProvider)
      .listStaffPurchaseLogs(businessId: session.primaryBusiness.id);
});

class StaffPurchaseLogsPage extends ConsumerWidget {
  const StaffPurchaseLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffPurchaseLogsProvider);
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final df = DateFormat('d MMM, h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Staff cash purchases')),
      body: DesktopPageShell(
        padding: EdgeInsets.zero,
        child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => StaffPurchaseLogsLoadError(
          subtitle: loadStateErrorSubtitle(e),
          onRetry: () => ref.invalidate(staffPurchaseLogsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return HexaEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No staff cash purchases yet',
              subtitle:
                  'Quick buys logged from the stock list will show up here.',
              primaryActionLabel: isStaff ? 'Open stock' : 'Go to stock',
              onPrimaryAction: () =>
                  context.go(isStaff ? '/staff/stock' : '/stock'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(staffPurchaseLogsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) {
                final r = rows[i];
                final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
                final amount = coerceToDoubleNullable(r['amount']);
                return ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: Text(r['item_name']?.toString() ?? 'Item'),
                  subtitle: Text(
                    '${formatStockQtyNumber(coerceToDouble(r['qty']))} '
                    '${(r['unit'] ?? '').toString().toUpperCase()}'
                    '${amount != null ? ' · Rs. ${amount.toStringAsFixed(0)}' : ''}\n'
                    '${r['supplier_name'] ?? 'No supplier'} · ${r['created_by_name'] ?? 'Staff'}'
                    '${dt != null ? ' · ${df.format(dt)}' : ''}',
                  ),
                  isThreeLine: true,
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: rows.length,
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Staff cash purchase logs load failure (UX-156).
@visibleForTesting
class StaffPurchaseLogsLoadError extends StatelessWidget {
  const StaffPurchaseLogsLoadError({
    super.key,
    required this.onRetry,
    this.subtitle,
  });

  final VoidCallback onRetry;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Could not load staff cash purchases',
      subtitle: subtitle ?? 'Check your connection, then retry.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
