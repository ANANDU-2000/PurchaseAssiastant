import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_breakdown_providers.dart';
import 'analytics_kpi_provider.dart';
import 'contacts_hub_provider.dart';
import 'dashboard_provider.dart';
import 'entries_list_provider.dart';
import 'full_reports_insights_providers.dart';
import 'home_insights_provider.dart';

/// KPIs and tables that depend on [analyticsDateRangeProvider] and/or entries.
void invalidateAnalyticsData(WidgetRef ref) {
  ref.invalidate(analyticsKpiProvider);
  ref.invalidate(analyticsDailyProfitProvider);
  ref.invalidate(analyticsItemsTableProvider);
  ref.invalidate(analyticsCategoriesTableProvider);
  ref.invalidate(analyticsSuppliersTableProvider);
  ref.invalidate(analyticsBrokersTableProvider);
  ref.invalidate(analyticsBestSupplierInsightProvider);
  ref.invalidate(fullReportsInsightsProvider);
  ref.invalidate(fullReportsGoalsProvider);
}

/// After purchases, entries, or other business writes, bust derived KPIs so
/// Home, Reports, Contacts KPIs, and lists do not show stale numbers.
void invalidateBusinessAggregates(WidgetRef ref) {
  invalidateAnalyticsData(ref);
  ref.invalidate(dashboardProvider);
  ref.invalidate(homeInsightsProvider);
  ref.invalidate(homeSevenDayProfitProvider);
  ref.invalidate(entriesListProvider);
  ref.invalidate(contactsSuppliersEnrichedProvider);
  ref.invalidate(contactsBrokersEnrichedProvider);
  ref.invalidate(contactsCategoriesProvider);
  ref.invalidate(contactsItemsProvider);
}
