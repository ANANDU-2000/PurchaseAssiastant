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
    return MaterialApp.router(
      title: title,
      theme: buildHexaTheme(Brightness.light),
      darkTheme: buildHexaTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
