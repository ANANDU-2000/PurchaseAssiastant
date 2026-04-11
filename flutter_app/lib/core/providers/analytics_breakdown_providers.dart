import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';

final analyticsItemsTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsItems(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsCategoriesTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsCategories(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsSuppliersTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsSuppliers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsBrokersTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsBrokers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});
