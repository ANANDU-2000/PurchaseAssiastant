import 'web_live_barcode_scanner.dart';

/// IO/mobile stub — web implementation in [barcode_scan_web.dart].
Future<String?> decodeBarcodeFromImageBytes(List<int> bytes) async => null;

bool get barcodeDetectorAvailable => false;

bool get isSafariBrowser => false;

bool get preferUploadBarcodeOnWeb => false;

WebLiveBarcodeScanner? createWebLiveBarcodeScanner() => null;
