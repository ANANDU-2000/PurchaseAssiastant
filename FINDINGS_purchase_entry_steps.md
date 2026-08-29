# FINDINGS: Purchase Entry Flow — Too Many Steps/Dialogs/Clicks (Issue #2)

**Status:** UX audit complete. Ready for consolidation plan review.

---

## Current Flow Map (Mobile — Stepped Wizard)

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 0: Party & Terms                                           │
│   • Supplier field (overlay autocomplete)                       │
│     – Tap "New supplier…" → fullscreen SupplierCreateSimple    │
│   • Broker field (overlay autocomplete)                         │
│     – Tap "New broker…" → fullscreen BrokerWizardPage          │
│   • Payment days, Commission, Header discount, Narration       │
│   • "Continue →" button                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (validation: supplier required)
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Items                                                   │
│   • List of added lines (PurchaseFastItemsStep)                 │
│   • "+ Add item" FAB → PurchaseItemEntrySheet (fullscreen)     │
│       – Catalog search (overlay autocomplete)                   │
│         • Tap "New catalog item…" → /catalog/quick-add route    │
│       – Qty, Unit, Landing, Selling, Discount, Tax, KG/bag     │
│       – "Save" → returns to Items list with snackbar           │
│   • "Review purchase →" button                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (validation: ≥1 line)
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Review (PurchaseReviewTallyStep)                        │
│   • Read-only Tally-style recap + expandable line math          │
│   • "Save" button                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ SAVE CONFIRMATION DIALOG (AlertDialog)                          │
│   "Confirm purchase save?"                                      │
│   [Cancel] [Save]                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ SERVER VALIDATION (validateTradePurchase)                       │
│   On failure: back to step with inline error, no dialog        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ SAVE RESULT SHEET (showPurchaseSavedSheet) — MULTI-ACTION       │
│   NEW purchase:                                                 │
│     • "Add another"       → reset wizard, stay on Step 0       │
│     • "Edit missing"      → push /purchase/edit/<id>           │
│     • "Later missing"     → pop to /purchase                   │
│     • "Delivery: Yes/No"  → pop to /purchase (+snackbar)       │
│     • "Detail"            → push /purchase/detail/<id>         │
│     • (back gesture)      → pop to /purchase                   │
│   EDIT purchase:                                                │
│     • "Add another"       → reset wizard, stay on Step 0       │
│     • (other actions)     → pop to /purchase                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Click/Step Count for Common Scenarios (Mobile)

| Scenario | Steps | Dialogs | Taps/Clicks |
|----------|-------|---------|-------------|
| **New purchase, 1 line** | 3 wizard steps + 1 item sheet | 3 (supplier create? / broker create? / save confirm / saved sheet) | ~18–22 |
| **New purchase, 3 lines** | 3 wizard steps + 3 item sheets | 5 (3 item sheets + save confirm + saved sheet) | ~30–36 |
| **Edit existing purchase** | 3 wizard steps (+1 item sheet per edit) | 2 (save confirm + saved sheet) | ~15–25 |
| **Quick supplier create** | – | 1 (fullscreen SupplierCreateSimple) | +4–6 taps inside |
| **Quick broker create** | – | 1 (fullscreen BrokerWizardPage) | +4–6 taps inside |
| **New catalog item from item sheet** | – | 1 (navigate to /catalog/quick-add) | +5–8 taps inside |

---

## Desktop/Tablet Flow (Single-Scroll Voucher)

```
┌─────────────────────────────────────────────────────────────────┐
│ SINGLE PAGE (Tally-style)                                       │
│   Header row: Supplier | Broker | Invoice Date | Invoice #     │
│   Terms row: Payment | Commission | Freight | Discount         │
│   ───────────────────────────────────────────────────────────  │
│   Items table (PurchaseFastItemsTable) — inline edit           │
│     • "Add row" → PurchaseItemEntrySheet (bottom sheet modal)  │
│     • Edit row → same sheet with initial data                  │
│   ───────────────────────────────────────────────────────────  │
│   Summary strip: Qty | Tax | Charges | Grand Total             │
│   Sticky footer: [Save / Update purchase]                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                  SAVE CONFIRMATION DIALOG (same as mobile)
                              │
                              ▼
                  SAVED SHEET (same as mobile)
```

**Desktop click count for 3-line purchase:** ~12–15 (no step navigation, inline items)

---

## Specific Pain Points Identified

### 1. Mobile Wizard Step Fragmentation
- **3 explicit steps** with "Continue" / "Review" buttons
- Each step validates and shows inline errors — but user must tap through
- Step 0 requires supplier; Step 1 requires ≥1 line; Step 2 is read-only
- **Why 3 steps?** Historical: "don't show items until supplier picked" (for catalog defaults). But desktop proves single-page works.

### 2. Item Entry = Fullscreen Modal (Mobile)
- Every line add/edit = full-screen push (`MaterialPageRoute`, `fullscreenDialog: true`)
- Returns to list → user taps "Review" → Step 2 → Save → Confirm → Saved Sheet
- **No "quick add another" from item sheet** — must close, tap +, reopen

### 3. Save Confirmation Dialog Is Redundant
- Step 2 (Review) **already shows full recap** with totals, terms, lines
- Then "Save" shows `AlertDialog: "Confirm purchase save?"` — duplicate confirmation
- Comment in code (line 1693): `// Review step (step 2) is the confirmation surface — no second AlertDialog.`
- But the dialog **still exists** (lines 1695–1717) and fires unless `_wizStep == 2`
- Since mobile wizard forces Step 2 before save, dialog **always shows** — contradiction

### 4. Saved Sheet = Decision Paralysis (5+ Buttons)
| Button | Action | When Useful? |
|--------|--------|--------------|
| Add another | Reset wizard, stay | Batch entry (common) |
| Edit missing | Push edit page | Only if server flags missing details |
| Later missing | Pop to list | Defer |
| Delivery: Yes/No | Pop to list | Warehouse workflow |
| Detail | Push detail page | Rare |
| Back gesture | Pop to list | Default exit |

**Most users just want:** "Saved → back to list" or "Saved → add another"
**Current:** 5 explicit buttons + back gesture = cognitive load

### 5. Supplier/Broker Quick-Create = Fullscreen Detour
- `SupplierCreateSimple` / `BrokerWizardPage` are full-screen routes
- User loses context of the purchase wizard
- On return, wizard reloads lists via `ref.invalidate()`

### 6. New Catalog Item from Item Sheet = Navigation Away
- `navigateCatalogQuickAddItem` pushes `/catalog/quick-add` route
- Returns `{id, name}` → wizard invalidates catalog → user continues
- **Three context switches** for one missing catalog item

---

## Cross-Platform Inconsistency

| Aspect | Mobile (<600) | Tablet (600–1023) | Desktop (≥1024) |
|--------|---------------|-------------------|-----------------|
| Layout | 3-step wizard | Single-scroll (voucher if ≥768) | Single-scroll voucher |
| Item entry | Fullscreen page | Bottom sheet (modal) | Bottom sheet (modal) |
| Save confirm | AlertDialog | AlertDialog | AlertDialog |
| Saved sheet | 5 buttons | 5 buttons | 5 buttons |
| Supplier create | Fullscreen | Fullscreen | Fullscreen |
| Broker create | Fullscreen | Fullscreen | Fullscreen |

**Desktop proves single-page works** — mobile could use same pattern with responsive collapse.

---

## Code References

| File | Key Lines | Role |
|------|-----------|------|
| `purchase_entry_wizard.dart` | 156–157 | `_wizStep = 0/1/2` state |
| `purchase_entry_wizard.dart` | 2171–2223 | `_wizNext()` step validation |
| `purchase_entry_wizard.dart` | 1693–1717 | Save confirmation dialog (redundant) |
| `purchase_entry_wizard.dart` | 1930–1993 | `showPurchaseSavedSheet` 5-button result |
| `purchase_entry_wizard.dart` | 1279–1432 | `_openItemSheet` — fullscreen on mobile |
| `purchase_party_step.dart` | 393–418, 588–612 | Supplier/Broker `PartyInlineSuggestField` |
| `purchase_item_entry_sheet.dart` | 3441 | Item `PartyInlineSuggestField` |
| `purchase_entry_wizard.dart` | 939–937, 940–982 | `_openQuickSupplierCreate`, `_openQuickBrokerCreate` |
| `purchase_item_entry_sheet.dart` | 1458–1484 | `navigateCatalogQuickAddItem` callback |

---

## Proposed Consolidation (Diff Description — Do Not Apply Until Approved)

### Option A: Mobile Single-Page Voucher (Align with Desktop)
**Scope:** Merge Steps 0+1+2 into single `ListView` on mobile (like tablet ≥768 / desktop)
- Supplier + Broker + Terms at top (collapsible if needed)
- Items table inline (compact rows, tap to edit in bottom sheet)
- Summary strip sticky at bottom
- **Eliminates:** Step navigation, "Continue" taps, Review step as separate page
- **Keeps:** Validation (inline errors scroll into view), Save confirmation dialog (or remove per Option B)

### Option B: Remove Redundant Save Confirmation Dialog
**Scope:** Delete `AlertDialog` in `_validateAndSave` (lines 1695–1717)
- Step 2 **is** the confirmation — user sees totals, terms, lines
- Tally/voucher UX: "Save" on review page commits directly
- **Risk:** Accidental save? Mitigation: `_isSaving` loading state + haptic feedback

### Option C: Simplify Saved Sheet to 2 Primary Actions
**Scope:** Reduce `showPurchaseSavedSheet` buttons
- **Primary:** "Back to list" (default, highlighted)
- **Secondary:** "Add another" (prominent, for batch entry)
- **Tertiary (overflow menu):** Edit missing, Detail, Delivery
- **Removes:** "Later missing" (back gesture covers it), "Delivery Yes/No" (move to list actions)

### Option D: Inline Quick-Create for Supplier/Broker/Catalog
**Scope:** Replace fullscreen routes with bottom sheets / inline forms
- Supplier create: bottom sheet with minimal fields (name, phone, GST)
- Broker create: bottom sheet (name, commission defaults)
- Catalog quick-add: bottom sheet from item entry sheet
- **Benefit:** No context loss, faster return, wizard state preserved

### Option E: "Add Another Line" from Item Sheet
**Scope:** In `PurchaseItemEntrySheet.onCommitted`, offer "Save & add another"
- Avoids: close sheet → tap FAB → reopen sheet cycle
- Returns line data + `wantsAnother: true` → wizard reopens sheet immediately

---

## Recommended Priority Order

| Priority | Change | Impact | Risk |
|----------|--------|--------|------|
| 1 | **Remove save confirmation dialog** (Option B) | -1 tap every save | Low (review step exists) |
| 2 | **Simplify saved sheet to 2 buttons** (Option C) | -3 buttons, clearer exit | Low |
| 3 | **"Save & add another" from item sheet** (Option E) | -3 taps per extra line | Low |
| 4 | **Inline quick-create bottom sheets** (Option D) | -2 context switches per create | Medium (new UI) |
| 5 | **Mobile single-page voucher** (Option A) | -3 steps, unified UX | High (layout rewrite) |

**Start with 1+2+3** — high impact, low risk, no layout changes. Then evaluate 4+5.

---

## Verification Checklist

- [ ] Save flow: Review step → Save → **no dialog** → saved sheet (2 buttons)
- [ ] Saved sheet: "Back to list" pops to `/purchase`; "Add another" resets wizard to Step 0
- [ ] Item sheet: "Save & add another" reopens sheet with cleared fields, same supplier
- [ ] Quick supplier/broker create: bottom sheet, returns to wizard without reload
- [ ] Mobile single-page: scroll performance with 20+ lines, keyboard avoidance works
- [ ] Desktop/tablet unchanged (already single-page)

---

## Next Steps

**Waiting for approval to implement:**
1. ✅ Findings documented — this file
2. ⏳ **Approve priority changes** (recommend 1+2+3 first)
3. ⏳ Implement save dialog removal + saved sheet simplification
4. ⏳ Implement "Save & add another" in item sheet
5. ⏳ Test on device: measure tap count for 3-line purchase (target: ≤15 from ~30)
6. ⏳ Then evaluate inline quick-create + single-page mobile