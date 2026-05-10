# Unit Migration Report

## Source
- Workbook: `data/products_categories_items/Products list.xlsx`
- Generated output: `master_item_profiles.json`
- Profiles generated: 505

## Canonical Rules Applied
- Bulk `NN KG` items at 10kg or above resolve to `BAG`, `stock_unit=kg`, `rate_dimension=bag`, and `weight_per_unit=NN`.
- Retail `GM`, `ML`, `LTR` pack rows stored as `PCS` resolve to `BOX` unless explicitly marked as tin/can/jar.
- Explicit `BOX`, `CTN`, or `CARTON` resolves to `BOX`.
- Explicit `TIN`, `CAN`, or `JAR` resolves to `TIN`.
- Loose/default kg rows without bulk-pack intent remain `KG`.

## Requested Examples
- `RUCHI 425 GM` -> `BOX`, rate `box`, size `425 GM`.
- `RUCHI 850GM` -> `BOX`, rate `box`, size `850 GM`.
- `SUNRICH 400GM BOX` -> `BOX`, rate `box`, size `400 GM`.
- `DALDA 1LTR BOX` -> `BOX`, rate `box`, size `1 LTR`.
- `JEERAKAM 30 KG` -> `BAG`, stock `kg`, rate `bag`, weight `30`.
- `SUGAR 50 KG` -> `BAG`, stock `kg`, rate `bag`, weight `50`.
