import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/contacts_hub_provider.dart';

final _brokerProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, brokerId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getBroker(
        businessId: session.primaryBusiness.id,
        brokerId: brokerId,
      );
});

final _brokerMetricsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, brokerId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  final r = contactsDefaultRange();
  return ref.read(hexaApiProvider).brokerMetrics(
        businessId: session.primaryBusiness.id,
        brokerId: brokerId,
        from: r.from,
        to: r.to,
      );
});

class BrokerDetailPage extends ConsumerWidget {
  const BrokerDetailPage({super.key, required this.brokerId});

  final String brokerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_brokerProvider(brokerId));
    final metricsAsync = ref.watch(_brokerMetricsProvider(brokerId));
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Broker'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (b) {
          final ct = b['commission_type']?.toString() ?? '—';
          final cv = b['commission_value'];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(b['name']?.toString() ?? '—', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.percent_outlined),
                title: Text('Commission: $ct${cv != null ? ' · $cv' : ''}'),
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
                  final tc = (m['total_commission'] as num?)?.toDouble() ?? 0;
                  final tp = (m['total_profit'] as num?)?.toDouble() ?? 0;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deals: $deals'),
                          Text('Total commission: ${tc.toStringAsFixed(0)}'),
                          Text('Related line profit: ${tp.toStringAsFixed(0)}'),
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
