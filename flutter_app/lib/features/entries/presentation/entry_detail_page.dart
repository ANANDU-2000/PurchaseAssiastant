import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/entry_detail_provider.dart';
import '../../../core/widgets/friendly_load_error.dart';

class EntryDetailPage extends ConsumerWidget {
  const EntryDetailPage({super.key, required this.entryId});

  final String entryId;

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entryDetailProvider(entryId));
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Entry detail'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load entry',
          onRetry: () => ref.invalidate(entryDetailProvider(entryId)),
        ),
        data: (data) {
          final rawDate = data['entry_date'];
          final dateStr = rawDate != null
              ? DateFormat.yMMMd().format(DateTime.parse(rawDate.toString()))
              : '—';
          final lines = data['lines'];
          double totalProfit = 0;
          double totalRevenue = 0;
          int lineCount = 0;
          if (lines is List) {
            for (final line in lines) {
              if (line is! Map) continue;
              lineCount++;
              final m = Map<String, dynamic>.from(line);
              final qty = (m['qty'] as num?)?.toDouble() ?? 0;
              final sp = (m['selling_price'] as num?)?.toDouble();
              final p = (m['profit'] as num?)?.toDouble() ?? 0;
              totalProfit += p;
              if (sp != null && qty > 0) totalRevenue += qty * sp;
            }
          }
          final marginPct =
              totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(dateStr,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (data['invoice_no'] != null)
                Text('Invoice: ${data['invoice_no']}', style: tt.bodyMedium),
              if (data['transport_cost'] != null)
                Text(
                    'Transport: ${_inr((data['transport_cost'] as num?)?.toDouble())}',
                    style: tt.bodyMedium),
              if (data['commission_amount'] != null)
                Text(
                    'Commission: ${_inr((data['commission_amount'] as num?)?.toDouble())}',
                    style: tt.bodyMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricCell(
                          label: 'Lines',
                          value: '$lineCount',
                        ),
                      ),
                      Expanded(
                        child: _MetricCell(
                          label: 'Profit',
                          value: _inr(totalProfit),
                        ),
                      ),
                      Expanded(
                        child: _MetricCell(
                          label: 'Margin',
                          value: marginPct == null
                              ? '—'
                              : '${marginPct.toStringAsFixed(1)}%',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Lines',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (lines is List)
                ...lines.map((line) {
                  if (line is! Map) return const SizedBox.shrink();
                  final m = Map<String, dynamic>.from(line);
                  final linked = m['catalog_item_id'] != null;
                  return Card(
                    child: ListTile(
                      onTap: linked
                          ? () => context.push('/catalog/item/${m['catalog_item_id']}')
                          : null,
                      leading: linked
                          ? Icon(Icons.bookmark_outline,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      title: Text(m['item_name']?.toString() ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${m['qty']} ${m['unit']} · landing ${_inr((m['landing_cost'] as num?)?.toDouble())} · '
                        'P/L ${_inr((m['profit'] as num?)?.toDouble())}'
                        '${linked ? ' · catalog' : ''}',
                      ),
                      trailing: linked
                          ? const Icon(Icons.chevron_right_rounded)
                          : null,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
