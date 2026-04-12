import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../config/app_config.dart';

/// In-app title (MaterialApp, task switcher on some platforms). Per-workspace when signed in.
final tenantAppTitleProvider = Provider<String>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null || s.businesses.isEmpty) return AppConfig.appName;
  return s.primaryBusiness.effectiveDisplayTitle;
});

/// Optional HTTPS logo for AppBar / settings (per workspace).
final tenantLogoUrlProvider = Provider<String?>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null || s.businesses.isEmpty) return null;
  final u = s.primaryBusiness.brandingLogoUrl?.trim();
  if (u == null || u.isEmpty) return null;
  return u;
});
