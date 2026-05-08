import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';

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
  final session = ref.read(sessionProvider);
  final token = scanDraftToken(scan);
  if (session == null || token == null) return null;

  await ref.read(hexaApiProvider).scanPurchaseBillV2Update(
        businessId: session.primaryBusiness.id,
        body: {'scan_token': token, 'scan': scan},
      );

  final created = await ref.read(hexaApiProvider).scanPurchaseBillV2Confirm(
        businessId: session.primaryBusiness.id,
        body: {
          'scan_token': token,
          'purchase_date': DateTime.now().toIso8601String().substring(0, 10),
          'status': 'confirmed',
          'force_duplicate': false,
        },
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
