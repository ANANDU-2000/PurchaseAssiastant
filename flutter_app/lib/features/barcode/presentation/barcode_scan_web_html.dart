import 'barcode_scan_web_stub.dart' as stub;

/// On web, [MobileScanner.analyzeImage] is the primary photo decode path.
bool get barcodeDetectorAvailable => true;

Future<String?> decodeBarcodeFromImageBytes(List<int> bytes) async {
  return stub.decodeBarcodeFromImageBytes(bytes);
}
