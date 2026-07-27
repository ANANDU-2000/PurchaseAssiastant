import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/realtime_events_provider.dart';

void main() {
  test('parses single item_id from realtime payload', () {
    expect(
      itemIdsFromRealtimePayload({'item_id': 'abc-123'}),
      {'abc-123'},
    );
  });

  test('parses item_ids list from realtime payload', () {
    expect(
      itemIdsFromRealtimePayload({
        'item_ids': ['a', 'b', 'a'],
      }),
      {'a', 'b'},
    );
  });
}
