# Production readiness score

**Score: 72 / 100** (subjective engineering snapshot for this repo state after the hardening program slice).

| Area | Weight | Score | Notes |
|------|--------|-------|-------|
| Calculation SSOT | 25 | 22 | Backend `compute_totals` + Flutter `computeTradeTotals` aligned for line/header freight; pytest + Dart parity tests |
| Scanner | 20 | 12 | V2/V3 pipeline + confidence fields; learning tables SQL + service stub; full alias learning not wired |
| Performance | 15 | 8 | `PERFORMANCE_AUDIT.md` baseline template only |
| UX / navigation | 15 | 12 | `FULL_PAGE_MATRIX.md`; spot fixes ongoing |
| Data integrity | 15 | 10 | Soft-delete audit doc; filters need systematic grep |
| QA / CI | 10 | 8 | Checklist + existing CI; expand integration tests later |
