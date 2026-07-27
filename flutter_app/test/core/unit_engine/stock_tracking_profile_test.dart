import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/unit_engine/stock_tracking_profile.dart';

void main() {
  group('StockTrackingMode.suggestFromName', () {
    test('SUGAR 50KG → BAG', () {
      expect(
        StockTrackingMode.suggestFromName('SUGAR 50KG'),
        StockTrackingMode.wholesaleBag,
      );
    });

    test('SUNRICH OIL BOX → BOX', () {
      expect(
        StockTrackingMode.suggestFromName('SUNRICH OIL BOX'),
        StockTrackingMode.box,
      );
    });

    test('SUNRICH OIL TIN → TIN', () {
      expect(
        StockTrackingMode.suggestFromName('SUNRICH OIL TIN'),
        StockTrackingMode.tin,
      );
    });

    test('SOAP PC → PC', () {
      expect(
        StockTrackingMode.suggestFromName('SOAP PC'),
        StockTrackingMode.piece,
      );
    });

    test('RICE LOOSE → KG', () {
      expect(
        StockTrackingMode.suggestFromName('RICE LOOSE'),
        StockTrackingMode.looseKg,
      );
    });

    test('GREEN PEAS 30KG → BAG', () {
      expect(
        StockTrackingMode.suggestFromName('GREEN PEAS 30KG'),
        StockTrackingMode.wholesaleBag,
      );
    });
  });

  group('StockTrackingMode.parseKgFromName', () {
    test('parses wholesale kg token', () {
      expect(StockTrackingMode.parseKgFromName('SUGAR 50KG'), 50);
      expect(StockTrackingMode.parseKgFromName('TRUSALT 25kg'), 25);
    });
  });

  group('StockTrackingMode labels', () {
    test('picker labels are KG/BAG/BOX/TIN/PC', () {
      expect(StockTrackingMode.pickerModes.length, 5);
      expect(StockTrackingMode.labelForMode(StockTrackingMode.looseKg), 'KG');
      expect(
        StockTrackingMode.labelForMode(StockTrackingMode.wholesaleBag),
        'BAG',
      );
      expect(StockTrackingMode.labelForMode(StockTrackingMode.box), 'BOX');
      expect(StockTrackingMode.labelForMode(StockTrackingMode.tin), 'TIN');
      expect(StockTrackingMode.labelForMode(StockTrackingMode.piece), 'PC');
    });
  });
}
