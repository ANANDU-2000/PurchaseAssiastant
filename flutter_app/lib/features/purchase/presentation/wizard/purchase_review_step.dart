import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/purchase_draft_provider.dart';
import 'purchase_summary_step.dart';
import 'purchase_terms_step.dart';
import 'purchase_wizard_shared.dart';

/// Final step: recap lines + totals, then editable header terms/charges.
class PurchaseReviewStep extends ConsumerWidget {
  const PurchaseReviewStep({
    super.key,
    required this.isEdit,
    required this.previewHumanId,
    required this.editHumanId,
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

  final bool isEdit;
  final String? previewHumanId;
  final String? editHumanId;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);

    final dateStr = DateFormat('dd MMM yyyy')
        .format(draft.purchaseDate ?? DateTime.now());
    final purLabel = isEdit
        ? (editHumanId ?? '—')
        : (previewHumanId ?? 'New');
    final supplier = draft.supplierName?.trim();
    final broker = draft.brokerName?.trim();

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              if (supplier != null && supplier.isNotEmpty) supplier else 'Supplier —',
              if (broker != null && broker.isNotEmpty) broker,
              dateStr,
              'PUR $purLabel',
            ].join(' · '),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 16),
          const PurchaseSummarySections(),
          const SizedBox(height: 16),
          Text(
            'Deal terms',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: kPurchaseFieldHeight + 18,
                      child: TextField(
                        controller: paymentDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            densePurchaseFieldDecoration('Payment days'),
                        onChanged: (s) {
                          ref
                              .read(purchaseDraftProvider.notifier)
                              .setPaymentDaysText(s);
                          onDraftChanged();
                        },
                      ),
                    ),
                    ListenableBuilder(
                      listenable: paymentDaysCtrl,
                      builder: (ctx, _) {
                        final pd =
                            int.tryParse(paymentDaysCtrl.text.trim());
                        if (pd == null || pd < 0) {
                          return const SizedBox.shrink();
                        }
                        final d0 =
                            draft.purchaseDate ?? DateTime.now();
                        final d = d0.add(Duration(days: pd));
                        final due = DateFormat('dd MMM yyyy').format(d);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Due: $due',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF0D9488),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: kPurchaseFieldHeight + 18,
                  child: TextField(
                    controller: commissionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: densePurchaseFieldDecoration(
                      'Broker commission %',
                    ),
                    onChanged: (s) {
                      ref
                          .read(purchaseDraftProvider.notifier)
                          .setCommissionText(s);
                      onDraftChanged();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PurchaseTermsStep(
            paymentDaysCtrl: paymentDaysCtrl,
            deliveredRateCtrl: deliveredRateCtrl,
            billtyRateCtrl: billtyRateCtrl,
            freightCtrl: freightCtrl,
            commissionCtrl: commissionCtrl,
            headerDiscCtrl: headerDiscCtrl,
            memoCtrl: memoCtrl,
            freightType: freightType,
            onFreightTypeChanged: onFreightTypeChanged,
            onDraftChanged: onDraftChanged,
            hidePaymentDaysAndCommission: true,
          ),
        ],
      ),
    );
  }
}
