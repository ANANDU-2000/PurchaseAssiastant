import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/purchase_draft_provider.dart';
import 'purchase_wizard_shared.dart';

/// Step 2 — deal terms once (vertical, no side‑by‑side rows on narrow screens).
class PurchaseTermsOnlyStep extends ConsumerWidget {
  const PurchaseTermsOnlyStep({
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

  static String _duePreview(WidgetRef ref, TextEditingController c) {
    final pd = int.tryParse(c.text.trim());
    if (pd == null || pd < 0) return 'Due: —';
    final d0 = ref.read(purchaseDraftProvider).purchaseDate ?? DateTime.now();
    final d = d0.add(Duration(days: pd));
    return 'Due: ${DateFormat('dd MMM yyyy').format(d)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) {
      return const Center(
        child: Text(
          'Select a supplier first.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }
    final hasBroker =
        draft.brokerId != null && draft.brokerId!.trim().isNotEmpty;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget field(
      TextEditingController c,
      String label, {
      TextInputType? keyboard,
      int maxLines = 1,
      void Function(String)? onChanged,
    }) {
      final tf = TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 1 : null,
        textCapitalization: maxLines > 1
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: densePurchaseFieldDecoration(label),
        onChanged: onChanged,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: maxLines > 1
            ? tf
            : SizedBox(
                height: kPurchaseFieldHeight + 18,
                child: tf,
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (draft.supplierName != null && draft.supplierName!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      size: 16, color: Color(0xFF0D9488)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Defaults from ${draft.supplierName!.trim()} (editable)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        field(
          paymentDaysCtrl,
          'Payment days',
          keyboard: TextInputType.number,
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setPaymentDaysText(s);
            onDraftChanged();
          },
        ),
        ListenableBuilder(
          listenable: paymentDaysCtrl,
          builder: (_, __) {
            final t = paymentDaysCtrl.text.trim();
            if (t.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _duePreview(ref, paymentDaysCtrl),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF0D9488),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
        if (hasBroker) ...[
          field(
            commissionCtrl,
            'Broker commission %',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setCommissionText(s);
              onDraftChanged();
            },
          ),
        ],
        field(
          deliveredRateCtrl,
          'Delivered rate',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setDeliveredText(s);
            onDraftChanged();
          },
        ),
        field(
          billtyRateCtrl,
          'Billty rate',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setBilltyText(s);
            onDraftChanged();
          },
        ),
        field(
          freightCtrl,
          'Freight amount',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setFreightText(s);
            onDraftChanged();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InputDecorator(
            decoration: densePurchaseFieldDecoration('Freight type'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: freightType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'separate', child: Text('Separate')),
                  DropdownMenuItem(value: 'included', child: Text('Included')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  onFreightTypeChanged(v);
                },
              ),
            ),
          ),
        ),
        field(
          headerDiscCtrl,
          'Discount % (purchase)',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setHeaderDiscountFromText(s);
            onDraftChanged();
          },
        ),
        field(
          memoCtrl,
          'Memo / invoice ref',
          maxLines: 2,
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setInvoiceText(s);
            onDraftChanged();
          },
        ),
        Text(
          'Freight, delivered, billty, and purchase discount apply once to this bill — not per line.',
          style: TextStyle(fontSize: 11, height: 1.3, color: sub),
        ),
      ],
    );
  }
}
