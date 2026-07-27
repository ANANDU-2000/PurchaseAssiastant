# Seed JSON — field map to the database

**Canonical copy:** this folder (`<repo>/data/files/`) is the default for the backend.  
`app.services.catalog_suppliers_seed.resolve_seed_data_dir` loads these files first, and falls
back to `backend/scripts/data/` only if a required file is missing here.

- Idempotent CLI: `backend/scripts/seed_catalog_and_suppliers.py` (optional `--seed-dir`).
- First-login / empty workspace: `POST /v1/me/bootstrap-workspace` uses the same resolution.
- Override: set env `SEED_DATA_DIR` or `seed_data_dir` in `backend/.env` to an absolute path.

Required in this directory:

- `categories_seed.json`
- `products_by_category_seed.json`
- `suppliers_gst_seed.json`

## `products_by_category_seed.json`

Top-level keys are **subcategory (type) names** that must match `subcategories[].name` in
`backend/scripts/data/categories_seed.json` (not raw `category_id` UUIDs — the script resolves
`ItemCategory` + `CategoryType` from that structure).

| JSON field       | App / `CatalogItem` column | Notes |
|------------------|----------------------------|--------|
| `name`           | `name`                     | Required |
| `code`           | `item_code`                | Truncated to 64 chars; optional |
| `hsn`            | `hsn_code`                 | Truncated to 32 chars |
| `unit`           | `default_unit` / `default_purchase_unit` | Normalized to `kg`, `bag`, `box`, `piece`, `tin` |
| `tax_rate`       | `tax_percent`              | |
| `purchase_rate`  | `default_landing_cost`     | “Default” landed rate, not a live moving average |

**Freight:** there is no per-product “default freight” in `CatalogItem`. Freight amounts live on
`TradePurchase.freight_amount` with `freight_type` `included` | `separate`. Do not invent a
`default_freight` column without a migration.

## `suppliers_gst_seed.json`

Array of suppliers.

| JSON field | `Supplier` column | Notes |
|------------|---------------------|--------|
| `name`     | `name` | |
| `gst`      | `gst_number` | Must be 15-char GSTIN if present; use importer validation |
| `phone`    | `phone` | Whitespace/newlines normalized |
| `email`    | `notes` | Stored as a line `Email: …` (merged with `notes` if both set) |
| `whatsapp` | `whatsapp_number` | Same cleaning as `phone` |
| `notes`    | `notes` | Free text, appended after email line if present |
| `address`  | `address`, `location` | |
| `default_payment_days` | `default_payment_days` | Integer; optional |
| `default_delivered_rate` | `default_delivered_rate` | Optional |
| `default_billty_rate` | `default_billty_rate` | Optional |
| `default_discount` | `default_discount` | Optional |
| `freight_type` | `freight_type` | Max 16 chars (e.g. `included` / `separate`) |

**Freight on supplier:** the model has `default_delivered_rate`, `default_billty_rate`, and
`freight_type`. Optional JSON keys above map directly when present. There is no standing
`default_freight_amount` column; use rates or `preferences_json` in the app for other cases.
