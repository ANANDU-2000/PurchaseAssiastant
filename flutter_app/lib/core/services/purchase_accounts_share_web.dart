// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

/// PWA: share PDF + text via navigator.share when supported.
Future<bool> tryWebSharePurchasePdf({
  required Uint8List bytes,
  required String filename,
  required String text,
  required String title,
}) async {
  final nav = html.window.navigator;
  if (!js_util.hasProperty(nav, 'share')) return false;

  final blob = html.Blob([bytes], 'application/pdf');
  final file = html.File([blob], filename, 'application/pdf');

  final shareData = js_util.jsify({
    'files': [file],
    'text': text,
    'title': title,
  });

  if (js_util.hasProperty(nav, 'canShare')) {
    final can = js_util.callMethod(nav, 'canShare', [shareData]);
    if (can is bool && !can) return false;
  }

  try {
    await js_util.promiseToFuture<void>(
      js_util.callMethod(nav, 'share', [shareData]),
    );
    return true;
  } catch (_) {
    return false;
  }
}
