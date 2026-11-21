import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/core/providers/home_dashboard_provider.dart';
import 'package:harisree_warehouse/core/providers/stock_detail_providers.dart';
import 'package:harisree_warehouse/core/theme/hexa_colors.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_desktop_detail_pane.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_operational_top_bar.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_warehouse_row.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_warehouse_table_header.dart';

/// Text anti-aliasing differs between operating systems (Windows dev machines vs the Linux CI
/// runner differ by ~1% of pixels), so each platform keeps its own baseline images.
String _golden(String file) => 'goldens/${Platform.operatingSystem}/$file';

/// Golden harness for the desktop operational stock page.
/// Mirrors StockPage._buildListBody desktop split: left table + right detail.
void main() {
  // The row renders relative times ("2d ago") from DateTime.now(). Fixed calendar dates made the
  // golden drift ("2d ago" -> "3mo ago"), so fixture times are relative to now (+1h margin keeps the
  // whole-day count stable regardless of the time the test runs).
  String daysAgoIso(int days) => DateTime.now()
      .toUtc()
      .subtract(Duration(days: days, hours: 1))
      .toIso8601String();

  final rows = <Map<String, dynamic>>[
    {
      'id': 'a1',
      'name': 'Basmati Rice Premium 25kg',
      'category_name': 'Grocery',
      'subcategory_name': 'Rice',
      'current_stock': 42.0,
      'physical_stock_qty': 40.0,
      'physical_stock_counted_by': 'krishna',
      'physical_stock_counted_at': daysAgoIso(1),
      'stock_status': 'healthy',
      'stock_unit': 'bag',
    },
    {
      'id': 'a2',
      'name': 'Sugar 50 KG',
      'category_name': 'Grocery',
      'subcategory_name': 'Sugar',
      'current_stock': 12.0,
      'physical_stock_qty': 5.0,
      'stock_status': 'low',
      'stock_unit': 'bag',
      'has_pending_order': true,
      'pending_delivery_qty': 52.0,
      'pending_order_days': 3,
    },
    {
      'id': 'a3',
      'name': 'Sunflower Oil 15L Tin',
      'category_name': 'Oil',
      'subcategory_name': 'Cooking Oil',
      'current_stock': 0.0,
      'physical_stock_qty': 0.0,
      'stock_status': 'out',
      'stock_unit': 'tin',
    },
    {
      'id': 'a4',
      'name': 'Toor Dal Casuals 30kg',
      'category_name': 'Pulses',
      'subcategory_name': 'Dal',
      'current_stock': 28.0,
      'physical_stock_qty': null,
      'stock_status': 'healthy',
      'stock_unit': 'bag',
      'last_purchase_at': daysAgoIso(3),
      'last_purchase_delivered': true,
    },
    {
      'id': 'a5',
      'name': 'Atta Whole Wheat 50kg',
      'category_name': 'Flour',
      'subcategory_name': 'Atta',
      'current_stock': 60.0,
      'physical_stock_qty': 63.0,
      'stock_status': 'healthy',
      'stock_unit': 'bag',
    },
    {
      'id': 'a6',
      'name': 'Green Peas Frozen 1kg',
      'category_name': 'Frozen',
      'subcategory_name': 'Vegetables',
      'current_stock': 7.0,
      'physical_stock_qty': 7.0,
      'stock_status': 'critical',
      'stock_unit': 'pack',
    },
  ];

  Future<void> pumpStockDesktop(
    WidgetTester tester,
    Size size,
  ) async {
    final item = {
      'id': 'a1',
      'name': 'Basmati Rice Premium 25kg',
      'unit': 'BAG',
      'current_stock': 42.0,
      'physical_stock_qty': 40.0,
      'opening_stock': 30.0,
      'purchased_qty': 12.0,
      'pending_delivery_qty': 0,
      'stock_status': 'healthy',
    };

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockItemActivityProvider('a1').overrideWith(
            (ref) async => {
              'activity': [
                {
                  'title': 'Physical count updated',
                  'actor_name': 'krishna',
                  'kind': 'physical_count',
                },
                {
                  'title': 'Purchase received',
                  'actor_name': 'owner',
                  'kind': 'purchase',
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            backgroundColor: HexaColors.scaffoldWarm,
            appBar: StockOperationalTopBar(
              isStaffMode: false,
              filterCount: 2,
              searchExpanded: false,
              isReloading: false,
              onToggleSearch: () {},
              onOpenPeriod: () {},
              onOpenFilters: () {},
              onOpenMovement: () {},
              onExportPdf: () {},
              onExportExcel: () {},
              currentPeriod: HomePeriod.allTime,
              tabController: TabController(vsync: TestVSync(), length: 2),
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      const StockWarehouseTableHeader(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (ctx, i) => RepaintBoundary(
                            child: Consumer(
                              builder: (context, ref, _) =>
                                  StockWarehouseRow(
                                ref: ref,
                                item: rows[i],
                                isStaffMode: false,
                                isFirstRow: i == 0,
                                isSelected: i == 0,
                                onTap: () {},
                                onSelect: () {},
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  flex: 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: StockDesktopDetailPane(item: item),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('stock desktop split at 1440', (tester) async {
    await pumpStockDesktop(tester, const Size(1440, 900));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(_golden('stock_desktop_1440.png')),
    );
  });

  testWidgets('stock desktop split at 1280', (tester) async {
    await pumpStockDesktop(tester, const Size(1280, 800));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(_golden('stock_desktop_1280.png')),
    );
  });
}

