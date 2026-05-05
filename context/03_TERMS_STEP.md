# SPEC 03 — TERMS STEP (Step 2: Deal Terms)
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Payment days field | ✅ Done |
| Commission % mode | ✅ Done |
| Commission flat (₹) mode | ✅ Done |
| Commission unit — per kg / per bag / per bill | ✅ Done |
| Commission unit auto-preselect based on item units | ⚠️ Implemented (verify) |
| Broker commission only shown when broker selected | ✅ Done |
| Discount % field | ✅ Done |
| Freight field + type dropdown | ✅ Done |
| Delivered rate field | ✅ Done |
| Billty rate field | ✅ Done |
| Narration/memo field | ✅ Done |
| Keyboard overlap on terms fields | ⚠️ Needs verify (wizard padding should cover) |
| Cost breakdown summary shown on this step | ⚠️ Shown on Review step (step 3), not terms |
| "Save Purchase" button on review step | ✅ Done |

---

## FILES TO EDIT
```
flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart
flutter_app/lib/features/purchase/presentation/wizard/purchase_review_tally_step.dart
flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart
```

---

## WHAT TO DO

### ❌ TASK 03-A: Commission unit — auto-preselect based on items
**File:** `purchase_terms_only_step.dart`

When the terms step initialises, read the draft lines and auto-set commission unit:

**Add to the wizard's `_onProceedToTerms()` or when `_wizStep` changes to 2:**
```dart
void _autoSelectCommissionUnit() {
  final lines = ref.read(purchaseDraftProvider).lines;
  final hasBag = lines.any((l) {
    final u = (l['unit']?.toString() ?? '').toLowerCase();
    return u == 'bag' || u == 'sack';
  });
  final hasBox = lines.any((l) =>
    (l['unit']?.toString() ?? '').toLowerCase() == 'box');
  final hasTin = lines.any((l) =>
    (l['unit']?.toString() ?? '').toLowerCase() == 'tin');
  final allKg = !hasBag && !hasBox && !hasTin;

  // Only auto-set if user hasn't already chosen
  final current = ref.read(purchaseDraftProvider).commissionMode ?? '';
  if (current.isNotEmpty && current != kPurchaseCommissionModePercent) return;

  String newMode;
  if (hasBag) newMode = kPurchaseCommissionModeFlatBag;
  else if (hasBox) newMode = kPurchaseCommissionModeFlatBag; // box uses same
  else if (hasTin) newMode = kPurchaseCommissionModeFlatTin;
  else newMode = kPurchaseCommissionModeFlatKg;

  ref.read(purchaseDraftProvider.notifier).setCommissionMode(newMode);
}
```

Call `_autoSelectCommissionUnit()` when transitioning to `_wizStep == 2`.

---

### ❌ TASK 03-B: Keyboard overlap on terms step
**File:** `purchase_terms_only_step.dart`

The terms step is rendered inside the wizard's `SingleChildScrollView`.
When a TextField is focused the keyboard pushes up content but the
"Save Purchase" button (in the wizard's bottom bar) is covered.

The wizard body fix in `01_PURCHASE_WIZARD.md` TASK 01-B handles this.
Confirm that when `01-B` is applied, terms step fields are also fixed.

If NOT fixed: add `scrollPadding: EdgeInsets.only(bottom: 160)` to every
`TextFormField` in `purchase_terms_only_step.dart` so the scroll view
moves the focused field above the keyboard.

---

## SPEC: Terms Step Layout

```
AppBar: "← New purchase — Terms"
──────────────────────────────────────────────

[Header summary — READ ONLY]
surag · kkkk · 5 May 2026 · PUR-2026-0005
Items: 1 (Basmathu · 100 bags · 5,000 kg)

══════ DEAL TERMS ══════════════════════════

Payment days        [  2  ]
                    Due: 7 May 2026 (auto-computed)

Broker commission   [% ▾]           [  1.00  ]
 ← if % mode:  commission = total × 1%
 ← if ₹ mode:  show unit picker:
               [kg ▾]  [  0.50  ]
               Units auto-selected from items:
               • if any bag/box → "bag · box"
               • if tin only → "tin"
               • if all kg → "kg"

Discount            [  0.00  ] %

──────────────────────────────────────────────

Freight             [  0.00  ]  [Separate ▾]
Delivered rate      [  0.00  ]
Billty rate         [  0.00  ]

──────────────────────────────────────────────

Narration / memo    [                        ]

══════ COST BREAKDOWN ══════════════════════

Lines (incl. tax/disc)      ₹1,30,000.00
Header discount                       —
Commission                       ₹1,300
Freight                              —
Billty                               —
Delivered                            —
──────────────────────────────────────────
FINAL TOTAL                  ₹1,31,300
Profit                          ₹5,000  ← green

──────────────────────────────────────────────

[           Save Purchase           ]  ← full width, h=56
```

---

## COMMISSION MODE REFERENCE
Modes defined in `purchase_draft.dart`:
```
kPurchaseCommissionModePercent      = 'percent'        → % of total
kPurchaseCommissionModeFlatInvoice  = 'flat_invoice'   → ₹ per bill
kPurchaseCommissionModeFlatKg       = 'flat_kg'        → ₹ per kg
kPurchaseCommissionModeFlatBag      = 'flat_bag'       → ₹ per bag/box
kPurchaseCommissionModeFlatTin      = 'flat_tin'       → ₹ per tin
```

The terms step commission row shows:
1. A mode dropdown: `[% | ₹/bill | ₹/unit]`
2. If `₹/unit`: a unit dropdown `[kg | bag | tin]` (auto-selected from items)
3. A value TextField

---

## VALIDATION
- [ ] Add bag item → go to terms → commission mode auto-sets to "₹/bag"
- [ ] Add kg item → commission mode auto-sets to "₹/kg"
- [ ] Keyboard opens on payment days → Save button still above keyboard
- [ ] Commission % mode: change % → cost breakdown updates in real time
- [ ] Commission ₹/bag mode: change unit price → breakdown updates
- [ ] "Save Purchase" saves and redirects to detail page
