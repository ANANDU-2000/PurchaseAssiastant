import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a full-screen purchase overlay is above the shell (edit / detail / new).
/// Background shell tabs stay mounted (IndexedStack) — gate list/report refetches.
final purchaseOverlayActiveProvider = StateProvider<bool>((ref) => false);

bool purchaseRouteIsOverlay(String loc) {
  if (loc == '/purchase/new') return true;
  if (loc.startsWith('/purchase/edit/')) return true;
  if (loc.startsWith('/purchase/detail/')) return true;
  return false;
}

void syncPurchaseOverlayActive(ProviderContainer container, String loc) {
  try {
    container.read(purchaseOverlayActiveProvider.notifier).state =
        purchaseRouteIsOverlay(loc);
  } catch (_) {}
}
