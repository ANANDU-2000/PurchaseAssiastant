import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/services/prefs_helper.dart';
import '../barcode_camera_session.dart';
import 'camera_permission_cache.dart';
import '../presentation/barcode_scan_web_stub.dart'
    if (dart.library.html) '../presentation/barcode_scan_web.dart';
import '../presentation/web_live_barcode_scanner.dart';

const kBarcodeCameraPermGrantedKey = 'camera_perm_granted';

/// Primary warehouse formats (fewer = faster decode per frame).
const kWarehouseBarcodeFormats = <BarcodeFormat>[
  BarcodeFormat.code128,
  BarcodeFormat.ean13,
  BarcodeFormat.qrCode,
];

/// Owns camera bootstrap / lifecycle. Reuses [BarcodeCameraSession] retain bag.
/// Initialized once; does not stop/start on scan result dismiss.
class BarcodeCameraController extends ChangeNotifier {
  BarcodeCameraController({required this.onCodeDetected});

  final void Function(String code) onCodeDetected;

  static bool _cameraPermissionGrantedThisSession = false;
  final _permCache = CameraPermissionCache.instance;

  MobileScannerController? mobile;
  WebLiveBarcodeScanner? webLiveScanner;
  bool useWebDetectorPreview = false;
  bool cameraInitInFlight = false;
  bool cameraDenied = false;
  bool cameraPermanent = false;
  String? cameraDeniedMessage;
  bool webCameraAwaitingGesture = false;
  bool torch = false;
  bool safariUploadNudgeShown = false;
  bool unreadableNudgeShown = false;
  bool hadDetectThisVisit = false;
  Timer? _safariNoDetectTimer;
  Timer? _unreadableNudgeTimer;
  bool _disposed = false;

  /// Soft banner copy when no decode after live session starts.
  String get unreadableNudgeMessage => barcodeMessageForUser(
        barcodeUnreadableError(),
        ctx: BarcodeOperationContext.scanner,
      );

  bool get isLive =>
      (mobile != null && mobile!.value.isRunning) ||
      (useWebDetectorPreview && (webLiveScanner?.isActive ?? false));

  Future<void> bootstrap() async {
    try {
      final persisted = await _readPersistedCameraPerm();
      _permCache.persistedGranted = persisted;
      if (persisted) {
        _cameraPermissionGrantedThisSession = true;
        _permCache.grantedThisSession = true;
      }
      if (kIsWeb && !_permCache.canAutoStartCamera) {
        webCameraAwaitingGesture = true;
        _notify();
        return;
      }
      await initCamera();
    } catch (e, st) {
      developer.log('Error bootstrapping camera', error: e, stackTrace: st);
    }
  }

  Future<void> startFromUserGesture() async {
    try {
      webCameraAwaitingGesture = false;
      _notify();
      await initCamera();
    } catch (e, st) {
      developer.log(
        'Error starting camera from user gesture',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> retryAfterDenial() async {
    try {
      await BarcodeCameraSession.reset();
      mobile = null;
      webLiveScanner = null;
      useWebDetectorPreview = false;
      await initCamera();
    } catch (e, st) {
      developer.log(
        'Error retrying camera after denial',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> toggleTorch() async {
    if (mobile == null) return;
    try {
      await mobile!.toggleTorch();
      torch = !torch;
      _notify();
    } catch (e, st) {
      developer.log('Error toggling torch', error: e, stackTrace: st);
    }
  }

  /// Keep warm — do not stop for continuous scan. Only pause native non-iOS if needed.
  Future<void> ensureRunning() async {
    if (useWebDetectorPreview && webLiveScanner != null) return;
    if (mobile == null) {
      await initCamera();
      return;
    }
    try {
      if (!mobile!.value.isInitialized) {
        await initCamera();
      } else if (!kIsWeb &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          !mobile!.value.isRunning) {
        await mobile!.start();
      }
    } catch (_) {
      await initCamera();
    }
  }

  void markHadDetect() {
    hadDetectThisVisit = true;
    _safariNoDetectTimer?.cancel();
    _unreadableNudgeTimer?.cancel();
    if (unreadableNudgeShown) {
      unreadableNudgeShown = false;
      _notify();
    }
  }

  void handleNativeDetect(BarcodeCapture cap) {
    final barcodes = cap.barcodes
        .where((b) => b.rawValue != null && b.rawValue!.trim().isNotEmpty)
        .toList();
    if (barcodes.isEmpty) return;
    final preferred = barcodes.firstWhere(
      (b) => b.format == BarcodeFormat.qrCode,
      orElse: () => barcodes.first,
    );
    final v = preferred.rawValue?.trim();
    if (v == null || v.isEmpty) return;
    markHadDetect();
    onCodeDetected(v);
  }

  Future<String?> analyzeImagePath(String path) async {
    try {
      if (mobile != null) {
        final cap = await mobile!.analyzeImage(path);
        if (cap != null && cap.barcodes.isNotEmpty) {
          return cap.barcodes.first.rawValue?.trim();
        }
      }
    } catch (e, st) {
      developer.log('Error analyzing barcode image', error: e, stackTrace: st);
    }
    return null;
  }

  Future<void> initCamera() async {
    if ((mobile != null && mobile!.value.isRunning) ||
        (useWebDetectorPreview && (webLiveScanner?.isActive ?? false))) {
      return;
    }
    if (cameraInitInFlight) return;
    cameraInitInFlight = true;
    try {
      final persisted = await _readPersistedCameraPerm();
      if (persisted) {
        _cameraPermissionGrantedThisSession = true;
      }
      if (kIsWeb) {
        if (BarcodeCameraSession.hasLiveWebDetector &&
            BarcodeCameraSession.webDetector != null) {
          webLiveScanner = BarcodeCameraSession.webDetector;
          useWebDetectorPreview = true;
          await webLiveScanner!.start(_onWebCode);
          cameraDenied = false;
          cameraPermanent = false;
          cameraDeniedMessage = null;
          _notify();
          return;
        }
        if (BarcodeCameraSession.hasLiveMobile &&
            BarcodeCameraSession.mobile != null) {
          var reuseOk = true;
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            reuseOk = false;
            await BarcodeCameraSession.reset();
          }
          if (reuseOk) {
            mobile = BarcodeCameraSession.mobile;
            cameraDenied = false;
            cameraPermanent = false;
            cameraDeniedMessage = null;
            _notify();
            return;
          }
        }
        if (await _tryStartWebBarcodeDetector()) return;
        await _startWebMobileScanner();
        return;
      }

      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        cameraDenied = true;
        cameraPermanent = true;
        cameraDeniedMessage = barcodeMessageForUser(
          barcodeCameraPermissionError(),
          ctx: BarcodeOperationContext.scanner,
        );
        _notify();
        return;
      }

      if (status.isGranted || status.isLimited) {
        await _markCameraPermGranted();
        await _startNativeMobileScanner();
        return;
      }

      if (_cameraPermissionGrantedThisSession || persisted) {
        final recheck = await Permission.camera.status;
        if (recheck.isGranted || recheck.isLimited) {
          await _markCameraPermGranted();
          await _startNativeMobileScanner();
          return;
        }
        if (persisted) {
          final prefs = PrefsHelper.prefs;
          await prefs.setBool(kBarcodeCameraPermGrantedKey, false);
        }
        _cameraPermissionGrantedThisSession = false;
      }

      final req = await Permission.camera.request();
      if (!req.isGranted && !req.isLimited) {
        cameraDenied = true;
        cameraPermanent = req.isPermanentlyDenied;
        cameraDeniedMessage = null;
        _notify();
        return;
      }

      await _markCameraPermGranted();
      await _startNativeMobileScanner();
    } finally {
      cameraInitInFlight = false;
    }
  }

  void onAppResumed() {
    unawaited(_onAppResumed());
  }

  Future<void> _onAppResumed() async {
    if (_disposed) return;
    if (!kIsWeb) {
      final status = await Permission.camera.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        cameraDenied = true;
        cameraPermanent = status.isPermanentlyDenied;
        cameraDeniedMessage = barcodeMessageForUser(
          barcodeCameraPermissionError(),
          ctx: BarcodeOperationContext.scanner,
        );
        mobile = null;
        _notify();
        return;
      }
    }
    if (kIsWeb) {
      if (!isLive && !webCameraAwaitingGesture) {
        await initCamera();
      }
      return;
    }
    await initCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    _safariNoDetectTimer?.cancel();
    _unreadableNudgeTimer?.cancel();
    if (BarcodeCameraSession.mobile == mobile) {
      BarcodeCameraSession.mobile = null;
    }
    if (kIsWeb) {
      webLiveScanner = null;
      mobile = null;
    } else {
      unawaited(_stopWebLiveScanner());
      unawaited(mobile?.stop());
      mobile = null;
    }
    super.dispose();
  }

  void _onWebCode(String code) {
    final v = code.trim();
    if (v.isEmpty) return;
    markHadDetect();
    onCodeDetected(v);
  }

  Future<bool> _tryStartWebBarcodeDetector() async {
    if (!kIsWeb) return false;
    final scanner = createWebLiveBarcodeScanner();
    if (scanner == null) return false;
    final ok = await scanner.start(_onWebCode);
    if (!ok) {
      await scanner.stop();
      return false;
    }
    await mobile?.dispose();
    mobile = null;
    BarcodeCameraSession.mobile = null;
    webLiveScanner = scanner;
    useWebDetectorPreview = true;
    BarcodeCameraSession.retainWebDetector(scanner);
    await _markCameraPermGranted();
    cameraDenied = false;
    cameraPermanent = false;
    cameraDeniedMessage = null;
    _scheduleSafariNoDetectNudge();
    _scheduleUnreadableNudge();
    _notify();
    return true;
  }

  Future<void> _startWebMobileScanner() async {
    await _stopWebLiveScanner();
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS && mobile == null) {
        if (BarcodeCameraSession.mobile != null) {
          await BarcodeCameraSession.mobile!.dispose();
          BarcodeCameraSession.mobile = null;
        }
      }
      mobile = (defaultTargetPlatform == TargetPlatform.iOS)
          ? _newScannerController()
          : (BarcodeCameraSession.mobile ?? _newScannerController());
      BarcodeCameraSession.retainMobile(mobile!);
      await _markCameraPermGranted();
      cameraDenied = false;
      cameraPermanent = false;
      cameraDeniedMessage = null;
      _scheduleSafariNoDetectNudge();
      _scheduleUnreadableNudge();
      _notify();
    } catch (e) {
      cameraDenied = true;
      cameraPermanent = false;
      cameraDeniedMessage = barcodeMessageForUser(
        barcodeCameraPermissionError(
          'Could not start the camera. Allow camera for this site, '
          'or use Upload barcode photo / manual entry below.',
        ),
        ctx: BarcodeOperationContext.scanner,
      );
      _notify();
    }
  }

  Future<void> _disposeNativeCamera() async {
    final cam = mobile;
    mobile = null;
    if (BarcodeCameraSession.mobile == cam) {
      BarcodeCameraSession.mobile = null;
    }
    if (cam != null) {
      await cam.stop();
      await cam.dispose();
    }
  }

  Future<void> _startNativeMobileScanner() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _disposeNativeCamera();
        mobile = _newScannerController();
      } else {
        mobile = BarcodeCameraSession.mobile ?? _newScannerController();
      }
      BarcodeCameraSession.retainMobile(mobile!);
      if (!mobile!.value.isRunning) {
        await mobile!.start();
      }
      await _markCameraPermGranted();
      cameraDenied = false;
      cameraDeniedMessage = null;
      _scheduleUnreadableNudge();
      _notify();
    } catch (e, st) {
      developer.log(
        'Error starting native mobile scanner',
        error: e,
        stackTrace: st,
      );
      cameraDenied = true;
      cameraPermanent = false;
      cameraDeniedMessage = barcodeMessageForUser(
        barcodeCameraPermissionError(
          'Camera could not start (in use or low memory). '
          'Close other camera apps, retry, or enter the code manually.',
        ),
        ctx: BarcodeOperationContext.scanner,
      );
      _notify();
    }
  }

  void _scheduleSafariNoDetectNudge() {
    if (!kIsWeb || !isSafariBrowser) return;
    _safariNoDetectTimer?.cancel();
    _safariNoDetectTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed || hadDetectThisVisit || safariUploadNudgeShown) return;
      safariUploadNudgeShown = true;
      _notify();
    });
  }

  void _scheduleUnreadableNudge() {
    _unreadableNudgeTimer?.cancel();
    if (hadDetectThisVisit || unreadableNudgeShown) return;
    _unreadableNudgeTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed || hadDetectThisVisit || unreadableNudgeShown) return;
      unreadableNudgeShown = true;
      _notify();
    });
  }

  MobileScannerController _newScannerController() {
    return MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: kIsWeb ? 400 : 100,
      facing: CameraFacing.back,
      formats: kWarehouseBarcodeFormats,
      cameraResolution: const Size(1280, 720),
      autoStart: true,
      returnImage: false,
    );
  }

  Future<void> _stopWebLiveScanner() async {
    await webLiveScanner?.stop();
    webLiveScanner = null;
    useWebDetectorPreview = false;
  }

  Future<bool> _readPersistedCameraPerm() async {
    try {
      return PrefsHelper.prefs.getBool(kBarcodeCameraPermGrantedKey) ?? false;
    } catch (e, st) {
      developer.log(
        'Error reading persisted camera permission',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _markCameraPermGranted() async {
    _cameraPermissionGrantedThisSession = true;
    _permCache.markGranted();
    try {
      await PrefsHelper.prefs.setBool(kBarcodeCameraPermGrantedKey, true);
    } catch (e, st) {
      developer.log(
        'Error marking camera permission granted',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
