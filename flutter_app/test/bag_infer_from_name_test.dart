import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/utils/line_display.dart';

void main() {
  test('parseKgPerBagHintFromItemName finds weight token', () {
    expect(parseKgPerBagHintFromItemName('SUGAR 50 KG'), 50);
    expect(parseKgPerBagHintFromItemName('RICE MALA GOLD 50KG'), 50);
    expect(parseKgPerBagHintFromItemName('UZHUNNU MAHARAJA 50 KG'), 50);
    expect(parseKgPerBagHintFromItemName('PLAIN RICE'), null);
  });

  test('inferBagCountForKgOnlyDisplay: sugar 40000 kg / 50 kg bag', () {
    expect(
      inferBagCountForKgOnlyDisplay(
        itemName: 'SUGAR 50 KG',
        totalKg: 40000,
        totalBags: 0,
      ),
      800,
    );
  });

  test('inferBagCountForKgOnlyDisplay: skips when bags already set', () {
    expect(
      inferBagCountForKgOnlyDisplay(
        itemName: 'SUGAR 50 KG',
        totalKg: 40000,
        totalBags: 800,
      ),
      null,
    );
  });

  test('inferBagCountForKgOnlyDisplay: no hint → null', () {
    expect(
      inferBagCountForKgOnlyDisplay(
        itemName: 'LOOSE COMMODITY',
        totalKg: 1000,
        totalBags: 0,
      ),
      null,
    );
  });

  test('inferBagCountForKgOnlyDisplay: rejects when total kg off nominal bags', () {
    expect(
      inferBagCountForKgOnlyDisplay(
        itemName: 'SUGAR 50 KG',
        totalKg: 40,
        totalBags: 0,
      ),
      null,
    );
  });
}
