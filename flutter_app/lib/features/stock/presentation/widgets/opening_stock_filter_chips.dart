import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart';

/// Compact horizontal chips: Pending / Completed / Low / Missing Barcode / Missing Code.
class OpeningStockFilterChips extends ConsumerWidget {
  const OpeningStockFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(openingStockSetupQueryProvider);

    bool pendingSelected = q.status == 'pending';
    bool completedSelected = q.status == 'completed';
    bool lowSelected = q.stockStatus == 'low';
    bool missingBarcodeSelected = q.missingBarcode;
    bool missingCodeSelected = q.missingItemCode;

    void setStatus(String status) {
      ref.read(openingStockSetupQueryProvider.notifier).state =
          q.copyWith(
            page: 1,
            status: status,
            stockStatus: 'all',
            missingBarcode: false,
            missingItemCode: false,
          );
    }

    void setLow() {
      ref.read(openingStockSetupQueryProvider.notifier).state =
          q.copyWith(
            page: 1,
            status: 'all',
            stockStatus: 'low',
            missingBarcode: false,
            missingItemCode: false,
          );
    }

    void setMissingBarcode() {
      ref.read(openingStockSetupQueryProvider.notifier).state =
          q.copyWith(
            page: 1,
            status: 'all',
            stockStatus: 'all',
            missingBarcode: true,
            missingItemCode: false,
          );
    }

    void setMissingCode() {
      ref.read(openingStockSetupQueryProvider.notifier).state =
          q.copyWith(
            page: 1,
            status: 'all',
            stockStatus: 'all',
            missingBarcode: false,
            missingItemCode: true,
          );
    }

    final chips = <({String label, bool selected, VoidCallback onTap})>[
      (label: 'Pending', selected: pendingSelected, onTap: () => setStatus('pending')),
      (label: 'Completed', selected: completedSelected, onTap: () => setStatus('completed')),
      (label: 'Low', selected: lowSelected, onTap: () => setLow()),
      (label: 'Missing Barcode', selected: missingBarcodeSelected, onTap: () => setMissingBarcode()),
      (label: 'Missing Code', selected: missingCodeSelected, onTap: () => setMissingCode()),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: HexaResponsive.pageGutter(context, operational: true),
        ),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final c = chips[i];
          return HexaAccessibleFilterChip(
            label: c.label,
            selected: c.selected,
            compact: true,
            onSelected: (_) => c.onTap(),
          );
        },
      ),
    );
  }
}

