# progress (append-only, newest at bottom)

2026-11-08 — P0 deploy fix committed (Render API as canonical). Backend /health/ready: db ok, schema_ok false (068 vs expected 069). Repo head migration is 070 → Render is running an older commit.
BLOCKED (human): set AUTO_MIGRATE=1 on Render + deploy latest main; set Vercel API_BASE_URL=https://my-purchases-api.onrender.com; rotate OpenAI key, GitHub token, DB password, JWT secrets (were pasted in chat).
FINDING: create_trade_purchase returns stock_updates=[]; stock only moves on commit_trade_purchase_delivery → P1 root cause task.
2026-11-08 - P0 login verify: prod bundle ab63ee7 still showed Cannot reach api.harisreeagency.online (fix existed only as an unapplied patch). Applied and pushed 711f659 (build defaults to Render). Fixed Playwright login selectors. Also pushed 3 previously-local UX commits. Follow-up: rerun prod QA after Vercel deploy; Render still on alembic 068 (expected 069) - BLOCKED human: AUTO_MIGRATE=1 + redeploy.
2026-11-08 - Vercel build FAILED on analyze error: stale test settings_sidebar_discoverability_test.dart referenced removed settingsSidebarShortcuts. Removed test. Next: confirm Vercel deploy READY then rerun prod login QA.
2026-11-08 - Prod login bug (real): login_page.dart Sign In/Enter used onPressed captured at build time (_isFormValid ? _signIn : showValidation); typing does not rebuild so first tap/Enter did nothing. Now onPressed/onActionSubmit = _signIn (validates at press time). Playwright login uses mouse click + keyboard.type (fill() scrolls Flutter canvas). Files: login_page.dart, ralph/qa/smoke.spec.ts. Next: confirm prod QA green after Vercel deploy.
2026-11-08 - DONE: prod login verified on desktop/tablet/mobile (build 3e34426), zero console errors. Playwright now clicks via semantics-derived coordinates (semantics layer is offset by viewport height), filters WebKit noise. Remaining failing smoke: 'API healthy and schema at head' = known BLOCKED (Render alembic 068, expected 069; needs AUTO_MIGRATE=1 + redeploy). Next task: verify /health/ready.
2026-11-08 - /health/ready checked: db ok, alembic_version=068, schema_ok=false, expected head reported 069 but repo head is 070. BLOCKED (human): set AUTO_MIGRATE=1 on Render and redeploy latest main. Task marked [!].
NEW BUG: health.py EXPECTED_ALEMBIC_HEAD hardcoded (069) is stale vs 070; added as next task.
2026-11-08 - QA round: added screens test (login/dashboard/stock/purchase/reports/search/settings x 3 viewports), shots saved to ralph/qa/shots/. desktop+tablet pass (tablet flaky), mobile fails only on WebKit cancelled-XHR noise. Logged 1 P0 + 5 P3 tasks from visible UI issues (Home vs Stock count mismatch, unit line wrap, nested cards).
2026-11-08 - PHASE 0 BASELINE (prod, Chromium 393x852, ~1.6Mbps/150ms latency, 4x CPU; cold load per route, ralph/qa/perf.spec.ts, raw: ralph/qa/shots/perf-baseline.json)
  screen     fcp_ms  first_data_ms  api_calls  dup_calls  console_errors
  dashboard   252      4773           14         0          0
  stock       216      4547           11         0          0
  purchase    160      5011           11         0          0
  reports     168      5263           16         0          0
  search      204      5169           18         0          0
  Notes: FCP is the HTML shell, not Flutter's first painted UI; first_data_ms (~4.5-5.3s) is the real wait. 11-18 API calls per cold screen, none exact duplicates on cold load. Duplicate/refetch behaviour after a save is Phase 2 and is not measured yet.
