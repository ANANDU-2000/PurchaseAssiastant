import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/purchase_draft_provider.dart';
import 'purchase_wizard_shared.dart';

/// Step 3 — collapsible header terms fields.
class PurchaseTermsStep extends ConsumerStatefulWidget {
  const PurchaseTermsStep({
    super.key,
    required this.paymentDaysCtrl,
    required this.deliveredRateCtrl,
    required this.billtyRateCtrl,
    required this.freightCtrl,
    required this.commissionCtrl,
    required this.headerDiscCtrl,
    required this.memoCtrl,
    required this.freightType,
    required this.onFreightTypeChanged,
    required this.onDraftChanged,
    this.hidePaymentDaysAndCommission = false,
  });

  final TextEditingController paymentDaysCtrl;
  final TextEditingController deliveredRateCtrl;
  final TextEditingController billtyRateCtrl;
  final TextEditingController freightCtrl;
  final TextEditingController commissionCtrl;
  final TextEditingController headerDiscCtrl;
  final TextEditingController memoCtrl;
  final String freightType;
  final ValueChanged<String> onFreightTypeChanged;
  final VoidCallback onDraftChanged;
  final bool hidePaymentDaysAndCommission;

  @override
  ConsumerState<PurchaseTermsStep> createState() => _PurchaseTermsStepState();
}

class _PurchaseTermsStepState extends ConsumerState<PurchaseTermsStep> {
  @override
  void initState() {
    super.initState();
    widget.paymentDaysCtrl.addListener(_onCtrl);
    widget.deliveredRateCtrl.addListener(_onCtrl);
    widget.memoCtrl.addListener(_onCtrl);
  }

  @override
  void dispose() {
    widget.paymentDaysCtrl.removeListener(_onCtrl);
    widget.deliveredRateCtrl.removeListener(_onCtrl);
    widget.memoCtrl.removeListener(_onCtrl);
    super.dispose();
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  static String _duePreview(WidgetRef ref, TextEditingController paymentDaysCtrl) {
    final pd = int.tryParse(paymentDaysCtrl.text.trim());
    if (pd == null || pd < 0) return 'Due: —';
    final d0 = ref.read(purchaseDraftProvider).purchaseDate ?? DateTime.now();
    final d = d0.add(Duration(days: pd));
    return 'Due: ${DateFormat('dd MMM yyyy').format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) {
      return const Center(
        child: Text(
          'Select supplier first.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            'Terms & charges',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          children: [
            if (draft.supplierName != null && draft.supplierName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_fix_high,
                          size: 14, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Defaults from ${draft.supplierName} (editable)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF0D9488),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!widget.hidePaymentDaysAndCommission) ...[
            SizedBox(
              height: kPurchaseFieldHeight + 18,
              child: TextField(
                controller: widget.paymentDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: densePurchaseFieldDecoration('Payment days'),
                onChanged: (s) {
                  ref.read(purchaseDraftProvider.notifier).setPaymentDaysText(s);
                  widget.onDraftChanged();
                },
              ),
            ),
            if (widget.paymentDaysCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _duePreview(ref, widget.paymentDaysCtrl),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0D9488),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: kPurchaseFieldHeight + 18,
                    child: TextField(
                      controller: widget.deliveredRateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          densePurchaseFieldDecoration('Delivered rate'),
                      onChanged: (s) {
                        ref.read(purchaseDraftProvider.notifier).setDeliveredText(s);
                        widget.onDraftChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: kPurchaseFieldHeight + 18,
                    child: TextField(
                      controller: widget.billtyRateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          densePurchaseFieldDecoration('Billty rate'),
                      onChanged: (s) {
                        ref.read(purchaseDraftProvider.notifier).setBilltyText(s);
                        widget.onDraftChanged();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: kPurchaseFieldHeight + 18,
                    child: TextField(
                      controller: widget.freightCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          densePurchaseFieldDecoration('Freight', prefixText: '₹ '),
                      onChanged: (s) {
                        ref.read(purchaseDraftProvider.notifier).setFreightText(s);
                        widget.onDraftChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: kPurchaseFieldHeight + 18,
                    child: InputDecorator(
                      decoration:
                          densePurchaseFieldDecoration('Freight type'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: widget.freightType,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                                value: 'separate', child: Text('Separate')),
                            DropdownMenuItem(
                                value: 'included', child: Text('Included')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            widget.onFreightTypeChanged(v);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.hidePaymentDaysAndCommission) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: kPurchaseFieldHeight + 18,
              child: TextField(
                controller: widget.commissionCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    densePurchaseFieldDecoration('Broker commission %'),
                onChanged: (s) {
                  ref.read(purchaseDraftProvider.notifier).setCommissionText(s);
                  widget.onDraftChanged();
                },
              ),
            ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: kPurchaseFieldHeight + 18,
              child: TextField(
                controller: widget.headerDiscCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    densePurchaseFieldDecoration('Discount % (purchase)'),
                onChanged: (s) {
                  ref
                      .read(purchaseDraftProvider.notifier)
                      .setHeaderDiscountFromText(s);
                  widget.onDraftChanged();
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: kPurchaseFieldHeight + 26,
              child: TextField(
                controller: widget.memoCtrl,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    densePurchaseFieldDecoration('Memo / invoice ref'),
                onChanged: (s) {
                  ref.read(purchaseDraftProvider.notifier).setInvoiceText(s);
                  widget.onDraftChanged();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ],
    );
  }
}
