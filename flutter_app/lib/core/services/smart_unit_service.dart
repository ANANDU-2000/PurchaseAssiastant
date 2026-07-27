import '../unit_engine/smart_unit_classifier.dart' as engine;
import '../utils/unit_classifier.dart' as name_rules;

/// Harisree v4 smart unit hints for catalog add-item (extends [name_rules.UnitClassifier]).
class SmartUnitSuggestion {
  const SmartUnitSuggestion({
    required this.catalogUnit,
    required this.label,
    this.confidence = 70,
  });

  /// `bag` | `box` | `kg` | `tin` | `piece`
  final String catalogUnit;
  final String label;
  final double confidence;
}

class SmartUnitService {
  SmartUnitService._();

  /// Fast name-token rules: *KG→bag, *L/*ML→box, *GM→piece, *xN→box, else null.
  static SmartUnitSuggestion? detectFromName(String rawName) {
    final unit = name_rules.UnitClassifier.detectUnitFromName(rawName);
    if (unit == null || unit.isEmpty) return null;
    final upper = unit.toUpperCase();
    return SmartUnitSuggestion(
      catalogUnit: unit,
      label: 'Detected: $upper (from name)',
      confidence: 78,
    );
  }

  /// Async rules engine (JSON + category) when name heuristics are insufficient.
  static Future<SmartUnitSuggestion?> classifyAsync(
    String itemName, {
    String? categoryName,
    bool brandDetected = false,
  }) async {
    final c = await engine.SmartUnitClassifier.classify(
      itemName,
      categoryName: categoryName,
      brandDetected: brandDetected,
    );
    final su = c.sellingUnit.toLowerCase();
    final mapped = _mapSellingUnit(su);
    if (mapped == null) return null;
    return SmartUnitSuggestion(
      catalogUnit: mapped,
      label: 'Detected: ${mapped.toUpperCase()} (smart rules)',
      confidence: c.confidence,
    );
  }

  static String? _mapSellingUnit(String sellingUnit) {
    switch (sellingUnit.toUpperCase()) {
      case 'BAG':
      case 'SACK':
        return 'bag';
      case 'BOX':
      case 'CASE':
      case 'CTN':
        return 'box';
      case 'TIN':
        return 'tin';
      case 'KG':
        return 'kg';
      case 'PCS':
      case 'PIECE':
      case 'PIECES':
        return 'piece';
      default:
        return null;
    }
  }
}
