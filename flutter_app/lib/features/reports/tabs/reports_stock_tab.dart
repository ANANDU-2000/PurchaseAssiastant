import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../stock/reports_stock_providers.dart';
import '../stock/reports_stock_status.dart';
import '../widgets/reports_stock_filter_sort_bar.dart';
import '../widgets/reports_stock_intel_card.dart';

/// Reports → Stock — card-based warehouse intel (ERP rebuild).
class ReportsStockTab extends ConsumerStatefulWidget {
  const ReportsStockTab({super.key, this.highlightSection});

  final String? highlightSection;

  @override
  ConsumerState<ReportsStockTab> createState() => _ReportsStockTabState();
}

class _ReportsStockTabState extends ConsumerState<ReportsStockTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chip = ReportsStockChipFilterX.fromHighlight(widget.highlightSection);
      if (chip != null) {
        ref.read(reportsStockChipFilterProvider.notifier).state = chip;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ops = ref.watch(operationalReportsProvider);

    return ops.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        final dio = e is DioException ? e : null;
        final offline = dio != null && dioIsNetworkError(dio);
        return Center(
          child: FriendlyLoadError(
            message: offline
                ? 'Could not load stock intel — check connection'
                : 'Could not load stock intel. Server error — tap to retry.',
            onRetry: () => ref.invalidate(operationalReportsProvider),
          ),
        );
      },
      data: (_) {
        final items = ref.watch(filteredReportsStockItemsProvider);
        final chip = ref.watch(reportsStockChipFilterProvider);

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: ReportsStockFilterSortBar()),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(filter: chip),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) =>
                      ReportsStockIntelCard(item: items[index]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final ReportsStockChipFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      ReportsStockChipFilter.dead => 'No dead stock found.',
      ReportsStockChipFilter.slow => 'No slow-moving items found.',
      ReportsStockChipFilter.fast => 'No fast-moving items in this window.',
      ReportsStockChipFilter.active => 'No active items with on-hand stock.',
      ReportsStockChipFilter.all => 'No stock items match your search.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: HexaDsType.bodyPrimary(context),
            ),
          ],
        ),
      ),
    );
  }
}
