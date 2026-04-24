import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/providers/business_profile_provider.dart';
import '../../../../core/services/purchase_pdf.dart';
import '../../../../core/theme/hexa_colors.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

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
  buf.write('(PDF: open app → Purchases → ${p.humanId} → share/print)');
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
}) async {
  final p = TradePurchase.fromJson(Map<String, dynamic>.from(savedJson));
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
              '${_inr(p.totalAmount)} · ${p.lines.length} line(s)',
              style: const TextStyle(color: HexaColors.neutral, fontSize: 13),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home dashboard'),
              subtitle: const Text('Close entry and go to overview'),
              onTap: () => Navigator.pop(ctx, 'home'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('View purchase'),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share PDF'),
              onTap: () async {
                Navigator.pop(ctx, 'home');
                await sharePurchasePdf(p, biz);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Print'),
              onTap: () async {
                Navigator.pop(ctx, 'home');
                await printPurchasePdf(p, biz);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded),
              title: const Text('WhatsApp (summary)'),
              subtitle: const Text('Opens WhatsApp with text — attach PDF from Share PDF if needed'),
              onTap: () async {
                Navigator.pop(ctx, 'home');
                await _openWhatsAppSummary(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              onTap: () async {
                Navigator.pop(ctx, 'home');
                final sub = Uri.encodeComponent('Purchase ${p.humanId}');
                final body = Uri.encodeComponent('Please find purchase ${p.humanId} attached.');
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
