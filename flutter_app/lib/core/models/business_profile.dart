import 'session.dart';

/// Workspace identity shown on purchase invoice PDFs.
class BusinessProfile {
  const BusinessProfile({
    required this.legalName,
    required this.displayTitle,
    this.gstNumber,
    this.address,
    this.phone,
    this.logoUrl,
  });

  final String legalName;
  final String displayTitle;
  final String? gstNumber;
  final String? address;
  final String? phone;
  final String? logoUrl;

  static String? _trimOrNull(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  factory BusinessProfile.fromBusinessBrief(BusinessBrief b) {
    return BusinessProfile(
      legalName: b.name,
      displayTitle: b.effectiveDisplayTitle,
      gstNumber: _trimOrNull(b.gstNumber),
      address: _trimOrNull(b.address),
      phone: _trimOrNull(b.phone),
      logoUrl: _trimOrNull(b.brandingLogoUrl),
    );
  }
}
