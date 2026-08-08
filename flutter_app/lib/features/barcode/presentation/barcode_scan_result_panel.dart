import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import 'widgets/scan_item_stock_summary_card.dart';

/// Compact scan result — used in mobile Hexa sheet and desktop right pane.
class BarcodeScanResultPanel extends StatelessWidget {
  const BarcodeScanResultPanel({
    super.key,
    required this.code,
    this.item,
    this.notFound = false,
    this.errorMessage,
    this.lookingUp = false,
    this.canStockEdit = false,
    this.canAddToPurchase = false,
    this.canPrint = false,
    this.onAddToPurchase,
    this.onEdit,
    this.onStock,
    this.onHistory,
    this.onPrint,
    this.onCreateItem,
    this.onAssign,
    this.onRetry,
    this.onDismiss,
    this.dense = false,
  });

  final String code;
  final Map<String, dynamic>? item;
  final bool notFound;
  final String? errorMessage;
  final bool lookingUp;
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
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = dense ? HexaDsSpace.s1 : HexaDsLayout.tightGap;

    if (lookingUp) {
      return Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Looking up…',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              code,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HexaColors.textBody,
              ),
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      );
    }

    if (errorMessage != null && errorMessage!.trim().isNotEmpty) {
      return Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lookup failed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: gap),
            Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HexaColors.textBody,
              ),
            ),
            SizedBox(height: gap),
            if (onRetry != null)
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            if (onDismiss != null)
              TextButton(
                onPressed: onDismiss,
                child: const Text('Continue scanning'),
              ),
          ],
        ),
      );
    }

    if (notFound || item == null) {
      return Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Barcode not linked to an item.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scanned: $code',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HexaColors.textBody,
              ),
            ),
            if (!canStockEdit) ...[
              SizedBox(height: gap),
              Text(
                "Your account doesn't have permission for this action.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            SizedBox(height: gap),
            if (canStockEdit) ...[
              if (onCreateItem != null)
                FilledButton.icon(
                  onPressed: onCreateItem,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Create new item'),
                ),
              if (onAssign != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.link),
                  label: const Text('Assign to existing item'),
                ),
              ],
            ],
            if (onDismiss != null)
              TextButton(
                onPressed: onDismiss,
                child: const Text('Continue scanning'),
              ),
          ],
        ),
      );
    }

    final unit = item!['unit']?.toString() ??
        item!['stock_unit']?.toString() ??
        item!['default_unit']?.toString() ??
        '';
    final barcode = item!['barcode']?.toString() ?? code;

    return Padding(
      padding: EdgeInsets.all(dense ? 12 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanItemStockSummaryCard(item: item!, showTitle: true),
          if (unit.isNotEmpty || barcode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (unit.isNotEmpty) 'Unit: $unit',
                'Barcode: $barcode',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: HexaColors.textBody,
              ),
            ),
          ],
          SizedBox(height: gap),
          if (canAddToPurchase && onAddToPurchase != null)
            FilledButton.icon(
              onPressed: onAddToPurchase,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Add to Purchase'),
            ),
          if (canStockEdit) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (onEdit != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onEdit,
                      child: const Text('Edit'),
                    ),
                  ),
                if (onEdit != null && onStock != null)
                  const SizedBox(width: 8),
                if (onStock != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onStock,
                      child: const Text('Stock'),
                    ),
                  ),
              ],
            ),
          ],
          if (onHistory != null || (canPrint && onPrint != null)) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (onHistory != null)
                  TextButton(
                    onPressed: onHistory,
                    child: const Text('History'),
                  ),
                if (canPrint && onPrint != null)
                  TextButton(
                    onPressed: onPrint,
                    child: const Text('Print label'),
                  ),
              ],
            ),
          ],
          if (onDismiss != null)
            TextButton(
              onPressed: onDismiss,
              child: const Text('Continue scanning'),
            ),
        ],
      ),
    );
  }
}
