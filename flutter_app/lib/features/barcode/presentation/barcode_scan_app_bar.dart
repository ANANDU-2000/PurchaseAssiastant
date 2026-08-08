import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../barcode_scan_controller.dart';
import '../services/barcode_camera_controller.dart';

PreferredSizeWidget barcodeScanAppBar({
  required BuildContext context,
  required BarcodeScanController scan,
  required BarcodeCameraController camera,
  required VoidCallback onBack,
  required Future<void> Function() onAudit,
}) {
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: onBack,
    ),
    title: const Text('Scan barcode'),
    actions: [
      IconButton(
        tooltip: scan.soundEnabled ? 'Sound on' : 'Sound off',
        icon: Icon(
          scan.soundEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
        ),
        onPressed: () => unawaited(scan.setSoundEnabled(!scan.soundEnabled)),
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) {
          switch (v) {
            case 'history':
              context.push('/barcode/scan-history');
            case 'manual':
              scan.manualFocus.requestFocus();
            case 'torch':
              unawaited(camera.toggleTorch());
            case 'audit':
              if (!scan.lookingUp) unawaited(onAudit());
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: 'history',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.history_rounded, size: 20),
              title: Text('Scan history'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'manual',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.keyboard_rounded, size: 20),
              title: Text('Manual entry'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (!kIsWeb)
            const PopupMenuItem(
              value: 'torch',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.flashlight_on_rounded, size: 20),
                title: Text('Torch'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const PopupMenuItem(
            value: 'audit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.fact_check_outlined, size: 20),
              title: Text('Start audit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ],
  );
}
