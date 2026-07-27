import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import 'home_dashboard_provider.dart' show homeOverviewReadyForSatellites;

final Map<String, Future<Map<String, dynamic>>> _openingMissingInflight = {};

/// Query for `GET /v1/businesses/{id}/stock/opening/setup`.
class OpeningStockSetupQuery {
  const OpeningStockSetupQuery({
    this.page = 1,
    this.perPage = 50,
    this.q = '',
    this.status = 'all',
    this.stockStatus = 'all',
    this.missingBarcode = false,
    this.missingItemCode = false,
    this.category = '',
    this.subcategory = '',
    this.supplierId,
    this.unit = '',
    this.updatedToday = false,
    this.updatedBy = '',
  });

  final int page;
  final int perPage;
  final String q;

  /// `all` | `pending` | `completed`
  final String status;
  final String stockStatus;
  final bool missingBarcode;
  final bool missingItemCode;
  final String category;
  final String subcategory;
  final String? supplierId;
  final String unit;
  final bool updatedToday;
  final String updatedBy;

  OpeningStockSetupQuery copyWith({
    int? page,
    int? perPage,
    String? q,
    String? status,
    String? stockStatus,
    bool? missingBarcode,
    bool? missingItemCode,
    String? category,
    String? subcategory,
    String? supplierId,
    String? unit,
    bool? updatedToday,
    String? updatedBy,
  }) {
    return OpeningStockSetupQuery(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      q: q ?? this.q,
      status: status ?? this.status,
      stockStatus: stockStatus ?? this.stockStatus,
      missingBarcode: missingBarcode ?? this.missingBarcode,
      missingItemCode: missingItemCode ?? this.missingItemCode,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      supplierId: supplierId ?? this.supplierId,
      unit: unit ?? this.unit,
      updatedToday: updatedToday ?? this.updatedToday,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

final openingStockSetupQueryProvider =
    StateProvider<OpeningStockSetupQuery>(
      (_) => const OpeningStockSetupQuery(),
    );

/// Server-backed list: summary + rows.
final openingStockSetupProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
    final session = ref.watch(sessionProvider);
    if (session == null) {
      return {
        'summary': {},
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'per_page': ref.read(openingStockSetupQueryProvider).perPage,
      };
    }
    final query = ref.watch(openingStockSetupQueryProvider);
    final body = await ref.read(hexaApiProvider).listOpeningStockSetup(
      businessId: session.primaryBusiness.id,
      page: query.page,
      perPage: query.perPage,
      q: query.q,
      status: query.status,
      stockStatus: query.stockStatus,
      missingBarcode: query.missingBarcode,
      missingItemCode: query.missingItemCode,
      category: query.category,
      subcategory: query.subcategory,
      supplierId: query.supplierId,
      unit: query.unit,
      updatedToday: query.updatedToday,
      updatedBy: query.updatedBy,
    );
    if (providerWasDisposed(disposed)) {
      return {
        'summary': {},
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': query.page,
        'per_page': query.perPage,
      };
    }
    return body;
  },
);

/// Bulk selection state for the Opening Stock Setup page.
final openingStockBulkSelectionProvider = StateProvider<Set<String>>(
  (ref) => {},
);

/// Items missing opening stock (home banners + critical alerts).
final openingStockMissingProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (!homeOverviewReadyForSatellites(ref)) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  final bid = session.primaryBusiness.id;
  final body = await _openingMissingInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .getMissingOpeningStock(businessId: bid)
        .whenComplete(() => _openingMissingInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  return body;
});
