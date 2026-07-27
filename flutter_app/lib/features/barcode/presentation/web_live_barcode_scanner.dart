import 'package:flutter/widgets.dart';

/// Live camera barcode scan on web (BarcodeDetector + getUserMedia). IO stub returns null.
abstract class WebLiveBarcodeScanner {
  bool get isActive;

  String get viewType;

  Future<bool> start(void Function(String code) onDetected);

  Future<void> stop();

  Widget buildPreview();
}
