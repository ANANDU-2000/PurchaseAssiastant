import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/session.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/providers/brokers_list_provider.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../state/purchase_draft_provider.dart';
import '../widgets/party_inline_suggest_field.dart';

/// Party step — full-width supplier, then broker, stacked vertically.
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

  /// Silent empty lists hide why autocomplete never opens—surface session / API / IDs.
  Widget _supplierListNotice(
    BuildContext context,
    WidgetRef ref, {
    required Session? session,
    required Widget supplierField,
    required List<InlineSearchItem> items,
    required List<Map<String, dynamic>> fullRaw,
  }) {
    if (session != null && items.isNotEmpty) return supplierField;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final msg = session == null
        ? 'Sign in to load suppliers.'
        : fullRaw.isEmpty
            ? 'No suppliers loaded yet. Reload below—or focus this field, then New supplier…'
            : 'Suppliers arrived but couldn’t be shown (missing IDs). Reload or check your data.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        supplierField,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            msg,
            style: TextStyle(fontSize: 11, height: 1.25, color: sub),
          ),
        ),
        if (session != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.invalidate(suppliersListProvider),
              child: const Text('Reload suppliers'),
            ),
          ),
      ],
    );
  }

  Widget _brokerListNotice(
    BuildContext context,
    WidgetRef ref, {
    required Session? session,
    required Widget brokerField,
    required List<InlineSearchItem> items,
    required List<Map<String, dynamic>> brokersRaw,
  }) {
    if (session != null && items.isNotEmpty) return brokerField;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final msg = session == null
        ? 'Sign in to load brokers.'
        : brokersRaw.isEmpty
            ? 'No brokers loaded yet. Reload—or focus this field, then New broker…'
            : 'Brokers arrived but couldn’t be shown (missing IDs). Reload or check your data.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        brokerField,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            msg,
            style: TextStyle(fontSize: 11, height: 1.25, color: sub),
          ),
        ),
        if (session != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.invalidate(brokersListProvider),
              child: const Text('Reload brokers'),
            ),
          ),
      ],
    );
  }

  /// Full-width supplier (with suggestions under field), spacing, full-width broker.
  Widget _partyFieldsColumn(BuildContext context, WidgetRef ref) {
    Widget supplierCell = ref.watch(suppliersListProvider).when(
      data: (list) {
        final session = ref.watch(sessionProvider);
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
        final field = PartyInlineSuggestField(
          controller: supplierCtrl,
          focusNode: supplierFocusNode,
          hintText: 'Search supplier by name…',
          prefixIcon: const Icon(Icons.store_rounded),
          minQueryLength: 1,
          maxMatches: 8,
          dense: true,
          textInputAction: TextInputAction.next,
          onSubmitted: () => brokerFocusNode.requestFocus(),
          items: items,
          showAddRow: session != null,
          addRowLabel: 'New supplier…',
          onAddRow: () => openQuickSupplierCreate(full),
          onSelected: (it) {
            if (it.id.isEmpty) return;
            onSupplierSelectedSync(full, it);
          },
        );
        return _supplierListNotice(
          context,
          ref,
          session: session,
          supplierField: field,
          items: items,
          fullRaw: full,
        );
      },
      error: (_, __) {
        if (lastGoodSuppliers != null) {
          final session = ref.watch(sessionProvider);
          final full = lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final filtered = filterSuppliersByCatalog(full, catalog);
          final items = _supplierItems(filtered);
          final field = PartyInlineSuggestField(
            controller: supplierCtrl,
            focusNode: supplierFocusNode,
            hintText: 'Search supplier by name…',
            prefixIcon: const Icon(Icons.store_rounded),
            minQueryLength: 1,
            maxMatches: 8,
            dense: true,
            textInputAction: TextInputAction.next,
            onSubmitted: () => brokerFocusNode.requestFocus(),
            items: items,
            showAddRow: session != null,
            addRowLabel: 'New supplier…',
            onAddRow: () => openQuickSupplierCreate(full),
            onSelected: (it) {
              if (it.id.isEmpty) return;
              onSupplierSelectedSync(full, it);
            },
          );
          return _supplierListNotice(
            context,
            ref,
            session: session,
            supplierField: field,
            items: items,
            fullRaw: full,
          );
        }
        final cs = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load suppliers.',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
            TextButton(
              onPressed: () => ref.invalidate(suppliersListProvider),
              child: const Text('Retry'),
            ),
          ],
        );
      },
      loading: () {
        if (lastGoodSuppliers != null) {
          final session = ref.watch(sessionProvider);
          final full = lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final filtered = filterSuppliersByCatalog(full, catalog);
          final items = _supplierItems(filtered);
          final field = PartyInlineSuggestField(
            controller: supplierCtrl,
            focusNode: supplierFocusNode,
            hintText: 'Search supplier by name…',
            prefixIcon: const Icon(Icons.store_rounded),
            minQueryLength: 1,
            maxMatches: 8,
            dense: true,
            textInputAction: TextInputAction.next,
            onSubmitted: () => brokerFocusNode.requestFocus(),
            items: items,
            showAddRow: session != null,
            addRowLabel: 'New supplier…',
            onAddRow: () => openQuickSupplierCreate(full),
            onSelected: (it) {
              if (it.id.isEmpty) return;
              onSupplierSelectedSync(full, it);
            },
          );
          return _supplierListNotice(
            context,
            ref,
            session: session,
            supplierField: field,
            items: items,
            fullRaw: full,
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
                final session = ref.watch(sessionProvider);
                final brokers = brokersRaw
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final items = _brokerItems(brokers);
                final field = PartyInlineSuggestField(
                  controller: brokerCtrl,
                  focusNode: brokerFocusNode,
                  hintText: 'Search broker by name…',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  minQueryLength: 0,
                  maxMatches: 8,
                  dense: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: onProceedFromParty,
                  items: items,
                  showAddRow: session != null,
                  addRowLabel: 'New broker…',
                  onAddRow: () => openQuickBrokerCreate(brokers),
                  onSelected: (it) {
                    if (it.id.isEmpty) return;
                    applyBrokerSelection(brokers, it);
                  },
                );
                return _brokerListNotice(
                  context,
                  ref,
                  session: session,
                  brokerField: field,
                  items: items,
                  brokersRaw: brokers,
                );
              },
              error: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load brokers.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(cx).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(brokersListProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(minHeight: 2),
            );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        supplierCell,
        const SizedBox(height: 16),
        brokerCell,
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showClearSupplier = ref.watch(
      purchaseDraftProvider.select(
        (d) =>
            d.supplierId != null &&
            d.supplierId!.isNotEmpty,
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
        _partyFieldsColumn(context, ref),
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
