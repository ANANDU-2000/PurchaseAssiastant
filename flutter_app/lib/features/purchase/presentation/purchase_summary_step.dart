import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calc_engine.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../domain/purchase_draft.dart';
import '../state/purchase_draft_provider.dart';

class PurchaseSummaryStep extends ConsumerWidget {
  const PurchaseSummaryStep({
    super.key,
    required this.onGoSupplier,
    required this.onGoItems,
    required this.onGoTerms,
    required this.onEditTerms,
    required this.onSave,
    required this.isSaving,
    required this.canSave,
    this.isEditMode = false,
    this.paymentDerivedStatus,
  });

  final VoidCallback onGoSupplier;
  final VoidCallback onGoItems;
  final VoidCallback onGoTerms;
  final VoidCallback onEditTerms;
  final VoidCallback onSave;
  final bool isSaving;
  final bool canSave;
  final bool isEditMode;
  final String? paymentDerivedStatus;

  static String _rs(double x) => 'Rs. ${x.toStringAsFixed(2)}';

  static String _fmtQty(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(3);

  static String _fmtWt(double kg) {
    if (kg <= 0) return '—';
    final t = kg == kg.roundToDouble();
    return '${t ? kg.toInt() : kg.toStringAsFixed(2)} kg';
  }

  static TradeCalcLine _toCalc(PurchaseLineDraft it) => TradeCalcLine(
        qty: it.qty,
        landingCost: it.landingCost,
        kgPerUnit: it.kgPerUnit,
        landingCostPerKg: it.landingCostPerKg,
        taxPercent: it.taxPercent,
        discountPercent: it.lineDiscountPercent,
      );

  static double _itemsSumLines(List<PurchaseLineDraft> lines) {
    var s = 0.0;
    for (final it in lines) {
      s += lineMoney(_toCalc(it));
    }
    return s;
  }

  static double _lineWeightKg(PurchaseLineDraft it) {
    final u = it.unit.trim().toLowerCase();
    final kpu = it.kgPerUnit;
    if ((u == 'bag' || u == 'sack') && kpu != null && kpu > 0) {
      return it.qty * kpu;
    }
    if (u == 'kg') return it.qty;
    final kpb = it.kgPerBox;
    if (u == 'box' && kpb != null && kpb > 0) return it.qty * kpb;
    if (u == 'tin' && kpu != null && kpu > 0) return it.qty * kpu;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    final b = ref.watch(purchaseStrictBreakdownProvider);
    final qtot = ref.watch(purchaseQuantityTotalsProvider);
    final saveVal = ref.watch(purchaseSaveValidationProvider);

    final delivered = draft.deliveredRate ?? 0;
    final billty = draft.billtyRate ?? 0;
    final freight =
        draft.freightType == 'included' ? 0.0 : (draft.freightAmount ?? 0);
    final itemsSub = _itemsSumLines(draft.lines);
    final bags = (qtot.qtyByUnit['bag'] ?? 0) + (qtot.qtyByUnit['sack'] ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEditMode && paymentDerivedStatus != null) ...[
          Text(
            'Payment: $paymentDerivedStatus',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
        ],
        Text('Items', style: HexaDsType.formSectionLabel),
        const SizedBox(height: 4),
        if (draft.lines.isEmpty)
          const Text(
            'No items added.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          )
        else ...[
          const _ItemTableHeader(),
          ...draft.lines.asMap().entries.map((e) {
            final i = e.key;
            final it = e.value;
            final calc = _toCalc(it);
            final lineTot = lineMoney(calc);
            final rate = it.qty > 0 ? lineTot / it.qty : it.landingCost;
            final wkg = _lineWeightKg(it);
            final err = saveVal.lineErrors[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          it.itemName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      _NumCell(flex: 1, text: _fmtQty(it.qty), fontSize: 11),
                      _NumCell(flex: 1, text: it.unit.trim(), fontSize: 10),
                      _NumCell(
                        flex: 1,
                        text: wkg > 0 ? _fmtWt(wkg) : '—',
                        fontSize: 10,
                      ),
                      _NumCell(flex: 1, text: _rs(rate), fontSize: 10),
                      _NumCell(flex: 1, text: _rs(lineTot), fontSize: 10),
                    ],
                  ),
                  if (err != null && err.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 2),
                      child: Text(
                        err,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade800,
                          height: 1.25,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HexaColors.brandBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BreakRow(label: 'Items subtotal:', value: _rs(itemsSub)),
              if (delivered > 0)
                _BreakRow(
                  label: 'Delivered (supplier):',
                  value: _rs(delivered),
                  trailing: TextButton(
                    onPressed: onEditTerms,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Edit ×', style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (billty > 0)
                _BreakRow(
                  label: 'Billty (supplier):',
                  value: _rs(billty),
                  trailing: TextButton(
                    onPressed: onEditTerms,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Edit ×', style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (freight > 0)
                _BreakRow(
                  label: 'Freight:',
                  value: _rs(freight),
                  trailing: TextButton(
                    onPressed: onEditTerms,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Edit ×', style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (b.discountTotal > 0)
                _BreakRow(
                  label: 'Discount:',
                  value: '- ${_rs(b.discountTotal)}',
                  valueColor: Colors.red.shade800,
                ),
              if (b.commission > 0)
                _BreakRow(label: 'Commission:', value: _rs(b.commission)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'TOTAL:',
                    style: HexaDsType.formSectionLabel.copyWith(fontSize: 15),
                  ),
                  Text(
                    _rs(b.grand),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F4C3A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                qtot.totalKg > 0
                    ? 'Total weight: ${_fmtWt(qtot.totalKg)}'
                    : 'Total weight: —',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                'Total bags: ${bags > 0 ? '${_fmtQty(bags)} bags' : '0 bags'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onGoSupplier,
                child: const Text('← Supplier', maxLines: 1),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: onGoItems,
                child: const Text('← Items', maxLines: 1),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: onGoTerms,
                child: const Text('← Terms', maxLines: 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (isSaving || !canSave)
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onSave();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F4C3A),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    isEditMode ? 'Save changes' : 'Save purchase',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ItemTableHeader extends StatelessWidget {
  const _ItemTableHeader();

  @override
  Widget build(BuildContext context) {
    TextStyle hdr() => TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          color: Colors.grey.shade700,
        );
    Widget h(int flex, String t, {bool right = true}) => Expanded(
          flex: flex,
          child: Text(
            t,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: hdr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Item', style: hdr())),
          h(1, 'Qty'),
          h(1, 'Unit'),
          h(1, 'Weight'),
          h(1, 'Rate'),
          h(1, 'Total'),
        ],
      ),
    );
  }
}

class _NumCell extends StatelessWidget {
  const _NumCell({
    required this.flex,
    required this.text,
    this.fontSize = 12,
  });

  final int flex;
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
          color: const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _BreakRow extends StatelessWidget {
  const _BreakRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF0F172A),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
