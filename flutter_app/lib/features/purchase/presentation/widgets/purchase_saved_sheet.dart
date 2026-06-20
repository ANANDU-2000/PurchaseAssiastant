import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/providers/business_profile_provider.dart';
import '../../../../core/services/purchase_pdf.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/design_system/hexa_responsive.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Merges wizard-local display fields when the create/update payload omits them
/// (e.g. minimal API rows) so PDF filename and email stay accurate.
Map<String, dynamic> enrichSavedTradePurchaseJson(
  Map<String, dynamic> saved, {
  String? supplierNameFallback,
  String? brokerNameFallback,
  DateTime? purchaseDateFallback,
}) {
  final o = Map<String, dynamic>.from(saved);
  void putIfBlank(String key, String? fb) {
    final cur = o[key]?.toString().trim() ?? '';
    final v = fb?.trim() ?? '';
    if (cur.isEmpty && v.isNotEmpty) {
      o[key] = v;
    }
  }

  putIfBlank('supplier_name', supplierNameFallback);
  putIfBlank('broker_name', brokerNameFallback);
  final pd = o['purchase_date']?.toString().trim() ?? '';
  if (pd.isEmpty && purchaseDateFallback != null) {
    o['purchase_date'] = DateFormat('yyyy-MM-dd').format(purchaseDateFallback);
  }
  return o;
}

/// Bottom sheet after purchase save. Returns where to navigate: `home`, `detail`, or null (treat as home).
Future<String?> showPurchaseSavedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> savedJson,
  required bool wasEdit,
  bool showDeliveryPrompt = false,
  String? displaySupplierName,
  String? displayBrokerName,
  DateTime? displayPurchaseDate,
}) async {
  final merged = enrichSavedTradePurchaseJson(
    savedJson,
    supplierNameFallback: displaySupplierName,
    brokerNameFallback: displayBrokerName,
    purchaseDateFallback: displayPurchaseDate,
  );
  final p = TradePurchase.fromJson(merged);
  final biz = ref.read(invoiceBusinessProfileProvider);

  if (!context.mounted) return null;
  return showHexaBottomSheet<String?>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: HexaColors.brandAccent, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                wasEdit ? 'Purchase updated' : 'Purchase saved',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          p.humanId,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: HexaColors.brandPrimary,
          ),
        ),
        Text(
          '${DateFormat('dd MMM yyyy').format(p.purchaseDate)} · '
          '${(p.supplierName ?? '').trim().isNotEmpty ? p.supplierName!.trim() : 'Supplier —'} · '
          '${_inr(p.totalAmount)} · ${p.lines.length} line(s)',
          style: const TextStyle(color: HexaColors.neutral, fontSize: 13),
        ),
        const Divider(height: 24),
        if (showDeliveryPrompt && !wasEdit) ...[
          const Icon(
            Icons.local_shipping_outlined,
            size: 32,
            color: Colors.orange,
          ),
          const SizedBox(height: 8),
          const Text(
            'Has this shipment arrived at your warehouse?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'delivery_no'),
                  child: const Text('Not yet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, 'delivery_yes'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Yes, received'),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
        ListTile(
          leading: const Icon(Icons.add_shopping_cart_rounded),
          title: const Text('Add more items'),
          subtitle: const Text('Continue adding items to a new purchase'),
          onTap: () => Navigator.pop(context, 'add_more'),
        ),
            if (savedJson['stock_updates'] is List &&
                (savedJson['stock_updates'] as List).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Stock updated',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final u
                            in (savedJson['stock_updates'] as List).take(6))
                          if (u is Map)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${u['item_name'] ?? u['name'] ?? 'Item'}: '
                                        '${u['old_qty'] ?? '—'} → ${u['new_qty'] ?? '—'} '
                                        '${u['unit'] ?? ''}'
                                    .trim(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (p.hasMissingDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade900, size: 22),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Some details missing — update now?',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Broker, payment days, freight type/amount, or header discount were left blank.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, 'later_missing'),
                                child: const Text('Later'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context, 'edit_missing'),
                                child: const Text('Edit now'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home dashboard'),
              subtitle: const Text('Close entry and go to overview'),
              onTap: () => Navigator.pop(context, 'home'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('View purchase'),
              onTap: () => Navigator.pop(context, 'detail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share PDF'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context, 'home');
                Future<void> doShare() async {
                  final result = await sharePurchasePdf(p, biz);
                  if (!context.mounted) return;
                  if (result.ok) {
                    messenger
                        .showSnackBar(SnackBar(content: Text(result.message)));
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      action: SnackBarAction(
                        label: 'Retry',
                        onPressed: () => doShare(),
                      ),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }

                await doShare();
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Print'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context, 'home');
                Future<void> doPrint() async {
                  final result = await printPurchasePdf(p, biz);
                  if (!context.mounted) return;
                  if (result.ok) {
                    messenger
                        .showSnackBar(SnackBar(content: Text(result.message)));
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      action: SnackBarAction(
                        label: 'Retry',
                        onPressed: () => doPrint(),
                      ),
                    ),
                  );
                }

                await doPrint();
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: const Text(
                'Prefills subject and details — attach the PDF from Share PDF',
              ),
              onTap: () async {
                Navigator.pop(context, 'home');
                final dateStr =
                    DateFormat('dd MMM yyyy').format(p.purchaseDate);
                final sup = (p.supplierName ?? '').trim().isNotEmpty
                    ? p.supplierName!.trim()
                    : '—';
                final sub = Uri.encodeComponent(
                  'Purchase ${p.humanId} · $dateStr · $sup',
                );
                final body = Uri.encodeComponent(
                  'Purchase: ${p.humanId}\n'
                  'Date: $dateStr\n'
                  'Supplier: $sup\n'
                  'Total: ${_inr(p.totalAmount)}\n\n'
                  'Attach the PDF from the app (Share PDF on this purchase).',
                );
                final uri = Uri.parse('mailto:?subject=$sub&body=$body');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            if (kIsWeb)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Share may use browser download on web.',
                  style: TextStyle(fontSize: 11, color: HexaColors.neutral),
                ),
              ),
      ],
    ),
  );
}
