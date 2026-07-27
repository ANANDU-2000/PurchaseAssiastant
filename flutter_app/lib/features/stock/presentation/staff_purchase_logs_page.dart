import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/utils/unit_utils.dart';

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
    final df = DateFormat('d MMM, h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Staff cash purchases')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userFacingError(e))),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No staff cash purchases yet.'));
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
    );
  }
}
