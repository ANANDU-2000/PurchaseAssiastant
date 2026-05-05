/// Maps item label + catalog unit context to a coarse line shape for UI,
/// validation, and mass math. Spec: `weight_bag`, `single_pack`, `multi_pack_box`.
enum UnitType {
  /// Bag/sack lines priced by kg per bag (user or catalog kg/bag).
  weightBag,

  /// One purchasable pack (box/tin/pcs/kg count) with optional fixed kg from name.
  singlePack,

  /// Box/carton without kg in the name — count-style box (items per box).
  multiPackBox,
}

/// Result of [UnitClassifier.classify].
class UnitClassification {
  const UnitClassification({
    required this.type,
    this.kgFromName,
  });

  final UnitType type;

  /// First `\d+ KG` in the item name (integer kg), if any.
  final double? kgFromName;
}

class UnitClassifier {
  /// Matches `50 KG`, `50.5 kg`, `25kg` in catalog / free-typed names.
  static final RegExp _kgInName =
      RegExp(r'(\d+(?:\.\d+)?)\s*KG', caseSensitive: false);

  /// Optional [categoryName] / [subcategoryName] are reserved for future rules.
  /// Optional [catalogDefaultKgPerBag] — when `(line/catalog) unit` is bag/sack and
  /// this is positive, resolves to [UnitType.weightBag] even without `\\d+ KG` in [itemName].
  static UnitClassification classify({
    required String itemName,
    String? lineUnit,
    String? catalogDefaultUnit,
    double? catalogDefaultKgPerBag,
    String? categoryName,
    String? subcategoryName,
  }) {
    final line = lineUnit?.trim() ?? '';
    final cat = catalogDefaultUnit?.trim() ?? '';
    final effective = line.isNotEmpty ? line : cat;
    final effU = effective.toUpperCase();

    if (effU == 'KG') {
      return UnitClassification(
        type: UnitType.singlePack,
        // For lines already recorded in KG, the quantity is the physical weight.
        // Do NOT apply "50 KG" from name as a multiplier (that is only meaningful
        // for pack/count units like BOX/TIN, not for KG itself).
        kgFromName: null,
      );
    }

    final kgFromName = _parseKgFromName(itemName);
    final nameUp = itemName.toUpperCase();
    final hasBagWord = nameUp.contains('BAG');
    final defaultIsBag = cat.toUpperCase() == 'BAG';
    if (kgFromName != null &&
        kgFromName > 0 &&
        (hasBagWord || defaultIsBag)) {
      return UnitClassification(
        type: UnitType.weightBag,
        kgFromName: kgFromName,
      );
    }

    final hasBoxWord = nameUp.contains('BOX') ||
        nameUp.contains('CTN') ||
        nameUp.contains('CARTON');
    final hasTinWord = nameUp.contains('TIN');
    if (hasBoxWord || hasTinWord) {
      if (kgFromName != null && kgFromName > 0) {
        return UnitClassification(
          type: UnitType.singlePack,
          kgFromName: kgFromName,
        );
      }
      return const UnitClassification(type: UnitType.multiPackBox);
    }

    if (effU == 'PCS' || effU == 'PIECE' || effU == 'PIECES') {
      return UnitClassification(
        type: UnitType.singlePack,
        kgFromName: kgFromName,
      );
    }

    if (_isBagOrSackUnit(effU) &&
        catalogDefaultKgPerBag != null &&
        catalogDefaultKgPerBag > 0) {
      return UnitClassification(
        type: UnitType.weightBag,
        kgFromName: kgFromName,
      );
    }

    return UnitClassification(
      type: UnitType.singlePack,
      kgFromName: kgFromName,
    );
  }

  static bool _isBagOrSackUnit(String effU) {
    return effU == 'BAG' || effU == 'SACK';
  }

  static double? _parseKgFromName(String itemName) {
    final m = _kgInName.firstMatch(itemName);
    if (m == null) return null;
    final n = double.tryParse(m.group(1) ?? '');
    if (n == null || n <= 0) return null;
    return n;
  }
}
