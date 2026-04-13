import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/session_notifier.dart' show sessionProvider;
import 'core/services/offline_store.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/providers/prefs_provider.dart'
    show kNotificationsOptInKey, sharedPreferencesProvider;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OfflineStore.init();
  final prefs = await SharedPreferences.getInstance();
  await LocalNotificationsService.instance.init();
  final notifOptIn = prefs.getBool(kNotificationsOptInKey) ?? false;
  await LocalNotificationsService.instance.setOptIn(notifOptIn);
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // Restore session before routes; cap wait on web so a slow/unreachable API never blocks runApp (blank screen).
  try {
    await container.read(sessionProvider.notifier).restore().timeout(
        kIsWeb ? const Duration(seconds: 4) : const Duration(seconds: 25));
  } catch (_) {
    // Offline / timeout — app still mounts; splash/login flows handle retry.
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HexaApp(),
    ),
  );
}
