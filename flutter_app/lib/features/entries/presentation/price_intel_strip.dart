import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';

/// Debounced Price Intelligence hint for the first line (parse-only backend; no auto-save).
class PriceIntelStrip extends ConsumerStatefulWidget {
  const PriceIntelStrip({
    super.key,
    required this.item,
    required this.qty,
    required this.landing,
  });

  final TextEditingController item;
  final TextEditingController qty;
  final TextEditingController landing;

  @override
  ConsumerState<PriceIntelStrip> createState() => _PriceIntelStripState();
}

class _PriceIntelStripState extends ConsumerState<PriceIntelStrip> {
  Timer? _debounce;
  Map<String, dynamic>? _pip;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.item.addListener(_schedule);
    widget.qty.addListener(_schedule);
    widget.landing.addListener(_schedule);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.item.removeListener(_schedule);
    widget.qty.removeListener(_schedule);
    widget.landing.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), _fetch);
  }

  Future<void> _fetch() async {
    final name = widget.item.text.trim();
    final land = double.tryParse(widget.landing.text.trim());
    final q = double.tryParse(widget.qty.text.trim());
    if (name.length < 2 || land == null || land <= 0 || q == null || q <= 0) {
      if (mounted) setState(() => _pip = null);
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _loading = true;
    });
    try {
      final pip = await ref.read(hexaApiProvider).priceIntelligence(
            businessId: session.primaryBusiness.id,
            item: name,
            currentPrice: land,
          );
      if (mounted) setState(() => _pip = pip);
    } catch (_) {
      if (mounted) setState(() => _pip = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2, color: cs.primary),
      );
    }
    final p = _pip;
    if (p == null || (p['confidence'] is num && (p['confidence'] as num) <= 0)) {
      return const SizedBox.shrink();
    }
    final avg = p['avg'];
    final trend = p['trend']?.toString() ?? '—';
    final conf = p['confidence'];
    final hints = p['decision_hints'];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Price intelligence', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Avg landing: ${avg is num ? '₹${avg.toStringAsFixed(2)}' : '—'} · Trend: $trend · Confidence: ${conf is num ? (conf * 100).toStringAsFixed(0) : '—'}%'),
              if (hints is List && hints.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(hints.take(3).map((e) => e.toString()).join(' '), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 4),
              Text('Based on your history only — landing cost stays what you enter.', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
