import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_breakdown_providers.dart';
import 'business_write_revision.dart';
import 'analytics_kpi_provider.dart';
import 'brokers_list_provider.dart';
import 'contacts_hub_provider.dart';
import 'dashboard_provider.dart';
import 'entries_list_provider.dart';
import 'full_reports_insights_providers.dart';
import 'home_insights_provider.dart';
import 'suppliers_list_provider.dart';

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
///
/// Also invalidates the keepAlive supplier/broker list providers so pickers
/// and preference JSON always reflect the latest server state.
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
  // keepAlive list providers — must be explicitly busted after any write that
  // touches supplier/broker rows (purchase save, item wizard, entry create).
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
  // Open ledger / item-insight screens use local or family providers — nudge
  // them to refetch after any aggregate-invalidating write.
  bumpBusinessDataWriteRevision(ref);
}
