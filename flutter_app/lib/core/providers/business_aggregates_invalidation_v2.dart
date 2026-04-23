import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Enhanced invalidation for all business aggregates
/// Ensures all UI pages update immediately after any data change

class BusinessAggregatesInvalidationV2 {
  /// Invalidate all analytics and reporting data
  static void invalidateAnalyticsData(WidgetRef ref) {
    try {
      // Analytics KPIs
      ref.invalidate(analyticsKpiProvider);
      ref.invalidate(analyticsBreakdownProviderFamily);
      ref.invalidate(analyticsTimeSeriesProvider);
      
      // Reports
      ref.invalidate(fullReportsInsightsProvider);
      ref.invalidate(fullReportsGoalsProvider);
      ref.invalidate(reportsPriorPeriodDeltaProvider);
      ref.invalidate(reportsPriorPeriodProvider);
      
      // Totals
      ref.invalidate(supplierTotalsProvider);
      ref.invalidate(brokerTotalsProvider);
      ref.invalidate(itemHistoryProvider);
      ref.invalidate(categoryTotalsProvider);
      
      // Home dashboard
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(homeDashboardProvider);
    } catch (e) {
      print('Error invalidating analytics: $e');
    }
  }

  /// Invalidate all business data (after purchase/supplier/item changes)
  static void invalidateBusinessAggregates(WidgetRef ref) {
    try {
      // Invalidate analytics first
      invalidateAnalyticsData(ref);
      
      // Invalidate home/dashboard
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(homeDashboardProvider);
      
      // Invalidate entries list
      ref.invalidate(tradeEntriesListProvider);
      ref.invalidate(tradeEntriesFilteredProvider);
      
      // Invalidate contacts
      ref.invalidate(suppliersListProvider);
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsEnrichedProvider);
      
      // Invalidate catalog
      ref.invalidate(catalogItemsProvider);
      ref.invalidate(catalogCategoriesProvider);
      ref.invalidate(catalogSearchProvider);
      
      // Invalidate purchases
      ref.invalidate(tradePurchasesProvider);
      ref.invalidate(tradePurchasesFilteredProvider);
      
      // Bump business write revision to force all derived providers to refresh
      ref.invalidate(businessWriteRevisionProvider);
    } catch (e) {
      print('Error invalidating business aggregates: $e');
    }
  }

  /// Invalidate only purchase-related data (faster for purchase-only changes)
  static void invalidatePurchaseData(WidgetRef ref) {
    try {
      // Purchase list
      ref.invalidate(tradePurchasesProvider);
      ref.invalidate(tradePurchasesFilteredProvider);
      
      // Analytics that depend on purchases
      ref.invalidate(analyticsKpiProvider);
      ref.invalidate(fullReportsInsightsProvider);
      ref.invalidate(reportsPriorPeriodDeltaProvider);
      
      // Home dashboard
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(homeDashboardProvider);
      
      // Supplier totals (affected by purchase)
      ref.invalidate(supplierTotalsProvider);
      
      // Bump revision
      ref.invalidate(businessWriteRevisionProvider);
    } catch (e) {
      print('Error invalidating purchase data: $e');
    }
  }

  /// Invalidate only supplier-related data
  static void invalidateSupplierData(WidgetRef ref) {
    try {
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsEnrichedProvider);
      ref.invalidate(supplierTotalsProvider);
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(businessWriteRevisionProvider);
    } catch (e) {
      print('Error invalidating supplier data: $e');
    }
  }

  /// Invalidate only item/catalog data
  static void invalidateCatalogData(WidgetRef ref) {
    try {
      ref.invalidate(catalogItemsProvider);
      ref.invalidate(catalogCategoriesProvider);
      ref.invalidate(catalogSearchProvider);
      ref.invalidate(itemHistoryProvider);
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(businessWriteRevisionProvider);
    } catch (e) {
      print('Error invalidating catalog data: $e');
    }
  }

  /// Invalidate only broker data
  static void invalidateBrokerData(WidgetRef ref) {
    try {
      ref.invalidate(brokersListProvider);
      ref.invalidate(brokerTotalsProvider);
      ref.invalidate(homeInsightsProvider);
      ref.invalidate(businessWriteRevisionProvider);
    } catch (e) {
      print('Error invalidating broker data: $e');
    }
  }
}

// TODO: Replace these with your actual provider names from your codebase
final analyticsKpiProvider = FutureProvider((ref) async => {});
final analyticsBreakdownProviderFamily = FutureProvider.family((ref, id) async => {});
final analyticsTimeSeriesProvider = FutureProvider((ref) async => {});
final fullReportsInsightsProvider = FutureProvider((ref) async => {});
final fullReportsGoalsProvider = FutureProvider((ref) async => {});
final reportsPriorPeriodDeltaProvider = FutureProvider((ref) async => {});
final reportsPriorPeriodProvider = FutureProvider((ref) async => {});
final supplierTotalsProvider = FutureProvider((ref) async => {});
final brokerTotalsProvider = FutureProvider((ref) async => {});
final itemHistoryProvider = FutureProvider((ref) async => {});
final categoryTotalsProvider = FutureProvider((ref) async => {});
final homeInsightsProvider = FutureProvider((ref) async => {});
final homeDashboardProvider = FutureProvider((ref) async => {});
final tradeEntriesListProvider = FutureProvider((ref) async => {});
final tradeEntriesFilteredProvider = FutureProvider.family((ref, filter) async => {});
final suppliersListProvider = FutureProvider((ref) async => {});
final brokersListProvider = FutureProvider((ref) async => {});
final contactsEnrichedProvider = FutureProvider((ref) async => {});
final catalogItemsProvider = FutureProvider((ref) async => {});
final catalogCategoriesProvider = FutureProvider((ref) async => {});
final catalogSearchProvider = FutureProvider.family((ref, query) async => {});
final tradePurchasesProvider = FutureProvider((ref) async => {});
final tradePurchasesFilteredProvider = FutureProvider.family((ref, filter) async => {});
final businessWriteRevisionProvider = StateProvider((ref) => 0);
