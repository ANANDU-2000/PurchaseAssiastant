import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../shared/widgets/search_picker_sheet.dart';
import '../../stock/presentation/stock_sheet_launch.dart';
import '../../stock/presentation/stock_undo_snackbar.dart';
import '../barcode_lookup_cache.dart';
import '../barcode_scan_controller.dart';
import '../barcode_scan_session.dart';
import '../services/barcode_camera_controller.dart';

/// Navigation / permission-gated CTAs for [BarcodeScanPage].
class BarcodeScanPageActions {
  BarcodeScanPageActions({
    required this.context,
    required this.ref,
    required this.scan,
    required this.camera,
    required this.onReadyForNext,
    required this.onRetryLookup,
  });

  final BuildContext context;
  final WidgetRef ref;
  final BarcodeScanController scan;
  final BarcodeCameraController camera;
  final VoidCallback onReadyForNext;
  final Future<void> Function(String code) onRetryLookup;

  VoidCallback? get addPurchase {
    final item = scan.session.current?.item;
    final session = ref.read(sessionProvider);
    final ok = session != null &&
        (sessionCanPurchaseCreate(session) || sessionCanPurchaseEdit(session));
    if (item == null || !ok) return null;
    return () {
      final id = item['id']?.toString() ?? '';
      onReadyForNext();
      if (id.isNotEmpty) {
        context.push(
          '/purchase/new?catalogItemId=${Uri.encodeComponent(id)}',
        );
      }
    };
  }

  VoidCallback? get edit {
    final item = scan.session.current?.item;
    final session = ref.read(sessionProvider);
    if (item == null || session == null || sessionIsStockReadOnly(session)) {
      return null;
    }
    return () async {
      final id = item['id']?.toString() ?? '';
      final code = scan.session.current?.code ?? '';
      if (id.isEmpty) return;
      // Keep code; leave result phase until we return.
      await context.push('/catalog/item/$id/edit');
      if (!context.mounted) return;
      final bid = ref.read(sessionProvider)?.primaryBusiness.id;
      if (bid != null && code.isNotEmpty) {
        BarcodeLookupCache.invalidate(bid, code);
        // Server truth after save or concurrent edit elsewhere.
        await onRetryLookup(code);
        return;
      }
      onReadyForNext();
      await camera.ensureRunning();
    };
  }

  VoidCallback? get stock {
    final item = scan.session.current?.item;
    final session = ref.read(sessionProvider);
    if (item == null || session == null || sessionIsStockReadOnly(session)) {
      return null;
    }
    return () async {
      final id = item['id']?.toString() ?? '';
      final name =
          item['name']?.toString() ?? scan.session.current?.code ?? '';
      onReadyForNext();
      if (id.isEmpty) return;
      scan.session.markAction();
      await openQuickStockWithFreshItem(
        context: context,
        ref: ref,
        itemId: id,
        itemName: name,
        fallbackRow: Map<String, dynamic>.from(item),
        skipFreshFetch: true,
      );
      await camera.ensureRunning();
    };
  }

  VoidCallback? get history {
    final item = scan.session.current?.item;
    if (item == null) return null;
    return () {
      final id = item['id']?.toString() ?? '';
      onReadyForNext();
      if (id.isNotEmpty) {
        context.push('/catalog/item/$id/purchase-history');
      }
    };
  }

  VoidCallback? get printLabel {
    final item = scan.session.current?.item;
    final session = ref.read(sessionProvider);
    if (item == null ||
        session == null ||
        !sessionCanBarcodePrint(session)) {
      return null;
    }
    return () {
      final id = item['id']?.toString() ?? '';
      onReadyForNext();
      if (id.isNotEmpty) context.push('/barcode/print/$id');
    };
  }

  void createItem() {
    final code = scan.session.current?.code ?? '';
    onReadyForNext();
    context.push(
      '/catalog/quick-add-from-scan?barcode=${Uri.encodeComponent(code)}',
    );
  }

  void assign() {
    final code = scan.session.current?.code ?? '';
    onReadyForNext();
    unawaited(assignBarcode(code));
  }

  VoidCallback? get retry {
    final snap = scan.session.current;
    if (snap?.phase != BarcodeScanPhase.error) return null;
    final code = snap?.code ?? '';
    return () {
      onReadyForNext();
      unawaited(onRetryLookup(code));
    };
  }

  Future<void> assignBarcode(String code) async {
    final session = ref.read(sessionProvider);
    if (session == null || !context.mounted) return;
    final catalog = ref.read(catalogItemsListProvider).valueOrNull ?? [];
    if (catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load catalog first, then try again')),
      );
      scan.readyForNext();
      return;
    }
    final picked = await showSearchPickerSheet<String>(
      context: context,
      title: 'Assign barcode $code',
      rows: [
        for (final row in catalog)
          SearchPickerRow<String>(
            value: row['id']?.toString() ?? '',
            title: row['name']?.toString() ?? '—',
            subtitle: row['item_code']?.toString(),
          ),
      ],
    );
    if (picked == null || picked.isEmpty || !context.mounted) {
      scan.readyForNext();
      return;
    }
    try {
      await scan.assignBarcode(
        businessId: session.primaryBusiness.id,
        itemId: picked,
        barcode: code,
      );
      ref.invalidate(catalogItemsListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode $code assigned')),
      );
      context.push('/catalog/item/$picked?source=scan');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barcodeMessageForUser(e, ctx: BarcodeOperationContext.scanner),
          ),
        ),
      );
      scan.readyForNext();
    }
  }

  Future<void> startAuditSession() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final existing = await ref.read(hexaApiProvider).getActiveStockAudit(
            businessId: session.primaryBusiness.id,
          );
      if (existing != null && existing['id'] != null) {
        if (!context.mounted) return;
        context.push('/barcode/audit-session');
        return;
      }
      await ref.read(hexaApiProvider).createStockAudit(
            businessId: session.primaryBusiness.id,
            notes: 'Mobile scan session',
          );
      ref.invalidate(activeStockAuditProvider);
      if (!context.mounted) return;
      context.push('/barcode/audit-session');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barcodeMessageForUser(e, ctx: BarcodeOperationContext.scanner),
          ),
        ),
      );
    }
  }

  /// Handles return=? deep-links after a successful found lookup.
  /// Returns true when the caller should stop (page already navigated/popped).
  Future<bool> handleReturnQuery({
    required Map<String, dynamic> item,
    required String id,
    required String name,
  }) async {
    final returnTo = GoRouterState.of(context).uri.queryParameters['return'];
    if (returnTo == 'search') {
      context.pop(Map<String, dynamic>.from(item));
      return true;
    }
    if (returnTo != 'stock') return false;
    final saved = await openQuickStockWithFreshItem(
      context: context,
      ref: ref,
      itemId: id,
      itemName: name,
      fallbackRow: Map<String, dynamic>.from(item),
      skipFreshFetch: true,
    );
    if (saved && context.mounted) {
      ref.invalidate(stockListProvider);
      ref.invalidate(stockAuditPeriodProvider);
      ref.invalidate(catalogItemDetailProvider(id));
      ref.invalidate(stockItemIntelligenceProvider(id));
      await scan.loadRecent();
      showStockUndoSnackBar(
        context: context,
        ref: ref,
        itemId: id,
        itemName: name,
      );
    }
    if (context.mounted) context.pop();
    return true;
  }
}
