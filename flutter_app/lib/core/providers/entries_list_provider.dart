import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

/// Server-side filter by item name substring (backend matches line item names).
final entrySearchQueryProvider = StateProvider<String>((ref) => '');

/// Optional inclusive date range filters (entry_date). Null = no filter on that bound.
final entryListFromProvider = StateProvider<DateTime?>((ref) => null);
final entryListToProvider = StateProvider<DateTime?>((ref) => null);

/// Optional supplier filter (entries.supplier_id).
final entryListSupplierIdProvider = StateProvider<String?>((ref) => null);

final entriesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final from = ref.watch(entryListFromProvider);
  final to = ref.watch(entryListToProvider);
  final supplierId = ref.watch(entryListSupplierIdProvider);
  final api = ref.read(hexaApiProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final raw = await api.listEntries(
    businessId: session.primaryBusiness.id,
    from: from == null ? null : fmt.format(from),
    to: to == null ? null : fmt.format(to),
    supplierId: supplierId,
  );
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
