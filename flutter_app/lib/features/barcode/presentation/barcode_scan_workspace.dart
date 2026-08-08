import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/design_system/hexa_desktop_layout.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/stock_offline_queue_provider.dart';
import '../barcode_scan_controller.dart';
import '../services/barcode_camera_controller.dart';
import 'barcode_desktop_result_pane.dart';
import 'barcode_desktop_scanner_pane.dart';
import 'barcode_scan_app_bar.dart';
import 'barcode_scan_page_actions.dart';

/// Scaffold + mobile/desktop body for the barcode scan page.
class BarcodeScanWorkspace extends ConsumerWidget {
  const BarcodeScanWorkspace({
    super.key,
    required this.scan,
    required this.camera,
    required this.resultActionFocus,
    required this.actions,
    required this.onLookup,
    required this.onUploadPhoto,
    required this.onDismissResult,
  });

  final BarcodeScanController scan;
  final BarcodeCameraController camera;
  final FocusNode resultActionFocus;
  final BarcodeScanPageActions actions;
  final Future<void> Function(String code) onLookup;
  final VoidCallback onUploadPhoto;
  final VoidCallback onDismissResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canEdit = session != null && !sessionIsStockReadOnly(session);
    final canPurchase = session != null &&
        (sessionCanPurchaseCreate(session) || sessionCanPurchaseEdit(session));
    final canPrint = session != null && sessionCanBarcodePrint(session);
    final pendingSync = ref.watch(stockOfflinePendingCountProvider);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final desktop = size.width >= kDesktopMin;
    final cameraH = desktop
        ? math.min(360.0, size.height * 0.45)
        : (size.height * (landscape ? 0.40 : 0.48))
            .clamp(landscape ? 180.0 : 260.0, landscape ? 280.0 : 420.0)
            .toDouble();

    return ListenableBuilder(
      listenable: Listenable.merge([scan, camera]),
      builder: (context, _) {
        KeyEventResult onKey(FocusNode node, KeyEvent event) {
          if (!desktop || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (scan.showResultPane) {
              onDismissResult();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if ((event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
              scan.manualFocus.hasFocus) {
            unawaited(onLookup(scan.manualCtrl.text));
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.tab &&
              scan.showResultPane &&
              !resultActionFocus.hasFocus &&
              !scan.manualFocus.hasFocus) {
            resultActionFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        return Focus(
          autofocus: desktop,
          onKeyEvent: onKey,
          child: Scaffold(
            appBar: barcodeScanAppBar(
              context: context,
              scan: scan,
              camera: camera,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/staff/home');
                }
              },
              onAudit: actions.startAuditSession,
            ),
            body: desktop
                ? DesktopMasterDetailScaffold(
                    listFlex: 46,
                    detailFlex: 54,
                    capDetailPane: false,
                    list: BarcodeDesktopScannerPane(
                      camera: camera,
                      scan: scan,
                      cameraHeight: cameraH,
                      onLookup: onLookup,
                      onUploadPhoto: onUploadPhoto,
                      pendingSync: pendingSync,
                      onSyncNow: () => ref
                          .read(stockOfflineSyncProvider.notifier)
                          .syncNow(),
                    ),
                    detail: BarcodeDesktopResultPane(
                      scan: scan,
                      focusNode: resultActionFocus,
                      canStockEdit: canEdit,
                      canAddToPurchase: canPurchase,
                      canPrint: canPrint,
                      onAddToPurchase: actions.addPurchase,
                      onEdit: actions.edit,
                      onStock: actions.stock,
                      onHistory: actions.history,
                      onPrint: actions.printLabel,
                      onCreateItem: canEdit ? actions.createItem : null,
                      onAssign: canEdit ? actions.assign : null,
                      onRetry: actions.retry,
                      onDismiss: onDismissResult,
                    ),
                  )
                : BarcodeMobileScannerBody(
                    camera: camera,
                    scan: scan,
                    cameraHeight: cameraH,
                    onLookup: onLookup,
                    onUploadPhoto: onUploadPhoto,
                    pendingSync: pendingSync,
                    onSyncNow: () =>
                        ref.read(stockOfflineSyncProvider.notifier).syncNow(),
                  ),
          ),
        );
      },
    );
  }
}
