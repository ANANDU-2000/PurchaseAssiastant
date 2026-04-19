import 'package:flutter_riverpod/flutter_riverpod.dart';

/// After a **new** purchase save, wizard sets this and navigates to `/home`.
/// [HomePage] shows [showPurchaseSavedSheet] once, then clears.
class PurchasePostSavePayload {
  const PurchasePostSavePayload({
    required this.savedJson,
    required this.wasEdit,
  });

  final Map<String, dynamic> savedJson;
  final bool wasEdit;
}

final purchasePostSaveProvider =
    StateProvider<PurchasePostSavePayload?>((ref) => null);
