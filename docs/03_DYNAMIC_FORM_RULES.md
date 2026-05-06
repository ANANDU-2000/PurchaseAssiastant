# 03 — Dynamic Form Rules (Package-Aware UI)

## Rule: forms must change by package type

The UI must never show irrelevant fields. Package type drives visibility.

## BAG form

Show:
- Quantity **bags**
- Auto `kg` preview (derived)
- Pricing mode selector: `₹/kg` or `₹/bag`
- Purchase rate + Selling rate

Hide:
- box/tin fields

## KG form

Show:
- Quantity `kg`
- Purchase rate `₹/kg` + Selling rate `₹/kg`

Hide:
- bags/weight-per-bag

## BOX form (default wholesale mode)

Show:
- Quantity **boxes**
- Purchase rate `₹/box` + Selling rate `₹/box`

Hide:
- kg totals, items per box, kg per item

## TIN form (default wholesale mode)

Show:
- Quantity **tins**
- Purchase rate `₹/tin` + Selling rate `₹/tin`

Hide:
- kg totals, weight per tin, items per tin

## PCS form

Show:
- Quantity pieces
- Purchase rate `₹/pc` + Selling rate `₹/pc`

## Advanced inventory mode (future)

When enabled per business:
- BOX may track items/box, weight/item, kg/box
- TIN may track weight/tin

Default build keeps advanced mode OFF.

