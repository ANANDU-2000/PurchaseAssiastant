# AGENTS.md

## Architecture notes

- **Stack:** Flutter (`flutter_app/`, Riverpod) + FastAPI (`backend/`) + Postgres.
- **Purchases:** `trade_purchases` + `trade_purchase_lines` (not legacy `entries` for main flow).
- **Money:** Backend is authoritative; UI formats with `en_IN` / ₹.
- **Design tokens:** Root `DESIGN.md` + `HexaColors` / `HexaDsColors` / `HexaDsType`.
- **Production web host:** `https://purchase-assiastant.vercel.app` (spelling **assiastant**). Typo host blanks / wrong app.
- **Sheets:** Always `showHexaBottomSheet` — never ad-hoc `showModalBottomSheet` for app chrome.
- Living board: `TASKS.md`. Specs: `specs/`. Skills: `.cursor/skills/`.

## Lessons learned (each one is a real bug — do not remove, only add)

### Verify agent edits actually persisted
**Rule:** After any agent run, run `git diff` / `git diff --stat` before trusting the agent's summary. Do not commit from the changelog alone.
**Why:** Agents on this project have reported complete work when edits never wrote to disk.
**Check:** Expected files appear in `git diff --stat`; open changed lines and confirm they match the ask.

### Desktop sheet zero-height blank
**Rule:** On desktop, `showHexaBottomSheet(compact: true)` must shrink-wrap content; `compact: false` must use a fixed dialog height. Callers with `Column` + `Expanded` must supply an explicit `SizedBox(height: …)` or use the non-compact host path. Never put a second `HexaResponsiveSheetViewport` inside a sheet already hosted by `showHexaBottomSheet`.
**Why:** Non-shrink-wrapping scroll under Dialog + max-height-only collapsed to blank white panels after Stock → Update on Flutter web.
**Check:** `sheet_compact_height_test.dart` passes; sheet dialog height > 80 at 1440px; no nested `HexaResponsiveSheetViewport` under `showHexaBottomSheet`.

### Do not remove HTML splash on empty first Flutter frame
**Rule:** Call `removeBootOverlayIfPresent` only after bootstrap spinner, error UI, or `HexaApp` is in the widget tree — never from `initState` alone before `_prepare` paints (UID-001).
**Why:** Early double-RAF removal left gray `#F5F7FA` body while CanvasKit/session were still starting on hard `/stock` reload.
**Check:** `main.dart` `_scheduleBootOverlayRelease` from bootstrap/error/app mount paths only.

### Align + maxWidth-only blanks ListView
**Rule:** Desktop master-detail panes must bind **width and height** (`LayoutBuilder` + `SizedBox(height: constraints.maxHeight)`). Never `Align` + `ConstrainedBox(maxWidth: …)` alone around a scrollable.
**Why:** Align-only width constraints left height unbounded → blank CanvasKit surface on stock/purchase detail panes.
**Check:** Stock and purchase desktop detail panes use height-bound `SizedBox` inside `Expanded`.

### Wrong production web host
**Rule:** Bookmark and deploy only `purchase-assiastant.vercel.app`. Detect/wrong-host messaging for lookalike hosts.
**Why:** `purchase-assistant.vercel.app` is a different project / 404 HTML for `main.dart.js` — looks like a blank Flutter app.
**Check:** Canonical host loads Flutter; wrong host shows guidance, not a silent blank canvas.

### Never leak API errors to users
**Rule:** User-visible errors go through `FriendlyLoadError` / `HexaErrorCard` / `userFacingError`. Never show `DioException`, HTTP codes, or stacks outside `kDebugMode`.
**Why:** Raw Dio messages confused warehouse staff and broke trust.
**Check:** Grep touched UI for `DioException` / `toString()` of errors in SnackBars.

### Trade purchases vs Entry analytics
**Rule:** Spend KPIs and report tables that claim trade spend must use trade-backed endpoints (`trade-items`, `trade-suppliers`, etc.), not Entry-only queries.
**Why:** Mixed sources made Home/Reports totals disagree with purchase history.
**Check:** Reports/Home spend paths call `/v1/businesses/{id}/reports/trade-*` (or trade providers), not Entry-only aggregates.

### Do not call primaryBusiness list `.first` without empty guard when blanking shell
**Rule:** After login/session refresh, never assume `businesses.first` exists without a friendly empty/error state — a throw blanks the whole shell on web.
**Why:** Documented risk in session/bootstrap paths; empty membership looks like a dead app.
**Check:** Session bootstrap paths show a recoverable UI when the business list is empty.

### Reports filters must use showHexaBottomSheet on phone
**Rule:** Mobile Reports filters open via `showHexaBottomSheet(compact: false)` + explicit `SizedBox(height:)`. Do not reintroduce `showModalBottomSheet` + `DraggableScrollableSheet` for app filter chrome.
**Why:** Ad-hoc drag sheets bypassed the blank-sheet host contract and diverged from Stock/Purchase filter patterns.
**Check:** Grep `showModalBottomSheet` under `features/` — only `hexa_responsive.dart` mobile fallback should remain (or none for filters).

### Nested HexaResponsiveSheetViewport under showHexaBottomSheet
**Rule:** Never wrap sheet *body* content in `HexaResponsiveSheetViewport` when the caller already used `showHexaBottomSheet` — the host owns mobile scroll/padding and desktop shrink-wrap/fixed height.
**Why:** Double viewport + Align/scroll produced blank or collapse on Flutter web (low-stock approval, opening-stock bulk).
**Check:** Grep sheet bodies for nested `HexaResponsiveSheetViewport`; prefer `Column(mainAxisSize: min)` or explicit `SizedBox(height:)`.

### Purchase history empty off History branch is intentional
**Rule:** Do not “fix” `tradePurchasesListProvider` returning empty rows when `shellCurrentBranchProvider` is not History (unless fullscreen search is active). KPIs/stats are separate providers — empty list ≠ empty KPI.
**Why:** IndexedStack keeps other tabs alive; refetching history off-tab was wasteful and briefly looked like a blank history bug.
**Check:** History tab + fullscreen search load pages; other branches may keep/cache empty view without treating KPIs as broken.

### Reports shell must stretch + bind height
**Rule:** Reports desktop `Row` uses `CrossAxisAlignment.stretch` and body `LayoutBuilder` + `SizedBox(height:)` around content.
**Why:** `start` alignment + unbounded height left the main pane at 0 height (blank Reports on web).
**Check:** `reports_shell_page.dart` keeps stretch + LayoutBuilder height bind (≥1024).
