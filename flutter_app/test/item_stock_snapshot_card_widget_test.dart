import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/auth/session_notifier.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/item_detail_providers.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart'
    show stockItemDetailProvider;
import 'package:harisree_warehouse/features/catalog/presentation/widgets/item_physical_verification_card.dart';
import 'package:harisree_warehouse/features/catalog/presentation/widgets/item_stock_snapshot_card.dart';

const _session = Session(
  accessToken: 'test',
  refreshToken: 'test',
  businesses: [
    BusinessBrief(id: 'biz-1', name: 'Test Biz', role: 'owner'),
  ],
);

const _itemId = 'test-item-id';

final _stock = {
  'stock_unit': 'bag',
  'current_stock': 1200,
  'physical_stock_qty': 1200,
  'period_purchased_qty': 0,
  'reorder_level': 100,
  'needs_verification': false,
  'item_code': 'ITM-0001',
  'barcode': 'ITM-0001',
  'physical_stock_counted_at': '2026-06-01T10:00:00Z',
};

void main() {
  testWidgets('ItemStockSnapshotCard renders owner sugar bag row', (tester) async {
    await tester.pumpWidget(_wrap(const ItemStockSnapshotCard(itemId: _itemId)));
    await tester.pumpAndSettle();
    expect(find.text('Stock summary'), findsOneWidget);
    expect(find.textContaining('could not load', findRichText: true), findsNothing);
  });

  testWidgets('ItemPhysicalVerificationCard renders counted stock', (tester) async {
    await tester.pumpWidget(
      _wrap(const ItemPhysicalVerificationCard(itemId: _itemId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verification log'), findsOneWidget);
    expect(find.textContaining('could not load', findRichText: true), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      sessionProvider.overrideWith(() => _FakeSessionNotifier()),
      stockItemDetailProvider(_itemId).overrideWith(
        (ref) async => _stock,
      ),
      itemDetailStockProvider(_itemId).overrideWith((ref) => _stock),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

class _FakeSessionNotifier extends SessionNotifier {
  @override
  Session? build() => _session;
}
