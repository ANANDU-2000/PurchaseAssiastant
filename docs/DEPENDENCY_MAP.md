# Dependency Map

Source: Graphify graph (`graphify-out/graph.json`, commit `47b8040`). Query it instead of reading this file for detail:

```
graphify query "how does a purchase get saved"      # BFS over the graph
graphify explain "Membership"                        # node + neighbours
graphify path "<A>" "<B>"                            # shortest path (use path::symbol if ambiguous)
```
Or via the Graphify MCP tools: `query_graph`, `get_node`, `get_neighbors`, `shortest_path`, `god_nodes`, `get_community`, `get_pr_impact`.

## Layering (observed)

```
Flutter UI (features/*)
   │ reads
Riverpod providers (core/providers, feature providers)
   │ calls
hexaApiProvider → core/api/hexa_api*.dart  ──HTTP/JSON──▶  FastAPI routers
                                                              │ Depends(get_db, require_membership, require_permission)
                                                          services/*
                                                              │
                                                          models/* → PostgreSQL
```
No import cycles were detected in either tree.

## High-fan-in hubs (change with care)

| Hub | Edges | Blast radius |
|---|---|---|
| `StatelessWidget` | 407 | n/a (framework base class) |
| `sessionProvider` | 304 | Almost every screen |
| `get_db()` | 242 | Every route |
| `Membership` | 234 | All authorization and tenant scoping |
| `hexaApiProvider` | 193 | All network calls |
| `require_membership()` | 166 | All tenant routes |
| `User` / `get_current_user()` | 122 / 106 | Auth |
| `CatalogItem` | 100 | Stock, purchases, barcodes, reports |

Largest communities (navigation hubs from the report): `stock_list.py`, `purchase_item_entry_sheet.dart`, `TradePurchase`, `home_dashboard_provider.dart`, `routers/auth.py`, `trade_purchase_service.py`, `reports_trade.py`, `purchase_entry_wizard.dart`, `shell_screen.dart`.

## Cross-stack coupling points (where frontend and backend must change together)

| Contract | Backend | Frontend |
|---|---|---|
| Trade purchase payload & totals | `schemas/trade_purchases.py`, `line_totals_service.py`, `trade_query.py` | `core/models/trade_purchase_models.dart`, `core/calc_engine.dart`, `core/reporting/trade_report_aggregate.dart` |
| Stock write + version conflict | `stock_movement_service.py`, `routers/stock/stock_detail.py` | `core/stock/stock_version_retry.dart`, `core/api/hexa_api_stock.dart` |
| Permissions | `services/permissions.py` | `core/auth/session_notifier.dart` |
| Unit normalisation | `services/unit_normalization.py`, `trade_unit_type.py` | `core/unit_engine`, `core/units`, `smart_unit_classifier.dart` |

Parity is guarded by Flutter "SSOT" tests (money/report/classifier) and backend `test_trade_query_vs_line_totals_parity.py`.

## Infrastructure dependencies

| Component | Depends on |
|---|---|
| Vercel build | `scripts/vercel-flutter-build.sh`, Flutter 3.41.6, `API_BASE_URL` env |
| Backend runtime | `DATABASE_URL`, JWT secrets, optional LLM keys, `AUTO_MIGRATE` |
| CI | `.github/workflows/ci.yml` (flutter analyze/test, SSOT smoke, web build, dead-host guard, backend pytest) |
| Backups | `.github/workflows/db-backup.yml` (weekly `pg_dump` artifact) |

## Impact-check procedure before a change

1. `get_pr_impact` (MCP) or `graphify explain "<symbol>"` for every touched hub.
2. List dependent files in the PR description.
3. Run the matching test group (see DEVELOPMENT_GUIDE §4).
