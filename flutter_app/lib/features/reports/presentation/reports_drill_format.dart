import 'package:flutter/material.dart';

import '../../../core/json_coerce.dart';
import '../../../core/theme/hexa_colors.dart';

/// Quantity with unit label for reports drill rows.
String reportsQtyWithUnit(num qty, String? unit) {
  final u = (unit ?? '').trim();
  final rounded = qty.roundToDouble();
  final qStr = (qty - rounded).abs() < 0.001
      ? '${rounded.round()}'
      : qty.toStringAsFixed(1);
  if (u.isEmpty || u == '—') return qStr;
  return '$qStr $u';
}

/// Drill list row: bold item name, qty+unit, optional muted supplier.
class ReportsDrillItemTile extends StatelessWidget {
  const ReportsDrillItemTile({
    super.key,
    required this.itemName,
    required this.qtyLine,
    this.supplierName,
    this.amountLine,
    this.onTap,
  });

  final String itemName;
  final String qtyLine;
  final String? supplierName;
  final String? amountLine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onTap: onTap,
      title: Text(
        itemName,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      subtitle: supplierName != null && supplierName!.trim().isNotEmpty
          ? Text(
              supplierName!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: HexaColors.textBody,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            qtyLine,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: HexaColors.brandPrimary,
            ),
          ),
          if (amountLine != null && amountLine!.isNotEmpty)
            Text(
              amountLine!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

String reportsInr0(num n) => '₹${n.round()}';

List<Map<String, dynamic>> reportsItemsForCategory(
  List<Map<String, dynamic>> items,
  String categoryName,
) {
  final key = categoryName.trim().toLowerCase();
  return [
    for (final r in items)
      if ((r['category_name'] ?? '').toString().trim().toLowerCase() == key) r,
  ];
}

List<Map<String, dynamic>> reportsItemsForSubcategory(
  List<Map<String, dynamic>> items,
  String subcategoryName,
) {
  final key = subcategoryName.trim().toLowerCase();
  return [
    for (final r in items)
      if ((r['type_name'] ?? r['subcategory_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase() ==
          key)
        r,
  ];
}

String reportsItemQtyLine(Map<String, dynamic> row) {
  final qty = coerceToDouble(row['total_qty'] ?? row['qty']);
  final unit = row['unit']?.toString();
  final bags = coerceToDouble(row['total_bags']);
  if (bags > 0) {
    return reportsQtyWithUnit(bags, 'bags');
  }
  return reportsQtyWithUnit(qty, unit);
}
