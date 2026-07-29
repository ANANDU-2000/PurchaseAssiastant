# Diagnostic Prompt — Slowness / Repeated Refresh

Produces evidence for UID-009 / UID-010 (`14_UID_009_010_SPEC.md`).

## Scope

Observe Network + code for:

| Scenario | What to look for |
|----------|------------------|
| 2 Rapid alt-tab / visibility | Overlapping `/health/*` or warehouse invalidation while a prior resume is still in flight |
| 3 Cold start / long wake | Wait >~2–3s with no user-visible “reconnecting / waking” feedback |
| 4 Rapid shell / route nav | Unrelated per-route refetch while cache should still be fresh — **name provider files** |
| 5 Multiple tabs | Duplicate backend hits across tabs; are throttles per-tab only? |
| Step 3 `reloadHexaApp` | Zero call sites → eligible for remove; any call site → keep |

## Outputs

Write findings into `docs/ai/15_diagnostic_report_slowness_refresh.md` with apply/skip for Tasks A–E.
