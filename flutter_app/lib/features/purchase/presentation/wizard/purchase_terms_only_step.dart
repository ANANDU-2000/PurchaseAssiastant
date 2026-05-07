import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';
import 'purchase_wizard_shared.dart';

/// Step 2 — deal terms once (vertical, no side‑by‑side rows on narrow screens).
class PurchaseTermsOnlyStep extends ConsumerWidget {
  const PurchaseTermsOnlyStep({
    super.key,
    required this.paymentDaysCtrl,
    required this.commissionCtrl,
    required this.headerDiscCtrl,
    required this.narrationCtrl,
    required this.onDraftChanged,
  });

  final TextEditingController paymentDaysCtrl;
  final TextEditingController commissionCtrl;
  final TextEditingController headerDiscCtrl;
  /// Stored on wire as `invoice_number`; UX label = Narration/Ref.
  final TextEditingController narrationCtrl;
  final VoidCallback onDraftChanged;

  static String _duePreview(WidgetRef ref, TextEditingController c) {
    final pd = int.tryParse(c.text.trim());
    if (pd == null || pd < 0) return 'Due: —';
    final d0 = ref.read(purchaseDraftProvider).purchaseDate ?? DateTime.now();
    final d = d0.add(Duration(days: pd));
    return 'Due: ${DateFormat('dd MMM yyyy').format(d)}';
  }

  /// Short label for the fixed-commission **unit** dropdown (same row as ₹).
  static String _unitDropdownLabel(String mode) {
    switch (PurchaseDraft.normalizeCommissionMode(mode)) {
      case kPurchaseCommissionModeFlatInvoice:
        return 'Once / bill';
      case kPurchaseCommissionModeFlatKg:
        return 'Kg';
      case kPurchaseCommissionModeFlatBag:
        return 'Bag';
      case kPurchaseCommissionModeFlatBox:
        return 'Box';
      case kPurchaseCommissionModeFlatTin:
        return 'Tin';
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) {
      return const Center(
        child: Text(
          'Select a supplier first.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }
    final hasBroker =
        draft.brokerId != null && draft.brokerId!.trim().isNotEmpty;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final mode = draft.commissionMode;

    Widget field(
      TextEditingController c,
      String label, {
      TextInputType? keyboard,
      int maxLines = 1,
      void Function(String)? onChanged,
    }) {
      final tf = TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 1 : null,
        scrollPadding: const EdgeInsets.only(bottom: 200),
        textCapitalization: maxLines > 1
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: densePurchaseFieldDecoration(label),
        onChanged: onChanged,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // Avoid fixed-height wrappers; they cause clipping/overlap on small phones
        // with larger text scale and when the keyboard is open.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kPurchaseFieldHeight),
          child: tf,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (draft.supplierName != null && draft.supplierName!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high,
                      size: 16, color: Color(0xFF0D9488)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Defaults from ${draft.supplierName!.trim()} (editable)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Payment terms',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        field(
          paymentDaysCtrl,
          'Payment days',
          keyboard: TextInputType.number,
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setPaymentDaysText(s);
            onDraftChanged();
          },
        ),
        ListenableBuilder(
          listenable: paymentDaysCtrl,
          builder: (_, __) {
            final t = paymentDaysCtrl.text.trim();
            if (t.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _duePreview(ref, paymentDaysCtrl),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF0D9488),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
        if (hasBroker) ...[
          Text(
            'Broker commission',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<String>(
                value: kPurchaseCommissionModePercent,
                label: Text('Commission %'),
                icon: Icon(Icons.percent_rounded, size: 18),
              ),
              ButtonSegment<String>(
                value: '_figure',
                label: Text('Fixed ₹'),
                icon: Icon(Icons.currency_rupee_rounded, size: 18),
              ),
            ],
            emptySelectionAllowed: false,
            selected: <String>{
              if (mode == kPurchaseCommissionModePercent)
                kPurchaseCommissionModePercent
              else
                '_figure',
            },
            onSelectionChanged: (Set<String> next) {
              final v = next.first;
              if (v == kPurchaseCommissionModePercent) {
                ref
                    .read(purchaseDraftProvider.notifier)
                    .setCommissionMode(kPurchaseCommissionModePercent);
              } else {
                final sug =
                    suggestedBrokerFigureModeFromLines(draft.lines);
                ref.read(purchaseDraftProvider.notifier).setCommissionMode(sug);
              }
              onDraftChanged();
            },
          ),
          if (mode == kPurchaseCommissionModePercent) ...[
            const SizedBox(height: 6),
            Text(
              '% of each line ₹ total after purchase discount. '
              'For ₹ per kg / bag / tin, switch to Fixed ₹.',
              style: TextStyle(fontSize: 11, height: 1.25, color: sub),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kPurchaseFieldHeight),
              child: TextField(
                controller: commissionCtrl,
                scrollPadding: const EdgeInsets.only(bottom: 200),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: densePurchaseFieldDecoration('Commission %')
                    .copyWith(suffixText: '%'),
                onChanged: (s) {
                  ref.read(purchaseDraftProvider.notifier).setCommissionText(s);
                  onDraftChanged();
                },
              ),
            ),
          ] else ...[
            Builder(
              builder: (context) {
                final figOpts = brokerFigureUiOptions(draft.lines);
                final allowed = figOpts.map((e) => e.$1).toSet();
                final coerced = allowed.contains(mode)
                    ? mode
                    : clampFigureModeToUiOptions(mode, draft.lines);
                if (coerced != mode) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ref
                        .read(purchaseDraftProvider.notifier)
                        .setCommissionMode(coerced);
                    onDraftChanged();
                  });
                }

                final hint =
                    brokerFigureBasisLineHint(draft.lines, coerced);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      'Choose what the ₹ amount multiplies by. '
                      'You can set this before adding items; hints update after lines exist.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: sub,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: kPurchaseFieldHeight),
                      child: TextField(
                        controller: commissionCtrl,
                        scrollPadding: const EdgeInsets.only(bottom: 200),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: densePurchaseFieldDecoration(
                          'Amount (₹)',
                        ),
                        onChanged: (s) {
                          ref
                              .read(purchaseDraftProvider.notifier)
                              .setCommissionText(s);
                          onDraftChanged();
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: densePurchaseFieldDecoration(
                        'Commission applies to',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: coerced,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            for (final o in figOpts)
                              DropdownMenuItem<String>(
                                value: o.$1,
                                child: Text(
                                  _unitDropdownLabel(o.$1),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            ref
                                .read(purchaseDraftProvider.notifier)
                                .setCommissionMode(v);
                            onDraftChanged();
                          },
                        ),
                      ),
                    ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          hint,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            color: sub,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
        field(
          headerDiscCtrl,
          'Discount %',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setHeaderDiscountFromText(s);
            onDraftChanged();
          },
        ),
        field(
          narrationCtrl,
          'Narration / ref (optional)',
          keyboard: TextInputType.text,
          maxLines: 2,
          onChanged: (s) {
            ref.read(purchaseDraftProvider.notifier).setInvoiceText(s);
            onDraftChanged();
          },
        ),
      ],
    );
  }
}
