class BusinessBrief {
  const BusinessBrief({
    required this.id,
    required this.name,
    required this.role,
    this.brandingTitle,
    this.brandingLogoUrl,
    this.gstNumber,
    this.address,
    this.phone,
    this.contactEmail,
  });

  final String id;
  final String name;
  final String role;

  /// Shown in-app instead of [name] when set (per-workspace white-label).
  final String? brandingTitle;
  final String? brandingLogoUrl;

  /// Invoice / legal header (GSTIN).
  final String? gstNumber;
  final String? address;
  final String? phone;
  /// Purchase order / contact (optional).
  final String? contactEmail;

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
      gstNumber: j['gst_number'] as String?,
      address: j['address'] as String?,
      phone: j['phone'] as String?,
      contactEmail: j['contact_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (contactEmail != null) 'contact_email': contactEmail,
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
