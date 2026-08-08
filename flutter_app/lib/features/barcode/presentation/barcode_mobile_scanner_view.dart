import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/hexa_colors.dart';
import '../barcode_scan_controller.dart';
import '../services/barcode_camera_controller.dart';
import 'barcode_scan_web_stub.dart'
    if (dart.library.html) 'barcode_scan_web.dart';
import 'barcode_scanner_preview_chrome.dart';

/// Mobile / left-pane camera preview with permission and fallback chrome.
class BarcodeMobileScannerView extends StatelessWidget {
  const BarcodeMobileScannerView({
    super.key,
    required this.camera,
    required this.scan,
    required this.height,
    required this.onUploadPhoto,
    required this.pendingSync,
    this.onSyncNow,
    this.showHint = true,
  });

  final BarcodeCameraController camera;
  final BarcodeScanController scan;
  final double height;
  final VoidCallback onUploadPhoto;
  final int pendingSync;
  final VoidCallback? onSyncNow;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safariUpload = kIsWeb && preferUploadBarcodeOnWeb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (safariUpload)
          MaterialBanner(
            content: const Text(
              'Live camera scan needs iOS 17 or newer in Safari. '
              'Upload a barcode photo or use manual search below.',
            ),
            actions: [
              TextButton(
                onPressed: scan.lookingUp ? null : onUploadPhoto,
                child: const Text('Upload photo'),
              ),
            ],
          ),
        if (pendingSync > 0)
          MaterialBanner(
            content: Text('Pending sync: $pendingSync stock change(s)'),
            actions: [
              TextButton(
                onPressed: onSyncNow,
                child: const Text('Sync now'),
              ),
            ],
          ),
        if (camera.webCameraAwaitingGesture)
          _GestureGate(
            busy: scan.lookingUp,
            onStart: () => unawaited(camera.startFromUserGesture()),
          )
        else if (camera.cameraDenied)
          _DeniedPanel(
            camera: camera,
            lookingUp: scan.lookingUp,
            onUploadPhoto: onUploadPhoto,
            onFocusManual: () => scan.manualFocus.requestFocus(),
          )
        else
          BarcodeScannerPreviewChrome(
            height: height,
            decodePulse: scan.decodePulse,
            lookingUp: scan.lookingUp,
            lookupLabel: scan.lookupLabel,
            child: ColoredBox(
              color: HexaColors.slate100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _previewBody(theme),
              ),
            ),
          ),
        if (showHint)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Scan item barcode or enter code manually.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (camera.safariUploadNudgeShown && !camera.hadDetectThisVisit)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.orange,
                ),
                title: const Text(
                  'Camera scanning not supported on this browser',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Upload a photo of the barcode, or type the item name below',
                ),
                trailing: ElevatedButton(
                  onPressed: scan.lookingUp ? null : onUploadPhoto,
                  child: const Text('Upload'),
                ),
              ),
            ),
          ),
        if (camera.unreadableNudgeShown &&
            !camera.hadDetectThisVisit &&
            !camera.cameraDenied &&
            !camera.webCameraAwaitingGesture)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 1,
              borderRadius: BorderRadius.circular(12),
              color: HexaColors.slate50,
              child: ListTile(
                leading: Icon(
                  Icons.qr_code_scanner,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  camera.unreadableNudgeMessage,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: TextButton(
                  onPressed: () => scan.manualFocus.requestFocus(),
                  child: const Text('Manual'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _previewBody(ThemeData theme) {
    if (camera.useWebDetectorPreview && camera.webLiveScanner != null) {
      return camera.webLiveScanner!.buildPreview();
    }
    if (camera.mobile != null) {
      return MobileScanner(
        controller: camera.mobile!,
        onDetect: (cap) {
          if (!scan.acceptsCameraDetect) return;
          camera.handleNativeDetect(cap);
        },
      );
    }
    return const ColoredBox(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          SizedBox(height: 12),
          Text(
            'Starting camera…',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GestureGate extends StatelessWidget {
  const _GestureGate({required this.busy, required this.onStart});
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.touch_app_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Tap to start camera',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Browsers require a tap before opening the camera.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : onStart,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Start camera'),
          ),
        ],
      ),
    );
  }
}

class _DeniedPanel extends StatelessWidget {
  const _DeniedPanel({
    required this.camera,
    required this.lookingUp,
    required this.onUploadPhoto,
    required this.onFocusManual,
  });

  final BarcodeCameraController camera;
  final bool lookingUp;
  final VoidCallback onUploadPhoto;
  final VoidCallback onFocusManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.videocam_off_outlined,
              size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Camera access needed',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            camera.cameraDeniedMessage ??
                'Allow camera access to scan barcodes.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (!kIsWeb && camera.cameraPermanent) ...[
            FilledButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: lookingUp
                ? null
                : () => unawaited(camera.retryAfterDenial()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Without camera',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Upload barcode photo'),
            onTap: lookingUp ? null : onUploadPhoto,
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: const Text('Search by name or code'),
            onTap: onFocusManual,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
