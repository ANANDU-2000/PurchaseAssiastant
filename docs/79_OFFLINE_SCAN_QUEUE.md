# 79 — OFFLINE_SCAN_QUEUE

## Goal
Never lose a scan when the network is weak/offline:
- preserve image locally
- retry automatically
- allow retry without reupload when possible

## Current status
- Backend v3 supports start/status polling (better UX under slow connections).
- Flutter offline queue persistence is **not yet implemented**.

## Planned Flutter approach
- Persist captured image bytes + metadata locally (Hive / file storage).
- Queue items with states: `queued → uploading → processing → ready`.
- On app restart, resume pending scans and poll status.

## Backend future-proofing
In-memory job cache in `backend/app/services/scanner_v3/pipeline.py` should be migrated to Redis for multi-worker deployments.

