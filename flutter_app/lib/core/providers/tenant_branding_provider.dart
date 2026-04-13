import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../config/app_config.dart';

/// Single watch for AppBar branding (avoids duplicate session reads on home).
class TenantBranding {
  const TenantBranding({required this.title, this.logoUrl});

  final String title;
  final String? logoUrl;
}

final tenantBrandingProvider = Provider<TenantBranding>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null || s.businesses.isEmpty) {
    return const TenantBranding(title: AppConfig.appName, logoUrl: null);
  }
  final b = s.primaryBusiness;
  final u = b.brandingLogoUrl?.trim();
  return TenantBranding(
    title: b.effectiveDisplayTitle,
    logoUrl: (u == null || u.isEmpty) ? null : u,
  );
});

/// In-app title (MaterialApp, task switcher on some platforms). Per-workspace when signed in.
final tenantAppTitleProvider = Provider<String>(
    (ref) => ref.watch(tenantBrandingProvider).title);

/// Optional HTTPS logo for AppBar / settings (per workspace).
final tenantLogoUrlProvider = Provider<String?>(
    (ref) => ref.watch(tenantBrandingProvider).logoUrl);
