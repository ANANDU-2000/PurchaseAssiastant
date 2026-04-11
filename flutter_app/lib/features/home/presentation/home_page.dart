import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../entries/presentation/entry_create_sheet.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  String _inr(num n) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

  static Future<void> _mediaVoiceSnack(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref.read(hexaApiProvider).mediaVoicePreview(businessId: session.primaryBusiness.id);
      if (!context.mounted) return;
      final note = r['note']?.toString() ?? 'Voice preview';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice preview: $e')));
      }
    }
  }

  static Future<void> _mediaOcrSnack(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref.read(hexaApiProvider).mediaOcrPreview(businessId: session.primaryBusiness.id);
      if (!context.mounted) return;
      final note = r['note']?.toString() ?? 'OCR preview';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR preview: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dash = ref.watch(dashboardProvider);
    final insights = ref.watch(homeInsightsProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.12),
                    cs.surface,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Purchase clarity at a glance',
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverToBoxAdapter(
              child: dash.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Could not load dashboard', style: tt.titleSmall),
                        const SizedBox(height: 8),
                        Text(e.toString(), style: tt.bodySmall?.copyWith(color: cs.error)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => ref.invalidate(dashboardProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (d) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroProfitCard(
                      cs: cs,
                      tt: tt,
                      profitText: _inr(d.totalProfit),
                      subtitle: 'This month · live from API',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _MiniStat(label: 'Purchase', value: _inr(d.totalPurchase), cs: cs, tt: tt)),
                        const SizedBox(width: 12),
                        Expanded(child: _MiniStat(label: 'Purchases', value: d.purchaseCount.toString(), cs: cs, tt: tt)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            label: 'Qty (base)',
                            value: d.totalQtyBase.toStringAsFixed(1),
                            cs: cs,
                            tt: tt,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniStat(
                            label: 'Alerts',
                            value: insights.maybeWhen(
                              data: (hi) => hi.alertCount.toString(),
                              orElse: () => '—',
                            ),
                            cs: cs,
                            tt: tt,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    insights.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (hi) {
                        if (hi.topItem == null && hi.alerts.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (hi.topItem != null)
                              Card(
                                child: ListTile(
                                  leading: Icon(Icons.emoji_events_outlined, color: cs.primary),
                                  title: Text('Top item · ${hi.topItem}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('Profit this month · ${_inr(hi.topItemProfit ?? 0)}'),
                                ),
                              ),
                            ...hi.alerts.map(
                              (a) => Card(
                                color: cs.errorContainer.withValues(alpha: 0.35),
                                child: ListTile(
                                  leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                                  title: Text(a['message']?.toString() ?? 'Alert', style: tt.bodyMedium),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text('Quick actions', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _QuickActions(
                      cs: cs,
                      onQuickEntry: () => showEntryCreateSheet(context),
                      onVoice: () => unawaited(_mediaVoiceSnack(context, ref)),
                      onScan: () => unawaited(_mediaOcrSnack(context, ref)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroProfitCard extends StatelessWidget {
  const _HeroProfitCard({
    required this.cs,
    required this.tt,
    required this.profitText,
    required this.subtitle,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final String profitText;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, const Color(0xFF0E7490), 0.35)!],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: cs.onPrimary.withValues(alpha: 0.95)),
                const SizedBox(width: 8),
                Text(
                  'Total profit',
                  style: tt.labelLarge?.copyWith(
                    color: cs.onPrimary.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              profitText,
              style: tt.headlineLarge?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.cs, required this.tt});

  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.cs,
    required this.onQuickEntry,
    required this.onVoice,
    required this.onScan,
  });

  final ColorScheme cs;
  final VoidCallback onQuickEntry;
  final VoidCallback onVoice;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onQuickEntry,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Quick entry'),
        ),
        OutlinedButton.icon(
          onPressed: onVoice,
          icon: Icon(Icons.mic_none_rounded, size: 20, color: cs.primary),
          label: const Text('Voice'),
        ),
        OutlinedButton.icon(
          onPressed: onScan,
          icon: Icon(Icons.document_scanner_outlined, size: 20, color: cs.primary),
          label: const Text('Scan bill'),
        ),
      ],
    );
  }
}
