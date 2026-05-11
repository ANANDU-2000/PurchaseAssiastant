import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assistant_chat_theme.dart';

/// Parsed preview row data for [PreviewCard.parse].
class PreviewCardData {
  const PreviewCardData({
    required this.item,
    required this.quantity,
    required this.unitPrice,
    required this.supplier,
    required this.total,
    this.landedLine,
    this.isEntity = false,
  });

  final String item;
  final String quantity;
  final String unitPrice;
  final String supplier;
  final String total;
  final String? landedLine;
  final bool isEntity;
}

/// Purchase preview summary + Cancel / Save (maps to YES/NO flow).
class PreviewCard extends StatelessWidget {
  const PreviewCard({
    super.key,
    required this.entryDraft,
    required this.onCancel,
    required this.onSave,
  });

  final Map<String, dynamic> entryDraft;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  static PreviewCardData? parse(Map<String, dynamic> d) {
    if (d['__assistant__'] == 'entity') {
      return const PreviewCardData(
        item: 'New record',
        quantity: '—',
        unitPrice: '—',
        supplier: '—',
        total: '—',
        isEntity: true,
      );
    }
    final lines = d['lines'];
    if (lines is! List || lines.isEmpty) return null;
    if (lines.length > 1) return null;
    final line = lines.first;
    if (line is! Map) return null;
    final m = Map<String, dynamic>.from(line);
    final item = (m['item_name'] ?? m['item'] ?? 'Item').toString();
    final qty = m['qty'];
    final unit = (m['unit'] ?? '').toString();
    final buy = m['buy_price'];
    final land = m['landing_cost'];
    final qtyN = qty is num ? qty.toDouble() : double.tryParse('$qty') ?? 0;
    final buyN = buy is num ? buy.toDouble() : double.tryParse('$buy');
    final landN = land is num ? land.toDouble() : double.tryParse('$land');
    final cur = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final supplierRaw = d['supplier_name']?.toString().trim() ??
        d['supplier']?.toString().trim() ??
        '';
    final supplier = supplierRaw.isNotEmpty
        ? supplierRaw
        : (d['supplier_id'] != null ? 'Linked' : '—');
    final totalN = (landN != null && qtyN > 0) ? qtyN * landN : null;
    return PreviewCardData(
      item: item,
      quantity: '${_fmtNum(qty)} $unit'.trim(),
      unitPrice: buyN != null ? cur.format(buyN) : '—',
      supplier: supplier,
      total: totalN != null ? cur.format(totalN) : (landN != null ? cur.format(landN) : '—'),
      landedLine: landN != null ? cur.format(landN) : null,
      isEntity: false,
    );
  }

  static String _fmtNum(dynamic v) {
    if (v is num) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toString();
    }
    return v?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final f = PreviewCard.parse(entryDraft);
    if (f == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AssistantChatTheme.mediumAnim,
      curve: AssistantChatTheme.motion,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4, right: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AssistantChatTheme.accent.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14075E54),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: AssistantChatTheme.previewHighlight,
                blurRadius: 0,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 20, color: AssistantChatTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      f.isEntity ? 'Preview' : 'Purchase preview',
                      style: AssistantChatTheme.jakarta(15,
                          w: FontWeight.w700, c: AssistantChatTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PreviewRow(label: 'Item', value: f.item),
                _PreviewRow(label: 'Quantity', value: f.quantity),
                _PreviewRow(label: 'Price / unit', value: f.unitPrice),
                if (f.landedLine != null) _PreviewRow(label: 'Landed / unit', value: f.landedLine!),
                _PreviewRow(label: 'Supplier', value: f.supplier),
                const Divider(height: 22),
                _PreviewRow(label: 'Total (est.)', value: f.total, strong: true),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text('Cancel', style: AssistantChatTheme.inter(14, w: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: AssistantChatTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text('Save', style: AssistantChatTheme.inter(14, w: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: AssistantChatTheme.inter(12.5,
                  w: FontWeight.w500, c: const Color(0xFF667781)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AssistantChatTheme.inter(13.5,
                  w: strong ? FontWeight.w700 : FontWeight.w600,
                  c: const Color(0xFF111B21)),
            ),
          ),
        ],
      ),
    );
  }
}
