class BusinessBrief {
  const BusinessBrief({
    required this.id,
    required this.name,
    required this.role,
    this.brandingTitle,
    this.brandingLogoUrl,
  });

  final String id;
  final String name;
  final String role;

  /// Shown in-app instead of [name] when set (per-workspace white-label).
  final String? brandingTitle;
  final String? brandingLogoUrl;

  /// Title for MaterialApp / chrome — not the OS store name.
  String get effectiveDisplayTitle {
    final t = brandingTitle?.trim();
    if (t != null && t.isNotEmpty) return t;
    return name;
  }

  factory BusinessBrief.fromJson(Map<String, dynamic> j) {
    return BusinessBrief(
      id: j['id'].toString(),
      name: j['name'] as String,
      role: j['role'] as String,
      brandingTitle: j['branding_title'] as String?,
      brandingLogoUrl: j['branding_logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
      };
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.businesses,
  });

  final String accessToken;
  final String refreshToken;
  final List<BusinessBrief> businesses;

  BusinessBrief get primaryBusiness => businesses.first;
}
