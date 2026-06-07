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
  // FIX 5: iPhone and iPad OS strings
  final match = RegExp(r'(?:iPhone |CPU )OS (\d+)[_\.]').firstMatch(ua);
  if (match != null) return int.tryParse(match.group(1) ?? '');
  final versionMatch = RegExp(r'Version/(\d+)').firstMatch(ua);
  if (versionMatch != null && isSafariBrowser) {
    return int.tryParse(versionMatch.group(1) ?? '');
  }
  return null;
}

/// Upload-only fallback when live camera is unreliable (old iOS or no APIs).
bool get preferUploadBarcodeOnWeb {
  // FIX 5: use live camera when BarcodeDetector is present
  if (barcodeDetectorAvailable) return false;
  if (isSafariBrowser) {
    final iosMajor = _iosMajorVersionFromUserAgent();
    if (iosMajor == null) return false;
    return iosMajor < 17;
  }
  return false;
}

/// Singleton web scanner — keeps getUserMedia stream alive across scan routes.
abstract final class HexaWebLiveBarcodeScanner {
  static WebLiveBarcodeScanner? _shared;

  static WebLiveBarcodeScanner get shared {
    _shared ??= _WebBarcodeDetectorScanner();
    return _shared!;
  }

  /// Tear down platform view — call when scan route is permanently disposed.
  static Future<void> disposeShared() async {
    final s = _shared;
    _shared = null;
    if (s is _WebBarcodeDetectorScanner) {
      await s.dispose();
    }
  }
}

WebLiveBarcodeScanner? createWebLiveBarcodeScanner() {
  if (!barcodeDetectorAvailable) return null;
  return HexaWebLiveBarcodeScanner.shared;
}

Future<void> disposeSharedWebBarcodeScanner() =>
    HexaWebLiveBarcodeScanner.disposeShared();

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

class _WebBarcodeDetectorScanner implements WebLiveBarcodeScanner {
  static int _nextViewId = 0;
  static const _detectIntervalMs = 150;

  html.VideoElement? _video;
  html.MediaStream? _stream;
  js.JsObject? _detector;
  Timer? _detectTimer;
  void Function(String code)? _onDetected;
  bool _active = false;
  bool _paused = false;
  bool _detectInFlight = false;
  late final String _viewType;
  bool _viewRegistered = false;

  _WebBarcodeDetectorScanner() {
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

  void _startDetectLoop() {
    _detectTimer?.cancel();
    _detectTimer = Timer.periodic(
      const Duration(milliseconds: _detectIntervalMs),
      (_) => unawaited(_detectOnce()),
    );
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _detectTimer?.cancel();
    _detectTimer = null;
    _onDetected = null;
    _detectInFlight = false;
  }

  @override
  Future<void> resume(void Function(String code) onDetected) async {
    if (!_active || _stream == null || _video == null) {
      await start(onDetected);
      return;
    }
    _paused = false;
    _onDetected = onDetected;
    _startDetectLoop();
  }

  @override
  Future<bool> start(void Function(String code) onDetected) async {
    if (_active && _stream != null && _video != null) {
      _paused = false;
      _onDetected = onDetected;
      _startDetectLoop();
      return true;
    }
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
      _video ??= html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true');
      _video!.srcObject = stream;

      await _video!.onLoadedMetadata.first.timeout(const Duration(seconds: 8));
      await _video!.play();

      _detector = _createBarcodeDetector();
      if (_detector == null) {
        await stop();
        return false;
      }

      _registerViewIfNeeded();
      _active = true;
      _paused = false;
      _startDetectLoop();
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  Future<void> _detectOnce() async {
    if (!_active ||
        _paused ||
        _detectInFlight ||
        _video == null ||
        _detector == null) {
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
    _paused = false;
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
      // Keep element alive so HtmlElementView can reuse on next start().
    }
  }

  Future<void> dispose() async {
    await stop();
    _video?.remove();
    _video = null;
    _viewRegistered = false;
  }
}
