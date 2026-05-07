# 109 — AI_SCAN_PERFORMANCE

## Goal

Keep scanning fast and predictable for traders.

## Targets (recommended)

- Start endpoint: \< 500ms to return `scan_token`
- Time to first partial result: \< 2s (show OCR or fallback parse)
- Time to ready: p50 \< 8s, p95 \< 20s (depends on OCR engine)

## Techniques

- Async start + poll (scanner v3)
- Multipass OCR with early exit when score is strong
- Merge top candidates to avoid reruns
- Keep parse deterministic fallback available (zero extra latency)

## Monitoring

Track in logs/metrics:

- stage durations: preparing → ocr → parse → match → validate
- error codes distribution (OCR_EMPTY, PARSE_EMPTY, etc.)
- retry counts + timeouts

