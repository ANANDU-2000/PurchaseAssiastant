import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'core/notifications/post_login_notification_prompt.dart';
import 'core/providers/reports_provider.dart';
import 'core/providers/analytics_kpi_provider.dart';
import 'features/reports/reports_prefs.dart';
import 'core/reporting/trade_report_aggregate.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/api_degraded_provider.dart';
import 'core/providers/tenant_branding_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';

String _n0(double v) =>
    (v - v.roundToDouble()).abs() < 1e-6 ? '${v.round()}' : v.toStringAsFixed(1);

String _qtyLine(TradeReportTotals t) {
  final p = <String>[];
  if (t.kg > 1e-9) p.add('${_n0(t.kg)} KG');
  if (t.bags > 1e-9) p.add('${_n0(t.bags)} BAGS');
  if (t.boxes > 1e-9) p.add('${_n0(t.boxes)} BOX');
  if (t.tins > 1e-9) p.add('${_n0(t.tins)} TIN');
  return p.join(' • ');
}

class _NotificationTapHandler extends ConsumerStatefulWidget {
  const _NotificationTapHandler({required this.child});
  final Widget child;

  @override
  ConsumerState<_NotificationTapHandler> createState() =>
      _NotificationTapHandlerState();
}

class _NotificationTapHandlerState extends ConsumerState<_NotificationTapHandler> {
  StreamSubscription<String>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = LocalNotificationsService.instance.payloadStream.listen((payload) {
      if (payload.trim() == 'whatsapp_report') {
        _onWhatsAppReportTapped();
      }
    });
  }

  Future<void> _onWhatsAppReportTapped() async {
    if (_busy) return;
    _busy = true;
    try {
      final enabled = await ReportsPrefs.getScheduleEnabled();
      final phone = await ReportsPrefs.getSchedulePhone();
      final type = await ReportsPrefs.getScheduleType();
      if (!enabled || phone.trim().isEmpty) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = switch (type) {
        'daily' => (today, today),
        'monthly' => (today.subtract(const Duration(days: 29)), today),
        _ => (today.subtract(const Duration(days: 6)), today),
      };

      ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
      ref.invalidate(reportsPurchasesPayloadProvider);
      await ref.read(reportsPurchasesPayloadProvider.future);
      final purchases = ref.read(reportsPurchasesMergedProvider);
      final agg = buildTradeReportAgg(purchases);

      final df = DateFormat('d MMM');
      final t = agg.totals;
      final parts = <String>[
        'Purchase Report (${df.format(from)} → ${df.format(to)})',
        '',
        'Total: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(t.inr)}',
        _qtyLine(t),
      ]..removeWhere((e) => e.trim().isEmpty);

      final msg = Uri.encodeComponent(parts.join('\n'));
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final uri = Uri.parse('https://wa.me/$digits?text=$msg');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ignore: best-effort convenience entrypoint.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HexaScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class HexaApp extends ConsumerWidget {
  const HexaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final title = ref.watch(tenantAppTitleProvider);
    // Harisree: light iOS-style surfaces only (gray / white / teal) — no dark mode in product UI.
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: title,
      theme: buildHexaTheme(Brightness.light),
      darkTheme: buildHexaTheme(Brightness.light),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        removeBootOverlayIfPresent();
        final body = child ?? const SizedBox.shrink();
        final banner = ref.watch(apiDegradedProvider);
        // Stack (not Column+Expanded): [MaterialApp.router] builder can get unbounded
        // height on web; Expanded would overflow. Overlay for tooltips lives under
        // [Navigator]/[child]; keep dismiss control without Tooltip (no Overlay ancestor).
        final shell = banner != null && banner.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  body,
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      elevation: 1,
                      color: const Color(0xFFFFF8E1),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  banner,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Semantics(
                                label: 'Dismiss connection warning',
                                button: true,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: null,
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () => ref
                                      .read(apiDegradedProvider.notifier)
                                      .clear(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : body;
        return DecoratedBox(
          decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
          child: _NotificationTapHandler(
            child: PostLoginNotificationPrompt(child: shell),
          ),
        );
      },
      scrollBehavior: _HexaScrollBehavior(),
    );
  }
}
