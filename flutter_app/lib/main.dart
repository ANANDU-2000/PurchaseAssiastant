import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/session_notifier.dart' show sessionProvider;
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/prefs_provider.dart'
    show kNotificationsOptInKey, sharedPreferencesProvider;
import 'core/services/offline_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /home instead of #/home). Requires SPA rewrites (see repo vercel.json).
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  // Do not await Hive / prefs / restore here: on web, flutter_bootstrap.js awaits
  // runApp until this async main() completes — a long wait leaves the HTML "Starting…"
  // overlay up and looks like a frozen white screen.
  runApp(const _HexaBootstrap());
}

class _HexaBootstrap extends StatefulWidget {
  const _HexaBootstrap();

  @override
  State<_HexaBootstrap> createState() => _HexaBootstrapState();
}

class _HexaBootstrapState extends State<_HexaBootstrap> {
  ProviderContainer? _container;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    setState(() => _error = null);

    final cap = kIsWeb ? const Duration(seconds: 15) : const Duration(minutes: 2);

    try {
      await OfflineStore.init().timeout(cap);
      final prefs = await SharedPreferences.getInstance().timeout(cap);
      await LocalNotificationsService.instance.init();
      final notifOptIn = prefs.getBool(kNotificationsOptInKey) ?? false;
      await LocalNotificationsService.instance.setOptIn(notifOptIn);

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

      try {
        await container.read(sessionProvider.notifier).restore().timeout(
              kIsWeb ? const Duration(seconds: 20) : const Duration(seconds: 25),
            );
      } catch (_) {
        // Offline / timeout — splash/login handle retry.
      }

      if (!mounted) return;
      setState(() => _container = container);
    } catch (e, st) {
      assert(() {
        debugPrint('Bootstrap failed: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildHexaTheme(Brightness.light),
        builder: (context, child) {
          removeBootOverlayIfPresent();
          final c = child ?? const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
            child: c,
          );
        },
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kIsWeb
                          ? 'Could not start offline storage. Try a hard refresh or another browser.'
                          : 'Could not start the app.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => unawaited(_prepare()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_container == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildHexaTheme(Brightness.light),
        builder: (context, child) {
          removeBootOverlayIfPresent();
          final c = child ?? const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
            child: c,
          );
        },
        home: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return UncontrolledProviderScope(
      container: _container!,
      child: const HexaApp(),
    );
  }
}
