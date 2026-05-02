import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'purchase_summary_step.dart';
import 'purchase_terms_step.dart';

/// Final step: recap lines + totals, then editable header terms/charges.
class PurchaseReviewStep extends ConsumerWidget {
  const PurchaseReviewStep({
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PurchaseSummarySections(),
          const SizedBox(height: 16),
          Text(
            'Deal terms',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
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
          ),
        ],
      ),
    );
  }
}
