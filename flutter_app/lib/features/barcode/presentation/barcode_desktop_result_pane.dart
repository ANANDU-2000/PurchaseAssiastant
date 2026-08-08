import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../barcode_scan_controller.dart';
import 'barcode_mobile_result_sheet.dart';

/// Persistent desktop right pane — updates in place (no per-scan dialog).
class BarcodeDesktopResultPane extends StatelessWidget {
  const BarcodeDesktopResultPane({
    super.key,
    required this.scan,
    required this.focusNode,
    required this.canStockEdit,
    required this.canAddToPurchase,
    required this.canPrint,
    this.onAddToPurchase,
    this.onEdit,
    this.onStock,
    this.onHistory,
    this.onPrint,
    this.onCreateItem,
    this.onAssign,
    this.onRetry,
    this.onDismiss,
  });

  final BarcodeScanController scan;
  final FocusNode focusNode;
  final bool canStockEdit;
  final bool canAddToPurchase;
  final bool canPrint;
  final VoidCallback? onAddToPurchase;
  final VoidCallback? onEdit;
  final VoidCallback? onStock;
  final VoidCallback? onHistory;
  final VoidCallback? onPrint;
  final VoidCallback? onCreateItem;
  final VoidCallback? onAssign;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final show = scan.showResultPane;

    return Focus(
      focusNode: focusNode,
      child: ColoredBox(
        color: HexaColors.panelWarm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HexaDsSpace.s2,
                HexaDsSpace.s2,
                HexaDsSpace.s2,
                HexaDsSpace.s1,
              ),
              child: Text(
                show ? 'Scan result' : 'Ready to scan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: show
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: barcodeResultPanelFromScan(
                        scan: scan,
                        canStockEdit: canStockEdit,
                        canAddToPurchase: canAddToPurchase,
                        canPrint: canPrint,
                        dense: false,
                        onAddToPurchase: onAddToPurchase,
                        onEdit: onEdit,
                        onStock: onStock,
                        onHistory: onHistory,
                        onPrint: onPrint,
                        onCreateItem: onCreateItem,
                        onAssign: onAssign,
                        onRetry: onRetry,
                        onDismiss: onDismiss,
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(HexaDsSpace.s3),
                        child: Text(
                          'Scan or search an item.\nResult stays here for the next action.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: HexaColors.textBody,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
