import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/contacts_hub_provider.dart';

final _supplierProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, supplierId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getSupplier(
        businessId: session.primaryBusiness.id,
        supplierId: supplierId,
      );
});

final _supplierMetricsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, supplierId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  final r = contactsDefaultRange();
  return ref.read(hexaApiProvider).supplierMetrics(
        businessId: session.primaryBusiness.id,
        supplierId: supplierId,
        from: r.from,
        to: r.to,
      );
});

class SupplierDetailPage extends ConsumerWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_supplierProvider(supplierId));
    final metricsAsync = ref.watch(_supplierMetricsProvider(supplierId));
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Supplier'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          final phone = s['phone']?.toString();
          final bid = s['broker_id']?.toString();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(s['name']?.toString() ?? '—', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (phone != null && phone.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () => _dial(phone),
                  icon: const Icon(Icons.call_rounded),
                  label: Text(phone),
                )
              else
                const ListTile(
                  leading: Icon(Icons.phone_outlined),
                  title: Text('No phone'),
                ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(s['location']?.toString() ?? '—'),
              ),
              if (bid != null)
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('Linked broker'),
                  subtitle: const Text('Open broker profile'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/broker/$bid'),
                ),
              const SizedBox(height: 16),
              Text('Last $contactsLookbackDays days', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              metricsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const Text('Could not load metrics'),
                data: (m) {
                  final deals = (m['deals'] as num?)?.toInt() ?? 0;
                  final tq = (m['total_qty'] as num?)?.toDouble() ?? 0;
                  final al = (m['avg_landing'] as num?)?.toDouble() ?? 0;
                  final tp = (m['total_profit'] as num?)?.toDouble() ?? 0;
                  final pam = (m['purchase_amount'] as num?)?.toDouble() ?? 0;
                  final margin = (m['profit_margin_pct'] as num?)?.toDouble() ?? 0;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deals: $deals · Total qty: ${tq.toStringAsFixed(2)}'),
                          Text('Avg landing: ${al.toStringAsFixed(2)}'),
                          Text('Purchase amount: ${pam.toStringAsFixed(0)}'),
                          Text('Total profit: ${tp.toStringAsFixed(0)} · Margin: ${margin.toStringAsFixed(1)}%'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
