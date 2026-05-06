# AI Purchase Scanner V2 — UI Flow

Design target: **iPhone 16 Pro** (393 × 852 pt at default text scale, clamped ≤ 1.15). Everything must work without horizontal scroll. Touch targets ≥ 44 × 44 pt.

This doc is binding for the Flutter implementation in `flutter_app/lib/features/purchase/presentation/scan_v2_page.dart` and its widgets under `widgets/scan_v2/`.

---

## 1. Entry points

- **Home page** ([home_page.dart](../flutter_app/lib/features/home/presentation/home_page.dart)) — "Scan bill" tile pushes `/purchase/scan-v2` (when `ENABLE_AI_SCANNER_V2`, else legacy).
- **Purchase home** ([purchase_home_page.dart](../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart)) — overflow menu "Scan" → same route.
- **Voice/keyboard plus button** in floating action — long-press surfaces "Scan".

---

## 2. Top-level layout (single screen, no horizontal scroll)

```
┌────────────────────────────────────────────────┐
│  ←  Scan bill                       Re-scan ⟳  │  AppBar (sticky)
├────────────────────────────────────────────────┤
│  [thumb 88×88]  Confidence 91% (amber)         │  Scan summary strip
├────────────────────────────────────────────────┤
│  Supplier  [SURAJ TRADERS  ✓]    confidence 96 │  pill row
│  Broker    [Riyas         ✓]     confidence 88 │
├────────────────────────────────────────────────┤
│  Items                                          │
│  Item              Bags  Kg    P. Rate  S. Rate  Total │  table header (compact)
│  ──────────────────────────────────────────────────── │
│  Sugar 50kg          100  5000   56     57    280000  ⋯ │  row (tap-to-edit, ⋯ = more)
│  Barli rice 50kg      40  2000   62     65    124000  ⋯ │
│  ──────────────────────────────────────────────────── │
│  Totals             140  7000              404000      │
├────────────────────────────────────────────────┤
│  ▾ Advanced (delivered, billty, freight, …)     │  collapsed by default
├────────────────────────────────────────────────┤
│  ⚠ 1 warning — tap to review                   │  warnings strip (shown only if any)
├────────────────────────────────────────────────┤
│  ₹ 4,04,000  total                  [ Save ➜ ] │  sticky save bar
└────────────────────────────────────────────────┘
```

### Width budget for the items table

iPhone 16 Pro safe area inside SafeArea is ≈ 361 pt. Allocations (in pt):

```
Item    flexible (min 92, ellipsizes)   ~115
Bags    monospace right-aligned          40
Kg      monospace right-aligned          50
P.Rate  monospace right-aligned          48
S.Rate  monospace right-aligned          48
Total   monospace right-aligned          60
⋯       icon button                      32
                                       —————
                                        ≈ 393 (with margins)
```

Padding around table: 4 pt left + 4 pt right + 8 pt vertical per row. We clamp `MediaQuery.textScaleFactor` to 1.15 inside this widget to avoid breaking the budget for users with large system text.

If the available width drops below 360 pt (rotated iPad split etc.), we hide the **S. Rate** column and surface it via the row "more" sheet, with an info banner ("S. Rate hidden on narrow screens"). Never show a horizontal scroll bar.

---

## 3. Confidence pills

Inline next to supplier / broker / item match name:

| score | pill | color tokens (DS) | behaviour |
| --- | --- | --- | --- |
| ≥ 92 | green check + `auto` | `glass.success.bg / glass.success.fg` | tap → quick "Change…" sheet (top-3) |
| 70–91 | amber `?` + `confirm` | `glass.warning.bg / glass.warning.fg` | tap → "Did you mean…" sheet (mandatory before save) |
| < 70 | red `!` + `pick` | `glass.error.bg / glass.error.fg` | tap → full picker; **save disabled until picked** |

The header summary chip ("Confidence 91%") follows the **lowest** bucket among all entities, not the average — to surface the worst case immediately.

---

## 4. Inline editing

- Tap any cell in the table → that cell becomes a `TextField` with the appropriate keyboard:
  - `TextInputType.numberWithOptions(decimal: true, signed: false)` for numeric.
  - `TextInputType.text` for item name (rare; usually disabled, name comes from the catalog match).
- Focus auto-advances Bags → Kg → P.Rate → S.Rate via `next` action key.
- Edits update derived totals immediately via the local `bag_logic` mirror.
- Conflicts show inline red underline + small `errorText` row beneath; never use snack bars for validation (per `.cursorrules`).

---

## 5. Row "more" sheet

Tapping the `⋯` overflow icon opens a bottom sheet for the line:

```
┌────────────────────────────────────────────────┐
│  Sugar 50kg                                    │
│                                                │
│  Delivered rate     [   ]                      │
│  Billty rate        [   ]                      │
│  Freight (line)     [   ]                      │
│  Discount (line)    [   ]                      │
│  Tax %              [   ]                      │
│  Notes              [                       ]  │
│                                                │
│  [ Cancel ]                       [ Save ➜ ]   │
└────────────────────────────────────────────────┘
```

Save here only updates local state for that row; nothing hits the network.

---

## 6. Header advanced expander

Collapsed by default. When expanded shows:

- Delivered rate (₹/kg or ₹/bag — selector)
- Billty rate (₹/bag flat or ₹/kg)
- Freight amount + freight type (`included` | `separate`)
- Payment days (numeric, default from supplier last-defaults)
- Broker commission:
  - Type segmented: `Percent` | `Fixed`
  - If `Percent`: a single `%` field
  - If `Fixed`: amount + applies-to dropdown (`per kg` | `per bag` | `per box` | `per tin` | `once / invoice`)
- Discount % (header-level)

These fields are pre-filled by the AI when present. The user can override; defaults reapply only if the field is empty.

---

## 7. Warnings strip

If `warnings.length > 0` we render a compact strip above the save bar:

- Severity colour determines the strip background.
- Tap to open a bottom sheet listing every warning with its target field, message, and "Jump to" CTA that scrolls/focuses the offending cell.
- `blocker` warnings disable the Save button. The bar shows "Fix N issues to save".

---

## 8. Sticky save bar

```
┌────────────────────────────────────────────────┐
│  ₹ 4,04,000        Total · 140 bags · 7000 kg  │
│                                  [ Save ➜ ]    │
└────────────────────────────────────────────────┘
```

Behaviour:

- The bar uses `SafeArea` + `BottomAppBar` so it never overlaps system home indicator.
- Tap "Save" → `confirm` request to backend.
- During request: button shows `CircularProgressIndicator` and is disabled.
- On 409 duplicate: dialog "Possible duplicate purchase" with "Edit / Save anyway / Cancel".
- On success: pop to History with a snack bar "Purchase saved · `PUR-2026-0001`" + bottom-sheet (`purchase_saved_sheet.dart`) for "Print / Share PDF".

---

## 9. Unsaved data protection (`PopScope`)

```dart
PopScope(
  canPop: !state.dirty,
  onPopInvoked: (didPop) async {
    if (didPop) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => UnsavedChangesDialog(),
    );
    if (ok == true && context.mounted) Navigator.of(context).pop();
  },
  child: …,
);
```

Dialog copy:

> **Unsaved purchase will be lost.**
> Do you want to discard the scan, or keep editing?
> [ Keep editing ] [ Discard ]

---

## 10. Autosave

- Every cell change → debounce 800 ms → write to `OfflineStore.putPurchaseScanV2Draft(businessId, payload)`.
- Resume banner on next entry: "You have an unsaved scan from 12 min ago. [Resume] [Discard]".
- Drafts auto-expire after 24 h (matches existing wizard logic).

---

## 11. Loading states

- After image picked: full-screen progress card with rotating status:
  1. "Reading image…" (Vision/multimodal call)
  2. "Understanding text…" (LLM JSON parse)
  3. "Matching items…" (matcher)
  4. "Validating…" (validators + duplicate detector)
- Use `LinearProgressIndicator` (indeterminate) inside a card; never block the whole screen with a spinner — per `.cursorrules`.
- Stage transitions are timed by client-side ticks (we don't yet stream from backend); after 8 s on the same stage, append "(slow network — almost there)".

---

## 12. Error states

- Network down → "No connection. Try again when online" + Retry button.
- 422 validation error before save → highlight offending row, focus the cell.
- 409 duplicate → modal listing matching purchases with date/amount/items + "Save anyway" / "Open existing" / "Cancel".
- 502 all providers down → "Couldn't read the image. Try a clearer photo or type manually" + "Type manually" button which opens the empty wizard.

---

## 13. Accessibility

- Every cell has a semantic label ("Bags for Sugar 50kg, current value 100"). 
- Confidence pills include semantic state ("Match confidence 96 %").
- Voice-over: focus order top-to-bottom, left-to-right within rows.
- Minimum tap target 44 × 44 pt; expand `⋯` icon hit-area to 44 × 44.

---

## 14. Theming

We reuse the design system tokens in [hexa_ds_tokens.dart](../flutter_app/lib/core/design_system/hexa_ds_tokens.dart) and the existing Plus Jakarta Sans font. No custom colours; no inline hex outside tokens.

---

## 15. Animations

Subtle only. Pill colour transitions over 150 ms. Row inserts/removes use `AnimatedSize`. We avoid hero animations on the table (kills jank-free scrolling on older Androids).

---

## 16. Print / share

After save, the existing PDF builder ([purchase_invoice_pdf_layout.dart](../flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart)) is reused (post-cleanup). The "Print" button opens `Printing.layoutPdf` like elsewhere in the app.
