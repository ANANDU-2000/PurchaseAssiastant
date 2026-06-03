/// India + Gulf accounts-staff WhatsApp numbers for wa.me and API storage.
library;

/// Normalized phone for accounts WhatsApp sharing and persistence.
class NormalizedAccountsWhatsappPhone {
  const NormalizedAccountsWhatsappPhone({
    required this.waMeDigits,
    required this.storageDigits,
  });

  /// Full digits for `https://wa.me/{waMeDigits}` (includes country code).
  final String waMeDigits;

  /// Value stored in `accounts_whatsapp_number` (India: 10 digits; Gulf: full intl).
  final String storageDigits;
}

const _gulfCountryNationalLength = <String, int>{
  '971': 9, // UAE
  '968': 8, // Oman
  '965': 8, // Kuwait
  '974': 8, // Qatar
};

String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

bool _isIndiaMobile10(String digits) =>
    digits.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(digits);

NormalizedAccountsWhatsappPhone? _fromIndiaDigits(String national10) {
  if (!_isIndiaMobile10(national10)) return null;
  return NormalizedAccountsWhatsappPhone(
    waMeDigits: '91$national10',
    storageDigits: national10,
  );
}

NormalizedAccountsWhatsappPhone? _fromGulfFull(String digits) {
  for (final entry in _gulfCountryNationalLength.entries) {
    final cc = entry.key;
    final nationalLen = entry.value;
    if (!digits.startsWith(cc)) continue;
    final national = digits.substring(cc.length);
    if (national.length != nationalLen) continue;
    if (!RegExp(r'^\d+$').hasMatch(national)) continue;
    return NormalizedAccountsWhatsappPhone(
      waMeDigits: digits,
      storageDigits: digits,
    );
  }
  return null;
}

/// UAE local mobile without country code (9 digits, typically starts with 5).
NormalizedAccountsWhatsappPhone? normalizeGulfMobile(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final digits = _digitsOnly(t);
  if (digits.isEmpty) return null;

  final full = _fromGulfFull(digits);
  if (full != null) return full;

  if (digits.length == 9 && digits.startsWith('5')) {
    final intl = '971$digits';
    return NormalizedAccountsWhatsappPhone(
      waMeDigits: intl,
      storageDigits: intl,
    );
  }
  return null;
}

/// India mobile: 10 digits; strips +91 when 12 digits present.
String? normalizeIndiaMobile10(String? raw) {
  final n = normalizeAccountsWhatsappPhone(raw);
  if (n == null) return null;
  if (n.storageDigits.length == 10 && _isIndiaMobile10(n.storageDigits)) {
    return n.storageDigits;
  }
  return null;
}

/// Unified normalizer for India and Gulf (UAE, Oman, Kuwait, Qatar).
NormalizedAccountsWhatsappPhone? normalizeAccountsWhatsappPhone(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  var digits = _digitsOnly(t);
  if (digits.isEmpty) return null;

  final gulf = _fromGulfFull(digits);
  if (gulf != null) return gulf;

  final gulfLocal = normalizeGulfMobile(t);
  if (gulfLocal != null) return gulfLocal;

  if (digits.startsWith('91') && digits.length == 12) {
    digits = digits.substring(2);
  }
  return _fromIndiaDigits(digits);
}

/// Reconstruct [NormalizedAccountsWhatsappPhone] from stored API value.
NormalizedAccountsWhatsappPhone? normalizedFromStoredAccountsWhatsapp(
  String? stored,
) {
  if (stored == null) return null;
  final t = stored.trim();
  if (t.isEmpty) return null;
  final digits = _digitsOnly(t);
  if (digits.isEmpty) return null;

  final gulf = _fromGulfFull(digits);
  if (gulf != null) return gulf;

  if (_isIndiaMobile10(digits)) {
    return NormalizedAccountsWhatsappPhone(
      waMeDigits: '91$digits',
      storageDigits: digits,
    );
  }

  return normalizeAccountsWhatsappPhone(t);
}

bool isValidAccountsWhatsappInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  return normalizeAccountsWhatsappPhone(t) != null;
}

String? storageDigitsForAccountsWhatsappInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return normalizeAccountsWhatsappPhone(t)?.storageDigits;
}
