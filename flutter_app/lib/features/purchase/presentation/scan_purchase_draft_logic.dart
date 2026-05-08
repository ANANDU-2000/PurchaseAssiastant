import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';

/// Updates cached scan JSON then confirms — returns created trade purchase JSON (same shape as createTradePurchase).
Future<Map<String, dynamic>> scanPurchaseUpdateAndConfirm({
  required dynamic ref,
  required String scanToken,
  required Map<String, dynamic> scanPayload,
  required DateTime purchaseDate,
  String? invoiceNumber,
  required bool forceDuplicate,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  await api.scanPurchaseBillV2Update(
    businessId: bid,
    body: {'scan_token': scanToken, 'scan': scanPayload},
  );
  final confirmBody = <String, dynamic>{
    'scan_token': scanToken,
    'purchase_date':
        '${purchaseDate.year.toString().padLeft(4, '0')}-${purchaseDate.month.toString().padLeft(2, '0')}-${purchaseDate.day.toString().padLeft(2, '0')}',
    'status': 'confirmed',
    'force_duplicate': forceDuplicate,
  };
  final inv = invoiceNumber?.trim();
  if (inv != null && inv.isNotEmpty) {
    confirmBody['invoice_number'] = inv;
  }
  return api.scanPurchaseBillV2Confirm(
    businessId: bid,
    body: confirmBody,
  );
}

/// Shared validation for scan → trade purchase confirm (scanner v2/v3 cache).
bool scanDraftReadyForCreate(Map<String, dynamic>? scan, {required bool scanIssueBlocker}) {
  if (scan == null || scanIssueBlocker) return false;
  final items = scan['items'];
  if (items is! List || items.whereType<Map>().isEmpty) return false;
  final supplier = scan['supplier'];
  final hasSupplier = supplier is Map &&
      (supplier['matched_id']?.toString().trim().isNotEmpty ?? false);
  if (!hasSupplier) return false;
  for (final item in items) {
    if (item is! Map) return false;
    final matched = (item['matched_catalog_item_id'] ?? item['matched_id'])?.toString().trim();
    final rate = double.tryParse(item['purchase_rate']?.toString() ?? '');
    if (matched == null || matched.isEmpty || rate == null || rate <= 0) {
      return false;
    }
  }
  return true;
}

String? scanDraftToken(Map<String, dynamic>? scan) {
  if (scan == null) return null;
  final t = scan['scan_token']?.toString().trim();
  return (t != null && t.isNotEmpty) ? t : null;
}

/// Persists edited scan to cache then confirms purchase; navigates to detail on success.
Future<String?> runScanDraftPurchaseCreate({
  required WidgetRef ref,
  required BuildContext context,
  required Map<String, dynamic> scan,
}) async {
  final token = scanDraftToken(scan);
  if (token == null) return null;

  DateTime pd = DateTime.now();
  final bd = scan['bill_date']?.toString();
  if (bd != null && bd.length >= 10) {
    pd = DateTime.tryParse(bd.substring(0, 10)) ?? pd;
  }

  final created = await scanPurchaseUpdateAndConfirm(
    ref: ref,
    scanToken: token,
    scanPayload: scan,
    purchaseDate: pd,
    invoiceNumber: scan['invoice_number']?.toString(),
    forceDuplicate: false,
  );

  return created['id']?.toString().trim();
}

/// Shows confirm dialog then creates purchase; returns true if navigated away.
Future<bool> confirmScanDraftPurchase({
  required WidgetRef ref,
  required BuildContext context,
  required Map<String, dynamic> scan,
  required bool scanIssueBlocker,
}) async {
  if (!scanDraftReadyForCreate(scan, scanIssueBlocker: scanIssueBlocker)) {
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Create purchase from this bill?'),
      content: const Text(
        'Nothing is saved to purchases until you confirm. After creation, totals '
        'and inventory update. Double-check supplier, items, and rates match the bill.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Create purchase'),
        ),
      ],
    ),
  );
  if (!context.mounted || ok != true) return false;

  try {
    HapticFeedback.mediumImpact();
    final id = await runScanDraftPurchaseCreate(ref: ref, context: context, scan: scan);
    if (!context.mounted) return false;
    if (id != null && id.isNotEmpty) {
      HapticFeedback.selectionClick();
      context.go('/purchase/detail/$id');
      return true;
    }
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create purchase.')),
      );
    }
  }
  return false;
}
