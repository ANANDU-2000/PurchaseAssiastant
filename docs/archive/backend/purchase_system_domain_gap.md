# Purchase System Domain Gap (Legacy → Target)

This document maps the existing Harisree schema to the wholesale **Purchase Management** target so migrations and APIs stay traceable.

## Legacy anchors

| Legacy | Role |
|--------|------|
| `entries` | Purchase header (date, supplier, broker, transport, commission). |
| `entry_line_items` | Line qty/unit/prices; optional `catalog_item_id` / `catalog_variant_id`. |
| `suppliers` | Contact + optional single `broker_id`. |
| `brokers` | Commission type/value; linked suppliers via ORM `suppliers` backref. |
| `item_categories` | Top-level category (maps to **Category**). |
| `category_types` | Mid layer (maps to **Subcategory**). |
| `catalog_items` / `catalog_variants` | Master items (maps to **Item** + variant granularity). |

## Target modules (implemented incrementally)

| Target concept | Implementation choice |
|----------------|------------------------|
| **Supplier** fields (GST, payment days, discount, delivered/billty rates) | Extend `suppliers` with nullable columns + API exposure. |
| **Broker.phone** + **broker ↔ suppliers** list | `brokers.phone`; new `broker_supplier_links` M2M (legacy `supplier.broker_id` still honored as fallback). |
| **Category / Subcategory** | Reuse `item_categories` / `category_types` (no rename in DB); new read APIs may alias names. |
| **Item** (HSN, tax, defaults, links) | Extend `catalog_items` (+ optional link tables later); variants stay `catalog_variants`. |
| **Purchase** `PUR-YYYY-XXXX` | New `trade_purchases` + `trade_purchase_lines` (confirmed purchases). Legacy `entries` kept for cutover/analytics compatibility. |
| **Draft / resume** | New `trade_purchase_drafts` (JSON payload per `business_id` + `user_id`). |
| **Duplicate detection** | New `POST .../trade-purchases/check-duplicate` using supplier + date + totals + line fingerprint (separate from legacy entry duplicate). |

## Breakpoints (where behavior diverges)

1. **Flutter “Purchase” tab** uses **trade purchase** APIs first; legacy Entries list remains reachable until reports fully dual-read.
2. **Assistant backend** unchanged; any “save purchase” from AI should eventually call trade purchase confirm — adapter work is explicit and small.
3. **Reports**: Phase 1 keeps existing `/analytics` on `entries`; optional `/reports/trade-summary` reads `trade_purchases` for new dashboard cards.

## Zero data loss

- Drafts persisted server-side + client can mirror in `OfflineStore` (Flutter).
- Final save is transactional (`trade_purchases` + lines).
- Legacy rows are never deleted by this migration path.
