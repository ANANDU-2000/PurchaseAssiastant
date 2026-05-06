import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'scan_purchase_v2_page.dart';

/// Standalone scan route — same UX as wizard-embedded [`PurchaseBillScanPanel`].
class ScanPurchasePage extends ConsumerWidget {
  const ScanPurchasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Master rebuild: v2 scanner UX (image preview + staged progress + preview table).
    return const ScanPurchaseV2Page();
  }
}
