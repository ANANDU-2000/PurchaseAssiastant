import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/unit_engine/smart_unit_classifier.dart';
import 'package:hexa_purchase_assistant/core/unit_engine/unit_rules_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(UnitRulesLoader.clearCache);

  test('SUGAR 50KG → BAG + SACK + 50 KG package', () async {
    final u = await SmartUnitClassifier.classify(
      'SUGAR 50KG',
      categoryName: 'SUGAR',
    );
    expect(u.sellingUnit, 'BAG');
    expect(u.packageType, 'SACK');
    expect(u.packageSize, 50);
    expect(u.packageMeasurement, 'KG');
    expect(u.stockUnit, 'KG');
    expect(u.conversionFactor, 50);
  });

  test('RUCHI 850GM + brand → BOX', () async {
    final u = await SmartUnitClassifier.classify(
      'RUCHI 850GM',
      categoryName: 'BRANDED_GROCERY',
      brandDetected: true,
    );
    expect(u.sellingUnit, 'BOX');
    expect(u.packageSize, 850);
    expect(u.packageMeasurement, 'GM');
  });

  test('DALDA 15LTR → TIN', () async {
    final u = await SmartUnitClassifier.classify(
      'DALDA 15LTR',
      categoryName: 'OIL',
    );
    expect(u.sellingUnit, 'TIN');
    expect(u.packageSize, 15);
    expect(u.packageMeasurement, 'LTR');
  });

  test('JEERAKAM LOOSE → KG', () async {
    final u = await SmartUnitClassifier.classify(
      'JEERAKAM LOOSE',
      categoryName: 'SPICES',
    );
    expect(u.sellingUnit, 'KG');
    expect(u.packageType, 'LOOSE');
  });
}
