import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/unit_engine/smart_validation_engine.dart';

void main() {
  test('detectUnitFromName maps common suffixes', () {
    expect(SmartValidationEngine.detectUnitFromName('SUGAR 50 KG'), 'bag');
    expect(SmartValidationEngine.detectUnitFromName('ATTA 5 KG'), 'piece');
    expect(SmartValidationEngine.detectUnitFromName('Oil 15 LTR'), 'box');
    expect(SmartValidationEngine.detectUnitFromName('Oil 500 ML'), 'box');
    expect(SmartValidationEngine.detectUnitFromName('Ruchi 850 GM'), 'piece');
    expect(SmartValidationEngine.detectUnitFromName('24 X 200 GM'), 'box');
    expect(SmartValidationEngine.detectUnitFromName('Plain name'), isNull);
  });
}
