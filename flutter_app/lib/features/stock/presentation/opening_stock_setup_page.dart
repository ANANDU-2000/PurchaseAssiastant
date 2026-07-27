import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_errors.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/design_system/hexa_responsive.dart';
import 'widgets/stock_pagination_bar.dart';

import 'widgets/opening_stock_sheets.dart';

class OpeningStockSetupPage extends ConsumerStatefulWidget {
  const OpeningStockSetupPage({super.key});

  @override
  ConsumerState<OpeningStockSetupPage> createState() =>
      _OpeningStockSetupPageState();
}

class _OpeningStockSetupPageState
    extends ConsumerState<OpeningStockSetupPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _searchExpanded = false;
  bool _selectionMode = false;

  void _toggleSelected(String id) {
    if (id.trim().isEmpty) return;
    final current = ref.read(openingStockBulkSelectionProvider);
    final next = <String>{...current};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    ref.read(openingStockBulkSelectionProvider.notifier).state = next;
    if (next.isEmpty && _selectionMode) {
      setState(() => _selectionMode = false);
    }
  }

  Future<void> _clearSelection() async {
    ref.read(openingStockBulkSelectionProvider.notifier).state = {};
    if (_selectionMode) {
      setState(() => _selectionMode = false);
    }
  }

  Future<void> _showBulkSetOpeningSheet(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return;
    final blob = ref.read(openingStockSetupProvider).valueOrNull;
    if (blob == null) return;

    final itemsRaw = (blob['items'] as List?) ?? const [];
    final selectedItems = itemsRaw
        .where((e) => e is Map && selectedIds.contains(e['id']?.toString()))
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (selectedItems.isEmpty) {
      await _clearSelection();
      return;
    }

    final units = selectedItems
        .map((it) => (it['stock_unit'] ?? it['unit'] ?? '').toString().trim())
        .where((u) => u.isNotEmpty)
        .toSet();
    if (units.length > 1) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select items with the same unit type')),
      );
      return;
    }

    final session = ref.read(sessionProvider);
    if (session == null) return;

    final businessId = session.primaryBusiness.id;
    final anyLocked = selectedItems.any((it) => it['opening_stock_locked'] == true);

    final ok = await showHexaBottomSheet<bool>(
      context: context,
      compact: true,
      child: _BulkOpeningSetSheetBody(
        businessId: businessId,
        items: selectedItems,
        anyLocked: anyLocked,
      ),
    );

    if (ok == true) {
      await _clearSelection();
      invalidateOpeningStockSaveSurfaces(
        ref,
        itemIds: selectedItems
            .map((it) => it['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final q = ref.read(openingStockSetupQueryProvider);
    _searchCtrl.text = q.q;
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final raw = _searchCtrl.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(openingStockSetupQueryProvider.notifier).state =
          ref.read(openingStockSetupQueryProvider).copyWith(
                q: raw,
                page: 1,
              );
    });
  }

  Future<void> _openFilters() async {
    await showOpeningStockFilters(context: context, ref: ref);
    ref.invalidate(openingStockSetupProvider);
  }

  Future<void> _openProgress(Map<String, dynamic> summary) async {
    await showOpeningStockProgressSheet(
      context: context,
      ref: ref,
      summary: summary,
    );
  }

  double _maxPage(int total, int perPage) {
    if (perPage <= 0) return 1;
    return (total / perPage).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(openingStockSetupQueryProvider);
    final listAsync = ref.watch(openingStockSetupProvider);
    final isReloading = listAsync.isLoading;
    final selectedIds = ref.watch(openingStockBulkSelectionProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: OpeningStockTopBar(
        searchExpanded: _searchExpanded,
        onToggleSearch: () => setState(() => _searchExpanded = !_searchExpanded),
        onOpenFilters: _openFilters,
        onOpenProgress: isReloading
            ? () {}
            : () {
                final s = listAsync.valueOrNull?['summary'];
                if (s is Map<String, dynamic>) unawaited(_openProgress(s));
              },
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userFacingError(e))),
        data: (data) {
          final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ??
              const {};
          final pendingCount = (summary['pending_count'] as num?)?.toInt() ?? 0;
          final completedCount =
              (summary['completed_count'] as num?)?.toInt() ?? 0;
          final totalCount = (summary['total_count'] as num?)?.toInt() ??
              (data['total'] as num?)?.toInt() ??
              0;
          final lastUpdatedAtIso = summary['last_updated_at']?.toString();
          final lastUpdatedBy = summary['last_updated_by']?.toString();

          final itemsRaw = (data['items'] as List?) ?? const [];
          final items = itemsRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

          final int perPage = (data['per_page'] as num?)?.toInt() ?? q.perPage;
          final int page = (data['page'] as num?)?.toInt() ?? q.page;
          final int total = (data['total'] as num?)?.toInt() ?? items.length;
          final maxPage = _maxPage(total, perPage).toInt().clamp(1, 9999);

          final desktop = context.isDesktopLayout;
          final scroll = CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: OpeningStockSummaryBar(
                    pendingCount: pendingCount,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    lastUpdatedAtIso: lastUpdatedAtIso,
                    lastUpdatedBy: lastUpdatedBy,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SearchHeaderDelegate(
                    expanded: _searchExpanded,
                    child: _OpeningStockSearchRow(
                      controller: _searchCtrl,
                      onClear: () {
                        _searchCtrl.clear();
                        ref
                            .read(openingStockSetupQueryProvider.notifier)
                            .state = q.copyWith(q: '', page: 1);
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: const OpeningStockFilterChips()),
                if (items.isNotEmpty) ...[
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _OpeningStockTableHeaderDelegate(),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => RepaintBoundary(
                        child: () {
                          final row = items[i];
                          final id = row['id']?.toString() ?? '';
                          return OpeningStockTableRow(
                            item: row,
                            selectionMode: _selectionMode,
                            isSelected: selectedIds.contains(id),
                            onToggleSelected: () => _toggleSelected(id),
                            onLongPress: () {
                              if (id.isEmpty) return;
                              if (!_selectionMode) {
                                setState(() => _selectionMode = true);
                              }
                              _toggleSelected(id);
                            },
                            onMissingBarcodeTap: () {
                              context.push('/stock/missing-barcodes');
                            },
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelected(id);
                                return;
                              }
                              unawaited(
                                showOpeningStockRowActions(
                                  context: context,
                                  ref: ref,
                                  item: row,
                                ),
                              );
                            },
                          );
                        }(),
                      ),
                      childCount: items.length,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: StockPaginationBar(
                      showingCount: items.length,
                      totalCount: total,
                      currentPage: page,
                      maxPage: maxPage,
                      loading: isReloading,
                      onPrev: page > 1
                          ? () {
                              ref.read(openingStockSetupQueryProvider.notifier).state =
                                  q.copyWith(page: page - 1);
                            }
                          : null,
                      onNext: page < maxPage
                          ? () {
                              ref.read(openingStockSetupQueryProvider.notifier).state =
                                  q.copyWith(page: page + 1);
                            }
                          : null,
                    ),
                  ),
                ],
                if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No opening stock items match filters.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                  ),
              ],
            );

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(openingStockSetupProvider);
              await ref.read(openingStockSetupProvider.future);
            },
            child: desktop
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: scroll,
                    ),
                  )
                : scroll,
          );
        },
      ),
      bottomNavigationBar: (_selectionMode && selectedIds.isNotEmpty)
          ? _BulkSelectionBar(
              selectedCount: selectedIds.length,
              onCancel: () => _clearSelection(),
              onBulkSet: () => _showBulkSetOpeningSheet(selectedIds),
            )
          : null,
    );
  }
}

class _OpeningStockSearchRow extends StatelessWidget {
  const _OpeningStockSearchRow({
    required this.controller,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        HexaResponsive.pageGutter(context, operational: true),
        4,
        HexaResponsive.pageGutter(context, operational: true),
        4,
      ),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search item, code, barcode…',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
              tooltip: 'Clear',
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD8D5D0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD8D5D0)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SearchHeaderDelegate({
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  double get minExtent => expanded ? 44 : 0;

  @override
  double get maxExtent => expanded ? 44 : 0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    if (!expanded) return const SizedBox.shrink();
    return child;
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) {
    return expanded != oldDelegate.expanded || child != oldDelegate.child;
  }
}

class _OpeningStockTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _OpeningStockTableHeaderDelegate();

  static const double _height = 34;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return const ColoredBox(
      color: Color(0xFFF5F3EE),
      child: OpeningStockTableHeader(),
    );
  }

  @override
  bool shouldRebuild(covariant _OpeningStockTableHeaderDelegate old) => false;
}

class _BulkSelectionBar extends StatelessWidget {
  const _BulkSelectionBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onBulkSet,
  });

  final int selectedCount;
  final Future<void> Function() onCancel;
  final Future<void> Function() onBulkSet;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: const Color(0xFFF8FAFC),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => onCancel(),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => onBulkSet(),
                child: const Text('Set opening qty'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkOpeningSetSheetBody extends ConsumerStatefulWidget {
  const _BulkOpeningSetSheetBody({
    required this.businessId,
    required this.items,
    required this.anyLocked,
  });

  final String businessId;
  final List<Map<String, dynamic>> items;
  final bool anyLocked;

  @override
  ConsumerState<_BulkOpeningSetSheetBody> createState() =>
      _BulkOpeningSetSheetBodyState();
}

class _BulkOpeningSetSheetBodyState
    extends ConsumerState<_BulkOpeningSetSheetBody> {
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_saving) return;
    final parsed = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid opening stock quantity')),
      );
      return;
    }

    final reason = _reasonCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    final perItemNeedReason = <String, bool>{};
    var requireAnyReason = false;
    for (final it in widget.items) {
      final id = it['id']?.toString() ?? '';
      final locked = it['opening_stock_locked'] == true;
      final current = coerceToDoubleNullable(it['opening_stock_qty']);
      final changed =
          current == null ? true : (parsed - current).abs() > 0.001;
      final needs = locked && changed;
      perItemNeedReason[id] = needs;
      if (needs) requireAnyReason = true;
    }

    if (requireAnyReason && reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reason is required for locked edits')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(hexaApiProvider);
      final total = widget.items.length;
      var done = 0;
      for (final it in widget.items) {
        done++;
        final id = it['id']?.toString() ?? '';
        final locked = it['opening_stock_locked'] == true;
        final needsReason = perItemNeedReason[id] == true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Setting opening ($done/$total)…'),
            duration: const Duration(seconds: 1),
          ),
        );

        await api.setOpeningStock(
          businessId: widget.businessId,
          itemId: id,
          qty: parsed,
          override: locked,
          reason: needsReason ? reason : null,
          notes: notes.isEmpty ? null : notes,
          idempotencyKey:
              'bulk-opening:${widget.businessId}:$id:${DateTime.now().microsecondsSinceEpoch}',
        );

        // Keep UI snappy on returns; data refresh happens via invalidations below.
      }

      invalidateOpeningStockSaveSurfaces(
        ref,
        itemIds: widget.items
            .map((it) => it['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );

      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HexaResponsiveSheetViewport(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          const Text(
            'Bulk set opening stock',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Qty',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.anyLocked) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (required if locked value changes)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _apply,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Apply to selected'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
