// Web-only module (conditional import). VM analyzer cannot resolve dart:js helpers.
// ignore_for_file: undefined_function, undefined_shown_name, deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js' show allowInterop;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'web_live_barcode_scanner.dart';

bool get barcodeDetectorAvailable =>
    js.context.hasProperty('BarcodeDetector');

bool get isSafariBrowser {
  final ua = html.window.navigator.userAgent;
  return ua.contains('Safari') &&
      !ua.contains('Chrome') &&
      !ua.contains('Chromium') &&
      !ua.contains('Edg');
}

int? _iosMajorVersionFromUserAgent() {
  final ua = html.window.navigator.userAgent;
  final match = RegExp(r'OS (\d+)_').firstMatch(ua);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

/// Upload-only fallback when live camera is unreliable (old iOS or no APIs).
bool get preferUploadBarcodeOnWeb {
  if (barcodeDetectorAvailable) return false;
  if (isSafariBrowser) {
    final iosMajor = _iosMajorVersionFromUserAgent();
    if (iosMajor != null && iosMajor >= 17) return false;
    return true;
  }
  return false;
}

WebLiveBarcodeScanner? createWebLiveBarcodeScanner() {
  if (!barcodeDetectorAvailable || !isSafariBrowser) return null;
  return _SafariBarcodeDetectorScanner();
}

Future<String?> decodeBarcodeFromImageBytes(List<int> bytes) async {
  if (!barcodeDetectorAvailable) return null;
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final img = html.ImageElement()..src = url;
    await img.onLoad.first.timeout(const Duration(seconds: 8));
    final formats = js.JsArray.from(['code_128', 'ean_13', 'qr_code', 'code_39']);
    final options = js.JsObject.jsify({'formats': formats});
    final ctor = js.context['BarcodeDetector'];
    if (ctor is! js.JsFunction) return null;
    final detector = js.JsObject(ctor, [options]);
    final promise = detector.callMethod('detect', [img]);
    final results = await _promiseToList(promise);
    if (results.isEmpty) return null;
    final first = results.first as js.JsObject;
    final raw = first['rawValue'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}

Future<List<dynamic>> _promiseToList(dynamic promise) {
  final completer = Completer<List<dynamic>>();
  final then = allowInterop((dynamic value) {
    if (value is List) {
      completer.complete(value);
    } else if (value is js.JsArray) {
      completer.complete(value.toList());
    } else {
      completer.complete(const []);
    }
  });
  final catchErr = allowInterop((dynamic _) {
    completer.complete(const []);
  });
  final p = promise as js.JsObject;
  p.callMethod('then', [then]).callMethod('catch', [catchErr]);
  return completer.future;
}

js.JsObject? _createBarcodeDetector() {
  final ctor = js.context['BarcodeDetector'];
  if (ctor is! js.JsFunction) return null;
  final formats = js.JsArray.from(['code_128', 'ean_13', 'qr_code', 'code_39']);
  final options = js.JsObject.jsify({'formats': formats});
  return js.JsObject(ctor, [options]);
}

String? _firstCodeFromDetectResults(List<dynamic> results) {
  if (results.isEmpty) return null;
  final first = results.first;
  if (first is! js.JsObject) return null;
  final raw = first['rawValue'];
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

class _SafariBarcodeDetectorScanner implements WebLiveBarcodeScanner {
  static int _nextViewId = 0;

  html.VideoElement? _video;
  html.MediaStream? _stream;
  js.JsObject? _detector;
  Timer? _detectTimer;
  void Function(String code)? _onDetected;
  bool _active = false;
  bool _detectInFlight = false;
  late final String _viewType;
  bool _viewRegistered = false;

  _SafariBarcodeDetectorScanner() {
    _viewType = 'barcode-live-${_nextViewId++}';
  }

  @override
  bool get isActive => _active;

  @override
  String get viewType => _viewType;

  void _registerViewIfNeeded() {
    if (_viewRegistered || _video == null) return;
    final video = _video!;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => video
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover',
    );
    _viewRegistered = true;
  }

  @override
  Widget buildPreview() {
    _registerViewIfNeeded();
    return HtmlElementView(viewType: _viewType);
  }

  @override
  Future<bool> start(void Function(String code) onDetected) async {
    await stop();
    _onDetected = onDetected;
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) return false;

      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': {'ideal': 'environment'},
        },
        'audio': false,
      });
      _stream = stream;
      _video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..srcObject = stream;

      await _video!.onLoadedMetadata.first.timeout(const Duration(seconds: 8));
      await _video!.play();

      _detector = _createBarcodeDetector();
      if (_detector == null) {
        await stop();
        return false;
      }

      _registerViewIfNeeded();
      _active = true;
      _detectTimer = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) => unawaited(_detectOnce()),
      );
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  Future<void> _detectOnce() async {
    if (!_active || _detectInFlight || _video == null || _detector == null) {
      return;
    }
    _detectInFlight = true;
    try {
      final promise = _detector!.callMethod('detect', [_video]);
      final results = await _promiseToList(promise);
      final code = _firstCodeFromDetectResults(results);
      if (code != null && _active) {
        _onDetected?.call(code);
      }
    } catch (_) {
      // ignore single-frame failures
    } finally {
      _detectInFlight = false;
    }
  }

  @override
  Future<void> stop() async {
    _active = false;
    _detectTimer?.cancel();
    _detectTimer = null;
    _detectInFlight = false;
    _onDetected = null;
    _detector = null;

    final tracks = _stream?.getTracks() ?? [];
    for (final t in tracks) {
      t.stop();
    }
    _stream = null;

    if (_video != null) {
      _video!.srcObject = null;
      _video!.remove();
      _video = null;
    }
  }
}
