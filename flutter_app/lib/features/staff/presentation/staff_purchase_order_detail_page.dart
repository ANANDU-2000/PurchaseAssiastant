import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../purchase/presentation/purchase_detail_page.dart';

/// Staff route wrapper — [PurchaseDetailPage] hides financials for staff role.
class StaffPurchaseOrderDetailPage extends ConsumerWidget {
  const StaffPurchaseOrderDetailPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PurchaseDetailPage(purchaseId: purchaseId);
  }
}
