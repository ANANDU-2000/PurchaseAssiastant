import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/widgets/operational_async_button.dart';
import '../services/bulk_pdf_chunks.dart';

class BulkBarcodePrintToolbar extends StatelessWidget {
  const BulkBarcodePrintToolbar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.denseA4,
    required this.useQr,
    required this.copies,
    required this.labelsPerPdfFile,
    required this.showStockOnLabel,
    required this.showLastPurchaseOnLabel,
    required this.showRateOnLabel,
    required this.progress,
    required this.statusText,
    required this.onDenseA4Changed,
    required this.onQrChanged,
    required this.onCopiesChanged,
    required this.onLabelsPerPdfFileChanged,
    required this.onShowStockOnLabelChanged,
    required this.onShowLastPurchaseOnLabelChanged,
    required this.onShowRateOnLabelChanged,
    required this.onPreview,
    required this.onPdf,
    required this.onPrint,
    this.pdfButtonLabel = 'PDF',
  });

  final int selectedCount;
  final bool busy;
  final bool denseA4;
  final bool useQr;
  final int copies;
  final BulkLabelsPerPdfFile labelsPerPdfFile;
  final bool showStockOnLabel;
  final bool showLastPurchaseOnLabel;
  final bool showRateOnLabel;
  final double? progress;
  final String? statusText;
  final ValueChanged<bool> onDenseA4Changed;
  final ValueChanged<bool> onQrChanged;
  final ValueChanged<int> onCopiesChanged;
  final ValueChanged<BulkLabelsPerPdfFile> onLabelsPerPdfFileChanged;
  final ValueChanged<bool> onShowStockOnLabelChanged;
  final ValueChanged<bool> onShowLastPurchaseOnLabelChanged;
  final ValueChanged<bool> onShowRateOnLabelChanged;
  final Future<void> Function() onPreview;
  final Future<void> Function() onPdf;
  final Future<void> Function() onPrint;
  final String pdfButtonLabel;

  Future<void> _openSettings(BuildContext context) async {
    await showHexaBottomSheet<void>(
      context: context,
      compact: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Label settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('A4 sheet layout'),
                subtitle: const Text('Off = thermal roll'),
                value: denseA4,
                onChanged: busy ? null : onDenseA4Changed,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('QR codes'),
                subtitle: const Text('Off = Code128 barcode'),
                value: useQr,
                onChanged: busy ? null : onQrChanged,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Copies per item'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: busy || copies <= 1
                          ? null
                          : () => onCopiesChanged(copies - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('×$copies'),
                    IconButton(
                      onPressed: busy || copies >= 5
                          ? null
                          : () => onCopiesChanged(copies + 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              if (denseA4)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Labels per page'),
                  subtitle: Text('${labelsPerPdfFile.count} labels per A4 page'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () {
                          final next = switch (labelsPerPdfFile) {
                            BulkLabelsPerPdfFile.n30 =>
                              BulkLabelsPerPdfFile.n50,
                            BulkLabelsPerPdfFile.n50 =>
                              BulkLabelsPerPdfFile.n60,
                            _ => BulkLabelsPerPdfFile.n30,
                          };
                          onLabelsPerPdfFileChanged(next);
                        },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Stock on label'),
                subtitle: const Text('Current qty and unit'),
                value: showStockOnLabel,
                onChanged: busy ? null : onShowStockOnLabelChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Last purchase'),
                subtitle: const Text('Date and qty (no empty filler)'),
                value: showLastPurchaseOnLabel,
                onChanged: busy ? null : onShowLastPurchaseOnLabelChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rate on label'),
                subtitle: const Text('Uses Rs. — safe for PDF print'),
                value: showRateOnLabel,
                onChanged: busy ? null : onShowRateOnLabelChanged,
              ),
              Text(
                'Downloads one PDF up to $kMaxLabelsSinglePdf labels.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !busy;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HexaOp.pageGutter,
            6,
            HexaOp.pageGutter,
            6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null || statusText != null) ...[
                LinearProgressIndicator(minHeight: 2, value: progress),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      statusText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
              Row(
                children: [
                  Expanded(
                    child: OperationalAsyncButton(
                      label: selectedCount > 0
                          ? 'Print selected ($selectedCount)'
                          : 'Print selected',
                      icon: Icons.print_outlined,
                      filled: true,
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPrint : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Label settings',
                    onPressed: busy ? null : () => _openSettings(context),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: enabled ? () => onPdf() : null,
                  child: Text(pdfButtonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
