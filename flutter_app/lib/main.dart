import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/session_notifier.dart';
import 'core/providers/prefs_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // Restore session before any route builds so /#/entries refresh keeps you signed in.
  await container.read(sessionProvider.notifier).restore();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HexaApp(),
    ),
  );
}
