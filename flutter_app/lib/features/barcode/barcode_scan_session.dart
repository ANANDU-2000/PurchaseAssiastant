/// Explicit barcode scanner phases (Step C).
enum BarcodeScanPhase {
  idle,
  scanning,
  lookingUp,
  result,
  action,
  readyForNext,
  error,
}

/// Outcome of a single scan identity.
enum BarcodeScanOutcome {
  found,
  notFound,
  networkError,
  permissionDenied,
}

/// Immutable snapshot bound to one [scanId].
class BarcodeScanSnapshot {
  const BarcodeScanSnapshot({
    required this.scanId,
    required this.code,
    required this.phase,
    this.outcome,
    this.item,
    this.errorMessage,
    this.fromCache = false,
  });

  final int scanId;
  final String code;
  final BarcodeScanPhase phase;
  final BarcodeScanOutcome? outcome;
  final Map<String, dynamic>? item;
  final String? errorMessage;
  final bool fromCache;

  String? get itemId => item?['id']?.toString();

  String get itemName =>
      item?['name']?.toString().trim().isNotEmpty == true
          ? item!['name'].toString()
          : code;

  BarcodeScanSnapshot copyWith({
    BarcodeScanPhase? phase,
    BarcodeScanOutcome? outcome,
    Map<String, dynamic>? item,
    String? errorMessage,
    bool? fromCache,
    bool clearItem = false,
    bool clearError = false,
  }) {
    return BarcodeScanSnapshot(
      scanId: scanId,
      code: code,
      phase: phase ?? this.phase,
      outcome: outcome ?? this.outcome,
      item: clearItem ? null : (item ?? this.item),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fromCache: fromCache ?? this.fromCache,
    );
  }
}

/// Scan FSM with generation so a slow older lookup cannot overwrite a newer one.
class BarcodeScanSession {
  int _nextId = 0;
  BarcodeScanSnapshot? _current;

  BarcodeScanSnapshot? get current => _current;

  int get activeScanId => _current?.scanId ?? 0;

  BarcodeScanPhase get phase =>
      _current?.phase ?? BarcodeScanPhase.idle;

  /// True while a lookup is in flight (UI may show inline loading).
  bool get isLookingUp => phase == BarcodeScanPhase.lookingUp;

  /// Camera may accept a new code when not mid-lookup for the same debounce window.
  /// Continuous scan: allow detect while RESULT/ERROR is showing (starts a new identity).
  bool get acceptsCameraDetect =>
      phase == BarcodeScanPhase.idle ||
      phase == BarcodeScanPhase.scanning ||
      phase == BarcodeScanPhase.readyForNext ||
      phase == BarcodeScanPhase.result ||
      phase == BarcodeScanPhase.error ||
      phase == BarcodeScanPhase.action;

  void goIdle() {
    _current = null;
  }

  void markScanning() {
    final cur = _current;
    if (cur == null) {
      _current = BarcodeScanSnapshot(
        scanId: 0,
        code: '',
        phase: BarcodeScanPhase.scanning,
      );
      return;
    }
    _current = cur.copyWith(phase: BarcodeScanPhase.scanning);
  }

  /// Begin lookup for [code]; returns the new [scanId].
  int beginLookup(String code) {
    final id = ++_nextId;
    _current = BarcodeScanSnapshot(
      scanId: id,
      code: code.trim(),
      phase: BarcodeScanPhase.lookingUp,
    );
    return id;
  }

  /// Apply found item only if [scanId] is still active.
  bool completeFound(
    int scanId, {
    required Map<String, dynamic> item,
    bool fromCache = false,
  }) {
    final cur = _current;
    if (cur == null || cur.scanId != scanId) return false;
    _current = cur.copyWith(
      phase: BarcodeScanPhase.result,
      outcome: BarcodeScanOutcome.found,
      item: Map<String, dynamic>.from(item),
      fromCache: fromCache,
      clearError: true,
    );
    return true;
  }

  bool completeNotFound(int scanId) {
    final cur = _current;
    if (cur == null || cur.scanId != scanId) return false;
    _current = cur.copyWith(
      phase: BarcodeScanPhase.result,
      outcome: BarcodeScanOutcome.notFound,
      clearItem: true,
      clearError: true,
    );
    return true;
  }

  bool completeError(
    int scanId, {
    required String message,
    BarcodeScanOutcome outcome = BarcodeScanOutcome.networkError,
  }) {
    final cur = _current;
    if (cur == null || cur.scanId != scanId) return false;
    _current = cur.copyWith(
      phase: BarcodeScanPhase.error,
      outcome: outcome,
      errorMessage: message,
      clearItem: true,
    );
    return true;
  }

  void markAction() {
    final cur = _current;
    if (cur == null) return;
    if (cur.phase != BarcodeScanPhase.result &&
        cur.phase != BarcodeScanPhase.error) {
      return;
    }
    _current = cur.copyWith(phase: BarcodeScanPhase.action);
  }

  /// After sheet close / desktop dismiss — ready for next decode without camera restart.
  void readyForNext() {
    final cur = _current;
    if (cur == null) {
      _current = const BarcodeScanSnapshot(
        scanId: 0,
        code: '',
        phase: BarcodeScanPhase.readyForNext,
      );
      return;
    }
    _current = cur.copyWith(
      phase: BarcodeScanPhase.readyForNext,
      clearItem: true,
      clearError: true,
    );
  }

  bool isStale(int scanId) =>
      _current == null || _current!.scanId != scanId;
}
