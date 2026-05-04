import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/utils/trade_purchase_commission.dart';

export 'purchase_draft_provider.dart';

/// Server returns full purchases per page — we prefetch in chunks while the UI
/// caps visible rows (+8 locally) until the next chunk is needed (`loadMore`).
const int ledgerTradeFetchChunk = 24;

const int ledgerTradeVisibleStep = 8;

const Duration ledgerSearchDebounce = Duration(milliseconds: 300);

enum LedgerFlattenKind {
  supplier,
  catalogItem,
  broker,
}

@immutable
class LedgerLineRow {
  const LedgerLineRow({
    required this.stableKey,
    required this.purchaseId,
    this.humanId,
    required this.purchaseDate,
    required this.supplierName,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.kg,
    required this.rateInr,
    this.sellingRateInr,
    required this.amountInr,
    required this.commissionInr,
  });

  final String stableKey;
  final String purchaseId;
  final String? humanId;
  final DateTime purchaseDate;
  final String supplierName;
  final String itemName;
  final double qty;
  final String unit;
  final double kg;
  final double rateInr;
  final double? sellingRateInr;
  final double amountInr;
  final double commissionInr;
}

String ledgerStableRowKey(TradePurchase p, TradePurchaseLine l) {
  if (l.id.isNotEmpty) return '${p.id}|${l.id}';
  final h = Object.hash(
    p.purchaseDate.toIso8601String(),
    p.humanId,
    l.itemName,
    l.qty,
    l.unit,
  );
  return '${p.id}|f_$h';
}

bool _catalogLineMatches(LedgerFlattenKind kind, TradePurchaseLine l, String catalogItemId) {
  if (kind != LedgerFlattenKind.catalogItem) return true;
  final cid = (l.catalogItemId ?? '').trim();
  return cid.isNotEmpty && cid == catalogItemId.trim();
}

LedgerLineRow ledgerRowFromPurchaseLine({
  required TradePurchase p,
  required TradePurchaseLine l,
  required bool allocateCommission,
}) {
  final kg = ledgerTradeLineWeightKg(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    kgPerUnit: l.kgPerUnit,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
  final amount = ledgerLineLandingGross(
    qty: l.qty,
    landingCost: l.landingCost,
    purchaseRate: l.purchaseRate,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    lineTotal: l.lineTotal,
  );
  final rate = ledgerLineDisplayRate(
    qty: l.qty,
    landingCost: l.landingCost,
    purchaseRate: l.purchaseRate,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    lineTotal: l.lineTotal,
  );
  return LedgerLineRow(
    stableKey: ledgerStableRowKey(p, l),
    purchaseId: p.id,
    humanId: p.humanId,
    purchaseDate: p.purchaseDate,
    supplierName: (p.supplierName ?? '').trim(),
    itemName: l.itemName.trim(),
    qty: l.qty,
    unit: l.unit.trim(),
    kg: kg,
    rateInr: rate,
    sellingRateInr: l.sellingRate,
    amountInr: amount,
    commissionInr: allocateCommission ? tradePurchaseLineCommissionInr(p, l) : 0,
  );
}

List<LedgerLineRow> ledgerFlattenPurchasesIntoRows({
  required LedgerFlattenKind kind,
  required String entityId,
  required List<TradePurchase> incoming,
}) {
  final seen = <String>{};
  final out = <LedgerLineRow>[];
  final allocateComm = kind == LedgerFlattenKind.broker;
  for (final p in incoming) {
    for (final l in p.lines) {
      if (!_catalogLineMatches(kind, l, entityId)) continue;
      final key = ledgerStableRowKey(p, l);
      if (!seen.add(key)) continue;
      out.add(
        ledgerRowFromPurchaseLine(
          p: p,
          l: l,
          allocateCommission: allocateComm,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = b.purchaseDate.compareTo(a.purchaseDate);
    return c != 0 ? c : a.stableKey.compareTo(b.stableKey);
  });
  return out;
}

/// Appends flattened rows from [incoming] purchases into [base], dedupe by [stableKey].
List<LedgerLineRow> ledgerAppendFlattenedDedup({
  required List<LedgerLineRow> base,
  required LedgerFlattenKind kind,
  required String entityId,
  required List<TradePurchase> incoming,
}) {
  final seen = <String>{for (final r in base) r.stableKey};
  final add = ledgerFlattenPurchasesIntoRows(kind: kind, entityId: entityId, incoming: incoming);
  final merged = <LedgerLineRow>[...base];
  for (final r in add) {
    if (!seen.contains(r.stableKey)) {
      seen.add(r.stableKey);
      merged.add(r);
    }
  }
  merged.sort((a, b) {
    final c = b.purchaseDate.compareTo(a.purchaseDate);
    return c != 0 ? c : a.stableKey.compareTo(b.stableKey);
  });
  return merged;
}

int ledgerFilteredLength(List<LedgerLineRow> rows, String effectiveQuery) {
  final q = effectiveQuery.trim().toLowerCase();
  if (q.isEmpty) return rows.length;
  var c = 0;
  for (final r in rows) {
    if (r.itemName.toLowerCase().contains(q) ||
        r.supplierName.toLowerCase().contains(q)) {
      c++;
    }
  }
  return c;
}

const _omitError = Object();

@immutable
class LedgerLinesState {
  const LedgerLinesState({
    required this.rows,
    required this.nextApiOffset,
    required this.exhausted,
    required this.loadingInitial,
    required this.loadingMore,
    required this.searchTyping,
    required this.searchEffective,
    required this.visibleCap,
    this.errorMessage,
  });

  factory LedgerLinesState.initial() => const LedgerLinesState(
        rows: [],
        nextApiOffset: 0,
        exhausted: false,
        loadingInitial: true,
        loadingMore: false,
        searchTyping: '',
        searchEffective: '',
        visibleCap: ledgerTradeVisibleStep,
      );

  final List<LedgerLineRow> rows;
  final int nextApiOffset;
  final bool exhausted;

  /// When true, replaces data (first chunk). When loading more chunks, clears first.
  final bool loadingInitial;
  final bool loadingMore;
  final String searchTyping;
  final String searchEffective;
  final int visibleCap;
  final String? errorMessage;

  List<LedgerLineRow> filtered() {
    final q = searchEffective.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return [
      for (final r in rows)
        if (r.itemName.toLowerCase().contains(q) ||
            r.supplierName.toLowerCase().contains(q))
          r,
    ];
  }

  List<LedgerLineRow> visibleRows() {
    final f = filtered();
    if (f.isEmpty) return f;
    final n = visibleCap.clamp(0, f.length);
    return f.sublist(0, n);
  }

  bool get canRevealMoreLocally {
    final f = filtered();
    return visibleCap < f.length;
  }

  /// True when we should fetch the next [`ledgerTradeFetchChunk`] of purchases —
  /// including when cached lines are empty but the server offset is not exhausted yet.
  bool get canRequestMorePurchases =>
      !(exhausted || loadingMore || loadingInitial) && !canRevealMoreLocally;

  LedgerLinesState copyWith({
    List<LedgerLineRow>? rows,
    int? nextApiOffset,
    bool? exhausted,
    bool? loadingInitial,
    bool? loadingMore,
    String? searchTyping,
    String? searchEffective,
    int? visibleCap,
    Object? errorMessage = _omitError,
  }) {
    return LedgerLinesState(
      rows: rows ?? this.rows,
      nextApiOffset: nextApiOffset ?? this.nextApiOffset,
      exhausted: exhausted ?? this.exhausted,
      loadingInitial: loadingInitial ?? this.loadingInitial,
      loadingMore: loadingMore ?? this.loadingMore,
      searchTyping: searchTyping ?? this.searchTyping,
      searchEffective: searchEffective ?? this.searchEffective,
      visibleCap: visibleCap ?? this.visibleCap,
      errorMessage: identical(errorMessage, _omitError)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class LedgerFlattenNotifier extends StateNotifier<LedgerLinesState> {
  LedgerFlattenNotifier(
    Ref ref,
    this.kind,
    this.entityId,
  )       : _ref = ref,
        super(LedgerLinesState.initial()) {
    _revisionSub = _ref.listen<int>(
      businessDataWriteRevisionProvider,
      (previous, next) {
        if (previous != null && next > previous) {
          unawaited(_fetchChunk(resetState: true));
        }
      },
    );
    unawaited(_fetchChunk(resetState: true));
  }

  final Ref _ref;
  final LedgerFlattenKind kind;
  final String entityId;

  late final ProviderSubscription<int> _revisionSub;
  Timer? _debounce;

  Future<void> refresh() async {
    await _fetchChunk(resetState: true);
  }

  /// Raw search typing (debounced into [LedgerLinesState.searchEffective]).
  void setSearchTyping(String raw) {
    state = state.copyWith(searchTyping: raw);
    _debounce?.cancel();
    _debounce = Timer(ledgerSearchDebounce, () {
      final typed = state.searchTyping;
      final eff = typed.trim();
      final fc = ledgerFilteredLength(state.rows, eff);
      final cap =
          fc == 0 ? 0 : min(ledgerTradeVisibleStep, fc);
      state = state.copyWith(searchEffective: eff, visibleCap: cap);
    });
  }

  void loadMore() {
    final f = state.filtered();
    final fc = f.length;
    if (fc > state.visibleCap) {
      final next = min(fc, state.visibleCap + ledgerTradeVisibleStep);
      state = state.copyWith(visibleCap: next);
      return;
    }
    if (state.canRequestMorePurchases) {
      unawaited(_fetchChunk(resetState: false));
    }
  }

  Future<void> _fetchChunk({required bool resetState}) async {
    final session = _ref.read(sessionProvider);
    if (session == null) {
      state = state.copyWith(
        loadingInitial: false,
        loadingMore: false,
        rows: [],
        errorMessage: 'Not signed in',
      );
      return;
    }

    if (resetState) {
      state = LedgerLinesState.initial().copyWith(
        loadingInitial: true,
        searchTyping: state.searchTyping,
        searchEffective: state.searchEffective,
        visibleCap: ledgerTradeVisibleStep,
        rows: [],
      );
    } else if (state.exhausted) {
      return;
    } else {
      state = state.copyWith(loadingMore: true, errorMessage: null);
    }

    try {
      final offset = resetState ? 0 : state.nextApiOffset;
      final rawList = await _ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: ledgerTradeFetchChunk,
            offset: offset,
            status: 'all',
            supplierId: kind == LedgerFlattenKind.supplier ? entityId : null,
            brokerId: kind == LedgerFlattenKind.broker ? entityId : null,
            catalogItemId: kind == LedgerFlattenKind.catalogItem ? entityId : null,
          );

      final purchases = <TradePurchase>[];
      for (final e in rawList) {
        try {
          purchases.add(TradePurchase.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }

      final merged = resetState
          ? ledgerFlattenPurchasesIntoRows(
              kind: kind,
              entityId: entityId,
              incoming: purchases,
            )
          : ledgerAppendFlattenedDedup(
              base: state.rows,
              kind: kind,
              entityId: entityId,
              incoming: purchases,
            );

      final exhausted = rawList.length < ledgerTradeFetchChunk;
      final nextOffset = offset + rawList.length;
      final fc = ledgerFilteredLength(merged, state.searchEffective);
      final cap = resetState
          ? (fc == 0 ? 0 : min(ledgerTradeVisibleStep, fc))
          : (fc == 0
              ? 0
              : min(fc, state.visibleCap + ledgerTradeVisibleStep));

      state = state.copyWith(
        rows: merged,
        nextApiOffset: nextOffset,
        exhausted: exhausted,
        loadingInitial: false,
        loadingMore: false,
        visibleCap: cap,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        loadingInitial: false,
        loadingMore: false,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _revisionSub.close();
    _debounce?.cancel();
    super.dispose();
  }
}

final supplierLedgerLinesProvider =
    StateNotifierProvider.autoDispose.family<LedgerFlattenNotifier, LedgerLinesState, String>(
  (ref, supplierId) => LedgerFlattenNotifier(ref, LedgerFlattenKind.supplier, supplierId),
);

final itemHistoryLinesProvider =
    StateNotifierProvider.autoDispose.family<LedgerFlattenNotifier, LedgerLinesState, String>(
  (ref, catalogItemId) => LedgerFlattenNotifier(ref, LedgerFlattenKind.catalogItem, catalogItemId),
);

final brokerHistoryLinesProvider =
    StateNotifierProvider.autoDispose.family<LedgerFlattenNotifier, LedgerLinesState, String>(
  (ref, brokerId) => LedgerFlattenNotifier(ref, LedgerFlattenKind.broker, brokerId),
);
