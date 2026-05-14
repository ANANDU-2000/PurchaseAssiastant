# Reports loading and recovery

## Problem

Operators perceived “infinite loading” when switching periods or when live refresh lagged Hive cache.

## Root cause

`reports_page.dart` showed a skeleton while `reportsPurchasesPayloadProvider` was loading **and** merged purchases were empty, with a separate stall banner timer.

## Fix

- Stall hint timer tightened from 2s to **1.5s** so the friendly empty / retry card appears sooner when live fetch is slow but cache is empty (`_armStallBanner`).
- Existing paths retained: `_bumpInvalidate()` for targeted refresh, merged Hive + live payload via `reportsPurchasesMergedProvider`, inline retry buttons on empty/error cards.

## Verification

- Open Reports, flip between Week/Month rapidly: UI should debounce (`_scheduleReportsReloadForRange`) and avoid blank infinite spinner; cached rows should render when available.
- Toggle airplane mode: expect copy referencing live refresh issues plus **Retry** / **Match Home period** actions.
