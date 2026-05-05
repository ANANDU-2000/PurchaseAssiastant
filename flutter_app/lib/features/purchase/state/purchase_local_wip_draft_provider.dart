import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/services/offline_store.dart';

const _draftKeyV1 = 'draft_trade_purchase_v1';

/// Local wizard draft surfaced on Purchase History (Hive + prefs, last 24h).
class PurchaseLocalWipDraftVm {
  const PurchaseLocalWipDraftVm({
    required this.savedAt,
    required this.subtitle,
    required this.titleLine,
  });

  final DateTime savedAt;
  final String subtitle;
  final String titleLine;
}

/// Same eligibility rules as [PurchaseEntryWizardV2._maybeShowResumeDraftMaterialBanner].
final purchaseLocalWipDraftForHistoryProvider =
    Provider<PurchaseLocalWipDraftVm?>((ref) {
  ref.watch(businessDataWriteRevisionProvider);
  final s = ref.watch(sessionProvider);
  if (s == null) return null;
  final bid = s.primaryBusiness.id;
  final k = '${_draftKeyV1}_$bid';
  var raw = OfflineStore.getPurchaseWizardDraft(bid);
  raw ??= ref.watch(sharedPreferencesProvider).getString(k);
  if (raw == null || raw.isEmpty) return null;
  try {
    final dec = jsonDecode(raw);
    if (dec is! Map) return null;
    final m = Map<String, dynamic>.from(dec);
    final meta = m['draftWizardMeta'];
    if (meta is! Map) return null;
    final at = DateTime.tryParse(meta['savedAt']?.toString() ?? '');
    if (at == null) return null;
    if (DateTime.now().difference(at) > const Duration(hours: 24)) {
      return null;
    }
    final items = m['items'] ?? m['lines'];
    final hasLines = items is List && items.isNotEmpty;
    final hasSupplier = (m['supplierId'] ?? m['supplier_id'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    if (!hasLines && !hasSupplier) return null;

    final supplierName = (m['supplierName'] ?? m['supplier_name'] ?? '')
        .toString()
        .trim();
    final titleLine = supplierName.isNotEmpty
        ? supplierName
        : (hasLines ? 'Items in progress' : 'Purchase in progress');

    return PurchaseLocalWipDraftVm(
      savedAt: at,
      subtitle: 'Saved ${DateFormat('MMM d · h:mm a').format(at)}',
      titleLine: titleLine,
    );
  } catch (_) {
    return null;
  }
});
