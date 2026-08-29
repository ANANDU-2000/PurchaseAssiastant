import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../state/purchase_draft_provider.dart';

/// Compact purchase totals strip placed **below** the items table.
///
/// Reads the same strict breakdown / quantity providers — display only except
/// freight fields (same notifier writes as the former desktop sidebar).
class PurchaseEntrySummaryStrip extends ConsumerStatefulWidget {
  const PurchaseEntrySummaryStrip({
    super.key,
    required this.onDraftChanged,
    this.compact = false,
  });

  final VoidCallback onDraftChanged;

  /// Tighter padding for desktop voucher chrome under the items table.
  final bool compact;

  @override
  ConsumerState<PurchaseEntrySummaryStrip> createState() =>
      _PurchaseEntrySummaryStripState();
}

class _PurchaseEntrySummaryStripState
    extends ConsumerState<PurchaseEntrySummaryStrip> {
  final TextEditingController _freightCtrl = TextEditingController();
  final FocusNode _freightFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final f = ref.read(purchaseDraftProvider).freightAmount;
    _freightCtrl.text =
        (f != null && f > 0) ? f.toStringAsFixed(2) : '';
  }

  @override
  void dispose() {
    _freightCtrl.dispose();
    _freightFocus.dispose();
    super.dispose();
  }

  final _inrFmt0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _inrFmt2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  String _inr(num n, {int decimals = 0}) =>
      (decimals == 0 ? _inrFmt0 : _inrFmt2).format(n);

  String _qtyLine() {
    final qt = ref.read(purchaseQuantityTotalsProvider);
    final unitBits = <String>[];
    if (qt.totalKg > 1e-6) {
      unitBits.add('${formatStockQtyForUnit('kg', qt.totalKg)} KG');
    }
    qt.qtyByUnit.forEach((k, v) {
      if (v > 1e-9) {
        final lk = k.trim().toLowerCase();
        if (lk == 'kg' || lk == 'kgs' || lk == 'kilogram') return;
        unitBits.add('${formatStockQtyForUnit(k, v)} ${k.toUpperCase()}');
      }
    });
    return unitBits.isEmpty ? '—' : unitBits.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(purchaseDraftProvider);
    final bd = ref.watch(purchaseStrictBreakdownProvider);
    ref.watch(purchaseQuantityTotalsProvider);
    ref.listen(purchaseDraftProvider, (prev, next) {
      if (_freightFocus.hasFocus) return;
      final f = next.freightAmount;
      final text = (f != null && f > 0) ? f.toStringAsFixed(2) : '';
      if (_freightCtrl.text != text) {
        _freightCtrl.text = text;
      }
    });

    final charges = bd.freight + bd.commission;
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: HexaColors.slate400,
      letterSpacing: 0.3,
    );
    final valueStyle = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: HexaColors.textOnLightSurface,
    );

    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: HexaColors.slateBorder),
            bottom: BorderSide(color: HexaColors.slateBorder),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            4,
            widget.compact ? 8 : 14,
            4,
            widget.compact ? 8 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final cells = <Widget>[
                    _MetricCell(
                      label: 'QTY',
                      value: _qtyLine(),
                      labelStyle: labelStyle,
                      valueStyle: valueStyle,
                      alignEnd: false,
                    ),
                    _MetricCell(
                      label: 'SUBTOTAL',
                      value: _inr(bd.subtotalGross),
                      labelStyle: labelStyle,
                      valueStyle: valueStyle,
                    ),
                    _MetricCell(
                      label: 'TAX',
                      value: _inr(bd.taxTotal, decimals: 2),
                      labelStyle: labelStyle,
                      valueStyle: valueStyle,
                    ),
                    _MetricCell(
                      label: 'CHARGES',
                      value: _inr(charges, decimals: 2),
                      labelStyle: labelStyle,
                      valueStyle: valueStyle,
                    ),
                    _MetricCell(
                      label: 'GRAND TOTAL',
                      value: _inr(bd.grand),
                      labelStyle: labelStyle.copyWith(
                        color: HexaColors.textOnLightSurface,
                        fontWeight: FontWeight.w800,
                      ),
                      valueStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: HexaColors.textOnLightSurface,
                      ),
                    ),
                  ];
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < cells.length; i++) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(child: cells[i]),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (final c in cells)
                        SizedBox(width: 140, child: c),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Text('FREIGHT / EXTRA', style: HexaDsType.overline()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _freightCtrl,
                      focusNode: _freightFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Freight (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        ref
                            .read(purchaseDraftProvider.notifier)
                            .setFreightText(v);
                        widget.onDraftChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: draft.freightType,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'separate',
                          child: Text('Separate'),
                        ),
                        DropdownMenuItem(
                          value: 'included',
                          child: Text('Included'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        ref
                            .read(purchaseDraftProvider.notifier)
                            .setFreightType(v);
                        widget.onDraftChanged();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
    this.alignEnd = true,
  });

  final String label;
  final String value;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        Text(
          value,
          style: valueStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }
}
