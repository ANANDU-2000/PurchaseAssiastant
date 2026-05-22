import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/stock_providers.dart';
class BulkBarcodePrintPreviewPanel extends ConsumerWidget {
  const BulkBarcodePrintPreviewPanel({
    super.key,
    required this.denseA4,
    required this.useQr,
    required this.copies,
    required this.selectedCount,
    required this.onPreviewAll,
  });

  final bool denseA4;
  final bool useQr;
  final int copies;
  final int selectedCount;
  final VoidCallback onPreviewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewId = ref.watch(bulkPreviewItemIdProvider);
    final data = ref.watch(bulkStockListProvider).valueOrNull;
    Map<String, dynamic>? item;
    if (previewId != null && data != null) {
      for (final e in data['items'] as List? ?? []) {
        if (e is Map && e['id']?.toString() == previewId) {
          item = Map<String, dynamic>.from(e);
          break;
        }
      }
    }

    final code = item?['barcode']?.toString().trim().isNotEmpty == true
        ? item!['barcode'].toString()
        : item?['item_code']?.toString() ?? '—';
    final name = item?['name']?.toString() ?? 'Select an item';

    return Material(
      color: const Color(0xFFF5F3EE),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.pageGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Label preview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (previewId != null && code != '—') ...[
                      if (useQr)
                        QrImageView(
                          data: code,
                          size: 120,
                          backgroundColor: Colors.white,
                        )
                      else
                        SvgPicture.string(
                          Barcode.code128().toSvg(
                            code,
                            width: 200,
                            height: 56,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        code,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ] else
                      Text(
                        'Tap preview on a row',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              denseA4 ? 'A4 dense grid' : 'Thermal roll',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              useQr ? 'QR codes' : 'Code 128',
              style: const TextStyle(fontSize: 13),
            ),
            Text('Copies per item: $copies', style: const TextStyle(fontSize: 13)),
            Text(
              '$selectedCount selected',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: selectedCount > 0 ? onPreviewAll : null,
              child: const Text('Preview all PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
