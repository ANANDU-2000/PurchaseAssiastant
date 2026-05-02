import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/post_login_notification_prompt.dart';
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/api_degraded_provider.dart';
import 'core/providers/tenant_branding_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';

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
        final shell = banner != null && banner.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                banner,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () =>
                                  ref.read(apiDegradedProvider.notifier).clear(),
                              tooltip: 'Dismiss',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: body),
                ],
              )
            : body;
        return DecoratedBox(
          decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
          child: PostLoginNotificationPrompt(child: shell),
        );
      },
      scrollBehavior: _HexaScrollBehavior(),
    );
  }
}
