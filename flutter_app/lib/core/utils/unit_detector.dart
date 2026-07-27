/// Parses wholesale item names for unit type and nominal kg snapshot.
class UnitDetectionResult {
  const UnitDetectionResult({
    required this.unit,
    this.kgPerUnit,
    this.isFixedWeightBox = false,
    required this.confidence,
  });

  /// bag | box | tin | kg | … (mirrors catalog / line units).
  final String unit;
  final double? kgPerUnit;
  final bool isFixedWeightBox;

  /// high: explicit KG in name; medium: BOX/TIN heuristic; low: fallback only.
  final String confidence;
}

class UnitDetector {
  /// Detect unit + optional kg from [itemName]. [catalogDefault] used only on low-confidence fallback.
  static UnitDetectionResult detect(String itemName, String? catalogDefault) {
    final name = itemName.toUpperCase().trim();
    final bagPattern = RegExp(r'\b(\d+(?:\.\d+)?)\s*KG\b');
    final match = bagPattern.firstMatch(name);

    if (match != null) {
      final kgValue = double.tryParse(match.group(1) ?? '');
      if (kgValue != null && kgValue > 0) {
        final isBox = name.contains('BOX') ||
            name.contains('CTN') ||
            name.contains('CARTON');
        if (isBox) {
          return UnitDetectionResult(
            unit: 'box',
            kgPerUnit: kgValue,
            isFixedWeightBox: true,
            confidence: 'high',
          );
        }
        return UnitDetectionResult(
          unit: 'bag',
          kgPerUnit: kgValue,
          isFixedWeightBox: false,
          confidence: 'high',
        );
      }
    }

    if (name.contains('TIN')) {
      return const UnitDetectionResult(
        unit: 'tin',
        kgPerUnit: null,
        confidence: 'medium',
      );
    }

    if (name.contains('BOX') ||
        name.contains('CTN') ||
        name.contains('CARTON')) {
      return const UnitDetectionResult(
        unit: 'box',
        kgPerUnit: null,
        isFixedWeightBox: true,
        confidence: 'medium',
      );
    }

    final raw = catalogDefault?.trim().toLowerCase() ?? '';
    final u = raw.isEmpty ? 'kg' : raw;
    return UnitDetectionResult(
      unit: u,
      kgPerUnit: null,
      isFixedWeightBox: false,
      confidence: 'low',
    );
  }
}
