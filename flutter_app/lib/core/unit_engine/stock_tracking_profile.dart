// Client mirror of backend stock-tracking modes (packaging type SSOT).

class StockTrackingMode {
  StockTrackingMode._();

  static const wholesaleBag = 'wholesale_bag';
  static const retailPacket = 'retail_packet';
  static const looseKg = 'loose_kg';
  static const box = 'box';
  static const tin = 'tin';
  static const piece = 'piece';

  /// Five warehouse units shown on create/edit pickers.
  static const pickerModes = [
    looseKg,
    wholesaleBag,
    box,
    tin,
    piece,
  ];

  static final _kgInName =
      RegExp(r'(\d+(?:\.\d+)?)\s*KG\b', caseSensitive: false);

  static const _wholesaleKgSizes = {25, 30, 35, 40, 45, 50, 55};

  /// Parse kg weight token from item name (e.g. SUGAR 50KG → 50).
  static double? parseKgFromName(String rawName) {
    final m = _kgInName.firstMatch(rawName.trim());
    if (m == null) return null;
    final v = double.tryParse(m.group(1) ?? '');
    if (v == null || v <= 0 || !v.isFinite) return null;
    return v;
  }

  /// Silent local unit detect from item name — no API, no UI banner.
  static String? suggestFromName(String rawName, {String? categoryName}) {
    final upper = rawName.toUpperCase().trim();
    if (upper.isEmpty) return null;

    if (RegExp(r'\b(BOX|CARTON|CTN)\b').hasMatch(upper)) return box;
    if (RegExp(r'\bTIN\b').hasMatch(upper)) return tin;
    if (RegExp(r'\b(PC|PCS|PIECE)\b').hasMatch(upper)) return piece;
    if (RegExp(r'\b(LOOSE|BULK)\b').hasMatch(upper)) return looseKg;

    final kgM = _kgInName.firstMatch(upper);
    if (kgM != null) {
      final kg = double.tryParse(kgM.group(1) ?? '');
      if (kg != null && _wholesaleKgSizes.contains(kg.round())) {
        return wholesaleBag;
      }
    }
    if (RegExp(r'\b(BAG|SACK)\b').hasMatch(upper)) return wholesaleBag;
    if (RegExp(r'\d+\s*GM\b').hasMatch(upper)) return piece;
    if (RegExp(r'\d+\s*LTR\b').hasMatch(upper)) return tin;

    return null;
  }

  /// Map packaging picker choice → catalog `default_unit`.
  static String catalogUnitForMode(String mode) {
    switch (mode) {
      case wholesaleBag:
        return 'bag';
      case retailPacket:
      case piece:
        return 'piece';
      case looseKg:
        return 'kg';
      case box:
        return 'box';
      case tin:
        return 'tin';
      default:
        return 'piece';
    }
  }

  static String labelForMode(String mode) {
    switch (mode) {
      case wholesaleBag:
        return 'BAG';
      case retailPacket:
      case piece:
        return 'PC';
      case looseKg:
        return 'KG';
      case box:
        return 'BOX';
      case tin:
        return 'TIN';
      default:
        return 'PC';
    }
  }

  /// Short chip label for create/edit unit picker.
  static String shortLabelForMode(String mode) => labelForMode(mode);

  static bool isPieceLikeMode(String? mode) =>
      mode == piece || mode == retailPacket;

  static bool isBagMode(String? mode) => mode == wholesaleBag;
}
