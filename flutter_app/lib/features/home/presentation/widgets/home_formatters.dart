import 'package:intl/intl.dart';

import '../../../../core/providers/home_dashboard_provider.dart';
import '../../home_pack_unit_word.dart';

String homeInr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String homeFmtQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

String homeDashboardUnitsLine(HomeDashboardData? data) {
  if (data == null) return '';
  final parts = <String>[];
  if (data.totalBags > 0) {
    parts.add(
        '${homeFmtQty(data.totalBags)} ${homePackUnitWord('BAG', data.totalBags)}');
  }
  if (data.totalBoxes > 0) {
    parts.add(
        '${homeFmtQty(data.totalBoxes)} ${homePackUnitWord('BOX', data.totalBoxes)}');
  }
  if (data.totalTins > 0) {
    parts.add(
        '${homeFmtQty(data.totalTins)} ${homePackUnitWord('TIN', data.totalTins)}');
  }
  if (data.totalKg > 0) parts.add('${homeFmtQty(data.totalKg)} KG');
  return parts.isEmpty ? '' : parts.join(' · ');
}

String homeTimeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat('d MMM').format(at);
}

String homeRefreshAgo(DateTime? at) {
  if (at == null) return 'just now';
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}
