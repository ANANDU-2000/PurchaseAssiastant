import '../api/hexa_api.dart';

final Map<String, Future<List<Map<String, dynamic>>>> _tradePurchasesPageInflight =
    {};

/// Dedupe key for concurrent `GET …/trade-purchases` pages (history + reports).
String tradePurchasesListDedupeKey({
  required String businessId,
  required int limit,
  required int offset,
  String? status,
  String? purchaseFrom,
  String? purchaseTo,
  bool includeLines = false,
}) {
  return '$businessId|${status ?? ''}|${purchaseFrom ?? ''}|${purchaseTo ?? ''}|'
      '$limit|$offset|$includeLines';
}

Future<List<Map<String, dynamic>>> fetchTradePurchasesPageDeduped({
  required HexaApi api,
  required String businessId,
  required int limit,
  required int offset,
  String? status,
  String? purchaseFrom,
  String? purchaseTo,
  bool includeLines = false,
}) {
  final key = tradePurchasesListDedupeKey(
    businessId: businessId,
    limit: limit,
    offset: offset,
    status: status,
    purchaseFrom: purchaseFrom,
    purchaseTo: purchaseTo,
    includeLines: includeLines,
  );
  return _tradePurchasesPageInflight.putIfAbsent(
    key,
    () => api
        .listTradePurchases(
          businessId: businessId,
          limit: limit,
          offset: offset,
          status: status,
          purchaseFrom: purchaseFrom,
          purchaseTo: purchaseTo,
          includeLines: includeLines,
        )
        .whenComplete(() => _tradePurchasesPageInflight.remove(key)),
  );
}

void bustTradePurchasesListInflight() {
  _tradePurchasesPageInflight.clear();
}
