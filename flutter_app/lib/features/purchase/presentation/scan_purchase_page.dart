import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/purchase_bill_scan_panel.dart';

/// Standalone scan route — same UX as wizard-embedded [`PurchaseBillScanPanel`].
class ScanPurchasePage extends ConsumerWidget {
  const ScanPurchasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan purchase bill'),
      ),
      body: PurchaseBillScanPanel(
        compactHeading: false,
        applyButtonLabel: 'Use this data → New purchase',
        applyButtonIcon: Icons.edit_note_rounded,
        onApplyDraft: (d) => context.push('/purchase/new', extra: d),
      ),
    );
  }
}
