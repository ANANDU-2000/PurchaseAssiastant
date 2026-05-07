# 60 — PRODUCTION_QA_CHECKLIST

## Automated gates

- `flutter analyze`
- `flutter test`
- `pytest backend/tests`

## Manual QA matrix (core)

### Items

- Sugar: `SUGAR 50 KG` + `100 bags` → `5000 KG • 100 BAGS`
- Rice: `RICE 26 KG` + `100 bags` → `2600 KG • 100 BAGS`
- Atta: `ATTA 30 KG` + `100 bags` → `3000 KG • 100 BAGS`
- Oil tin: `OIL 15 LTR TIN` + `50 tins` → `50 TINS` (no kg)
- Box: `SUNRICH 400GM BOX` + `200 boxes` → `200 BOXES` (no kg)

### Mixed invoice

- 1 bag line + 1 box line + 1 tin line:
  - totals show bags/boxes/tins separately
  - total kg is bag-only

### Commission modes

- `flat_bag` counts only bag/sack
- `flat_box` counts only box
- `flat_tin` counts only tin

### Viewports

- iPhone 14 / 16 Pro
- Android small
- Landscape + keyboard open: Continue remains visible