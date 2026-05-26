import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'business_aggregates_invalidation.dart';

final realtimeInvalidationProvider = StreamProvider.autoDispose<int>((ref) async* {
  final session = ref.watch(sessionProvider);
  if (session == null) return;
  final api = ref.read(hexaApiProvider);
  final seen = <String>{};
  var tick = 0;

  Future<void> poll({required bool initial}) async {
    final rows = await api.listRealtimeEvents(
      businessId: session.primaryBusiness.id,
      limit: 50,
    );
    for (final row in rows) {
      final key =
          '${row['type']}:${row['created_at']}:${row['payload']?.toString() ?? ''}';
      if (!seen.add(key) || initial) continue;
      final type = row['type']?.toString() ?? '';
      if (type == 'stock.changed' ||
          type == 'stock.activity_changed' ||
          type == 'purchase.changed' ||
          type == 'notification.changed') {
        invalidateWarehouseSurfaces(ref);
      }
    }
  }

  await poll(initial: true);
  yield tick;
  final timer = Stream.periodic(const Duration(seconds: 30));
  await for (final _ in timer) {
    await poll(initial: false);
    yield ++tick;
  }
});
