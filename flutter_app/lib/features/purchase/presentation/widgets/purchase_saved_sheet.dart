import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/providers/business_profile_provider.dart';
import '../../../../core/services/purchase_pdf.dart';
import '../../../../core/theme/hexa_colors.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

/// Merges wizard-local display fields when the create/update payload omits them
/// (e.g. minimal API rows) so PDF filename, WhatsApp, and email stay accurate.
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
    o['purchase_date'] =
        DateFormat('yyyy-MM-dd').format(purchaseDateFallback);
  }
  return o;
}

String _whatsappSummary(TradePurchase p) {
  final buf = StringBuffer();
  buf.writeln('*Purchase ${p.humanId}*');
  buf.writeln(DateFormat('dd MMM yyyy').format(p.purchaseDate));
  if ((p.supplierName ?? '').trim().isNotEmpty) {
    buf.writeln('Supplier: ${p.supplierName}');
  }
  for (final l in p.lines) {
    final line = '${l.itemName}  ${l.qty} ${l.unit}  @ ${_inr(l.landingCost)}  →  ${_inr(l.qty * l.landingCost)}';
    buf.writeln(line);
  }
  buf.writeln('Total: ${_inr(p.totalAmount)}');
  buf.writeln(
    'Bill PDF: in the app use Share PDF on this purchase (no web link).',
  );
  return buf.toString();
}

Future<void> _openWhatsAppSummary(TradePurchase p) async {
  final text = _whatsappSummary(p);
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Bottom sheet after purchase save. Returns where to navigate: `home`, `detail`, or null (treat as home).
Future<String?> showPurchaseSavedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> savedJson,
  required bool wasEdit,
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
  return showModalBottomSheet<String?>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: HexaColors.brandAccent, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    wasEdit ? 'Purchase updated' : 'Purchase saved',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => ctx.pop('later_missing'),
                                child: const Text('Later'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    ctx.pop( 'edit_missing'),
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
              onTap: () => ctx.pop('home'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('View purchase'),
              onTap: () => ctx.pop('detail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share PDF'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                ctx.pop('home');
                Future<void> doShare() async {
                  final ok = await sharePurchasePdf(p, biz);
                  if (!context.mounted) return;
                  if (ok) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Could not export PDF. Try again.'),
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
                ctx.pop('home');
                Future<void> doPrint() async {
                  final ok = await printPurchasePdf(p, biz);
                  if (!context.mounted) return;
                  if (ok) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Could not print PDF. Try again.'),
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
              leading: const Icon(Icons.chat_rounded),
              title: const Text('WhatsApp (summary)'),
              subtitle: const Text(
                'Opens WhatsApp with a text summary — use Share PDF to send the actual bill file',
              ),
              onTap: () async {
                ctx.pop('home');
                await _openWhatsAppSummary(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: const Text(
                'Prefills subject and details — attach the PDF from Share PDF',
              ),
              onTap: () async {
                ctx.pop('home');
                final dateStr = DateFormat('dd MMM yyyy').format(p.purchaseDate);
                final sup =
                    (p.supplierName ?? '').trim().isNotEmpty ? p.supplierName!.trim() : '—';
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
                  'Share / WhatsApp may use browser download on web.',
                  style: TextStyle(fontSize: 11, color: HexaColors.neutral),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
