import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Full purchase preview table for AI chatbot — shows ALL lines.
class PurchasePreviewTable extends StatelessWidget {
  const PurchasePreviewTable({
    super.key,
    required this.entryDraft,
    required this.onCancel,
    required this.onSave,
    required this.onEdit,
  });

  final Map<String, dynamic> entryDraft;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onEdit;

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lines = (entryDraft['lines'] as List?) ?? [];
    final supplier = entryDraft['supplier_name']?.toString() ??
        entryDraft['supplier_id']?.toString() ??
        '—';
    final broker = entryDraft['broker_name']?.toString() ?? '';
    final payDays = entryDraft['payment_days']?.toString() ?? '';

    var grand = 0.0;
    for (final raw in lines) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final qty = (m['qty'] as num?)?.toDouble() ?? 0;
      final rate = (m['purchase_rate'] as num?)?.toDouble() ??
          (m['landing_cost'] as num?)?.toDouble() ??
          0;
      grand += qty * rate;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '📦 Purchase Preview',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Edit in wizard',
                ),
              ],
            ),
            Text(
              '$supplier${broker.isNotEmpty ? "  ·  Broker: $broker" : ""}',
              style: tt.bodyMedium,
            ),
            if (payDays.isNotEmpty)
              Text(
                'Payment: $payDays days',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            const Divider(height: 16),
            const _TableRow(
              isHeader: true,
              item: 'Item',
              qty: 'Qty',
              unit: 'Unit',
              rate: 'Rate',
              amount: 'Amount',
            ),
            const Divider(height: 1),
            for (final raw in lines)
              if (raw is Map) _buildLineRow(Map<String, dynamic>.from(raw)),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Total: ',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _inr.format(grand),
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                  onPressed: onCancel,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Save Purchase'),
                    onPressed: onSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineRow(Map<String, dynamic> raw) {
    final item = raw['item_name']?.toString() ??
        raw['item']?.toString() ??
        'Item';
    final qty = (raw['qty'] as num?)?.toStringAsFixed(0) ?? '0';
    final unit = raw['unit']?.toString() ?? '';
    final rate = (raw['purchase_rate'] as num?)?.toDouble() ??
        (raw['landing_cost'] as num?)?.toDouble() ??
        0;
    final amount = ((raw['qty'] as num?)?.toDouble() ?? 0) * rate;
    return _TableRow(
      item: item,
      qty: qty,
      unit: unit,
      rate: rate > 0 ? _inr.format(rate) : '—',
      amount: amount > 0 ? _inr.format(amount) : '—',
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.item,
    required this.qty,
    required this.unit,
    required this.rate,
    required this.amount,
    this.isHeader = false,
  });

  final String item;
  final String qty;
  final String unit;
  final String rate;
  final String amount;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)
        : const TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              item,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(qty, style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 36,
            child: Text(unit, style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 60,
            child: Text(rate, style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 70,
            child: Text(amount, style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
