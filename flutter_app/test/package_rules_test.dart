import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/calc_engine.dart';
import 'package:hexa_purchase_assistant/core/utils/unit_classifier.dart';
import 'package:hexa_purchase_assistant/features/purchase/domain/purchase_draft.dart';

/// Master rebuild package rules — the spec calls these out as non-negotiable
/// so they all need explicit assertions:
///
/// - BAG products auto-derive `per_bag_kg` from the item label.
/// - BAG: `qty bags × per_bag_kg = total_kg` (NOT `1 bag = 1 kg`).
/// - BAG rate-mode supports both ₹/kg (`5000 × 55`) and ₹/bag (`100 × 2750`).
/// - BOX products: count-only, no kg fields, no items-per-box.
/// - TIN products: count-only, no kg fields, no kg display.
void main() {
  group('UnitClassifier auto-detect bag weight', () {
    test('SUGAR 50 KG → weightBag with kgFromName=50', () {
      final c = UnitClassifier.classify(itemName: 'SUGAR 50 KG', lineUnit: 'bag');
      expect(c.type, UnitType.weightBag);
      expect(c.kgFromName, 50.0);
    });

    test('RICE 26 KG → weightBag with kgFromName=26', () {
      final c = UnitClassifier.classify(itemName: 'RICE 26 KG', lineUnit: 'bag');
      expect(c.type, UnitType.weightBag);
      expect(c.kgFromName, 26.0);
    });

    test('RICE MALA GOLD 30 KG → weightBag with kgFromName=30', () {
      final c = UnitClassifier.classify(
          itemName: 'RICE MALA GOLD 30 KG', lineUnit: 'bag');
      expect(c.type, UnitType.weightBag);
      expect(c.kgFromName, 30.0);
    });

    test('RBD 15LTR TIN → singlePack (no kgFromName needed for tin count)', () {
      final c = UnitClassifier.classify(itemName: 'RBD 15LTR TIN', lineUnit: 'tin');
      expect(c.type, UnitType.singlePack);
    });

    test('SUNRICH 400GM BOX → singlePack count-only (no kg semantics)', () {
      final c = UnitClassifier.classify(
          itemName: 'SUNRICH 400GM BOX', lineUnit: 'box');
      expect(c.type, UnitType.singlePack);
    });
  });

  group('BAG calculation rule (per spec: NEVER 1 bag = 1 kg)', () {
    test('100 bags × 50 kg/bag = 5000 kg', () {
      final kg = linePhysicalWeightKg(unit: 'bag', qty: 100, kgPerUnit: 50);
      expect(kg, 5000.0);
    });

    test('100 bags × 26 kg/bag = 2600 kg', () {
      final kg = linePhysicalWeightKg(unit: 'bag', qty: 100, kgPerUnit: 26);
      expect(kg, 2600.0);
    });

    test('100 bags × 30 kg/bag = 3000 kg', () {
      final kg = linePhysicalWeightKg(unit: 'bag', qty: 100, kgPerUnit: 30);
      expect(kg, 3000.0);
    });

    test('bag without kgPerUnit returns 0 (forces explicit detection)', () {
      final kg = linePhysicalWeightKg(unit: 'bag', qty: 100);
      expect(kg, 0.0);
    });
  });

  group('BAG rate modes (₹/kg vs ₹/bag)', () {
    test('₹/kg mode: 5000 kg × ₹55/kg = 275000', () {
      final m = lineMoney(const TradeCalcLine(
        qty: 100,
        landingCost: 50 * 55, // 2750/bag derived
        kgPerUnit: 50,
        landingCostPerKg: 55,
        taxPercent: 0,
      ));
      expect(m, 275000.0);
    });

    test('₹/bag mode: 100 bags × ₹2750/bag = 275000', () {
      final m = lineMoney(const TradeCalcLine(
        qty: 100,
        landingCost: 2750,
        taxPercent: 0,
      ));
      expect(m, 275000.0);
    });

    test('₹/kg and ₹/bag modes produce the same total when consistent', () {
      final viaKg = lineMoney(const TradeCalcLine(
        qty: 100,
        landingCost: 50 * 55,
        kgPerUnit: 50,
        landingCostPerKg: 55,
        taxPercent: 0,
      ));
      final viaBag = lineMoney(const TradeCalcLine(
        qty: 100,
        landingCost: 2750,
        taxPercent: 0,
      ));
      expect(viaKg, viaBag);
    });
  });

  group('BOX/TIN are count-only — kg always zero', () {
    test('linePhysicalWeightKg unit=box returns 0 even with kgPerUnit set', () {
      final kg =
          linePhysicalWeightKg(unit: 'box', qty: 100, kgPerUnit: 0.4);
      expect(kg, 0.0);
    });

    test('linePhysicalWeightKg unit=tin returns 0 even with weightPerTin set', () {
      final kg = linePhysicalWeightKg(
          unit: 'tin', qty: 50, kgPerUnit: 15, weightPerTin: 15);
      expect(kg, 0.0);
    });

    test('ledgerTradeLineWeightKg returns 0 for box even when item name has kg', () {
      final kg = ledgerTradeLineWeightKg(
          itemName: 'SUNRICH 400GM BOX', unit: 'box', qty: 100);
      expect(kg, 0.0);
    });

    test('ledgerTradeLineWeightKg returns 0 for tin even when item name has ltr/kg', () {
      final kg = ledgerTradeLineWeightKg(
          itemName: 'RBD 15LTR TIN', unit: 'tin', qty: 50);
      expect(kg, 0.0);
    });
  });

  group('purchaseLineSaveBlockReason validation engine', () {
    test('BOX with qty + landing cost is save-ready (no kg needed)', () {
      final l = PurchaseLineDraft(
        catalogItemId: 'cid-box',
        itemName: 'SUNRICH 400GM BOX',
        qty: 100,
        unit: 'box',
        landingCost: 2300,
      );
      expect(purchaseLineSaveBlockReason(l), isNull);
    });

    test('TIN with qty + landing cost is save-ready (no kg needed)', () {
      final l = PurchaseLineDraft(
        catalogItemId: 'cid-tin',
        itemName: 'RBD 15LTR TIN',
        qty: 50,
        unit: 'tin',
        landingCost: 2200,
      );
      expect(purchaseLineSaveBlockReason(l), isNull);
    });

    test('BAG without kgPerUnit is rejected', () {
      final l = PurchaseLineDraft(
        catalogItemId: 'cid-bag',
        itemName: 'SUGAR 50 KG',
        qty: 100,
        unit: 'bag',
        landingCost: 2750,
      );
      final r = purchaseLineSaveBlockReason(l);
      expect(r, isNotNull);
      expect(r, contains('Kg per bag'));
    });

    test('BAG with kgPerUnit + per-kg cost is save-ready (HSN required → null)', () {
      final l = PurchaseLineDraft(
        catalogItemId: 'cid-bag',
        itemName: 'SUGAR 50 KG',
        qty: 100,
        unit: 'bag',
        landingCost: 50 * 55,
        kgPerUnit: 50,
        landingCostPerKg: 55,
        hsnCode: '17019910',
      );
      expect(purchaseLineSaveBlockReason(l), isNull);
    });

    test('Fractional bag count is rejected', () {
      final l = PurchaseLineDraft(
        catalogItemId: 'cid-bag',
        itemName: 'SUGAR 50 KG',
        qty: 100.5,
        unit: 'bag',
        landingCost: 2750,
        kgPerUnit: 50,
        landingCostPerKg: 55,
        hsnCode: '17019910',
      );
      expect(purchaseLineSaveBlockReason(l), contains('whole number'));
    });
  });
}
