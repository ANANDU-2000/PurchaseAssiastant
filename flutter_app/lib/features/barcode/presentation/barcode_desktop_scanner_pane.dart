import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../barcode_scan_controller.dart';
import '../services/barcode_camera_controller.dart';
import 'barcode_mobile_scanner_view.dart';

/// Desktop left pane: camera + recent + manual search.
class BarcodeDesktopScannerPane extends StatelessWidget {
  const BarcodeDesktopScannerPane({
    super.key,
    required this.camera,
    required this.scan,
    required this.cameraHeight,
    required this.onLookup,
    required this.onUploadPhoto,
    required this.pendingSync,
    this.onSyncNow,
  });

  final BarcodeCameraController camera;
  final BarcodeScanController scan;
  final double cameraHeight;
  final Future<void> Function(String code) onLookup;
  final VoidCallback onUploadPhoto;
  final int pendingSync;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: HexaDsSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BarcodeMobileScannerView(
            camera: camera,
            scan: scan,
            height: cameraHeight,
            onUploadPhoto: onUploadPhoto,
            pendingSync: pendingSync,
            onSyncNow: onSyncNow,
          ),
          if (scan.recent.isNotEmpty) _RecentRow(scan: scan, onLookup: onLookup),
          _ManualSearchBlock(scan: scan, onLookup: onLookup, theme: theme),
        ],
      ),
    );
  }
}

/// Mobile body below AppBar: camera + recent + expandable manual search.
class BarcodeMobileScannerBody extends StatelessWidget {
  const BarcodeMobileScannerBody({
    super.key,
    required this.camera,
    required this.scan,
    required this.cameraHeight,
    required this.onLookup,
    required this.onUploadPhoto,
    required this.pendingSync,
    this.onSyncNow,
  });

  final BarcodeCameraController camera;
  final BarcodeScanController scan;
  final double cameraHeight;
  final Future<void> Function(String code) onLookup;
  final VoidCallback onUploadPhoto;
  final int pendingSync;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarcodeMobileScannerView(
          camera: camera,
          scan: scan,
          height: cameraHeight,
          onUploadPhoto: onUploadPhoto,
          pendingSync: pendingSync,
          onSyncNow: onSyncNow,
        ),
        if (scan.recent.isNotEmpty) _RecentRow(scan: scan, onLookup: onLookup),
        Expanded(
          child: _ManualSearchBlock(
            scan: scan,
            onLookup: onLookup,
            theme: theme,
            expanded: true,
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.scan, required this.onLookup});
  final BarcodeScanController scan;
  final Future<void> Function(String code) onLookup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Recent scans',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: scan.recent.length.clamp(0, 8),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final r = scan.recent[i];
              final label = r.name.length > 15
                  ? '${r.name.substring(0, 15)}…'
                  : r.name;
              return ActionChip(
                label: Text(label, maxLines: 1),
                onPressed: scan.lookingUp
                    ? null
                    : () {
                        if (r.id.isNotEmpty) {
                          context.push('/catalog/item/${r.id}?source=scan');
                        } else {
                          scan.manualCtrl.text = r.code;
                          onLookup(r.code);
                        }
                      },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ManualSearchBlock extends StatelessWidget {
  const _ManualSearchBlock({
    required this.scan,
    required this.onLookup,
    required this.theme,
    this.expanded = false,
  });

  final BarcodeScanController scan;
  final Future<void> Function(String code) onLookup;
  final ThemeData theme;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final matches = scan.manualMatches;
    final list = matches.isEmpty
        ? null
        : ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final item = matches[i];
              final id = item['id']?.toString();
              final name = item['name']?.toString() ?? 'Item';
              final code = item['item_code']?.toString();
              final barcode = item['barcode']?.toString();
              return ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  [
                    if (code != null && code.isNotEmpty) code,
                    if (barcode != null) barcode,
                  ].whereType<String>().join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: id == null || id.isEmpty
                    ? null
                    : () => context.push('/catalog/item/$id?source=scan'),
              );
            },
          );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: scan.manualFocus,
                  controller: scan.manualCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Search item / barcode / item code',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) => onLookup(v),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: scan.lookingUp
                    ? null
                    : () => onLookup(scan.manualCtrl.text),
                child: const Text('Search'),
              ),
            ],
          ),
          if (scan.manualSearching) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (list != null) ...[
            const SizedBox(height: 10),
            if (expanded)
              Expanded(child: list)
            else
              SizedBox(height: 280, child: list),
          ],
        ],
      ),
    );
    return expanded ? body : body;
  }
}
