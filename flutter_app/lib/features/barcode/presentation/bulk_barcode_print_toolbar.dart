import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/widgets/operational_async_button.dart';
class BulkBarcodePrintToolbar extends StatelessWidget {
  const BulkBarcodePrintToolbar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.denseA4,
    required this.useQr,
    required this.copies,
    required this.progress,
    required this.statusText,
    required this.onDenseA4Changed,
    required this.onQrChanged,
    required this.onCopiesChanged,
    required this.onPreview,
    required this.onPdf,
    required this.onPrint,
  });

  final int selectedCount;
  final bool busy;
  final bool denseA4;
  final bool useQr;
  final int copies;
  final double? progress;
  final String? statusText;
  final ValueChanged<bool> onDenseA4Changed;
  final ValueChanged<bool> onQrChanged;
  final ValueChanged<int> onCopiesChanged;
  final Future<void> Function() onPreview;
  final Future<void> Function() onPdf;
  final Future<void> Function() onPrint;

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
            8,
            HexaOp.pageGutter,
            8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null || statusText != null) ...[
                LinearProgressIndicator(minHeight: 3, value: progress),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(statusText!, style: const TextStyle(fontSize: 11)),
                  ),
                const SizedBox(height: 8),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('A4')),
                        ButtonSegment(value: false, label: Text('Thermal')),
                      ],
                      selected: {denseA4},
                      onSelectionChanged: busy
                          ? null
                          : (s) => onDenseA4Changed(s.first),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('QR')),
                        ButtonSegment(value: false, label: Text('Code128')),
                      ],
                      selected: {useQr},
                      onSelectionChanged: busy
                          ? null
                          : (s) => onQrChanged(s.first),
                    ),
                    const SizedBox(width: 8),
                    _CopiesStepper(
                      value: copies,
                      enabled: !busy,
                      onChanged: onCopiesChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OperationalAsyncButton(
                      label: 'Preview',
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPreview : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OperationalAsyncButton(
                      label: 'PDF',
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPdf : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OperationalAsyncButton(
                      label: 'Print',
                      filled: true,
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPrint : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopiesStepper extends StatelessWidget {
  const _CopiesStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: !enabled || value <= 1
              ? null
              : () => onChanged(value - 1),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: !enabled || value >= 5
              ? null
              : () => onChanged(value + 1),
        ),
      ],
    );
  }
}
