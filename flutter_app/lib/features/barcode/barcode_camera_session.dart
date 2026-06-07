import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'presentation/barcode_scan_web_stub.dart'
    if (dart.library.html) 'presentation/barcode_scan_web.dart';
import 'presentation/web_live_barcode_scanner.dart';

/// Keeps one camera stream on web so Safari/Chrome do not re-prompt every tab visit.
abstract final class BarcodeCameraSession {
  static MobileScannerController? mobile;
  static WebLiveBarcodeScanner? webDetector;
  static bool useWebDetectorPreview = false;

  static bool get hasLiveWebDetector =>
      useWebDetectorPreview && (webDetector?.isActive ?? false);

  static bool get hasLiveMobile =>
      mobile != null && (mobile!.value.isRunning);

  static void retainMobile(MobileScannerController controller) {
    if (!kIsWeb) return;
    mobile = controller;
  }

  static void retainWebDetector(WebLiveBarcodeScanner scanner) {
    if (!kIsWeb) return;
    webDetector = scanner;
    useWebDetectorPreview = true;
  }

  /// Drop streams (logout, permission denied, explicit retry).
  static Future<void> reset() async {
    if (kIsWeb) {
      await disposeSharedWebBarcodeScanner();
    } else {
      await webDetector?.stop();
    }
    webDetector = null;
    useWebDetectorPreview = false;
    await mobile?.dispose();
    mobile = null;
  }
}
