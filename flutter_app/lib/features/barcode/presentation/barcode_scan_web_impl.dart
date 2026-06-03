import 'barcode_scan_web_stub.dart' as stub;
import 'web_live_barcode_scanner.dart';

bool get barcodeDetectorAvailable => stub.barcodeDetectorAvailable;

bool get isSafariBrowser => stub.isSafariBrowser;

bool get preferUploadBarcodeOnWeb => stub.preferUploadBarcodeOnWeb;

Future<String?> decodeBarcodeFromImageBytes(List<int> bytes) =>
    stub.decodeBarcodeFromImageBytes(bytes);

WebLiveBarcodeScanner? createWebLiveBarcodeScanner() =>
    stub.createWebLiveBarcodeScanner();
