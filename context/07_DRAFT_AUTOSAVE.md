# SPEC 07 — DRAFT AUTO-SAVE & RESUME
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Auto-save draft every 800ms | ✅ Done |
| `OfflineStore.getPurchaseWizardDraft()` used | ✅ Done |
| Resume banner on purchase home page | ✅ Done |
| Draft shown in History tab with "Draft" badge | ✅ Done |
| Draft older than 24h auto-cleared | ✅ Done |
| `_savedAt` timestamp in draft JSON | ✅ Done |
| Draft cleared after successful save | ✅ Done |
| Resume restores all fields (supplier, broker, items, terms) | ⚠️ Supplier/broker restore unverified |

---

## FILES TO EDIT
```
flutter_app/lib/features/purchase/presentation/purchase_home_page.dart
flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart
flutter_app/lib/features/purchase/presentation/widgets/resume_purchase_draft_banner.dart
flutter_app/lib/core/services/offline_store.dart
```

---

## WHAT TO DO

### ❌ TASK 07-A: Show WIP draft in History list

**File:** `purchase_home_page.dart`

At the TOP of the purchase list, before the API-fetched cards, check for a local WIP draft
and show a "Draft" card if found:

```dart
Widget _buildWipDraftCard(BuildContext context, String rawJson) {
  Map<String, dynamic> draft = {};
  String savedAt = '';
  String supplierName = 'Unknown supplier';
  int itemCount = 0;
  
  try {
    final o = jsonDecode(rawJson) as Map<String, dynamic>;
    draft = o;
    final meta = o['draftWizardMeta'] as Map? ?? {};
    savedAt = meta['savedAt']?.toString() ?? '';
    supplierName = o['supplierName']?.toString() ?? 'Draft purchase';
    itemCount = (o['lines'] as List?)?.length ?? 0;
  } catch (_) {}
  
  final timeStr = savedAt.isNotEmpty
      ? DateFormat('d MMM, h:mm a').format(DateTime.tryParse(savedAt) ?? DateTime.now())
      : 'Recently';
  
  return GestureDetector(
    onTap: () => context.push('/purchase/new'),  // wizard opens → resume banner shows
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),  // amber-50
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: Color(0xFFE65100), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplierName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'} · Saved $timeStr',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCC80),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Draft',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF4A2800)),
            ),
          ),
        ],
      ),
    ),
  );
}
```

**In the list build:**
```dart
// Before the main ListView:
Builder(builder: (ctx) {
  final biz = ref.read(sessionProvider)?.primaryBusiness.id ?? '';
  final raw = OfflineStore.getPurchaseWizardDraft(biz);
  if (raw != null && raw.isNotEmpty) {
    return _buildWipDraftCard(ctx, raw);
  }
  return const SizedBox.shrink();
}),
```

---

### ⚠️ TASK 07-B: Verify supplier/broker restored on resume

**File:** `purchase_entry_wizard_v2.dart`

When `_resumeDraft(json)` is called, it must restore:
1. `supplierId` and `supplierName` → set text in supplier field controller
2. `brokerId` and `brokerName` → set text in broker field controller
3. All `lines` → restore items list
4. Terms fields: `paymentDaysCtrl`, `commissionCtrl`, etc.

Find `_syncControllersFromDraft()` or similar and ensure it sets:
```dart
_supplierCtrl.text = draft.supplierName ?? '';
_brokerCtrl.text = draft.brokerName ?? '';
// Lines are already in draft state — wizard re-reads from purchaseDraftProvider
```

Also ensure `_pickInProgress` guard doesn't block the restore.

---

### ⚠️ TASK 07-C: Verify 24h auto-expiry

**File:** `resume_purchase_draft_banner.dart`

Confirm the banner already has age check. If missing, add:
```dart
// In ResumePurchaseDraftBanner.build():
final savedAtStr = (meta['savedAt']?.toString() ?? '');
final savedAt = DateTime.tryParse(savedAtStr);
if (savedAt != null && DateTime.now().difference(savedAt).inHours > 24) {
  // Auto-clear stale draft
  OfflineStore.clearPurchaseWizardDraft(biz);
  return const SizedBox.shrink();
}
```

---

## SPEC: Draft flow

```
User starts filling wizard → auto-saves every 800ms to OfflineStore
User presses back → discard dialog → "Save draft" saves & exits
User taps home → ResumePurchaseDraftBanner shown on PurchaseHomePage
History tab → amber "Draft" card shown at top of list
User taps Resume or Draft card → wizard opens at step 0 with fields pre-filled
User completes wizard → saves → draft cleared from OfflineStore
Draft older than 24h → auto-cleared, not shown
```

---

## VALIDATION
- [ ] Fill in supplier → close app → reopen → banner shown "Resume draft from X"
- [ ] Tap Resume → wizard at step 0 with supplier field filled
- [ ] Draft card shown in History tab with amber badge
- [ ] After save, draft card disappears from History
- [ ] Draft >24h old → not shown (auto-cleared)
