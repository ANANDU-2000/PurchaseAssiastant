import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/barcode_lookup_cache.dart';
import 'package:harisree_warehouse/features/barcode/barcode_scan_session.dart';

void main() {
  tearDown(() {
    BarcodeLookupCache.clear();
  });

  group('BarcodeLookupCache', () {
    test('get/put and invalidate single code', () {
      BarcodeLookupCache.put('biz', 'ABC', {'id': '1', 'name': 'Rice'});
      expect(BarcodeLookupCache.get('biz', 'ABC')?['id'], '1');
      BarcodeLookupCache.invalidate('biz', 'ABC');
      expect(BarcodeLookupCache.get('biz', 'ABC'), isNull);
    });

    test('invalidate leaves other codes', () {
      BarcodeLookupCache.put('biz', 'A', {'id': '1'});
      BarcodeLookupCache.put('biz', 'B', {'id': '2'});
      BarcodeLookupCache.invalidate('biz', 'A');
      expect(BarcodeLookupCache.get('biz', 'B')?['id'], '2');
    });

    test('invalidateBusiness clears only that business', () {
      BarcodeLookupCache.put('biz1', 'A', {'id': '1'});
      BarcodeLookupCache.put('biz2', 'A', {'id': '2'});
      BarcodeLookupCache.invalidateBusiness('biz1');
      expect(BarcodeLookupCache.get('biz1', 'A'), isNull);
      expect(BarcodeLookupCache.get('biz2', 'A')?['id'], '2');
    });
  });

  group('BarcodeScanSession', () {
    test('stale lookup does not overwrite newer result', () {
      final session = BarcodeScanSession();
      final first = session.beginLookup('111');
      final second = session.beginLookup('222');
      expect(session.isStale(first), isTrue);
      expect(
        session.completeFound(first, item: {'id': 'old'}),
        isFalse,
      );
      expect(
        session.completeFound(second, item: {'id': 'new', 'name': 'N'}),
        isTrue,
      );
      expect(session.current?.itemId, 'new');
      expect(session.phase, BarcodeScanPhase.result);
    });

    test('readyForNext clears item but keeps phase ready', () {
      final session = BarcodeScanSession();
      final id = session.beginLookup('X');
      session.completeNotFound(id);
      session.readyForNext();
      expect(session.phase, BarcodeScanPhase.readyForNext);
      expect(session.current?.item, isNull);
      expect(session.acceptsCameraDetect, isTrue);
    });

    test('completeError sets error phase', () {
      final session = BarcodeScanSession();
      final id = session.beginLookup('Z');
      expect(
        session.completeError(id, message: "Couldn't reach server. Retry."),
        isTrue,
      );
      expect(session.phase, BarcodeScanPhase.error);
      expect(session.current?.errorMessage, contains('Retry'));
    });
  });
}
