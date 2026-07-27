import '../auth/session_notifier.dart';
import '../errors/user_facing_errors.dart';
import '../../features/stock/stock_list_row_patch.dart'
    show stockListPatchFromPhysicalCount, stockListPatchFromStockDetail;
import 'stock_list_providers.dart';
import 'stock_detail_providers.dart';

/// Realtime single-item refresh: fetch one row and patch list cache (no full list refetch).
Future<void> patchStockItemInCache(
  dynamic ref, {
  required String itemId,
}) async {
  if (itemId.isEmpty) return;
  final session = ref.read(sessionProvider);
  if (session == null) return;
  try {
    final detail = await ref.read(hexaApiProvider).getStockItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
        );
    final patch = <String, dynamic>{
      ...stockListPatchFromStockDetail(detail),
      ...stockListPatchFromPhysicalCount(detail),
    };
    if (patch.isNotEmpty) {
      applyStockListRowPatch(ref, itemId: itemId, patch: patch);
    }
    clearStockItemDetailPatch(ref, itemId: itemId);
    ref.invalidate(stockItemDetailProvider(itemId));
    ref.invalidate(stockItemIntelligenceProvider(itemId));
    ref.invalidate(stockItemActivityProvider(itemId));
  } catch (e, st) {
    logSilencedApiError(e, st);
    ref.invalidate(stockItemDetailProvider(itemId));
    ref.invalidate(stockItemActivityProvider(itemId));
  }
}
