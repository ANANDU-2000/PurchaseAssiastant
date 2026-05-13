# Form scroll architecture

## Single scroll owner rule

Each screen should have **at most one** primary vertical scrollable that participates in **keyboard inset** negotiation, unless a nested list is intentionally **bounded** inside a flex child.

## Master inventory (Flutter `lib/`)

| Route / widget | `resizeToAvoidBottomInset` | Scroll owner | Notes |
|----------------|----------------------------|--------------|-------|
| `purchase_entry_wizard_v2` | **true** (post-change) | Steps 0,1,3: `SingleChildScrollView`; Step 2: inner `ListView` in `PurchaseFastItemsStep` | Step 2 **must not** wrap outer `SingleChildScrollView` — `Column` + `Expanded(ListView)` needs bounded height from `Expanded`. |
| `purchase_item_entry_sheet` (fullPage) | true | `KeyboardSafeFormViewport` → `SingleChildScrollView` | Pinned preview outside viewport (separate column). |
| `FullScreenFormScaffold` | true | `KeyboardSafeFormViewport` | Canonical full-screen pattern. |
| `supplier_create_wizard_page` | true | `KeyboardSafeFormViewport` | |
| `supplier_create_simple` | true | `KeyboardSafeFormViewport` | |
| `catalog_add_*` pages | true | `KeyboardSafeFormViewport` | |
| `login_page` / `signup` / `forgot_password` / `reset_password` | true | varies | Audit per-page when touched. |
| `scan_purchase_v2_page` | true | custom | |
| `assistant_chat_page` | true | custom | |

## NestedScrollView

Avoid `NestedScrollView` in trader forms unless a design explicitly requires collapsing header + inner list — it complicates keyboard + focus.

## Wizard step 2 rationale

`PurchaseFastItemsStep` builds:

```text
Column(
  summaryCard,
  headerRow,
  Expanded(ListView(lines)),  // bounded by Expanded
  + Add Item button,
)
```

Wrapping this entire subtree in an outer `SingleChildScrollView` would give the inner `Expanded` **unbounded** constraints → layout error. Therefore step 2 is the **documented exception** to “one outer scroll” — the **list** is the scroll owner.

## Helper

- [form_field_scroll.dart](../../flutter_app/lib/core/widgets/form_field_scroll.dart) — `ensureFormFieldVisible` for validation jumps.
