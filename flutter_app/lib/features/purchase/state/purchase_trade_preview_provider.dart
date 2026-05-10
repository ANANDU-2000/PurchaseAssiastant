import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/feature_flags.dart';
import '../../../core/strict_decimal.dart';
import 'purchase_draft_provider.dart';

/// Debounced `POST …/trade-purchases/preview-lines` snapshot for the wizard.
///
/// On failure or when [kUseServerTradePurchasePreview] is false, state is
/// `AsyncData(null)` so callers fall back to local [computePurchaseTotals].
final tradePurchasePreviewProvider = NotifierProvider.autoDispose<
    TradePurchasePreviewNotifier, AsyncValue<Map<String, dynamic>?>>(
  TradePurchasePreviewNotifier.new,
);

class TradePurchasePreviewNotifier
    extends AutoDisposeNotifier<AsyncValue<Map<String, dynamic>?>> {
  Timer? _debounce;

  @override
  AsyncValue<Map<String, dynamic>?> build() {
    ref.listen(
      purchaseDraftProvider,
      (_, __) => _schedule(),
      fireImmediately: true,
    );
    ref.onDispose(() => _debounce?.cancel());
    return const AsyncValue.data(null);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      unawaited(_fetch());
    });
  }

  Future<void> _fetch() async {
    if (!kUseServerTradePurchasePreview) {
      state = const AsyncValue.data(null);
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      state = const AsyncValue.data(null);
      return;
    }
    final draft = ref.read(purchaseDraftProvider);
    if (draft.lines.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final api = ref.read(hexaApiProvider);
      final body =
          ref.read(purchaseDraftProvider.notifier).buildTradePurchasePreviewBody();
      final m = await api.previewTradePurchaseLines(
        businessId: session.primaryBusiness.id,
        body: body,
      );
      state = AsyncValue.data(m);
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }
}

/// Parsed `lines[i].line_total` from [tradePurchasePreviewProvider], or null.
double? tradePreviewLineTotal(AsyncValue<Map<String, dynamic>?> snap, int lineIndex) {
  final map = snap.asData?.value;
  if (map == null) return null;
  final rawLines = map['lines'];
  if (rawLines is! List || lineIndex < 0 || lineIndex >= rawLines.length) {
    return null;
  }
  final row = rawLines[lineIndex];
  if (row is! Map) return null;
  final t = row['line_total'];
  if (t == null) return null;
  return StrictDecimal.fromObject(t).toDouble();
}

/// Sum of preview line totals (pre-header-discount line money), or null.
double? tradePreviewSumLineTotals(AsyncValue<Map<String, dynamic>?> snap) {
  final map = snap.asData?.value;
  if (map == null) return null;
  final rawLines = map['lines'];
  if (rawLines is! List || rawLines.isEmpty) return null;
  var s = 0.0;
  for (final row in rawLines) {
    if (row is! Map) return null;
    final t = row['line_total'];
    if (t == null) return null;
    s += StrictDecimal.fromObject(t).toDouble();
  }
  return s;
}
