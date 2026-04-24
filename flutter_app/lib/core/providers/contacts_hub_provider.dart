import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

/// Default lookback for Contacts KPIs (days).
const int contactsLookbackDays = 90;

({String from, String to}) contactsDefaultRange() {
  final fmt = DateFormat('yyyy-MM-dd');
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: contactsLookbackDays));
  return (from: fmt.format(from), to: fmt.format(to));
}

/// Suppliers merged with last-90d analytics rows (key `_metrics` when present).
final contactsSuppliersEnrichedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final r = contactsDefaultRange();
  final list = await api.listSuppliers(businessId: session.primaryBusiness.id);
  List<Map<String, dynamic>> metrics = [];
  try {
    metrics = await api.tradeReportSuppliers(
        businessId: session.primaryBusiness.id, from: r.from, to: r.to);
  } catch (_) {}
  final byId = <String, Map<String, dynamic>>{};
  for (final m in metrics) {
    byId[m['supplier_id']?.toString() ?? ''] = m;
  }
  return list.map((s) {
    final id = s['id']?.toString() ?? '';
    final mx = byId[id];
    return {...s, if (mx != null) '_metrics': mx};
  }).toList();
});

final contactsBrokersEnrichedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final r = contactsDefaultRange();
  final list = await api.listBrokers(businessId: session.primaryBusiness.id);
  List<Map<String, dynamic>> metrics = [];
  try {
    metrics = await api.analyticsBrokers(
        businessId: session.primaryBusiness.id, from: r.from, to: r.to);
  } catch (_) {}
  final byId = <String, Map<String, dynamic>>{};
  for (final m in metrics) {
    byId[m['broker_id']?.toString() ?? ''] = m;
  }
  return list.map((b) {
    final id = b['id']?.toString() ?? '';
    final mx = byId[id];
    return {...b, if (mx != null) '_metrics': mx};
  }).toList();
});

final contactsCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final r = contactsDefaultRange();
  try {
    return await api.tradeReportCategories(
        businessId: session.primaryBusiness.id, from: r.from, to: r.to);
  } catch (_) {
    return [];
  }
});

final contactsItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final r = contactsDefaultRange();
  return api.analyticsItems(
      businessId: session.primaryBusiness.id, from: r.from, to: r.to);
});
