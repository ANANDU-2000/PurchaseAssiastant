# Pre-production QA checklist — Harisree / HEXA Purchase Assistant

Use this for manual testing before production. Record **Pass / Fail / N/A** and notes.

**Automated (run in CI / locally):**

- `backend/`: `python -m pytest tests -q`
- `flutter_app/`: `dart analyze lib` · `flutter test`

---

## 1. Environment & API (blockers)

| # | Check | Expected |
|---|--------|----------|
| 1.1 | `DATABASE_URL` uses `postgresql+asyncpg` (Supabase) | API starts; no SQLite in prod |
| 1.2 | `APP_ENV=production` only on prod hosts | `DEV_RETURN_OTP=false`, strong JWT, no `DATABASE_SSL_INSECURE` |
| 1.3 | `AI_PROVIDER` not `stub` if you sell AI | `openai` / `groq` / `gemini` + valid keys |
| 1.4 | WhatsApp outbound | `AUTHKEY_*` or `DIALOG360_*` configured; test send |
| 1.5 | `CORS_ORIGINS` includes prod app origin(s) | No browser CORS errors |
| 1.6 | `GET /health` (or `/docs`) | 200 |

---

## 2. Auth & session

| # | Check | Expected |
|---|--------|----------|
| 2.1 | Cold open app → splash → login or home | Correct redirect |
| 2.2 | Email/password login | JWT; `GET /v1/me/businesses` works |
| 2.3 | Google Sign-In (if enabled) | `GOOGLE_OAUTH_CLIENT_IDS` set; login completes |
| 2.4 | Logout (Settings) | Session cleared; login screen |
| 2.5 | Token refresh / resume app | Still signed in or clear error + retry |

---

## 3. Shell navigation (bottom bar)

Branches: **Home** · **Entries** · **FAB** · **Contacts** · **Reports**

| # | Check | Expected |
|---|--------|----------|
| 3.1 | Each tab switches branch | Correct page; no duplicate API storm |
| 3.2 | FAB → New purchase sheet | Sheet opens; haptic (mobile) |
| 3.3 | Offline banner | Shows when offline; cached home if implemented |

---

## 4. Home

| # | Check | Expected |
|---|--------|----------|
| 4.1 | Dashboard KPIs load | Numbers or friendly error + Retry |
| 4.2 | Period selector | Range updates |
| 4.3 | Pull to refresh | Data reloads |
| 4.4 | 7-day chart (if data) | No web console hit-test flood (`fl_chart`) |
| 4.5 | Notifications bell | Opens `/notifications` |
| 4.6 | Settings icon | Opens `/settings` |

---

## 5. Entries

| # | Check | Expected |
|---|--------|----------|
| 5.1 | List loads | Rows or empty state |
| 5.2 | Open entry detail | `/entry/:id` loads |
| 5.3 | New entry flow | Preview → confirm → success / offline queue message |
| 5.4 | Validation errors | Clear messages; no raw stack traces |

---

## 6. Contacts

| # | Check | Expected |
|---|--------|----------|
| 6.1 | Suppliers / brokers lists | Load or error + Retry |
| 6.2 | Supplier detail | `/supplier/:id` |
| 6.3 | Broker detail | `/broker/:id` |
| 6.4 | Category items | `/contacts/category?name=...` |

---

## 7. Reports (Analytics)

| # | Check | Expected |
|---|--------|----------|
| 7.1 | Tabs: Overview, Items, Categories, Suppliers, Brokers | Each loads or errors gracefully |
| 7.2 | Date range + presets | Data matches range |
| 7.3 | Search / filters (where present) | Filters rows |
| 7.4 | Item analytics deep link | `/item-analytics/:itemKey` |

---

## 8. Catalog

| # | Check | Expected |
|---|--------|----------|
| 8.1 | `/catalog` | List/categories |
| 8.2 | Item detail | `/catalog/item/:itemId` |
| 8.3 | Category detail | `/catalog/category/:categoryId` |

---

## 9. Settings

| # | Check | Expected |
|---|--------|----------|
| 9.1 | Theme / prefs | Persist |
| 9.2 | Branding (owner) | Save; logo rules |
| 9.3 | Billing (if used) | Razorpay test mode only in staging |

---

## 10. Hidden / guard behaviour

| # | Check | Expected |
|---|--------|----------|
| 10.1 | `/ai` | Redirects to `/home` (in-app AI hidden) |
| 10.2 | Deep link unknown route | Friendly “Could not open” |

---

## 11. Web (PWA) vs mobile

| # | Check | Expected |
|---|--------|----------|
| 11.1 | Chrome: resize / scroll | No layout assertion spam |
| 11.2 | iOS Safari / installed PWA | Navigation + FAB usable |
| 11.3 | Keyboard open (forms) | Fields not obscured |

---

## 12. Production safety (final gate)

- [ ] No secrets in repo; `.env` only on server
- [ ] All keys from chat / tickets **rotated** if ever exposed
- [ ] Supabase: backups / RLS reviewed for your threat model
- [ ] Rate limits & WhatsApp provider rules verified
- [ ] Error monitoring (e.g. Sentry) if available

---

---

## Appendix — Browser E2E notes (Flutter web)

- **OneDrive / sync:** If `flutter run` fails on `build\flutter_assets`, copy the project under `%LOCALAPPDATA%\Temp` or run from a non-synced folder.
- **Semantics:** For automation, tap **“Enable accessibility”** on the Flutter web canvas so more controls appear in the accessibility tree.
- **Agent smoke (example):** With web-server on `http://127.0.0.1:8080`, the **login** shell loads; navigating to **`/#/ai`** while signed out ends at **`/#/login`** (guarded route + auth redirect). Full signed-in tab testing requires a running API and valid credentials.

---

*Generated for internal QA. Update routes if `app_router.dart` changes.*
