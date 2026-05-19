import 'package:intl/intl.dart';

import '../../../../core/models/trade_purchase_models.dart';

/// One row in a grouped purchase history list.
sealed class PurchaseHistoryEntry {
  const PurchaseHistoryEntry();
}

class PurchaseHistoryDateHeader extends PurchaseHistoryEntry {
  const PurchaseHistoryDateHeader(this.label);
  final String label;
}

class PurchaseHistoryPurchaseRow extends PurchaseHistoryEntry {
  const PurchaseHistoryPurchaseRow(this.purchase);
  final TradePurchase purchase;
}

String purchaseHistoryDateGroupLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (!d.isBefore(today.subtract(const Duration(days: 7)))) return 'This week';
  if (d.year == today.year && d.month == today.month) {
    return DateFormat('d MMM').format(d);
  }
  return DateFormat('MMM yyyy').format(d);
}

int _groupSortKey(String label) {
  switch (label) {
    case 'Today':
      return 0;
    case 'Yesterday':
      return 1;
    case 'This week':
      return 2;
    default:
      return 3;
  }
}

/// Flatten purchases into date headers + rows for dense ledger UI.
List<PurchaseHistoryEntry> buildGroupedPurchaseHistory(
  List<TradePurchase> purchases,
) {
  if (purchases.isEmpty) return const [];

  final buckets = <String, List<TradePurchase>>{};
  for (final p in purchases) {
    final key = purchaseHistoryDateGroupLabel(p.purchaseDate);
    buckets.putIfAbsent(key, () => []).add(p);
  }

  final keys = buckets.keys.toList()
    ..sort((a, b) {
      final c = _groupSortKey(a).compareTo(_groupSortKey(b));
      if (c != 0) return c;
      return a.compareTo(b);
    });

  final out = <PurchaseHistoryEntry>[];
  for (final key in keys) {
    out.add(PurchaseHistoryDateHeader(key));
    final rows = buckets[key]!
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    for (final p in rows) {
      out.add(PurchaseHistoryPurchaseRow(p));
    }
  }
  return out;
}
