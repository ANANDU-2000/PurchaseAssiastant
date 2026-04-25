# Production audit (findings) — Harisree Purchases

**Date:** 2026-04-23  
**Scope:** Flutter app + FastAPI backend per production roadmap Part A.  
**Counts (approximate from static review):** ~18 findings — **0 CRITICAL (runtime not exercised here)** — see priorities below.

## Summary

| Priority | Count | Themes |
|----------|-------|--------|
| **HIGH** | 6 | Assistant grounded in legacy `Entry` for analytics-style queries; cloud cost flags did not match “3-day pre-due” product rule; iOS notification permission not explicitly requested. |
| **MEDIUM** | 8 | Donut center stack density; navigation `push` vs `go` on tab-adjacent routes (review per screen); report CSV column parity; supplier review placeholder copy. |
| **LOW** | 4 | Help text still references “Entries” in places; test coverage for snapshot/API contracts. |

**Highest-risk screens (by blast radius):** `home_page.dart` (dashboard + cloud card), `full_reports_page.dart`, `purchase_home_page.dart`, `app_assistant_chat.py`, `cloud_expense_service.py`, `app_router.dart` + `shell_screen.dart`.

---

## Findings (template: symptom → cause → area)

### Navigation & shell
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| NAV-1 | MED | Global | Rare double-stack on tab paths | Some screens use `context.push` for destinations that are also top-level `GoRoute`s | Prefer `go` / `goBranch` for tab targets; keep `push` for push stacks (detail, modal flows) | `app_router.dart`, grep `context.push` |
| NAV-2 | LOW | Assistant | Pushes to `/catalog`, `/contacts` from assistant | Intentional drill-in from non-shell context | OK; verify back returns to assistant | `assistant_chat_page.dart` |

### API & data
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| API-1 | **HIGH** | Assistant “best supplier” | Answers could ignore wholesale trade | `_grounded_query_reply` used `Entry` / `EntryLineItem` for comparisons | **Fixed in roadmap:** use `TradePurchase` / `TradePurchaseLine` + `trade_query` | `app_assistant_chat.py` |
| API-2 | **HIGH** | Cloud cost home card | Shown at any time before due | `compute_ui_flags` was due-date binary | **Fixed:** 3-day pre-due window + `show_home_card` | `cloud_expense_service.py`, `home_page.dart` |
| API-3 | MED | Cloud pay | No provider reference on payment | History row lacked external id | **Fixed:** migration + PATCH body | `cloud_expense.py` (router), `CloudPaymentHistory` model |

### Home & dashboard
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| HOM-1 | MED | Donut | Dense center / legend on small devices | Many lines in `Stack` (amount + units + chart qty) | Tighten copy; optional remove redundant qty line | `home_page.dart` |
| HOM-2 | LOW | Unit string | Order differed from spec | Ordering was kg-first | **Fixed:** `bag | box | tin | kg` in KPI string | `home_page.dart` |

### Reports
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| REP-1 | MED | Items table | Missing unit columns vs snapshot | API item rows were summary-only | **Fixed:** add rollups in items breakdown | `reports_trade.py`, `full_reports_page.dart` |
| REP-2 | LOW | exports | CSV columns not extended | Export uses hard-coded headers | Future: add columns to match UI | `full_reports_page.dart` |

### History & search
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| HIS-1 | MED | Search | UUID not findable in fuzzy search | Haystack missed raw `id` | **Fixed:** append `p.id` | `purchase_home_page.dart` |

### Forms & UX
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| FOR-1 | MED | Supplier review | “Not configured yet” / “Not set” | Placeholder copy | **Fixed:** friendlier copy | `supplier_create_wizard_page.dart` |
| FOR-2 | MED | iOS / long forms | Keyboard overlap on dropdowns | `DropdownButtonFormField` in scroll | **Partial:** `showModalSheet` for category; scroll helper for forms | `catalog_add_item_page.dart`, `form_field_scroll.dart` (new) |

### Notifications
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| NOT-1 | **HIGH** (iOS) | First run | No OS permission prompt on iOS | Android-only `requestNotificationsPermission` in `init` | **Fixed:** iOS `requestPermissions` + one-shot pref after session | `local_notifications_service.dart`, `app.dart` |
| NOT-2 | MED | Killed app | No true reminder | In-app + local only | Product: FCM + backend scheduler (out of scope for this pass) | Document in roadmap |

### Performance & polish
| ID | Priority | Page / flow | Symptom | Root cause (hypothesis) | Suggested fix | Files |
|----|----------|------------|---------|--------------------------|---------------|--------|
| PRF-1 | LOW | Tab switches | Perceived flash | Some providers re-fetch | Already `IndexedStack`; keep `skipLoadingOnReload` | `home_page.dart` |

---

## Part B — Manual QA (staging) checklist

**Use this for todo `p13-validate` (not automated in CI).**

1. **Auth:** login, refresh token, sign out, cold start with cached session.  
2. **Tabs:** each shell tab, FAB → new purchase, back, no duplicate shells.  
3. **Home:** period chips, donut tap-through, unit line matches reports date range, cloud card hidden **outside** 3-day window; visible inside window; UPI when configured.  
4. **Reports:** item/supplier/category tables, totals row styling, date presets vs home.  
5. **History:** search by `PUR-` id, supplier name, item; open detail, edit, delete, mark paid.  
6. **Assistant:** “best supplier for &lt;item&gt;” returns trade-grounded list; GROUNDED JSON block present for synthesis.  
7. **Cloud:** pay records optional `payment_id`; history shows new fields.  
8. **Notifications:** Android + iOS permission path once per install; in-app list still populates.  
9. **Offline banner:** airline mode shows offline strip.

---

*This document is the Part A deliverable. Implementation work is tracked in repo changes per roadmap phases; do not treat this file as a live ticket dump.*
