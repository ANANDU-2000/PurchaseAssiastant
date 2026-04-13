import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/tenant_branding_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

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
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(),
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
    );
  }
}
