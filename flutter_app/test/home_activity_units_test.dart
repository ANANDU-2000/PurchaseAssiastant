import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/utils/home_activity_units.dart';
import 'package:harisree_warehouse/core/utils/purchase_units_subtitle.dart';

void main() {
  test('stockAuditActivityUnitsLine includes unit', () {
    expect(
      stockAuditActivityUnitsLine({
        'old_qty': 0,
        'new_qty': 100,
        'unit': 'bag',
      }),
      '+100 BAG',
    );
  });

  test('stockAuditActivityUnitsLine falls back to item name', () {
    expect(
      stockAuditActivityUnitsLine({
        'old_qty': 5,
        'new_qty': 15,
        'item_name': 'Rice',
      }),
      '+10 · Rice',
    );
  });

  test('purchaseUnitsSubtitleFromLines compacts single bag plus kg', () {
    expect(
      purchaseUnitsSubtitleFromLines([
        {
          'qty': 1,
          'unit': 'BAG',
          'total_weight': 10,
          'kg_per_unit': 10,
        },
      ]),
      '10 KG',
    );
  });

  test('purchaseUnitsSubtitleFromLines handles misc unit labels', () {
    final line = purchaseUnitsSubtitleFromLines([
      {'qty': 10, 'unit': 'piece'},
    ]);
    expect(line, '10 PIECE');
  });

  test('dedupeActivityUnitsLine removes audit and purchase duplicates', () {
    expect(
      dedupeActivityUnitsLine('+10 KG · 10 KG'),
      '10 KG',
    );
    expect(
      dedupeActivityUnitsLine('+10 KG · +1 BAG · 1 BAG · 10 KG'),
      '10 KG · 1 BAG',
    );
    expect(
      dedupeActivityUnitsLine('+100 BAG · 100 BAGS · 100 BOXES'),
      '100 BAG · 100 BOXES',
    );
  });

  test('warehouseActivityDeliveryUnitsLabel hides bill ids', () {
    expect(
      warehouseActivityDeliveryUnitsLabel(
        qtyChange: 'PUR-2026-0014',
      ),
      '—',
    );
    expect(
      warehouseActivityDeliveryUnitsLabel(
        unitsLine: '1 BAG · 10 KG',
      ),
      '1 BAG · 10 KG',
    );
  });
}
