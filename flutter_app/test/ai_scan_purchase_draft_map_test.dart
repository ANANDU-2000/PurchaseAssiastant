import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/features/purchase/domain/purchase_draft.dart';
import 'package:hexa_purchase_assistant/features/purchase/mapping/ai_scan_purchase_draft_map.dart';

void main() {
  group('purchaseDraftFromScanResultJson', () {
    test('maps supplier, broker, charges, and KG line', () {
      final scan = <String, dynamic>{
        'scan_token': 'tok-1',
        'bill_date': '2026-03-15',
        'invoice_number': ' INV-9 ',
        'payment_days': 12,
        'supplier': {
          'matched_id': 'sup-a',
          'matched_name': 'Acme',
          'raw_text': 'raw sup',
          'confidence': 0.9,
        },
        'broker': {
          'matched_id': 'bro-b',
          'matched_name': 'Broker Co',
          'raw_text': 'raw bro',
        },
        'charges': {
          'delivered_rate': 10.0,
          'billty_rate': 2.0,
          'freight_amount': 50.0,
          'freight_type': 'separate',
          'discount_percent': 1.5,
        },
        'broker_commission': {'type': 'percent', 'value': 2.0},
        'items': [
          {
            'unit_type': 'KG',
            'qty': 100.0,
            'matched_catalog_item_id': 'cat-1',
            'matched_name': 'Sugar',
            'purchase_rate': 42.0,
            'selling_rate': 45.0,
          },
        ],
      };

      final d = purchaseDraftFromScanResultJson(scan);
      expect(d.supplierId, 'sup-a');
      expect(d.supplierName, 'Acme');
      expect(d.brokerId, 'bro-b');
      expect(d.brokerName, 'Broker Co');
      expect(d.paymentDays, 12);
      expect(d.invoiceNumber, 'INV-9');
      expect(d.deliveredRate, 10.0);
      expect(d.billtyRate, 2.0);
      expect(d.freightAmount, 50.0);
      expect(d.freightType, 'separate');
      expect(d.headerDiscountPercent, 1.5);
      expect(d.commissionMode, kPurchaseCommissionModePercent);
      expect(d.commissionPercent, 2.0);
      expect(d.lines, hasLength(1));
      expect(d.lines.first.catalogItemId, 'cat-1');
      expect(d.lines.first.itemName, 'Sugar');
      expect(d.lines.first.qty, 100.0);
      expect(d.lines.first.unit, 'kg');
      expect(d.lines.first.landingCost, 42.0);
      expect(d.lines.first.sellingPrice, 45.0);
    });

    test('BAG line uses weight_per_unit_kg for kgPerUnit when rate looks per bag', () {
      final scan = <String, dynamic>{
        'items': [
          {
            'unit_type': 'BAG',
            'bags': 5.0,
            'weight_per_unit_kg': 50.0,
            'purchase_rate': 2750.0,
            'matched_name': 'Cement',
          },
        ],
      };
      final d = purchaseDraftFromScanResultJson(scan);
      expect(d.lines.first.unit, 'bag');
      expect(d.lines.first.qty, 5.0);
      expect(d.lines.first.kgPerUnit, 50.0);
      expect(d.lines.first.landingCost, 2750.0);
      expect(d.lines.first.landingCostPerKg, closeTo(55.0, 0.001));
    });
  });

  group('scanResultJsonMergePurchaseDraft', () {
    test('preserves scan_token and merges supplier id from draft', () {
      final base = <String, dynamic>{
        'scan_token': 'keep-me',
        'warnings': [
          {'severity': 'info', 'code': 'x'},
        ],
        'supplier': {
          'raw_text': 'Old',
          'matched_id': null,
          'matched_name': null,
          'confidence': 0.1,
          'candidates': [],
        },
        'items': [
          {
            'raw_name': 'Line',
            'unit_type': 'KG',
            'qty': 1.0,
            'purchase_rate': 10.0,
          },
        ],
        'charges': <String, dynamic>{},
      };

      final draft = PurchaseDraft(
        supplierId: 'new-sup',
        supplierName: 'New Sup',
        lines: [
          PurchaseLineDraft(
            catalogItemId: 'c99',
            itemName: 'Merged item',
            qty: 2.0,
            unit: 'kg',
            landingCost: 20.0,
          ),
        ],
      );

      final merged = scanResultJsonMergePurchaseDraft(base, draft);
      expect(merged['scan_token'], 'keep-me');
      expect(merged['warnings'], isA<List>());
      final sup = merged['supplier'] as Map;
      expect(sup['matched_id'], 'new-sup');
      expect(sup['matched_name'], 'New Sup');
      final items = merged['items'] as List;
      expect(items, hasLength(1));
      final row = items.first as Map<String, dynamic>;
      expect(row['matched_catalog_item_id'], 'c99');
      expect(row['qty'], 2.0);
      expect(row['purchase_rate'], 20.0);
    });
  });
}
