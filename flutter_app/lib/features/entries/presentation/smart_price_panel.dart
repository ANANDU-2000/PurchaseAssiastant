import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';

/// Landing or selling intelligence: range bar, avg/last/trend, supplier compare.
class SmartPricePanel extends ConsumerStatefulWidget {
  const SmartPricePanel({
    super.key,
    required this.item,
    required this.qty,
    required this.priceController,
    required this.metric,
    this.compact = false,
    this.onInsight,

    /// When [metric] is `landing`, pass landed cost here so the API compares apples to apples (history is landed cost).
    this.currentPriceResolver,
  });

  final TextEditingController item;
  final TextEditingController qty;
  final TextEditingController priceController;

  /// API `price_field`: landing | selling
  final String metric;
  final bool compact;

  /// Fired when price intelligence payload updates (or clears).
  final void Function(Map<String, dynamic>? pip)? onInsight;

  /// Optional override for the numeric price sent as `current_price` (defaults to parsing [priceController]).
  final double? Function()? currentPriceResolver;

  @override
  ConsumerState<SmartPricePanel> createState() => _SmartPricePanelState();
}

class _SmartPricePanelState extends ConsumerState<SmartPricePanel> {
  Timer? _debounce;
  Map<String, dynamic>? _pip;
  bool _loading = false;
  bool _expanded = false;

  /// Last `currentPriceResolver` value we reacted to — avoids re-scheduling on every parent `setState`.
  double? _lastResolverSnapshot;

  @override
  void initState() {
    super.initState();
    widget.item.addListener(_schedule);
    widget.qty.addListener(_schedule);
    widget.priceController.addListener(_schedule);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.item.removeListener(_schedule);
    widget.qty.removeListener(_schedule);
    widget.priceController.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didUpdateWidget(SmartPricePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent rebuilds on every keystroke in the entry form. Only re-fetch when the resolved
    // landed price actually changes (e.g. purchase field or entry-level commission).
    if (widget.currentPriceResolver == null) return;
    final v = widget.currentPriceResolver!.call();
    if (v == null || v <= 0) {
      _lastResolverSnapshot = null;
      return;
    }
    final last = _lastResolverSnapshot;
    if (last != null && (v - last).abs() < 0.005) return;
    _lastResolverSnapshot = v;
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _fetch);
  }

  Future<void> _fetch() async {
    final name = widget.item.text.trim();
    final price = widget.currentPriceResolver?.call() ??
        double.tryParse(widget.priceController.text.trim());
    final q = double.tryParse(widget.qty.text.trim());
    if (name.length < 2 || price == null || price <= 0 || q == null || q <= 0) {
      if (mounted) {
        setState(() => _pip = null);
        widget.onInsight?.call(null);
      }
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _loading = true);
    try {
      final pip = await ref.read(hexaApiProvider).priceIntelligence(
            businessId: session.primaryBusiness.id,
            item: name,
            currentPrice: price,
            priceField: widget.metric,
          );
      if (mounted) {
        setState(() => _pip = pip);
        widget.onInsight?.call(pip);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pip = null);
        widget.onInsight?.call(null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title =
        widget.metric == 'landing' ? 'Landing insight' : 'Selling insight';

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2, color: cs.primary),
      );
    }
    final p = _pip;
    if (p == null ||
        (p['confidence'] is num && (p['confidence'] as num) <= 0)) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'No history yet — your first price builds the baseline.',
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final avg = p['avg'];
    final low = p['low'];
    final high = p['high'];
    final last = p['last_price'];
    final trend = p['trend']?.toString() ?? 'flat';
    final pos = p['position_pct'];
    final freq = p['frequency'];
    final hints = p['decision_hints'];
    final suppliers = (p['supplier_compare'] as List<dynamic>?) ?? [];

    final cur = double.tryParse(widget.priceController.text.trim());
    Widget rangeBar = const SizedBox.shrink();
    if (avg is num && low is num && high is num && high > low && cur != null) {
      final t = (cur - low) / (high - low);
      final clamped = t.clamp(0.0, 1.0);
      rangeBar = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${low.toStringAsFixed(0)}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                Text('₹${high.toStringAsFixed(0)}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (ctx, c) {
                final w = c.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [cs.primaryContainer, cs.tertiaryContainer],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (w - 12) * clamped,
                      top: -2,
                      child: Icon(Icons.circle, size: 12, color: cs.primary),
                    ),
                  ],
                );
              },
            ),
            if (pos is num)
              Text(
                'vs range: ${pos.toStringAsFixed(0)}% · Avg ₹${avg.toStringAsFixed(2)}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      );
    }

    final trendIcon = trend == 'up'
        ? Icons.trending_up_rounded
        : trend == 'down'
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    final body = Card(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(title,
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            if (!widget.compact) rangeBar,
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _chip(tt, 'Avg',
                    avg is num ? '₹${avg.toStringAsFixed(2)}' : '—', cs),
                _chip(tt, 'Last',
                    last is num ? '₹${last.toStringAsFixed(2)}' : '—', cs),
                _chip(tt, 'Times', freq is int ? '$freq' : '—', cs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(trendIcon, size: 16, color: cs.tertiary),
                    const SizedBox(width: 4),
                    Text(trend, style: tt.labelMedium),
                  ],
                ),
              ],
            ),
            if (hints is List && hints.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...hints.take(3).map(
                    (hint) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notifications_active_outlined,
                              size: 16, color: cs.tertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('$hint', style: tt.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (suppliers.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded
                      ? 'Hide supplier prices'
                      : 'Supplier-wise avg (${suppliers.length})'),
                ),
              ),
            if (_expanded && suppliers.isNotEmpty)
              ...suppliers.take(5).map(
                (s) {
                  if (s is! Map) return const SizedBox.shrink();
                  final m = Map<String, dynamic>.from(s);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${m['name']}: ₹${(m['avg_landing'] as num?)?.toStringAsFixed(2) ?? '—'}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    if (widget.compact) {
      return body;
    }
    return Padding(padding: const EdgeInsets.only(top: 8), child: body);
  }

  Widget _chip(TextTheme tt, String k, String v, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text('$k: $v',
          style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
