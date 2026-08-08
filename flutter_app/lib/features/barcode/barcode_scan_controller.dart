import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api/hexa_api.dart';
import '../../core/errors/barcode_operation_errors.dart';
import '../../core/providers/barcode_recent_scans.dart';
import '../../core/services/prefs_helper.dart';
import 'barcode_lookup_cache.dart';
import 'barcode_scan_session.dart';
import 'barcode_scan_sounds.dart';
import 'services/assign_barcode_helper.dart';

const kBarcodeScanSoundEnabledKey = 'barcode_scan_sound_enabled';
const kBarcodeMaxRecent = 10;
const kBarcodeDebounceMs = 200;
const kBarcodeManualSearchDebounceMs = 400;

typedef BarcodeLookupFn = Future<Map<String, dynamic>> Function({
  required String businessId,
  required String code,
});

typedef BarcodeStockSearchFn = Future<Map<String, dynamic>> Function({
  required String businessId,
  required String q,
});

/// Orchestrates FSM lookup, recent scans, manual search, sound prefs, timings.
class BarcodeScanController extends ChangeNotifier {
  BarcodeScanController({
    required this.lookupFn,
    required this.stockSearchFn,
    this.assignFn,
  });

  final BarcodeLookupFn lookupFn;
  final BarcodeStockSearchFn stockSearchFn;
  final Future<void> Function({
    required String businessId,
    required String itemId,
    required String barcode,
  })? assignFn;

  final BarcodeScanSession session = BarcodeScanSession();
  final manualCtrl = TextEditingController();
  final manualFocus = FocusNode();

  bool soundEnabled = true;
  bool lookingUp = false;
  bool resultUiOpen = false;
  bool decodePulse = false;
  String? lookupLabel;
  String? lastCode;
  DateTime? lastAt;
  List<BarcodeRecentScan> recent = [];
  List<Map<String, dynamic>> manualMatches = const [];
  bool manualSearching = false;
  String manualQuery = '';
  Timer? _manualDebounce;
  bool _disposed = false;

  /// Last measured lookup duration (ms) — set after each completed lookup.
  int? lastLookupMs;
  bool? lastLookupFromCache;

  /// Last rejected decode message (empty/garbage) for UI SnackBar once.
  String? lastRejectMessage;

  bool get acceptsCameraDetect =>
      !resultUiOpen &&
      session.acceptsCameraDetect &&
      !session.isLookingUp;

  bool get showResultPane =>
      session.phase == BarcodeScanPhase.result ||
      session.phase == BarcodeScanPhase.error ||
      session.phase == BarcodeScanPhase.lookingUp ||
      session.phase == BarcodeScanPhase.action;

  Future<void> loadPrefs() async {
    try {
      soundEnabled =
          PrefsHelper.prefs.getBool(kBarcodeScanSoundEnabledKey) ?? true;
    } catch (_) {
      soundEnabled = true;
    }
    _notify();
  }

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    try {
      await PrefsHelper.prefs.setBool(kBarcodeScanSoundEnabledKey, value);
    } catch (_) {}
    _notify();
  }

  Future<void> loadRecent() async {
    try {
      recent = await loadBarcodeRecentScans(max: kBarcodeMaxRecent);
      _notify();
    } catch (e, st) {
      developer.log('Error loading recent scans', error: e, stackTrace: st);
    }
  }

  void onManualChanged() {
    final next = manualCtrl.text.toLowerCase().trim();
    if (next == manualQuery) return;
    manualQuery = next;
    if (next.length < 2) {
      manualMatches = const [];
      manualSearching = false;
      _notify();
    }
    _manualDebounce?.cancel();
    if (next.length < 2) return;
    _manualDebounce = Timer(
      const Duration(milliseconds: kBarcodeManualSearchDebounceMs),
      () => unawaited(searchManualBound(next)),
    );
  }

  Future<void> searchManualBound(String q) async {
    final bid = _boundBusinessId;
    if (bid == null || bid.isEmpty) return;
    manualSearching = true;
    _notify();
    try {
      final blob = await stockSearchFn(businessId: bid, q: q);
      if (manualQuery != q) return;
      final items = [
        for (final row in (blob['items'] as List? ?? []))
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      manualMatches = items;
      manualSearching = false;
      _notify();
    } catch (_) {
      manualMatches = const [];
      manualSearching = false;
      _notify();
    }
  }

  static BarcodeScanController fromApi({
    required HexaApi api,
    required String businessId,
  }) {
    final c = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) =>
          api.barcodeStockLookup(businessId: businessId, code: code),
      stockSearchFn: ({required String businessId, required String q}) =>
          api.listStock(businessId: businessId, q: q, perPage: 8, page: 1),
      assignFn: ({
        required String businessId,
        required String itemId,
        required String barcode,
      }) =>
          assignBarcodeToItem(
            api: api,
            businessId: businessId,
            itemId: itemId,
            barcode: barcode,
          ),
    );
    c.bindBusinessId(businessId);
    return c;
  }

  String? _boundBusinessId;

  void bindBusinessId(String businessId) {
    _boundBusinessId = businessId;
  }

  bool debouncePass(String code) {
    final now = DateTime.now();
    if (lastCode == code &&
        lastAt != null &&
        now.difference(lastAt!) <
            const Duration(milliseconds: kBarcodeDebounceMs)) {
      return false;
    }
    lastCode = code;
    lastAt = now;
    return true;
  }

  /// Returns false if [raw] is empty/garbage (sets [lastRejectMessage]).
  bool acceptDecode(String raw) {
    if (isGarbageBarcodeDecode(raw)) {
      lastRejectMessage = barcodeMessageForUser(
        barcodeEmptyDecodeError(),
        ctx: BarcodeOperationContext.scanner,
      );
      unawaited(BarcodeScanSounds.playFailure(enabled: soundEnabled));
      _notify();
      return false;
    }
    lastRejectMessage = null;
    return true;
  }

  void clearRejectMessage() {
    if (lastRejectMessage == null) return;
    lastRejectMessage = null;
    _notify();
  }

  /// Decode accepted — pulse + optional click before lookup.
  void onDecoded(String code) {
    unawaited(BarcodeScanSounds.playDecode(enabled: soundEnabled));
    decodePulse = true;
    _notify();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (_disposed) return;
      decodePulse = false;
      _notify();
    });
  }

  void setResultUiOpen(bool open) {
    resultUiOpen = open;
    _notify();
  }

  void readyForNext() {
    session.readyForNext();
    resultUiOpen = false;
    lookupLabel = null;
    lookingUp = false;
    lastCode = null;
    lastAt = null;
    _notify();
  }

  Future<void> pushRecent(BarcodeRecentScan row) async {
    recent = [
      row,
      ...recent.where((x) => x.code != row.code),
    ].take(kBarcodeMaxRecent).toList();
    _notify();
    try {
      await saveBarcodeRecentScans(recent);
    } catch (e, st) {
      developer.log('Error saving recent scans', error: e, stackTrace: st);
    }
  }

  Future<void> lookup(
    String raw, {
    required String businessId,
    void Function(Map<String, dynamic> row)? onReturnStock,
  }) async {
    if (_disposed) return;
    if (!acceptDecode(raw)) return;
    final code = raw.trim();
    if (session.isLookingUp) return;

    final scanId = session.beginLookup(code);
    lookingUp = true;
    lookupLabel = code;
    final sw = Stopwatch()..start();
    _notify();

    try {
      final cached = BarcodeLookupCache.get(businessId, code);
      if (cached != null) {
        final id = cached['id']?.toString();
        if (id != null && id.isNotEmpty) {
          // Instant UI from cache, then revalidate.
          if (!session.isStale(scanId)) {
            lastLookupFromCache = true;
            lastLookupMs = sw.elapsedMilliseconds;
            if (kDebugMode) {
              debugPrint(
                '[BarcodeScan] lookup CACHE_HIT ${lastLookupMs}ms code=$code',
              );
            }
            await BarcodeScanSounds.playSuccess(enabled: soundEnabled);
            session.completeFound(scanId, item: cached, fromCache: true);
            lookingUp = false;
            _notify();
            await pushRecent(
              BarcodeRecentScan(
                id: id,
                name: cached['name']?.toString() ?? code,
                code: code,
              ),
            );
            if (onReturnStock != null) {
              onReturnStock(Map<String, dynamic>.from(cached));
            }
          }
          await _revalidateCached(
            scanId: scanId,
            businessId: businessId,
            code: code,
            cached: cached,
            sw: sw,
          );
          return;
        }
        BarcodeLookupCache.invalidate(businessId, code);
      }

      final row = await lookupFn(businessId: businessId, code: code)
          .timeout(const Duration(seconds: 6));
      if (session.isStale(scanId) || _disposed) return;

      BarcodeLookupCache.put(businessId, code, row);
      sw.stop();
      lastLookupMs = sw.elapsedMilliseconds;
      lastLookupFromCache = false;
      if (kDebugMode) {
        debugPrint(
          '[BarcodeScan] lookup CACHE_MISS ${lastLookupMs}ms code=$code',
        );
      }
      await _applyFoundOrEmpty(
        scanId: scanId,
        code: code,
        row: row,
        fromCache: false,
        onReturnStock: onReturnStock,
      );
    } on TimeoutException catch (e) {
      await _failLookup(
        scanId,
        sw,
        barcodeNetworkError(e),
      );
    } on DioException catch (e) {
      if (session.isStale(scanId) || _disposed) return;
      sw.stop();
      lastLookupMs = sw.elapsedMilliseconds;
      lastLookupFromCache = false;
      if (e.response?.statusCode == 404) {
        await BarcodeScanSounds.playFailure(enabled: soundEnabled);
        session.completeNotFound(scanId);
        lookingUp = false;
        _notify();
        return;
      }
      await _failLookup(scanId, sw, e);
    } catch (e) {
      await _failLookup(scanId, sw, e);
    }
  }

  Future<void> _revalidateCached({
    required int scanId,
    required String businessId,
    required String code,
    required Map<String, dynamic> cached,
    required Stopwatch sw,
  }) async {
    try {
      final row = await lookupFn(businessId: businessId, code: code)
          .timeout(const Duration(seconds: 6));
      if (session.isStale(scanId) || _disposed) return;
      BarcodeLookupCache.put(businessId, code, row);
      sw.stop();
      lastLookupMs = sw.elapsedMilliseconds;
      if (kDebugMode) {
        debugPrint(
          '[BarcodeScan] lookup CACHE_REVALIDATE ${lastLookupMs}ms code=$code',
        );
      }
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) {
        BarcodeLookupCache.invalidate(businessId, code);
        await BarcodeScanSounds.playFailure(enabled: soundEnabled);
        session.completeNotFound(scanId);
        lookingUp = false;
        _notify();
        return;
      }
      // Replace pane if data changed (same scanId still active).
      session.completeFound(scanId, item: row, fromCache: false);
      lookingUp = false;
      _notify();
    } on DioException catch (e) {
      if (session.isStale(scanId) || _disposed) return;
      if (e.response?.statusCode == 404) {
        BarcodeLookupCache.invalidate(businessId, code);
        await BarcodeScanSounds.playFailure(enabled: soundEnabled);
        session.completeNotFound(scanId);
        lookingUp = false;
        _notify();
        return;
      }
      // Keep cached result on flaky network — do not wipe.
      sw.stop();
      lastLookupMs = sw.elapsedMilliseconds;
      lookingUp = false;
      _notify();
      if (kDebugMode) {
        debugPrint(
          '[BarcodeScan] revalidate kept cache after network error code=$code',
        );
      }
    } on TimeoutException {
      if (session.isStale(scanId) || _disposed) return;
      sw.stop();
      lastLookupMs = sw.elapsedMilliseconds;
      lookingUp = false;
      _notify();
    } catch (_) {
      if (session.isStale(scanId) || _disposed) return;
      lookingUp = false;
      _notify();
    }
  }

  Future<void> _applyFoundOrEmpty({
    required int scanId,
    required String code,
    required Map<String, dynamic> row,
    required bool fromCache,
    void Function(Map<String, dynamic> row)? onReturnStock,
  }) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) {
      await BarcodeScanSounds.playFailure(enabled: soundEnabled);
      session.completeNotFound(scanId);
      lookingUp = false;
      _notify();
      return;
    }
    await BarcodeScanSounds.playSuccess(enabled: soundEnabled);
    session.completeFound(scanId, item: row, fromCache: fromCache);
    await pushRecent(
      BarcodeRecentScan(
        id: id,
        name: row['name']?.toString() ?? code,
        code: code,
      ),
    );
    if (onReturnStock != null) {
      onReturnStock(Map<String, dynamic>.from(row));
    }
    lookingUp = false;
    _notify();
  }

  Future<void> _failLookup(int scanId, Stopwatch sw, Object e) async {
    if (session.isStale(scanId) || _disposed) return;
    if (sw.isRunning) sw.stop();
    lastLookupMs = sw.elapsedMilliseconds;
    lastLookupFromCache = false;
    await BarcodeScanSounds.playFailure(enabled: soundEnabled);
    session.completeError(
      scanId,
      message: barcodeMessageForUser(
        e,
        ctx: BarcodeOperationContext.scanner,
      ),
    );
    lookingUp = false;
    _notify();
  }

  Future<void> assignBarcode({
    required String businessId,
    required String itemId,
    required String barcode,
  }) async {
    final fn = assignFn;
    if (fn == null) return;
    await fn(businessId: businessId, itemId: itemId, barcode: barcode);
    BarcodeLookupCache.invalidate(businessId, barcode);
  }

  /// Invalidate in-flight work when leaving the page.
  void abandonInFlight() {
    session.goIdle();
    lookingUp = false;
    lookupLabel = null;
    resultUiOpen = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _manualDebounce?.cancel();
    session.goIdle();
    lookingUp = false;
    manualCtrl.dispose();
    manualFocus.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
