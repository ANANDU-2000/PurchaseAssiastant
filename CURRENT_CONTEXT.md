# Current context

Last updated: 2026-05-20

## Focus

Harisree doc hub at `docs/harisree/` wired into Cursor rules. Owner visibility shipped. Next: resume Render + manual QA.

## Doc hub

- [docs/harisree/MASTER_REFERENCE.md](docs/harisree/MASTER_REFERENCE.md) — read first every session
- [docs/harisree/README.md](docs/harisree/README.md) — index

## Key code paths

- `flutter_app/lib/features/stock/presentation/widgets/stock_today_feed.dart`
- `flutter_app/lib/features/stock/presentation/stock_page.dart`
- `flutter_app/lib/features/home/presentation/home_page.dart`
- `backend/app/routers/stock.py`, `backend/app/services/stock_variance_notifications.py`

## Next

1. Resume Render → `curl https://my-purchases-api.onrender.com/health`
2. Manual smoke: home movement → `/stock/today-feed`; purchase save → stock card
