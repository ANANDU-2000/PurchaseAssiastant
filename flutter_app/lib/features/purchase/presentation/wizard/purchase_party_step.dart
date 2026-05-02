import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/providers/brokers_list_provider.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../state/purchase_draft_provider.dart';
import '../widgets/party_inline_suggest_field.dart';

/// Party step — minimal two-column supplier / broker layout (keyboard-driven flow).
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
    required this.supplierFocusNode,
    required this.brokerFocusNode,
    required this.onProceedFromParty,
    required this.supplierFieldError,
    required this.catalog,
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
  final FocusNode supplierFocusNode;
  final FocusNode brokerFocusNode;

  /// After broker IME “next”: advance to Items when supplier gate passes.
  final VoidCallback onProceedFromParty;

  final String? supplierFieldError;
  final List<Map<String, dynamic>> catalog;
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
    List<Map<String, dynamic>>,
    List<Map<String, dynamic>>,
  ) filterSuppliersByCatalog;
  final void Function(List<Map<String, dynamic>>, InlineSearchItem)
      onSupplierSelectedSync;
  final Future<void> Function(List<Map<String, dynamic>>)
      openQuickSupplierCreate;
  final VoidCallback onSupplierClear;

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

  Widget _compactMeta(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    final dateTxt =
        DateFormat('dd MMM yy').format(draft.purchaseDate ?? DateTime.now());
    final idVal = isEdit ? (editHumanId ?? '—') : (previewHumanId ?? 'Auto');
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        InkWell(
          onTap: () => _pickDate(context, ref),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: Text(
              dateTxt,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: HexaColors.brandPrimary,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            idVal,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: isEdit ? Colors.black87 : sub,
            ),
          ),
        ),
      ],
    );
  }

  List<InlineSearchItem> _supplierItems(List<Map<String, dynamic>> filtered) {
    final sorted = sortSuppliers(filtered);
    final items = <InlineSearchItem>[
      for (final m in sorted)
        if (supplierRowId(m).isNotEmpty)
          InlineSearchItem(
            id: supplierRowId(m),
            label: supplierMapLabel(m),
            subtitle: supplierSubtitleFor(m),
          ),
    ];
    return items;
  }

  List<InlineSearchItem> _brokerItems(List<Map<String, dynamic>> list) {
    return [
      for (final m in list)
        if (brokerRowId(m).isNotEmpty)
          InlineSearchItem(id: brokerRowId(m), label: brokerMapLabel(m)),
    ];
  }

  /// Single row: supplier | broker (+ inline lists).
  Widget _partyFieldsRow(BuildContext context, WidgetRef ref) {
    Widget supplierCell = ref.watch(suppliersListProvider).when(
      data: (list) {
        final full =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final filtered = filterSuppliersByCatalog(full, catalog);

        final sig =
            '${ref.read(purchaseDraftProvider).lines.map((l) => l.catalogItemId ?? "").join(",")}|${filtered.length}|${full.length}';
        if (filtered.length == 1 &&
            full.isNotEmpty &&
            (ref.read(purchaseDraftProvider).supplierId == null ||
                ref.read(purchaseDraftProvider).supplierId!.isEmpty)) {
          if (lastAutoSupplierFromCatalogSig != sig) {
            onLastAutoSupplierFromCatalogSigChanged(sig);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final d = ref.read(purchaseDraftProvider);
              if (d.supplierId != null && d.supplierId!.isNotEmpty) {
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
                  subtitle: supplierSubtitleFor(row),
                ),
              );
            });
          }
        }

        final items = _supplierItems(filtered);
        return PartyInlineSuggestField(
          controller: supplierCtrl,
          focusNode: supplierFocusNode,
          hintText: 'Supplier',
          prefixIcon: const Icon(Icons.store_rounded),
          minQueryLength: 1,
          maxMatches: 8,
          dense: true,
          textInputAction: TextInputAction.next,
          onSubmitted: () => brokerFocusNode.requestFocus(),
          items: items,
          showAddRow: full.isNotEmpty,
          addRowLabel: 'New supplier…',
          onAddRow: () => openQuickSupplierCreate(full),
          onSelected: (it) {
            if (it.id.isEmpty) return;
            onSupplierSelectedSync(full, it);
          },
        );
      },
      error: (_, __) {
        if (lastGoodSuppliers != null) {
          final full = lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final filtered = filterSuppliersByCatalog(full, catalog);
          final items = _supplierItems(filtered);
          return PartyInlineSuggestField(
            controller: supplierCtrl,
            focusNode: supplierFocusNode,
            hintText: 'Supplier',
            prefixIcon: const Icon(Icons.store_rounded),
            minQueryLength: 1,
            maxMatches: 8,
            dense: true,
            textInputAction: TextInputAction.next,
            onSubmitted: () => brokerFocusNode.requestFocus(),
            items: items,
            showAddRow: true,
            addRowLabel: 'New supplier…',
            onAddRow: () => openQuickSupplierCreate(full),
            onSelected: (it) {
              if (it.id.isEmpty) return;
              onSupplierSelectedSync(full, it);
            },
          );
        }
        return Text(
          'Could not load suppliers',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      },
      loading: () {
        if (lastGoodSuppliers != null) {
          final full = lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final filtered = filterSuppliersByCatalog(full, catalog);
          final items = _supplierItems(filtered);
          return PartyInlineSuggestField(
            controller: supplierCtrl,
            focusNode: supplierFocusNode,
            hintText: 'Supplier',
            prefixIcon: const Icon(Icons.store_rounded),
            minQueryLength: 1,
            maxMatches: 8,
            dense: true,
            textInputAction: TextInputAction.next,
            onSubmitted: () => brokerFocusNode.requestFocus(),
            items: items,
            showAddRow: true,
            addRowLabel: 'New supplier…',
            onAddRow: () => openQuickSupplierCreate(full),
            onSelected: (it) {
              if (it.id.isEmpty) return;
              onSupplierSelectedSync(full, it);
            },
          );
        }
        return const LinearProgressIndicator(minHeight: 2);
      },
    );

    if (supplierFieldError != null) {
      supplierCell = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          supplierCell,
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              supplierFieldError!,
              style: TextStyle(color: Colors.red[800], fontSize: 11),
            ),
          ),
        ],
      );
    }

    Widget brokerCell = Builder(
      builder: (cx) {
        return ref.watch(brokersListProvider).when(
              data: (brokersRaw) {
                final brokers = brokersRaw
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final items = _brokerItems(brokers);
                return PartyInlineSuggestField(
                  controller: brokerCtrl,
                  focusNode: brokerFocusNode,
                  hintText: 'Broker',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  minQueryLength: 0,
                  maxMatches: 8,
                  dense: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: onProceedFromParty,
                  items: items,
                  showAddRow: brokers.isNotEmpty,
                  addRowLabel: 'New broker…',
                  onAddRow: () => openQuickBrokerCreate(brokers),
                  onSelected: (it) {
                    if (it.id.isEmpty) return;
                    applyBrokerSelection(brokers, it);
                  },
                );
              },
              error: (_, __) => Text(
                'Could not load brokers',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(cx).colorScheme.error,
                ),
              ),
              loading: () => const LinearProgressIndicator(minHeight: 2),
            );
      },
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: supplierCell),
        const SizedBox(width: 8),
        Expanded(flex: 1, child: brokerCell),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showClearSupplier = ref.watch(
      purchaseDraftProvider.select(
        (d) => (d.supplierId != null && d.supplierId!.isNotEmpty),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEdit && loadedDerivedStatus != null) ...[
          Text(
            'Payment: $loadedDerivedStatus · Bal ₹${(loadedRemaining ?? 0).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 4),
        ],
        _compactMeta(context, ref),
        const SizedBox(height: 6),
        _partyFieldsRow(context, ref),
        if (showClearSupplier)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: onSupplierClear,
              child: Text(
                'Clear supplier',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
