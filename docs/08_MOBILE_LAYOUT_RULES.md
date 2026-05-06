# 08 — Mobile Layout Rules (No Overflow, No Overlap)

Target: **iPhone 16 Pro** viewport.

## Hard rules

- No horizontal scroll on purchase preview table.
- Use `Flexible`, `Expanded`, `maxLines`, `ellipsis` to prevent overflow.
- One primary scroll; avoid nested scrolling inside pages.
- Sticky bottom actions must respect `SafeArea` and never overlap content.

## Prevent known issues

- Overlapping widgets
- Clipped warnings
- Infinite height layouts
- Bottom button collisions

## Required techniques

- `LayoutBuilder` for width budgeting
- `Text` with `maxLines: 1` for table cells
- `IntrinsicHeight` avoided in lists (performance)

