import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/business_profile.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/providers/business_profile_provider.dart';
import '../../../../core/services/purchase_pdf.dart';
import '../../../../core/theme/hexa_colors.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

/// Bottom sheet after purchase save — replaces a blocking dialog.
Future<void> showPurchaseSavedSheet(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> savedJson,
  required bool wasEdit,
}) async {
  final p = TradePurchase.fromJson(Map<String, dynamic>.from(savedJson));
  final biz = ref.read(businessProfileProvider).valueOrNull ??
      const BusinessProfile(legalName: '', displayTitle: '');

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: HexaColors.brandAccent, size: 32),
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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: HexaColors.brandPrimary,
              ),
            ),
            Text(
              '${_inr(p.totalAmount)} · ${p.lines.length} line(s)',
              style: TextStyle(color: HexaColors.neutral, fontSize: 13),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share PDF'),
              onTap: () async {
                Navigator.pop(ctx);
                await sharePurchasePdf(p, biz);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Print'),
              onTap: () async {
                Navigator.pop(ctx);
                await printPurchasePdf(p, biz);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded),
              title: const Text('WhatsApp'),
              onTap: () async {
                Navigator.pop(ctx);
                await sharePurchasePdf(p, biz);
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              onTap: () async {
                Navigator.pop(ctx);
                final sub = Uri.encodeComponent('Purchase ${p.humanId}');
                final body = Uri.encodeComponent('Please find purchase ${p.humanId} attached.');
                final uri = Uri.parse('mailto:?subject=$sub&body=$body');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('View purchase'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/purchase/detail/${p.id}');
              },
            ),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
