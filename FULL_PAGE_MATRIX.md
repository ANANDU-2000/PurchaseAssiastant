# Full page matrix (Phase 6)

Primary routes from [`flutter_app/lib/core/router/app_router.dart`](flutter_app/lib/core/router/app_router.dart). Nested shell: `/home`, `/reports`, `/purchase`, `/assistant`.

## Auth / onboarding

| Path | Purpose |
|------|---------|
| `/` | Root |
| `/splash` | Splash |
| `/get-started` | Onboarding |
| `/login`, `/signup` | Auth |
| `/forgot-password`, `/reset-password` | Recovery |

## Core app (shell)

| Path | Purpose |
|------|---------|
| `/home` | Dashboard (+ `breakdown-more` child) |
| `/reports` | Reports hub |
| `/purchase` | Purchase history |
| `/assistant` | Assistant |

## Purchases

| Path | Purpose |
|------|---------|
| `/purchase/new` | New purchase wizard |
| `/purchase/scan` | Bill scan |
| `/purchase/scan-draft` | Scan draft flow |
| `/purchase/edit/:purchaseId` | Edit |
| `/purchase/detail/:purchaseId` | Detail |

## Catalog / items

| `/catalog` | Catalog home |
| `/catalog/new-category` | New category |
| `/catalog/category/:categoryId` | Category |
| `/catalog/category/:categoryId/type/:typeId` | Type |
| `/catalog/category/:categoryId/type/:typeId/add-item` | Add item |
| `/catalog/item/:itemId` | Item detail |
| `/catalog/item/:itemId/purchase-history` | Item purchase history |
| `/catalog/item/:itemId/ledger` | Item ledger |

## Contacts / trade parties

| `/contacts` | Contacts |
| `/contacts/category` | Category picker |
| `/contacts/supplier/new` | New supplier |
| `/supplier/:supplierId`, `/supplier/:supplierId/ledger` | Supplier |
| `/broker/:brokerId`, `/broker/:brokerId/ledger` | Broker |
| `/suppliers/quick-create`, `/brokers/quick-create` | Quick create |

## Other

| `/search` | Global search |
| `/settings`, `/settings/business`, `/settings/maintenance/history` | Settings |
| `/entries` | Entries |
| `/analytics` | Analytics |
| `/item-analytics/:itemKey` | Item analytics |
| `/ai` | AI |
| `/notifications` | Notifications |
| `/voice` | Voice |
| `/reports/item-detail` | Report item drill-down |

## UX audit checklist (per page)

- [ ] Back / deep-link behaves (GoRouter)
- [ ] Keyboard + safe area on sheets
- [ ] Loading / empty / error
- [ ] 375px width layout
