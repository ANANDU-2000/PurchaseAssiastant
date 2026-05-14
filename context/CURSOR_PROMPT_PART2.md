# 🔧 HARISREE PURCHASE ASSISTANT — CURSOR PROMPT PART 2
**Supplement to:** `CURSOR_MASTER_PROMPT.md`  
**Date:** 12 May 2026  
**Stack:** Flutter (Riverpod) + FastAPI + Supabase

> Read `CURSOR_MASTER_PROMPT.md` first. This file covers 6 additional issues confirmed from new screenshots. Work through each numbered section in order. Run `flutter analyze` after each section.

---

## 📋 ADDITIONAL ISSUES — TABLE OF CONTENTS

1. [CRITICAL: Suggestion List — Scroll + Smart Close (Deep Fix)](#1-critical-suggestion-list--scroll--smart-close-deep-fix)
2. [HIGH: Purchase Order Cards — Bold Days / Bags / KG Numbers](#2-high-purchase-order-cards--bold-days--bags--kg-numbers)
3. [HIGH: PDF Share — Include Supplier, Broker, Date + Remove Junk](#3-high-pdf-share--include-supplier-broker-date--remove-junk)
4. [HIGH: ZIP Export — Add Order PDFs + Ledger + Statements](#4-high-zip-export--add-order-pdfs--ledger--statements)
5. [MEDIUM: Add Item Button — Sticky Bottom + Auto-Scroll (Deep Fix)](#5-medium-add-item-button--sticky-bottom--auto-scroll-deep-fix)
6. [MEDIUM: Reports Page — Confirm Speed & Tab Response](#6-medium-reports-page--confirm-speed--tab-response)

---

## 1. CRITICAL: Suggestion List — Scroll + Smart Close (Deep Fix)

### 📸 Screenshot Evidence
**Image 5 → Image 6:** User types "su" → suggestions appear (SUMATHI SPICES, SUMATHI TRADINGS, etc.) → any accidental touch collapses the entire list → field still shows "su" with nothing selected → user is stuck. Same bug confirmed for broker search and item search.

### 🔍 Exact Root Cause (Code-level)

In `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart` and supplier/broker/item search widgets, the focus listener pattern is:

```dart
// BUG: FocusNode listener fires before tap completes on suggestion items
_focusNode.addListener(() {
  if (!_focusNode.hasFocus) {
    setState(() => _showDropdown = false); // closes before tap registers
  }
});
```

The sequence of events:
1. User taps suggestion item
2. Flutter fires `PointerDown` → text field loses focus (onFocusChange fires)
3. `_showDropdown = false` → list rebuilds → suggestion item disappears
4. `PointerUp` fires on nothing → selection never registered

### ✅ Complete Fix — Rewrite Suggestion Widget

**Create new shared widget:** `flutter_app/lib/shared/widgets/smart_search_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A search field whose suggestion list:
/// - Scrolls internally (never closes on internal scroll/touch)
/// - Closes ONLY when user taps OUTSIDE the entire field+list area
/// - Shows a close (✕) icon to dismiss manually
/// - Uses DraggableScrollableSheet on mobile for large lists
class SmartSearchField<T> extends StatefulWidget {
  final String hintText;
  final String Function(T) labelBuilder;
  final String? Function(T)? subtitleBuilder;
  final Future<List<T>> Function(String query) onSearch;
  final void Function(T selected) onSelected;
  final TextEditingController? controller;
  final Widget? prefixIcon;
  final bool autofocus;
  final int maxSuggestionsInline; // beyond this → bottom sheet

  const SmartSearchField({
    super.key,
    required this.hintText,
    required this.labelBuilder,
    required this.onSearch,
    required this.onSelected,
    this.subtitleBuilder,
    this.controller,
    this.prefixIcon,
    this.autofocus = false,
    this.maxSuggestionsInline = 6,
  });

  @override
  State<SmartSearchField<T>> createState() => _SmartSearchFieldState<T>();
}

class _SmartSearchFieldState<T> extends State<SmartSearchField<T>> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  List<T> _suggestions = [];
  bool _showSuggestions = false;
  bool _isLoading = false;
  // Flag: user is currently touching inside the suggestion list
  bool _touchingInsideSuggestions = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    // Only close suggestions when focus lost AND NOT touching inside suggestions
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && !_touchingInsideSuggestions) {
        // Delay to allow tap to complete
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_touchingInsideSuggestions) {
            setState(() => _showSuggestions = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String query) async {
    if (query.isEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    setState(() { _isLoading = true; _showSuggestions = true; });
    final results = await widget.onSearch(query);
    if (mounted) setState(() { _suggestions = results; _isLoading = false; });
  }

  void _selectItem(T item) {
    widget.onSelected(item);
    _ctrl.text = widget.labelBuilder(item);
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    setState(() { _showSuggestions = false; _suggestions = []; });
    _focusNode.unfocus();
    HapticFeedback.selectionClick();
  }

  void _openBottomSheetPicker() {
    _focusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SuggestionBottomSheet<T>(
        initialQuery: _ctrl.text,
        labelBuilder: widget.labelBuilder,
        subtitleBuilder: widget.subtitleBuilder,
        onSearch: widget.onSearch,
        onSelected: (item) {
          Navigator.pop(ctx);
          _selectItem(item);
        },
        hintText: widget.hintText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      // Tapping OUTSIDE this region (field + inline list) closes suggestions
      onTapOutside: (_) {
        if (!_touchingInsideSuggestions) {
          setState(() => _showSuggestions = false);
          _focusNode.unfocus();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Search field ──────────────────────────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _focusNode.hasFocus ? [
                BoxShadow(
                  color: const Color(0xFF1A7A6A).withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ] : [],
            ),
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onChanged: _onChanged,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: Color(0xFF1A3A35),
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: widget.prefixIcon,
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() { _suggestions = []; _showSuggestions = false; });
                          _focusNode.requestFocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5FFFE),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCCE5E2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCCE5E2), width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A7A6A), width: 2.5)),
              ),
            ),
          ),

          // ── Inline suggestion list (up to maxSuggestionsInline) ──
          if (_showSuggestions) ...[
            const SizedBox(height: 4),
            Container(
              constraints: BoxConstraints(
                maxHeight: _suggestions.length > widget.maxSuggestionsInline
                    ? widget.maxSuggestionsInline * 64.0
                    : _suggestions.length * 64.0 + 48,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0F2F1)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header row with item count + close
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          _isLoading ? 'Searching...' : '${_suggestions.length} results',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                        ),
                        const Spacer(),
                        // Scroll hint if many items
                        if (_suggestions.length > widget.maxSuggestionsInline)
                          TextButton.icon(
                            onPressed: _openBottomSheetPicker,
                            icon: const Icon(Icons.open_in_full, size: 14),
                            label: const Text('See all', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF1A7A6A),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                          ),
                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Color(0xFF888888)),
                          onPressed: () => setState(() => _showSuggestions = false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A7A6A)),
                    )
                  else
                    Flexible(
                      child: Listener(
                        // Track when user is touching inside suggestion list
                        onPointerDown: (_) => _touchingInsideSuggestions = true,
                        onPointerUp: (_) => Future.delayed(
                          const Duration(milliseconds: 300),
                          () => _touchingInsideSuggestions = false,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          itemBuilder: (_, i) {
                            final item = _suggestions[i];
                            return InkWell(
                              onTap: () => _selectItem(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.labelBuilder(item),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A3A35)),
                                    ),
                                    if (widget.subtitleBuilder != null && widget.subtitleBuilder!(item) != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.subtitleBuilder!(item)!,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen bottom sheet for large suggestion lists
class _SuggestionBottomSheet<T> extends StatefulWidget {
  final String initialQuery;
  final String hintText;
  final String Function(T) labelBuilder;
  final String? Function(T)? subtitleBuilder;
  final Future<List<T>> Function(String) onSearch;
  final void Function(T) onSelected;

  const _SuggestionBottomSheet({
    required this.initialQuery,
    required this.hintText,
    required this.labelBuilder,
    required this.onSearch,
    required this.onSelected,
    this.subtitleBuilder,
  });

  @override
  State<_SuggestionBottomSheet<T>> createState() => _SuggestionBottomSheetState<T>();
}

class _SuggestionBottomSheetState<T> extends State<_SuggestionBottomSheet<T>> {
  late final TextEditingController _ctrl;
  List<T> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _search(widget.initialQuery);
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final r = await widget.onSearch(q);
    if (mounted) setState(() { _results = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1A7A6A)),
                suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                filled: true, fillColor: const Color(0xFFF5FFFE),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A7A6A), width: 2)),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: Color(0xFF1A7A6A), minHeight: 2),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final item = _results[i];
                return ListTile(
                  title: Text(widget.labelBuilder(item), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: widget.subtitleBuilder != null ? Text(widget.subtitleBuilder!(item) ?? '') : null,
                  onTap: () => widget.onSelected(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### How to Wire This Into the Purchase Wizard

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart` (Supplier step)

```dart
// Replace existing supplier TextField + dropdown with:
SmartSearchField<Supplier>(
  hintText: 'Search supplier by name...',
  prefixIcon: const Icon(Icons.storefront_outlined, color: Color(0xFF1A7A6A)),
  onSearch: (query) async {
    final all = ref.read(suppliersListProvider).valueOrNull ?? [];
    return all.where((s) => s.name.toLowerCase().contains(query.toLowerCase())).toList();
  },
  labelBuilder: (s) => s.name,
  subtitleBuilder: (s) => s.gstNumber ?? s.phone,
  onSelected: (s) {
    ref.read(purchaseDraftProvider.notifier).setSupplier(s);
  },
  maxSuggestionsInline: 5,
)

// Replace broker search field with:
SmartSearchField<Broker>(
  hintText: 'Search broker by name...',
  onSearch: (q) async {
    final all = ref.read(brokersListProvider).valueOrNull ?? [];
    return all.where((b) => b.name.toLowerCase().contains(q.toLowerCase())).toList();
  },
  labelBuilder: (b) => b.name,
  subtitleBuilder: (b) => b.phone,
  onSelected: (b) => ref.read(purchaseDraftProvider.notifier).setBroker(b),
)
```

**File:** `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart` (Item search)

```dart
SmartSearchField<CatalogItem>(
  hintText: 'Search item (name, code, HSN)...',
  autofocus: true,
  prefixIcon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF1A7A6A)),
  onSearch: (q) async {
    final all = ref.read(catalogItemsListProvider).valueOrNull ?? [];
    return all.where((i) =>
      i.name.toLowerCase().contains(q.toLowerCase()) ||
      (i.hsnCode?.contains(q) ?? false)
    ).take(20).toList();
  },
  labelBuilder: (i) => i.name,
  subtitleBuilder: (i) => [i.categoryName, i.defaultUnit].whereType<String>().join(' · '),
  onSelected: _onItemSelected,
  maxSuggestionsInline: 6,
)
```

---

## 2. HIGH: Purchase Order Cards — Bold Days / Bags / KG Numbers

### 📸 Screenshot Evidence
**Image 2** (Search purchases): Each card shows `100 bags • 5,000 kg` and `11 May 2026`. The bags and KG numbers are plain grey text — hard to read quickly. The user needs: days-overdue number in **bold red**, bags number **bold**, KG number **bold**.

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/presentation/widgets/purchase_list_card.dart` (or wherever the card is built)

```dart
class PurchaseListCard extends StatelessWidget {
  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final daysAgo = DateTime.now().difference(purchase.date).inDays;
    final isOverdue = purchase.paymentStatus != 'paid' && daysAgo > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Supplier name + Amount ──────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    purchase.supplierName ?? '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1A3A35),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '₹${_formatAmount(purchase.totalAmount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF1A7A6A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ── Row 2: Item name ────────────────────────────
            Text(
              purchase.primaryItemName ?? '${purchase.lineCount} items',
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 6),

            // ── Row 3: Bags • KG (BOLD) + Days ─────────────
            Row(
              children: [
                // Bags number — BOLD
                if (purchase.totalBags != null && purchase.totalBags! > 0) ...[
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${purchase.totalBags}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800, // ← BOLD
                            fontSize: 13,
                            color: Color(0xFF1A3A35),
                          ),
                        ),
                        const TextSpan(
                          text: ' bags',
                          style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                  ),
                  const Text(' • ', style: TextStyle(color: Color(0xFF888888))),
                ],
                // KG number — BOLD
                if (purchase.totalKg != null && purchase.totalKg! > 0)
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _formatKg(purchase.totalKg!),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800, // ← BOLD
                            fontSize: 13,
                            color: Color(0xFF1A3A35),
                          ),
                        ),
                        const TextSpan(
                          text: ' kg',
                          style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                // Days number — BOLD RED if overdue
                _DaysChip(purchase: purchase, daysAgo: daysAgo, isOverdue: isOverdue),
              ],
            ),
            const SizedBox(height: 4),

            // ── Row 4: PUR ID + Date ─────────────────────────
            Row(
              children: [
                Text(
                  purchase.purchaseId ?? '',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                ),
                const Text(' • ', style: TextStyle(color: Color(0xFFCCCCCC))),
                Text(
                  _formatDate(purchase.date),
                  style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Days chip — shows days since purchase, red and bold if overdue
class _DaysChip extends StatelessWidget {
  final TradePurchase purchase;
  final int daysAgo;
  final bool isOverdue;

  const _DaysChip({required this.purchase, required this.daysAgo, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    if (purchase.paymentStatus == 'paid' && purchase.deliveryStatus == 'received') {
      return const SizedBox.shrink(); // No chip needed for fully completed
    }

    final label = daysAgo == 0
        ? 'Today'
        : daysAgo == 1 ? '1 day' : '$daysAgo days';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue ? const Color(0xFFFFEBEE) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOverdue ? const Color(0xFFEF9A9A) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.schedule : Icons.calendar_today,
            size: 11,
            color: isOverdue ? const Color(0xFFD32F2F) : const Color(0xFF888888),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800, // ← ALWAYS BOLD
              color: isOverdue ? const Color(0xFFD32F2F) : const Color(0xFF666666), // RED if overdue
            ),
          ),
        ],
      ),
    );
  }
}

String _formatKg(double kg) {
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k';
  return kg.toStringAsFixed(0);
}

String _formatAmount(double amount) {
  // Indian number format: 1,80,001
  final formatter = NumberFormat('#,##,###', 'en_IN');
  return formatter.format(amount);
}

String _formatDate(DateTime date) {
  return DateFormat('d MMM yyyy').format(date);
}
```

---

## 3. HIGH: PDF Share — Include Supplier, Broker, Date + Remove Junk

### 🔍 Issue
When user shares a purchase PDF:
- Supplier name and broker name are missing from the PDF
- Purchase date is missing or wrong
- Unwanted URLs and random numbers appear in the PDF body
- The shared PDF file name doesn't include supplier/date context

### ✅ Fix Required

**File:** `flutter_app/lib/features/purchase/services/purchase_invoice_pdf_layout.dart` (or equivalent PDF builder)

#### A. PDF Header — Supplier, Broker, Date (Always Included)

```dart
// In buildProfessionalPurchaseInvoiceDoc() — update the header section:

pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    // Company name
    pw.Text('NEW HARISREE AGENCY', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
    pw.Text('6/366A, Thrithallur, Thrissur 680619', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    pw.Text('Ph: 8078103800 / 7025333999', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    pw.SizedBox(height: 12),
    pw.Divider(),
    pw.SizedBox(height: 8),

    // Purchase ID + Date
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PURCHASE ORDER', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(purchase.purchaseId ?? '', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Date: ${DateFormat('dd MMM yyyy').format(purchase.date)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 10),

    // Supplier details — ALWAYS SHOW
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.teal200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        color: PdfColors.teal50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SUPPLIER', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(
            purchase.supplierName ?? 'N/A',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          if (purchase.supplierGst?.isNotEmpty ?? false)
            pw.Text('GST: ${purchase.supplierGst}', style: const pw.TextStyle(fontSize: 9)),
          if (purchase.supplierPhone?.isNotEmpty ?? false)
            pw.Text('Ph: ${purchase.supplierPhone}', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ),
    pw.SizedBox(height: 6),

    // Broker details — show ONLY if present
    if (purchase.brokerName?.isNotEmpty ?? false)
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('BROKER', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 2),
            pw.Text(
              purchase.brokerName!,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            if (purchase.brokerPhone?.isNotEmpty ?? false)
              pw.Text('Ph: ${purchase.brokerPhone}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
  ],
),
```

#### B. Remove Unwanted URLs and Numbers

Audit every place `pw.Text(...)` is called in the PDF builder:

```dart
// REMOVE any lines like:
pw.Text(purchase.scanImageUrl ?? ''),      // ← DELETE
pw.Text(purchase.rawApiResponse ?? ''),    // ← DELETE
pw.Text(purchase.internalId.toString()),   // ← DELETE (use purchaseId instead)

// SAFE — keep only:
// - purchase.purchaseId (e.g., "PUR-2026-0034")
// - purchase.date
// - purchase.supplierName, supplierGst, supplierPhone
// - purchase.brokerName, brokerPhone
// - Line items: name, qty, unit, rate, amount
// - Totals: subtotal, freight, tax, total
// - Payment status
```

#### C. Smart PDF File Name

```dart
// When saving/sharing the PDF:
String _buildPdfFileName(TradePurchase purchase) {
  final supplier = (purchase.supplierName ?? 'Purchase')
    .replaceAll(RegExp(r'[^\w\s]'), '')
    .trim()
    .replaceAll(' ', '_');
  final date = DateFormat('ddMMMyyyy').format(purchase.date);
  final id = purchase.purchaseId?.replaceAll('-', '') ?? '';
  return '${supplier}_${date}_${id}.pdf';
  // e.g.: "SUMATHI_SPICES_12May2026_PUR20260034.pdf"
}

// Share with proper file name:
final file = File('${dir.path}/${_buildPdfFileName(purchase)}');
await file.writeAsBytes(pdfBytes);
await Share.shareXFiles(
  [XFile(file.path)],
  subject: 'Purchase ${purchase.purchaseId} — ${purchase.supplierName}',
  text: 'Purchase from ${purchase.supplierName} on ${DateFormat("d MMM yyyy").format(purchase.date)}',
);
```

---

## 4. HIGH: ZIP Export — Add Order PDFs + Ledger + Statements

### 🔍 Issue
When user exports a ZIP file (backup), it contains only raw data — no individual order PDFs, no supplier ledger PDFs, no statements. User cannot read the backup without re-importing it into the app.

### ✅ Fix Required

**File:** `flutter_app/lib/features/settings/services/backup_export_service.dart` (or equivalent)

```dart
Future<File> buildExportZip(String businessId) async {
  final dir = await getTemporaryDirectory();
  final zipDir = Directory('${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}');
  await zipDir.create();

  // ── 1. Raw JSON data (existing) ──────────────────────────
  final purchases = await ref.read(tradePurchasesApiProvider).listAll(businessId);
  await File('${zipDir.path}/purchases.json').writeAsString(jsonEncode(purchases));

  final suppliers = await ref.read(suppliersApiProvider).listAll(businessId);
  await File('${zipDir.path}/suppliers.json').writeAsString(jsonEncode(suppliers));

  // ── 2. Individual Order PDFs ─────────────────────────────
  final ordersDir = Directory('${zipDir.path}/orders');
  await ordersDir.create();

  for (final purchase in purchases) {
    try {
      final pdfBytes = await buildPurchaseInvoicePdf(purchase); // existing PDF builder
      final fileName = _buildPdfFileName(purchase);
      await File('${ordersDir.path}/$fileName').writeAsBytes(pdfBytes);
    } catch (e) {
      debugPrint('PDF export failed for ${purchase.purchaseId}: $e');
    }
  }

  // ── 3. Supplier Ledger PDFs ──────────────────────────────
  final ledgersDir = Directory('${zipDir.path}/ledgers');
  await ledgersDir.create();

  final uniqueSuppliers = {for (final p in purchases) p.supplierId: p.supplierName};
  for (final entry in uniqueSuppliers.entries) {
    try {
      final ledgerData = await ref.read(ledgerApiProvider).getSupplierLedger(
        businessId: businessId,
        supplierId: entry.key,
      );
      final pdfBytes = await buildSupplierLedgerPdf(
        supplierName: entry.value ?? 'Unknown',
        ledgerLines: ledgerData,
        businessId: businessId,
      );
      final safeName = (entry.value ?? 'Supplier').replaceAll(RegExp(r'[^\w]'), '_');
      await File('${ledgersDir.path}/Ledger_${safeName}.pdf').writeAsBytes(pdfBytes);
    } catch (e) {
      debugPrint('Ledger export failed for ${entry.value}: $e');
    }
  }

  // ── 4. Summary Statement PDF ─────────────────────────────
  final summaryBytes = await buildSummaryStatementPdf(
    businessId: businessId,
    purchases: purchases,
    fromDate: purchases.last.date,
    toDate: purchases.first.date,
  );
  await File('${zipDir.path}/Summary_Statement.pdf').writeAsBytes(summaryBytes);

  // ── 5. README.txt ────────────────────────────────────────
  await File('${zipDir.path}/README.txt').writeAsString('''
HARISREE PURCHASE ASSISTANT — DATA EXPORT
Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}
Business: NEW HARISREE AGENCY

Contents:
  purchases.json     — All purchase records (raw data)
  suppliers.json     — All supplier records
  orders/            — Individual purchase order PDFs (${purchases.length} files)
  ledgers/           — Supplier-wise ledger PDFs (${uniqueSuppliers.length} suppliers)
  Summary_Statement.pdf — Overall purchase summary

Support: 8078103800
''');

  // ── 6. Package as ZIP ────────────────────────────────────
  final zipFile = File('${dir.path}/HarisreeExport_${DateFormat("ddMMMyyyy").format(DateTime.now())}.zip');
  await ZipEncoder().zipDirectory(zipDir, filename: zipFile.path);
  await zipDir.delete(recursive: true);

  return zipFile;
}
```

**Required packages** (add to `pubspec.yaml` if not present):
```yaml
dependencies:
  archive: ^3.4.9          # ZIP encoding
  share_plus: ^7.2.1        # File sharing
  path_provider: ^2.1.2     # Temp directory
```

---

## 5. MEDIUM: Add Item Button — Sticky Bottom + Auto-Scroll (Deep Fix)

### 📸 Screenshot Evidence
**Image 4** (New purchase — Items): When 0 items, "Add Item" is visible. When multiple items are added, button is pushed off screen. User must scroll far down to find it.

### ✅ Fix — Two Complementary Solutions

#### Solution A: Make "+ Add Item" a Sticky Bottom Button

```dart
// In the Items step widget (purchase_items_step.dart or equivalent):
Scaffold(
  body: Column(
    children: [
      // Total card at top (fixed)
      _TotalCard(total: draftTotal),

      // Items list — scrollable
      Expanded(
        child: items.isEmpty
            ? const _EmptyItemsPlaceholder()
            : ListView.builder(
                controller: _scrollController,
                itemCount: items.length,
                itemBuilder: (_, i) => PurchaseLineCard(line: items[i]),
              ),
      ),

      // ── STICKY: Always at bottom, never scrolls away ──────
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              OutlinedButton.icon(
                onPressed: _openAddItemSheet,
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF1A7A6A)),
                label: const Text(
                  '+ Add Item',
                  style: TextStyle(color: Color(0xFF1A7A6A), fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: Color(0xFF1A7A6A), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: items.isEmpty ? null : _onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A7A6A),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Continue →', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
)
```

#### Solution B: Auto-scroll Animation After Item Save

```dart
// After _openAddItemSheet() returns (item was saved):
void _onItemSaved(PurchaseLineDraft line) {
  ref.read(purchaseDraftProvider.notifier).addLine(line);
  
  // Scroll to bottom with animation so user sees the item was added
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  });
  
  // Show brief confirmation toast
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${line.itemName} added ✓'),
      duration: const Duration(seconds: 1),
      backgroundColor: const Color(0xFF1A7A6A),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
    ),
  );
}
```

---

## 6. MEDIUM: Reports Page — Confirm Speed & Tab Response

### 📸 Screenshot Evidence
**All report-related screenshots** confirm reports data loads (Image 10 shows correctly populated data), but tab/filter switching is still slow because each change re-fetches from network.

### ✅ Verification + Fix

**Step 1: Confirm the reports provider is NOT re-fetching on tab switch**

```bash
# In Cursor, search for this pattern (bad):
grep -r "ref.invalidate(tradeReport" flutter_app/lib/features/reports/ --include="*.dart"
grep -r "ref.refresh(tradeReport" flutter_app/lib/features/reports/ --include="*.dart"
```

If any results appear inside tab-switch callbacks → remove them.

**Step 2: Verify client-side filter is used for group/tab changes**

```dart
// In reports_screen.dart — tab switch must be LOCAL ONLY:
void _onTabChange(ReportTab tab) {
  ref.read(selectedReportTabProvider.notifier).state = tab; // ← local state, NO network call
  HapticFeedback.selectionClick(); // instant haptic
}

void _onGroupFilterChange(String group) {
  ref.read(reportGroupFilterProvider.notifier).state = group; // ← local state
}
```

**Step 3: Add Tab transition animation for perceived speed**

```dart
// Wrap tab content with AnimatedSwitcher for instant visual feedback:
AnimatedSwitcher(
  duration: const Duration(milliseconds: 200),
  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
  child: KeyedSubtree(
    key: ValueKey(selectedTab),
    child: _buildTabContent(selectedTab, filteredData),
  ),
)
```

**Step 4: Preload reports data on screen open (not on first interaction)**

```dart
// In ReportsScreen.initState() or build():
@override
void initState() {
  super.initState();
  // Eagerly start loading current period data
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(tradeReportProvider(currentRange).future).ignore();
  });
}
```

---

## ✅ POST-PART-2 VERIFICATION CHECKLIST

### UX Tests (Manual, Physical Device)
- [ ] Type "su" in supplier field → suggestions appear with scroll indicator
- [ ] Accidentally brush/touch the middle of the suggestion list → list does NOT close
- [ ] Tap a suggestion item firmly → item IS selected, field updates, list closes
- [ ] Tap outside the suggestion list (on the page background) → list closes
- [ ] Tap ✕ button on suggestion panel → list closes, field text remains
- [ ] Add 5+ items to purchase → "Add Item" button always visible (sticky at bottom)
- [ ] After adding item → screen auto-scrolls, brief "Item added ✓" toast appears
- [ ] Open a purchase PDF → supplier name visible in header
- [ ] Open a purchase PDF → broker name visible if one was entered
- [ ] Open a purchase PDF → date matches the purchase date
- [ ] Open a purchase PDF → no random URLs or internal IDs visible
- [ ] PDF file name format: `SUPPLIER_NAME_DDMMMYYYYy_PURID.pdf`
- [ ] Export ZIP → contains `orders/` folder with individual PDFs
- [ ] Export ZIP → contains `ledgers/` folder with supplier ledger PDFs
- [ ] Export ZIP → contains `Summary_Statement.pdf`
- [ ] Purchase order cards → bags number is **bold**
- [ ] Purchase order cards → KG number is **bold**
- [ ] Purchase order cards with overdue status → days number is **bold RED**
- [ ] Reports → switch Items/Suppliers tabs → instant (<150ms) with fade transition

### Flutter Analysis
```bash
cd flutter_app && flutter analyze && flutter test
```

---

## 📁 KEY FILES FOR PART 2

| Area | File |
|------|------|
| Supplier search field | `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart` |
| Item entry sheet | `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart` |
| Purchase list card | `flutter_app/lib/features/purchase/presentation/widgets/purchase_list_card.dart` |
| PDF builder | `flutter_app/lib/features/purchase/services/purchase_invoice_pdf_layout.dart` |
| Backup/export service | `flutter_app/lib/features/settings/services/backup_export_service.dart` |
| Reports screen | `flutter_app/lib/features/reports/screens/reports_screen.dart` |
| New shared search widget | `flutter_app/lib/shared/widgets/smart_search_field.dart` ← **CREATE NEW** |

---

*Generated: 12 May 2026 | Supplement to CURSOR_MASTER_PROMPT.md | Harisree Purchase Assistant*
