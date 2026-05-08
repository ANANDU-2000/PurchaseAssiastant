import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory scan JSON between **Scan bill** and **Purchase draft wizard** (until DB drafts exist).
class PurchaseScanDraftMapNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setDraft(Map<String, dynamic> scan) {
    state = Map<String, dynamic>.from(scan);
  }

  void clear() => state = null;
}

final purchaseScanDraftMapProvider =
    NotifierProvider<PurchaseScanDraftMapNotifier, Map<String, dynamic>?>(
  PurchaseScanDraftMapNotifier.new,
);
