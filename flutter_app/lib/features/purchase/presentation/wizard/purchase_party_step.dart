import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/providers/brokers_list_provider.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../state/purchase_draft_provider.dart';
import 'purchase_wizard_shared.dart';

/// Step 1 — date, human id, supplier, broker. Bottom CTA is parent's bar.
class PurchasePartyStep extends ConsumerWidget {
  const PurchasePartyStep({
    super.key,
    required this.isEdit,
    required this.loadedDerivedStatus,
    required this.loadedRemaining,
    required this.previewHumanId,
    required this.editHumanId,
    required this.supplierCtrl,
    required this.brokerCtrl,
    required this.supplierFieldError,
    required this.catalog,
    required this.supplierLastPurchaseById,
    required this.lastGoodSuppliers,
    required this.lastAutoSupplierFromCatalogSig,
    required this.onLastAutoSupplierFromCatalogSigChanged,
    required this.onDraftChanged,
    required this.supplierSubtitleFor,
    required this.supplierRowId,
    required this.supplierMapLabel,
    required this.sortSuppliers,
    required this.filterSuppliersByCatalog,
    required this.onSupplierSelectedSync,
    required this.openQuickSupplierCreate,
    required this.onSupplierClear,
    required this.supplierRowById,
    required this.applyBrokerFromSupplierRow,
    required this.applyBrokerSelection,
    required this.openQuickBrokerCreate,
    required this.brokerRowId,
    required this.brokerMapLabel,
  });

  final bool isEdit;
  final String? loadedDerivedStatus;
  final double? loadedRemaining;
  final String? previewHumanId;
  final String? editHumanId;
  final TextEditingController supplierCtrl;
  final TextEditingController brokerCtrl;
  final String? supplierFieldError;
  final List<Map<String, dynamic>> catalog;
  final Map<String, DateTime> supplierLastPurchaseById;
  final List<Map<String, dynamic>>? lastGoodSuppliers;
  final String? lastAutoSupplierFromCatalogSig;
  final void Function(String?) onLastAutoSupplierFromCatalogSigChanged;
  final VoidCallback onDraftChanged;

  final String Function(Map<String, dynamic>) supplierSubtitleFor;
  final String Function(Map<String, dynamic>) supplierRowId;
  final String Function(Map<String, dynamic>) supplierMapLabel;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
      sortSuppliers;
  final List<Map<String, dynamic>> Function(
          List<Map<String, dynamic>>, List<Map<String, dynamic>>)
      filterSuppliersByCatalog;
  final void Function(List<Map<String, dynamic>>, InlineSearchItem)
      onSupplierSelectedSync;
  final Future<void> Function(List<Map<String, dynamic>>) openQuickSupplierCreate;
  final VoidCallback onSupplierClear;

  final Map<String, dynamic>? Function(String supplierId) supplierRowById;
  final VoidCallback applyBrokerFromSupplierRow;
  final void Function(List<Map<String, dynamic>>, InlineSearchItem)
      applyBrokerSelection;
  final Future<void> Function(List<Map<String, dynamic>>) openQuickBrokerCreate;
  final String Function(Map<String, dynamic>) brokerRowId;
  final String Function(Map<String, dynamic>) brokerMapLabel;

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(purchaseDraftProvider);
    DateTime sel = draft.purchaseDate ?? DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime provisional = sel;
    final chosen = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) {
        final bg = CupertinoColors.systemBackground.resolveFrom(ctx);
        return Container(
          height: 300,
          color: bg,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      CupertinoButton(
                        child: const Text('Done'),
                        onPressed: () => Navigator.pop(ctx, provisional),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: sel.isAfter(today)
                        ? today
                        : (sel.isBefore(DateTime(2020)) ? DateTime(2020) : sel),
                    minimumDate: DateTime(2020),
                    maximumDate: today,
                    onDateTimeChanged: (dt) =>
                        provisional = DateTime(dt.year, dt.month, dt.day),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !context.mounted) return;
    ref.read(purchaseDraftProvider.notifier).setPurchaseDate(chosen);
    onDraftChanged();
  }

  Widget _supplierColumn(
    BuildContext context,
    WidgetRef ref, {
    required List<Map<String, dynamic>> list,
    required List<Map<String, dynamic>> lookupList,
    required bool narrowed,
  }) {
    if (list.isEmpty) {
      return const Text(
        'No suppliers in this workspace yet — add one under Suppliers or run bootstrap.',
        style: TextStyle(fontSize: 12),
      );
    }
    final sorted = sortSuppliers(list);
    final items = <InlineSearchItem>[
      for (final m in sorted)
        if (supplierRowId(m).isNotEmpty)
          InlineSearchItem(
            id: supplierRowId(m),
            label: supplierMapLabel(m),
            subtitle: supplierSubtitleFor(m),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrowed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Only suppliers saved as defaults for the catalog line(s) you added.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InlineSearchField(
                key: const ValueKey('purchase_supplier_search_v2'),
                controller: supplierCtrl,
                placeholder: 'Type at least 1 letter, then pick…',
                prefixIcon: const Icon(Icons.business),
                items: items,
                onSelected: (it) {
                  if (it.id.isEmpty) return;
                  onSupplierSelectedSync(lookupList, it);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add new supplier',
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF17A8A7)),
              onPressed: () => openQuickSupplierCreate(lookupList),
            ),
          ],
        ),
      ],
    );
  }

  Widget _brokerColumn(BuildContext context, List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Text(
        'No brokers yet — add one under Brokers or leave blank.',
        style: TextStyle(fontSize: 12),
      );
    }
    final items = <InlineSearchItem>[
      for (final m in list)
        if (brokerRowId(m).isNotEmpty)
          InlineSearchItem(id: brokerRowId(m), label: brokerMapLabel(m)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InlineSearchField(
            key: const ValueKey('purchase_broker_search_v2'),
            controller: brokerCtrl,
            placeholder: 'Broker (optional)…',
            prefixIcon: const Icon(Icons.person_search_outlined),
            items: items,
            onSelected: (it) {
              if (it.id.isEmpty) return;
              applyBrokerSelection(list, it);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Add new broker',
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF17A8A7)),
          onPressed: () => openQuickBrokerCreate(list),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    return LayoutBuilder(
      builder: (context, cts) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isEdit && loadedDerivedStatus != null) ...[
              Text(
                'Payment: $loadedDerivedStatus · Bal ₹${(loadedRemaining ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 6),
            ],
            SizedBox(
              height: kPurchaseFieldHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _pickDate(context, ref),
                      child: InputDecorator(
                        decoration:
                            densePurchaseFieldDecoration('Date'),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 16, color: HexaColors.brandPrimary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                DateFormat('dd MMM yyyy').format(
                                    draft.purchaseDate ?? DateTime.now()),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InputDecorator(
                      decoration: densePurchaseFieldDecoration(
                        isEdit ? 'Purchase ID' : 'ID (preview)',
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isEdit ? (editHumanId ?? '—') : (previewHumanId ?? 'Auto'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color:
                                isEdit ? Colors.black87 : HexaColors.brandPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  physics: MediaQuery.of(context).viewInsets.bottom > 0
                      ? null
                      : const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                      top:
                          MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Text('Supplier *',
                          style:
                              TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 4),
                      ref.watch(suppliersListProvider).when(
                            data: (list) {
                              final full =
                                  list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                              final filtered =
                                  filterSuppliersByCatalog(full, catalog);
                              final sig =
                                  '${ref.read(purchaseDraftProvider).lines.map((l) => l.catalogItemId ?? "").join(",")}|${filtered.length}|${full.length}';
                              if (filtered.length == 1 &&
                                  full.isNotEmpty &&
                                  (ref.read(purchaseDraftProvider).supplierId == null ||
                                      ref.read(purchaseDraftProvider).supplierId!.isEmpty)) {
                                if (lastAutoSupplierFromCatalogSig != sig) {
                                  onLastAutoSupplierFromCatalogSigChanged(sig);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    final d = ref.read(purchaseDraftProvider);
                                    if (d.supplierId != null &&
                                        d.supplierId!.isNotEmpty) {
                                      return;
                                    }
                                    if (filtered.length != 1) return;
                                    final row = filtered.first;
                                    if (supplierRowId(row).isEmpty) return;
                                    onSupplierSelectedSync(
                                      full,
                                      InlineSearchItem(
                                        id: supplierRowId(row),
                                        label: supplierMapLabel(row),
                                        subtitle:
                                            supplierSubtitleFor(row),
                                      ),
                                    );
                                  });
                                }
                              }
                              return _supplierColumn(context, ref,
                                  list: filtered,
                                  lookupList: full,
                                  narrowed: filtered.length < full.length);
                            },
                            error: (_, __) {
                              if (lastGoodSuppliers != null) {
                                final full = lastGoodSuppliers!
                                    .map((e) =>
                                        Map<String, dynamic>.from(e as Map))
                                    .toList();
                                return _supplierColumn(context, ref,
                                    list:
                                        filterSuppliersByCatalog(full, catalog),
                                    lookupList: full,
                                    narrowed: false);
                              }
                              return const Text('Could not load suppliers');
                            },
                            loading: () {
                              if (lastGoodSuppliers != null) {
                                final full = lastGoodSuppliers!
                                    .map((e) =>
                                        Map<String, dynamic>.from(e as Map))
                                    .toList();
                                return _supplierColumn(context, ref,
                                    list:
                                        filterSuppliersByCatalog(full, catalog),
                                    lookupList: full,
                                    narrowed: false);
                              }
                              return const LinearProgressIndicator();
                            },
                          ),
                      if (supplierFieldError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            supplierFieldError!,
                            style: TextStyle(color: Colors.red[800], fontSize: 12),
                          ),
                        ),
                      if (draft.supplierId != null &&
                          draft.supplierId!.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: onSupplierClear,
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Change supplier',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text('Broker (optional)',
                          style:
                              TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (bx) {
                        final supplierRow =
                            draft.supplierId != null && draft.supplierId!.isNotEmpty
                                ? supplierRowById(draft.supplierId!)
                                : null;
                        final defaultBid = supplierRow?['broker_id']?.toString();
                        final hasDefault = defaultBid != null &&
                            defaultBid.isNotEmpty &&
                            (draft.brokerId == null || draft.brokerId!.isEmpty);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (hasDefault)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: OutlinedButton.icon(
                                  onPressed: applyBrokerFromSupplierRow,
                                  icon: const Icon(Icons.link, size: 18),
                                  label: const Text('Use supplier’s default broker'),
                                ),
                              ),
                            if (draft.brokerId != null &&
                                draft.brokerId!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (draft.brokerName != null &&
                                                draft.brokerName!.trim().isNotEmpty)
                                            ? draft.brokerName!.trim()
                                            : 'Broker',
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        ref
                                            .read(purchaseDraftProvider.notifier)
                                            .setBroker(null, null);
                                        brokerCtrl.clear();
                                        onDraftChanged();
                                      },
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              ),
                            ref.watch(brokersListProvider).when(
                                  data: (list) =>
                                      _brokerColumn(context, list),
                                  error: (_, __) =>
                                      const Text('Could not load brokers'),
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
