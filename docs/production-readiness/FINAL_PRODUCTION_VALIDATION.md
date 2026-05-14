# Final production validation

Use this checklist before tagging a release candidate.

## Purchase history

- [ ] KPI strip matches visible cards for Month/Week presets (`purchaseHistoryMonthStatsProvider` vs list).
- [ ] Filters that hide all rows show **Filters hide all purchases** with clear action.
- [ ] Deep link `/purchase` after cold start: list populates (shell branch guard).

## Purchase detail

- [ ] Open detail from list with airplane mode OFF: seed (if any) flashes “Refreshing…” then full totals.
- [ ] Turn airplane ON, open detail without seed: skeleton ≤15s then inline retry.
- [ ] PDF print/share/download failure surfaces SnackBar + retry (existing hardened paths).

## Wizard / keyboard

- [ ] Party → Terms → Items: numeric keyboard never covers commission or Continue.
- [ ] Add item (full page): item → qty → rates scroll; totals visible.

## Reports

- [ ] Period thrash: no stuck spinner >1.5s without empty-state guidance.
- [ ] Retry + “Match Home period” recover after API errors.

## Shell / safe area

- [ ] Bottom nav clears home indicator; FAB not clipped.
- [ ] Offline banner copy matches degraded API banner tone.

## Automation

- [ ] `flutter analyze` (repo root `flutter_app/`).
- [ ] `pytest` if backend touched (not required for this Flutter-only pass).

## Sign-off

Tester device model + OS version: _______________________  
Date: _______________________
