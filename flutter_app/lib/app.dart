import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'core/notifications/post_login_notification_prompt.dart';
import 'core/platform/launcher_quick_actions.dart';
import 'core/platform/app_foreground_listener.dart';
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/api_degraded_provider.dart';
import 'core/providers/home_breakdown_tab_providers.dart';
import 'core/providers/home_dashboard_provider.dart';
import 'core/providers/reports_provider.dart';
import 'core/auth/session_notifier.dart';
import 'core/config/app_config.dart';
import 'core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches, tradePurchasesListProvider;
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';
import 'core/widgets/hexa_page_error_boundary.dart';

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

/// Binds launcher shortcuts to [appRouterProvider] on first frame so cold starts
/// from a home-screen action work before [ShellScreen] exists.
class _LauncherShortcutsBootstrap extends ConsumerStatefulWidget {
  const _LauncherShortcutsBootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_LauncherShortcutsBootstrap> createState() =>
      _LauncherShortcutsBootstrapState();
}

class _LauncherShortcutsBootstrapState
    extends ConsumerState<_LauncherShortcutsBootstrap> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bindLauncherShortcutsRouter(ref.read(appRouterProvider));
      unawaited(setupLauncherQuickActions());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Heuristic: transient layout / lifecycle issues should not replace the entire app.
bool _hexaFlutterErrorLikelyNonFatal(FlutterErrorDetails details) =>
    hexaErrorLikelyNonFatal(details);

/// Catches framework errors so the web build can show recovery UI instead of a blank screen.
class _HexaErrorBoundary extends StatefulWidget {
  const _HexaErrorBoundary({
    required this.child,
    required this.onGoHome,
  });

  final Widget child;
  final VoidCallback onGoHome;

  @override
  State<_HexaErrorBoundary> createState() => _HexaErrorBoundaryState();
}

class _HexaErrorBoundaryState extends State<_HexaErrorBoundary> {
  Object? _error;
  void Function(FlutterErrorDetails)? _previousOnError;

  /// Web PWA: per-page [FriendlyLoadError] handles API failures; a global hook
  /// turns transient provider/async faults into "Could not load the app".
  bool get _useGlobalErrorHook => !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!_useGlobalErrorHook) return;
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _previousOnError?.call(details);
      if (!mounted) return;
      if (_hexaFlutterErrorLikelyNonFatal(details)) {
        FlutterError.dumpErrorToConsole(details);
        return;
      }
      // Never call setState from inside another widget's build / focus callbacks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _error = details.exception);
      });
    };
  }

  @override
  void dispose() {
    if (_useGlobalErrorHook) {
      FlutterError.onError = _previousOnError;
    }
    super.dispose();
  }

  void _clearError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _error = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_useGlobalErrorHook || _error == null) {
      return widget.child;
    }
    return Material(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Could not load the app. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (kDebugMode && _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error.toString().split('\n').first,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _clearError,
                      child: const Text('Retry'),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        _clearError();
                        widget.onGoHome();
                      },
                      child: const Text('Go to Home'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _RouterBootPlaceholder extends StatelessWidget {
  const _RouterBootPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HexaColors.brandBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              HexaColors.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary,
                  ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class HexaApp extends ConsumerWidget {
  const HexaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final session = ref.watch(sessionProvider);
    final title = session?.primaryBusiness.effectiveDisplayTitle ??
        AppConfig.appName;
    // Harisree: light iOS-style surfaces only (gray / white / teal) — no dark mode in product UI.
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: title,
      theme: buildHexaTheme(Brightness.light),
      darkTheme: buildHexaTheme(Brightness.light),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        final routed = child != null
            ? SizedBox.expand(child: child)
            : const SizedBox.expand(child: _RouterBootPlaceholder());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          removeBootOverlayIfPresent();
        });
        // Web: the router [child] can lay out with zero intrinsic height unless we
        // force it to fill the viewport — otherwise the shell / Home body stays blank
        // while the bottom bar (sibling scaffold) still paints.
        final body = routed;
        final banner = ref.watch(apiDegradedProvider);
        // Stack (not Column+Expanded): [MaterialApp.router] builder can get unbounded
        // height on web; Expanded would overflow. Overlay for tooltips lives under
        // [Navigator]/[child]; keep dismiss control without Tooltip (no Overlay ancestor).
        final shell = banner != null && banner.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: body),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      elevation: 0,
                      color: const Color(0xFFE8F4F2),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_queue_rounded,
                                size: 20,
                                color: HexaColors.brandPrimary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  banner,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: const Color(0xFF1C1917),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        height: 1.25,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!context.mounted) return;
                                    ref.invalidate(homeDashboardDataProvider);
                                    ref.invalidate(homeShellReportsProvider);
                                    invalidateTradePurchaseCaches(ref);
                                    ref.invalidate(tradePurchasesListProvider);
                                    ref.invalidate(reportsPurchasesPayloadProvider);
                                  });
                                },
                                child: const Text('Retry'),
                              ),
                              Semantics(
                                label: 'Dismiss connection notice',
                                button: true,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  // No [tooltip]: this subtree is a sibling of the router
                                  // [Navigator] in the builder Stack — tooltips need an Overlay.
                                  icon: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!context.mounted) return;
                                      ref
                                          .read(apiDegradedProvider.notifier)
                                          .clear();
                                    });
                                  },
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
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
            child: _HexaErrorBoundary(
              onGoHome: () => ref.read(appRouterProvider).go('/home'),
              child: AppForegroundListener(
                child: _LauncherShortcutsBootstrap(
                  child: PostLoginNotificationPrompt(child: shell),
                ),
              ),
            ),
          ),
        );
      },
      scrollBehavior: _HexaScrollBehavior(),
    );
  }
}
