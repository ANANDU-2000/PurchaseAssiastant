import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

/// Lazily configured [GoogleSignIn] so sign-in and sign-out use the same instance.
GoogleSignIn? _instance;

/// Returns null if [AppConfig.googleOAuthClientId] is not set (release builds should set it for Google).
GoogleSignIn? googleSignInIfConfigured() {
  final id = AppConfig.googleOAuthClientId;
  if (id.isEmpty) return null;
  return _instance ??= GoogleSignIn(
    scopes: const ['email', 'openid', 'profile'],
    serverClientId: id,
    clientId: kIsWeb ? id : null,
  );
}

Future<void> signOutGoogleIfNeeded() async {
  final g = _instance ?? googleSignInIfConfigured();
  if (g == null) return;
  try {
    await g.signOut();
  } catch (_) {}
}
