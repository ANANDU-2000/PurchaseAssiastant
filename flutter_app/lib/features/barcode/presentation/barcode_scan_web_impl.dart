import 'barcode_scan_web_stub.dart' as stub;

bool get barcodeDetectorAvailable => stub.barcodeDetectorAvailable;

Future<String?> decodeBarcodeFromImageBytes(List<int> bytes) =>
    stub.decodeBarcodeFromImageBytes(bytes);
