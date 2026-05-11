# CURSOR AGENT MASTER PROMPT — Purchase Assistant v14
> ONE-SHOT PROMPT. Paste entire file into Cursor Composer (Agent mode).
> Model: claude-sonnet or gpt-4o. Mode: Agent (not Ask/Edit).
> Agent works phase by phase. Updates SOLUTION_TASKS_V14.md checkbox after each task.
> DO NOT code anything not in this prompt. DO NOT change test files.

---

## IDENTITY

You are a senior Flutter/Dart + FastAPI engineer for the Harisree Purchase Assistant app. This is a live production app for a Kerala wholesale grocery trading business. Real client. Real money. Be precise.

Stack: Flutter 3.x, Dart 3.3, Riverpod 2.6.1, GoRouter 14, Dio 5.7, Hive 2.2, FastAPI (Python), PostgreSQL (Supabase).

## RULES

1. After EVERY task: update checkbox in `SOLUTION_TASKS_V14.md` (mark ✅ + date)
2. After EVERY file change: run `flutter analyze` in `flutter_app/`. Fix all NEW errors before proceeding.
3. NEVER break existing tests. Run `flutter test` after each phase.
4. Do NOT add packages to `pubspec.yaml` unless explicitly told to.
5. Do NOT change any `*_test.dart` files.
6. Do NOT add `print()` statements.
7. Read `BUGS_AND_PLAN.md` for full context before starting.
8. When changing a backend file, also check `backend/app/routers/` to understand the router structure first.

---

## ═══════════════════════════════════════
## PHASE 0 — CRITICAL DASHBOARD BUGS
## ═══════════════════════════════════════

### TASK 0-A: Fix "Today" Tab Infinite Loading

**File:** `flutter_app/lib/core/providers/home_dashboard_provider.dart`

Find the `_homeDashboardPullFresh` function. Find the block that checks `_snapshotHasTradeActivity`:

```dart
if (_snapshotHasTradeActivity(fromSnapshot)) {
  return ok(fromSnapshot, ...);
}
// ... falls through to phase 2 ...
```

Just BELOW this, after `if (purchases.isEmpty) { return ok(fromSnapshot, ...); }`, there is already an early return for 0 purchases. That's correct.

The bug is in `HomeDashboardDataNotifier.build()`. Find it. Find this pattern:

```dart
final hasRenderableCache = hydrated != null;
return HomeDashboardDashState(
  snapshot: seed,
  refreshing: !hasRenderableCache,
);
```

Change to — add a 4-second max-wait so `refreshing` never stays `true` indefinitely:

```dart
final hasRenderableCache = hydrated != null;
// Start max-wait timer: if still refreshing after 4s with no data,
// force refreshing=false to avoid infinite spinner.
if (!hasRenderableCache) {
  Future<void>.delayed(const Duration(seconds: 4), () {
    if (_dead) return;
    if (state.refreshing) {
      state = HomeDashboardDashState(
        snapshot: state.snapshot,
        refreshing: false,
      );
    }
  });
}
return HomeDashboardDashState(
  snapshot: seed,
  refreshing: !hasRenderableCache,
);
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-001 ✅

---

### TASK 0-B: Fix Donut Chart Empty State

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find where the donut/ring chart widget is built. Find `"Loading Items breakdown…"` text or the donut chart render code.

Currently: shows empty gray ring when `itemSlices.isEmpty`.

Change the UI logic for the breakdown section:

```dart
// Find the breakdown section. It likely looks like:
if (data.itemSlices.isEmpty)
  const Center(child: Text('Loading Items breakdown...'))
else
  // ... chart widget
```

Replace the loading/empty handling with:

```dart
if (state.refreshing || data.itemSlices.isEmpty) {
  // Show skeleton shimmer instead of spinner or empty ring
  // Use the existing ListSkeleton widget from lib/core/widgets/list_skeleton.dart
  return Column(children: [
    // Skeleton ring placeholder
    Container(
      width: 180, height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade200,
      ),
    ),
    const SizedBox(height: 16),
    const ListSkeleton(count: 4),
  ]);
}
// else show real chart
```

Also find the breakdown tab content (Category/Subcategory/Supplier/Items tabs). For each tab content:

```dart
// If data is empty AND refreshing, show ListSkeleton(count: 5)
// Replace "Loading Items breakdown..." with ListSkeleton
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-002 ✅

---

### TASK 0-C: Improve Breakdown Tabs Performance

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find the `TabBarView` that renders Category/Subcategory/Supplier/Items breakdown lists.

For each tab content widget (there should be 4 corresponding child widgets or inline builds):

Step 1: Extract each tab content into its own `StatefulWidget` with `AutomaticKeepAliveClientMixin`:
```dart
class _CategoryBreakdownTab extends StatefulWidget {
  const _CategoryBreakdownTab({required this.data});
  final HomeDashboardData data;
  @override
  State<_CategoryBreakdownTab> createState() => _CategoryBreakdownTabState();
}
class _CategoryBreakdownTabState extends State<_CategoryBreakdownTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context); // required by mixin
    // ... list content
  }
}
```

Step 2: In the list builder for each tab, use `ListView.builder` instead of `Column` + mapped children.

Step 3: Add `const` to all row widgets that don't use dynamic data.

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-003 ✅

---

## ═══════════════════════════════════════
## PHASE 1 — BUG FIXES
## ═══════════════════════════════════════

### TASK 1-A: Fix Draft Filter in Purchase History

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

Find `purchaseHistoryVisibleSortedForRef` function. Find the `if (primary == 'due')` block. Add a new block right after:

```dart
if (primary == 'due') {
  v = v.where(_purchaseHistoryMatchesDuePrimary).toList();
}
// ADD THIS:
if (primary == 'draft') {
  // Only show local WIP draft + any server-side draft-status purchases
  v = v.where((p) => p.statusEnum == PurchaseStatus.draft).toList();
}
```

Also find the section that controls local WIP draft banner visibility:

```dart
final showLocalWipRow = localWip != null && !_selectMode;
```

Change to:
```dart
final showLocalWipRow = localWip != null && !_selectMode &&
    (primary == 'draft' || primary == 'all');
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-004 ✅

---

### TASK 1-B: Fix Search — Last Purchase Date + Days Ago

**File:** `flutter_app/lib/features/search/presentation/search_page.dart`

Find the `items` enrichment block (search for `lastLineByItemId` — around line 265). Add date string capture:

```dart
// ADD these maps at the top of the enrichment block (alongside lastLineByItemId etc):
final lastDateStringByItemId = <String, String>{};

// IN the bills loop, after `lastLineByItemId[cid] = ln;`:
final dtStr = p['purchase_date']?.toString() ?? '';
if (dtStr.length >= 10) {
  lastDateStringByItemId[cid] = dtStr.substring(0, 10);
}

// IN the items.map block, after `next['last_purchase_price'] = ...`:
final dateStr = lastDateStringByItemId[id];
if (dateStr != null) next['last_purchase_date'] = dateStr;
```

Now find the UI widget that renders a catalog item row (search for `last buy` string in the file). It's likely a `ListTile` or custom row. After the rate line text widget, add:

```dart
if (m['last_purchase_date'] != null) ...[
  const SizedBox(height: 2),
  Builder(builder: (ctx) {
    final rawDate = m['last_purchase_date']?.toString() ?? '';
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return const SizedBox.shrink();
    final days = DateTime.now().difference(parsed).inDays;
    final label = days == 0 ? 'today' : days == 1 ? 'yesterday' : '$days days ago';
    return Text(
      '${DateFormat('MMM d').format(parsed)} · $label',
      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
      ),
    );
  }),
],
```

Make sure `import 'package:intl/intl.dart';` is present.

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-006 ✅

---

### TASK 1-C: Add Unit Totals to Search Category Rows

**File:** `flutter_app/lib/features/search/presentation/search_page.dart`

Find where category/type rows are rendered (search for `catalog_subcategories` in the build section, find the list tile builder for type rows).

Currently: shows just name + parent category.

Add below the name/subtitle: a compact summary line using data from the enrichment that already happens for `bills`:

```dart
// In the type row builder, compute a summary from `bills` that match this type:
// (This is client-side — use available bill data as approximation)

// For each type row `t`:
final typeName = (t['name'] ?? '').toString().toLowerCase();
// Count matching items from `items` list that belong to this type
final matchingItemIds = items
    .where((it) => (it['category_name'] ?? it['type_name'] ?? '').toString().toLowerCase() == typeName)
    .map((it) => it['id']?.toString() ?? '')
    .where((id) => id.isNotEmpty)
    .toSet();

// Sum bags/kg from lastLineByItemId for these items
var typeTotalBags = 0.0;
var typeTotalKg = 0.0;
for (final id in matchingItemIds) {
  final ln = lastLineByItemId[id];
  if (ln == null) continue;
  final qty = _toD(ln['qty']) ?? 0;
  final unit = ln['unit']?.toString().toLowerCase() ?? '';
  if (unit == 'bag' || unit == 'sack') typeTotalBags += qty;
  if (unit == 'kg') typeTotalKg += qty;
}

// Show in the subtitle:
final parts = <String>[];
if (typeTotalBags > 0) parts.add('${_fmtQty(typeTotalBags)} bags');
if (typeTotalKg > 0) parts.add('${_fmtQty(typeTotalKg)} kg');
final summaryText = parts.isEmpty ? null : parts.join(' · ');

// In the ListTile:
subtitle: summaryText != null ? Text(summaryText, ...) : Text(parentName, ...),
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-007 ✅

---

### TASK 1-D: Fix AI Preview — Show Full Table

**File:** `flutter_app/lib/features/assistant/presentation/widgets/preview_card.dart`

Step 1 — Create a new widget file: `flutter_app/lib/features/assistant/presentation/widgets/purchase_preview_table.dart`

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Full purchase preview table for AI chatbot — shows ALL lines, editable.
class PurchasePreviewTable extends StatelessWidget {
  const PurchasePreviewTable({
    super.key,
    required this.entryDraft,
    required this.onCancel,
    required this.onSave,
    required this.onEdit,
  });

  final Map<String, dynamic> entryDraft;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onEdit;

  static final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lines = (entryDraft['lines'] as List?) ?? [];
    final supplier = entryDraft['supplier_name']?.toString() ?? entryDraft['supplier_id']?.toString() ?? '—';
    final broker = entryDraft['broker_name']?.toString() ?? '';
    final payDays = entryDraft['payment_days']?.toString() ?? '';

    double grand = 0;
    for (final raw in lines) {
      if (raw is! Map) continue;
      final qty = (raw['qty'] as num?)?.toDouble() ?? 0;
      final rate = (raw['purchase_rate'] as num?)?.toDouble() ??
          (raw['landing_cost'] as num?)?.toDouble() ?? 0;
      grand += qty * rate;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(children: [
              Expanded(child: Text('📦 Purchase Preview',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit, tooltip: 'Edit in wizard'),
            ]),
            Text('$supplier${broker.isNotEmpty ? "  ·  Broker: $broker" : ""}',
              style: tt.bodyMedium),
            if (payDays.isNotEmpty)
              Text('Payment: $payDays days', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const Divider(height: 16),
            // Table header
            _TableRow(isHeader: true, item: 'Item', qty: 'Qty', unit: 'Unit', rate: 'Rate', amount: 'Amount'),
            const Divider(height: 1),
            // Data rows
            for (final raw in lines)
              if (raw is Map) _buildLineRow(raw),
            const Divider(height: 16),
            // Total
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Total: ', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(_inr.format(grand), style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: cs.primary)),
            ]),
            const SizedBox(height: 12),
            // Actions
            Row(children: [
              OutlinedButton.icon(icon: const Icon(Icons.close, size: 16), label: const Text('Cancel'), onPressed: onCancel),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(icon: const Icon(Icons.check, size: 16), label: const Text('Save Purchase'), onPressed: onSave)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildLineRow(Map raw) {
    final item = raw['item_name']?.toString() ?? raw['item']?.toString() ?? 'Item';
    final qty = (raw['qty'] as num?)?.toStringAsFixed(0) ?? '0';
    final unit = raw['unit']?.toString() ?? '';
    final rate = (raw['purchase_rate'] as num?)?.toDouble() ??
        (raw['landing_cost'] as num?)?.toDouble() ?? 0;
    final amount = ((raw['qty'] as num?)?.toDouble() ?? 0) * rate;
    return _TableRow(
      item: item, qty: qty, unit: unit,
      rate: rate > 0 ? _inr.format(rate) : '—',
      amount: amount > 0 ? _inr.format(amount) : '—',
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.item, required this.qty, required this.unit,
    required this.rate, required this.amount, this.isHeader = false});
  final String item, qty, unit, rate, amount;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)
        : const TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 4, child: Text(item, style: style, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 36, child: Text(qty, style: style, textAlign: TextAlign.right)),
        SizedBox(width: 36, child: Text(unit, style: style, textAlign: TextAlign.center)),
        SizedBox(width: 60, child: Text(rate, style: style, textAlign: TextAlign.right)),
        SizedBox(width: 70, child: Text(amount, style: style, textAlign: TextAlign.right)),
      ]),
    );
  }
}
```

Step 2 — In `assistant_chat_page.dart`: find where `PreviewCard` is used in `build()`. Import the new widget. Replace `PreviewCard(...)` with:

```dart
PurchasePreviewTable(
  entryDraft: msg.draftSnapshot!,
  onCancel: () => _sendWithText('NO'),
  onSave: _confirmPreviewThenYes,
  onEdit: () {
    // Navigate to wizard with pre-filled draft
    final draft = msg.draftSnapshot;
    if (draft != null) {
      context.push('/purchase/new', extra: {'entryDraft': draft});
    }
  },
)
```

Step 3 — Verify the route `/purchase/new` in `app_router.dart` accepts `extra.entryDraft` and passes it to `PurchaseEntryWizardV2` as `initialDraft`.

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-008 ✅ and T-019 ✅

---

## ═══════════════════════════════════════
## PHASE 2 — DELIVERY TRACKING FEATURE
## ═══════════════════════════════════════

### TASK 2-A: Add Delivery Fields to Flutter Model

**File:** `flutter_app/lib/core/models/trade_purchase_models.dart`

Find `class TradePurchase`. Find the last constructor field before the closing `}`. Add:

```dart
// ADD to constructor:
this.isDelivered = false,
this.deliveredAt,
this.deliveryNotes,

// ADD as class fields (near other nullable fields):
final bool isDelivered;
final DateTime? deliveredAt;
final String? deliveryNotes;
```

Find `TradePurchase.fromJson` factory. Add to the return statement:

```dart
isDelivered: (j['is_delivered'] as bool?) ?? false,
deliveredAt: j['delivered_at'] != null
    ? DateTime.tryParse(j['delivered_at'].toString())
    : null,
deliveryNotes: j['delivery_notes']?.toString(),
```

Run: `flutter analyze` — fix any copyWith/equality issues if `TradePurchase` has them.
Update SOLUTION_TASKS_V14.md: T-011 ✅

---

### TASK 2-B: Add markPurchaseDelivered to HexaApi

**File:** `flutter_app/lib/core/api/hexa_api.dart`

Add a new method to `HexaApi` class:

```dart
/// Marks/unmarks a purchase as delivered (received at warehouse).
Future<Map<String, dynamic>> markPurchaseDelivered({
  required String businessId,
  required String purchaseId,
  required bool isDelivered,
  String? deliveryNotes,
}) async {
  final path = '/v1/businesses/$businessId/trade-purchases/$purchaseId/delivery';
  final resp = await _dio.patch<dynamic>(path, data: {
    'is_delivered': isDelivered,
    if (deliveryNotes != null && deliveryNotes.isNotEmpty)
      'delivery_notes': deliveryNotes,
    if (isDelivered) 'delivered_at': DateTime.now().toIso8601String(),
  });
  return _asMap(resp.data);
}
```

Run: `flutter analyze`

---

### TASK 2-C: Delivery Prompt After Purchase Save

**File:** `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`

Find the `_doSave()` or equivalent save success handler. After the success sheet logic, add:

```dart
// After the purchase is saved and we have the purchaseId:
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _showDeliveryPrompt(savedPurchaseId);
});
```

Create the `_showDeliveryPrompt` method:

```dart
Future<void> _showDeliveryPrompt(String purchaseId) async {
  if (!mounted) return;
  final session = ref.read(sessionProvider);
  if (session == null) return;
  final bid = session.primaryBusiness.id;

  final delivered = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.local_shipping_outlined, size: 40, color: Colors.orange),
          const SizedBox(height: 12),
          const Text('Has this shipment arrived at your warehouse?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => ctx.pop(false),
                child: const Text('Not Yet'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Yes, Received'),
                onPressed: () => ctx.pop(true),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
          ]),
        ],
      ),
    ),
  );

  if (delivered == true && mounted) {
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
        businessId: bid,
        purchaseId: purchaseId,
        isDelivered: true,
      );
      invalidatePurchaseWorkspace(ref);
    } catch (_) {
      // Non-critical — silently ignore if delivery mark fails
    }
  }
}
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-012 ✅

---

### TASK 2-D: Delivery Badge in Purchase List Rows

**File:** `flutter_app/lib/features/purchase/presentation/purchase_home_page.dart`

Find the purchase list tile widget (search for `PurchaseStatus.overdue` or the tile that shows supplier name + amount). This is typically a `ListTile` or custom card.

In the tile's `trailing` or `subtitle`, add the delivery badge. Find a good place in the tile layout and add:

```dart
// Delivery status chip — add next to the status/amount display
if (!p.isDelivered && p.statusEnum != PurchaseStatus.deleted && p.statusEnum != PurchaseStatus.cancelled)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Text('🚚 Pending',
      style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
  )
else if (p.isDelivered)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('✅ Received',
      style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
  ),
```

Also add "Pending Delivery" filter chip in the chips row (after 'Draft'):

```dart
('pending_delivery', '🚚 Awaiting'),
```

In `purchaseHistoryVisibleSortedForRef`, add handling for `primary == 'pending_delivery'`:

```dart
if (primary == 'pending_delivery') {
  v = v.where((p) =>
    !p.isDelivered &&
    p.statusEnum != PurchaseStatus.deleted &&
    p.statusEnum != PurchaseStatus.cancelled
  ).toList();
}
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-013 ✅

---

### TASK 2-E: Delivery Toggle in Purchase Detail

**File:** `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`

Find the purchase detail page widget. Find where the header stats are shown (bills, amount, etc.).

Add a delivery status tile below the stats:

```dart
Card(
  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  child: ListTile(
    leading: Icon(
      purchase.isDelivered ? Icons.check_circle : Icons.local_shipping,
      color: purchase.isDelivered ? Colors.green : Colors.orange,
    ),
    title: Text(purchase.isDelivered ? 'Received at warehouse' : 'Pending delivery'),
    subtitle: purchase.deliveredAt != null
        ? Text('Received on ${DateFormat('MMM d, y').format(purchase.deliveredAt!)}')
        : const Text('Not yet confirmed as received'),
    trailing: TextButton(
      onPressed: () => _toggleDelivery(context, ref, purchase),
      child: Text(purchase.isDelivered ? 'Mark Pending' : 'Mark Received'),
    ),
  ),
),
```

Add `_toggleDelivery` method:

```dart
Future<void> _toggleDelivery(BuildContext context, WidgetRef ref, TradePurchase p) async {
  final session = ref.read(sessionProvider);
  if (session == null) return;
  try {
    await ref.read(hexaApiProvider).markPurchaseDelivered(
      businessId: session.primaryBusiness.id,
      purchaseId: p.id,
      isDelivered: !p.isDelivered,
    );
    invalidatePurchaseWorkspace(ref);
    ref.invalidate(tradePurchaseDetailProvider(p.id));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update delivery status. Try again.')));
    }
  }
}
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-014 ✅

---

## ═══════════════════════════════════════
## PHASE 3 — QUICK ADD ITEM FROM HOME
## ═══════════════════════════════════════

### TASK 3-A: Quick Add Item Sheet

Create file: `flutter_app/lib/features/catalog/presentation/quick_add_item_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/api/hexa_api.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../shared/widgets/inline_search_field.dart';

/// Bottom sheet for quick item creation from home dashboard.
class QuickAddItemSheet extends ConsumerStatefulWidget {
  const QuickAddItemSheet({super.key});
  @override
  ConsumerState<QuickAddItemSheet> createState() => _QuickAddItemSheetState();
}

class _QuickAddItemSheetState extends ConsumerState<QuickAddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  String? _selectedTypeId;
  String? _selectedTypeName;
  String _unit = 'kg';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(itemCategoriesListProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add New Item', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          // Subcategory search
          categoriesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load categories: $e'),
            data: (cats) => _SubcategorySearchField(
              categories: cats,
              selectedName: _selectedTypeName,
              onSelected: (id, name) => setState(() {
                _selectedTypeId = id;
                _selectedTypeName = name;
              }),
            ),
          ),
          const SizedBox(height: 12),
          // Item name
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Item name *',
              hintText: 'e.g. THUVARA JP 50 KG',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          // Unit
          Row(children: [
            const Text('Unit: '),
            const SizedBox(width: 8),
            for (final u in ['kg', 'bag', 'box', 'tin', 'piece'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(u),
                  selected: _unit == u,
                  onSelected: (_) => setState(() { _unit = u; _kgCtrl.clear(); }),
                ),
              ),
          ]),
          if (_unit == 'bag') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _kgCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Kg per bag',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Cancel'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Item'),
            )),
          ]),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    if (name.isEmpty) { setState(() => _error = 'Item name is required.'); return; }
    if (_selectedTypeId == null) { setState(() => _error = 'Select a subcategory.'); return; }
    setState(() { _saving = true; _error = null; });
    final session = ref.read(sessionProvider);
    if (session == null) { setState(() => _saving = false); return; }
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
        businessId: session.primaryBusiness.id,
        name: name,
        typeId: _selectedTypeId!,
        defaultUnit: _unit,
        defaultKgPerBag: _unit == 'bag' ? double.tryParse(_kgCtrl.text.trim()) : null,
      );
      ref.invalidate(catalogItemsListProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Item "$name" created ✓')));
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Could not create item: $e'; });
    }
  }
}

class _SubcategorySearchField extends StatelessWidget {
  const _SubcategorySearchField({required this.categories, required this.selectedName, required this.onSelected});
  final List<Map<String, dynamic>> categories;
  final String? selectedName;
  final void Function(String id, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    // Simple dropdown or searchable list
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(labelText: 'Subcategory *', border: OutlineInputBorder()),
      value: null,
      hint: Text(selectedName ?? 'Select subcategory'),
      items: categories.map((c) => DropdownMenuItem(
        value: c['id']?.toString(),
        child: Text('${c["parent_name"] ?? c["category_name"] ?? ""} · ${c["name"] ?? ""}',
          style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: (id) {
        if (id == null) return;
        final cat = categories.firstWhere((c) => c['id']?.toString() == id, orElse: () => {});
        onSelected(id, cat['name']?.toString() ?? '');
      },
    );
  }
}
```

In `home_page.dart`, find the FAB. If it's a single `FloatingActionButton`, wrap it with a simple `Column`-based multi-button setup or just add a secondary FAB:

```dart
// Find the FloatingActionButton. Add a second mini-FAB above it:
Stack(
  alignment: Alignment.bottomCenter,
  children: [
    // existing FAB (purchase)
    // ADD:
    Positioned(
      bottom: 80,
      child: FloatingActionButton.small(
        heroTag: 'add_item',
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => const QuickAddItemSheet(),
        ),
        child: const Icon(Icons.inventory_2_outlined),
        tooltip: 'Add Item',
      ),
    ),
  ],
)
```

Add import for `QuickAddItemSheet`. Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-016 ✅

---

## ═══════════════════════════════════════
## PHASE 4 — REMOVE UNUSED FEATURES
## ═══════════════════════════════════════

### TASK 4-A: Feature Flags Cleanup

**File:** `flutter_app/lib/core/feature_flags.dart`

Find `FeatureFlags` class (or `AppFeatureFlags` — check the file name). Add if not present:

```dart
class FeatureFlags {
  static const bool showVoiceTab = false;
  static const bool showMaintenanceFeeCard = false;
  static const bool showAnalyticsTab = true;
}
```

**File:** `flutter_app/lib/features/shell/shell_screen.dart`

Find the bottom navigation bar / navigation rail construction. Find the Voice tab entry. Wrap with:

```dart
if (FeatureFlags.showVoiceTab) ...[
  // voice tab entry
],
```

Find maintenance fee card in `home_page.dart` or `maintenance_home_card.dart`. Wrap with:

```dart
if (FeatureFlags.showMaintenanceFeeCard)
  const MaintenanceHomeCard(),
```

Run: `flutter analyze`
Update SOLUTION_TASKS_V14.md: T-024 ✅

---

## ═══════════════════════════════════════
## FINAL STEPS
## ═══════════════════════════════════════

After all phases complete:

```bash
cd flutter_app

# 1. Full analyze
flutter analyze

# 2. Full tests
flutter test

# 3. Check no debug prints added
grep -rn "print(" lib/ --include="*.dart" | grep -v "debugPrint\|kDebugMode"
```

Fix any failures. Then commit:
```bash
git add .
git commit -m "feat: delivery tracking, dashboard fixes, AI table preview, search dates, fast item add, cleanup"
```

Update `SOLUTION_TASKS_V14.md` final progress table.

---

## DO NOT

- Do NOT add `print()` anywhere
- Do NOT touch `*_test.dart` files  
- Do NOT change `pubspec.yaml` unless adding `uuid` (which is already a dep via `http_parser`)
- Do NOT refactor the calc engine (`calc_engine.dart`)
- Do NOT change the AI scan mapping logic (`ai_scan_purchase_draft_map.dart`) — that's stable
- Do NOT change any auth flows
- Do NOT change `hexa_api.dart` except adding the `markPurchaseDelivered` method
