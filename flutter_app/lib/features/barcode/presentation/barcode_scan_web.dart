// Web: prefer MobileScanner.analyzeImage in [barcode_scan_page]; optional BarcodeDetector via JS.
export 'barcode_scan_web_impl.dart'
    if (dart.library.html) 'barcode_scan_web_html.dart';
