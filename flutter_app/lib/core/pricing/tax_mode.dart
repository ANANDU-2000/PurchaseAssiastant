/// How GST applies to the entered purchase rate for preview + [computeTradeTotals].
enum TaxMode {
  /// Tax is added on top of the taxable line base (default / backend-aligned).
  exclusive,

  /// Entered line amounts are tax-inclusive; GST is backed out for display.
  inclusive,

  /// No GST on the line (tax_percent forced to 0 on save when used alone).
  none,
}

TaxMode? taxModeFromWire(String? raw) {
  final s = raw?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  if (s == 'inclusive') return TaxMode.inclusive;
  if (s == 'exclusive') return TaxMode.exclusive;
  if (s == 'none') return TaxMode.none;
  return null;
}

String taxModeToWire(TaxMode m) => switch (m) {
      TaxMode.exclusive => 'exclusive',
      TaxMode.inclusive => 'inclusive',
      TaxMode.none => 'none',
    };
