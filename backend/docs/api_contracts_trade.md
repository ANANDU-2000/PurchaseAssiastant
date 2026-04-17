# Trade purchase API contracts

Base path: `/v1/businesses/{business_id}` (requires Bearer JWT + membership).

## Trade purchases

| Method | Path | Body / query | Response |
|--------|------|--------------|----------|
| GET | `/trade-purchases` | `limit` 1–200 | JSON array of `TradePurchaseOut` |
| POST | `/trade-purchases` | `TradePurchaseCreateRequest` | `201` + `TradePurchaseOut` |
| GET | `/trade-purchases/{purchase_id}` | — | `TradePurchaseOut` |
| POST | `/trade-purchases/check-duplicate` | `TradeDuplicateCheckRequest` | `TradeDuplicateCheckResponse` |
| GET | `/trade-purchases/draft` | — | `TradeDraftOut` or `404` |
| PUT | `/trade-purchases/draft` | `TradeDraftUpsertRequest` | `TradeDraftOut` |
| DELETE | `/trade-purchases/draft` | — | `204` |

### `TradePurchaseCreateRequest`

- `purchase_date` (ISO date)
- `supplier_id`, `broker_id` optional UUIDs
- `payment_days`, `discount` (header %), `commission_percent`, `delivered_rate`, `billty_rate`, `freight_amount` optional
- `lines[]`: `item_name`, `qty`, `unit`, `landing_cost`, optional `selling_cost`, `discount`, `tax_percent`, `catalog_item_id`

### Human IDs

Server assigns `human_id` like `PUR-2026-0001` per business and calendar year.

## Reports (trade)

| Method | Path | Query | Response |
|--------|------|-------|----------|
| GET | `/reports/trade-summary` | `from`, `to`, `supplier_id` optional | `{ deals, total_purchase, total_qty, avg_cost }` |

## Cutover

- Legacy `/entries` remains for historical data and analytics that still read `entries`.
- New Flutter **Purchase** tab uses trade purchase endpoints only.
