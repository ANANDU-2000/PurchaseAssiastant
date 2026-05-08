import 'package:flutter/material.dart';

String scanDraftConfLabel(Object? v) {
  final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  if (d == null) return 'Needs review';
  if (d >= 0.92) return 'High';
  if (d >= 0.70) return 'Medium';
  return 'Needs review';
}

Color scanDraftConfBg(Object? v) {
  final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  if (d == null) return const Color(0xFFFEF2F2);
  if (d >= 0.92) return const Color(0xFFECFDF3);
  if (d >= 0.70) return const Color(0xFFFFFBEB);
  return const Color(0xFFFEF2F2);
}

Color scanDraftConfFg(Object? v) {
  final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  if (d == null) return const Color(0xFF991B1B);
  if (d >= 0.92) return const Color(0xFF027A48);
  if (d >= 0.70) return const Color(0xFFB45309);
  return const Color(0xFF991B1B);
}

Widget scanDraftConfChip(Object? v) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: scanDraftConfBg(v),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Text(
      scanDraftConfLabel(v),
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: scanDraftConfFg(v)),
    ),
  );
}

Widget scanDraftConfidencePill(double c) {
  final (bg, fg, label) = c >= 0.85
      ? (const Color(0xFFECFDF5), const Color(0xFF065F46), 'HIGH')
      : (c >= 0.55
          ? (const Color(0xFFFFFBEB), const Color(0xFF92400E), 'MEDIUM')
          : (const Color(0xFFFEF2F2), const Color(0xFF991B1B), 'LOW'));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: fg.withAlpha(35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

class ScanDraftTableHeader extends StatelessWidget {
  const ScanDraftTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.black54,
        );
    return Row(
      children: [
        Expanded(flex: 6, child: Text('Item', style: s)),
        Expanded(flex: 2, child: Text('Qty', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('Unit', style: s, textAlign: TextAlign.center)),
        Expanded(flex: 2, child: Text('P', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('S', style: s, textAlign: TextAlign.right)),
      ],
    );
  }
}

/// ERP-style row with a leading expand control for kg / amount / raw fields.
class ScanDraftExpandableItemRow extends StatefulWidget {
  const ScanDraftExpandableItemRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.trailing,
  });

  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final Widget trailing;

  @override
  State<ScanDraftExpandableItemRow> createState() => _ScanDraftExpandableItemRowState();
}

class _ScanDraftExpandableItemRowState extends State<ScanDraftExpandableItemRow> {
  bool _expanded = false;

  String _fmt(Object? v) {
    if (v == null) return '—';
    if (v is num) {
      return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);
    }
    final t = v.toString().trim();
    return t.isEmpty ? '—' : t;
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
            Expanded(
              child: ScanDraftTableRow(
                item: it,
                onTap: widget.onEdit,
                trailing: widget.trailing,
              ),
            ),
          ],
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 44, right: 8, bottom: 8),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Raw: ${_fmt(it['raw_name'])}',
                      style: const TextStyle(color: Colors.black54)),
                  Text('Kg (line): ${_fmt(it['total_kg'] ?? it['kg'] ?? it['line_kg'])}'),
                  Text('Amount: ${_fmt(it['line_total'] ?? it['preview_line_total'])}'),
                  Text(
                    'Catalog match: ${_fmt(it['matched_catalog_item_id'] ?? it['matched_id'])}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ScanDraftTableRow extends StatelessWidget {
  const ScanDraftTableRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.trailing,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final Widget trailing;

  String _s(Object? v, [String fallback = '—']) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  String _n(Object? v) {
    if (v is num) return (v == v.roundToDouble()) ? '${v.round()}' : v.toStringAsFixed(2);
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? '—' : t;
  }

  @override
  Widget build(BuildContext context) {
    final name = _s(item['matched_name'] ?? item['raw_name']);
    final qty = _n(item['bags'] ?? item['qty']);
    final unit = _s(item['unit_type'], '—').toLowerCase();
    final p = _n(item['purchase_rate']);
    final sr = _n(item['selling_rate']);
    final conf = item['confidence'];
    final c = (conf is num) ? conf.toDouble() : double.tryParse(conf?.toString() ?? '');
    final matched = (item['matched_catalog_item_id'] ?? item['matched_id'])?.toString().trim();
    final hasMatch = matched != null && matched.isNotEmpty;
    final hasRate = (item['purchase_rate'] is num) ||
        (double.tryParse(item['purchase_rate']?.toString() ?? '') != null);
    final needsReview = (c == null || c < 0.70) || !hasMatch || !hasRate;
    final bg = !needsReview
        ? Colors.transparent
        : (c != null && c >= 0.70 ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2));
    final border = !needsReview
        ? Colors.transparent
        : (c != null && c >= 0.70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(left: BorderSide(color: border, width: needsReview ? 3 : 0)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(flex: 2, child: Text(qty, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text(unit, textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(p, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text(sr, textAlign: TextAlign.right)),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
