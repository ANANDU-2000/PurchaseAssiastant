import '../../../core/api/hexa_api.dart';

/// Shared barcode assign/patch helper — keeps call sites on one API path.
Future<Map<String, dynamic>> assignBarcodeToItem({
  required HexaApi api,
  required String businessId,
  required String itemId,
  required String barcode,
}) {
  return api.patchCatalogItemBarcode(
    businessId: businessId,
    itemId: itemId,
    barcode: barcode,
  );
}
