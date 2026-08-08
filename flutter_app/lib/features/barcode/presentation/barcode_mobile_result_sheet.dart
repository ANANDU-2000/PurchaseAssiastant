import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../barcode_scan_controller.dart';
import '../barcode_scan_session.dart';
import 'barcode_scan_result_panel.dart';

/// Shows the scan result in a compact Hexa bottom sheet (phone / tablet).
Future<void> showBarcodeMobileResultSheet({
  required BuildContext context,
  required BarcodeScanController scan,
  required BarcodeScanResultPanel panel,
}) async {
  scan.setResultUiOpen(true);
  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: EdgeInsets.zero,
    child: panel,
  );
  scan.setResultUiOpen(false);
  scan.readyForNext();
}

/// Builds a [BarcodeScanResultPanel] from the controller session snapshot.
BarcodeScanResultPanel barcodeResultPanelFromScan({
  required BarcodeScanController scan,
  required bool canStockEdit,
  required bool canAddToPurchase,
  required bool canPrint,
  required bool dense,
  VoidCallback? onAddToPurchase,
  VoidCallback? onEdit,
  VoidCallback? onStock,
  VoidCallback? onHistory,
  VoidCallback? onPrint,
  VoidCallback? onCreateItem,
  VoidCallback? onAssign,
  VoidCallback? onRetry,
  VoidCallback? onDismiss,
}) {
  final snap = scan.session.current;
  final code = snap?.code ?? '';
  final lookingUp = snap?.phase == BarcodeScanPhase.lookingUp;
  final err = snap?.phase == BarcodeScanPhase.error
      ? (snap?.errorMessage ?? "Couldn't reach server. Retry.")
      : null;
  final notFound = snap?.outcome == BarcodeScanOutcome.notFound;
  final item = snap?.item;

  return BarcodeScanResultPanel(
    code: code,
    item: item,
    notFound: notFound && item == null,
    errorMessage: err,
    lookingUp: lookingUp,
    canStockEdit: canStockEdit,
    canAddToPurchase: canAddToPurchase,
    canPrint: canPrint,
    dense: dense,
    onAddToPurchase: onAddToPurchase,
    onEdit: onEdit,
    onStock: onStock,
    onHistory: onHistory,
    onPrint: onPrint,
    onCreateItem: onCreateItem,
    onAssign: onAssign,
    onRetry: onRetry,
    onDismiss: onDismiss,
  );
}

bool barcodeDesktopSplit(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopMin;
