# AI Purchase Scanner V2 — Error Handling

Every error class has: a server-side cause, an HTTP status, a stable error code, a user-friendly message, and a recovery action. The Flutter client maps codes to UI states deterministically.

---

## 1. Error envelope

All non-2xx responses use this envelope (already standard in the backend's exception handlers):

```json
{
  "detail": "Human friendly message",
  "code":   "STABLE_CODE",
  "params": { "…": "…" }
}
```

The client switches on `code`, falls back to `detail` if missing.

---

## 2. Catalog of errors

| HTTP | code | cause | user message | recovery |
| --- | --- | --- | --- | --- |
| 400 | `EMPTY_IMAGE` | uploaded body 0 bytes | "Empty image — please retake the photo." | re-pick |
| 400 | `IMAGE_TOO_LARGE` | > 8 MB | "Image too large. Crop or compress and try again." | re-pick (auto-compress on retry) |
| 400 | `UNSUPPORTED_FORMAT` | not jpeg/png/webp | "Unsupported file. Use a JPG or PNG." | re-pick |
| 400 | `BLURRY_IMAGE` | OCR confidence < 0.2 AND extracted < 12 chars | "The photo is too blurry to read. Try better lighting." | retake |
| 401 | `UNAUTHORIZED` | missing/expired JWT | "Sign in again." | re-auth |
| 403 | `FORBIDDEN_BUSINESS` | user not a member of `business_id` | "You don't have access to this workspace." | switch workspace |
| 408 | `OCR_TIMEOUT` | Vision/multimodal request > 30 s | "Reading the image is taking too long. Try again." | retry button |
| 409 | `DUPLICATE_PURCHASE` | dup detector found suspect | "Possible duplicate. We found 1 similar purchase on 06 May." | modal (see UI flow §12) |
| 415 | `OCR_NO_TEXT` | OCR returned empty | "Couldn't find any text. Take a clearer photo." | retake |
| 422 | `VALIDATION_BLOCKED` | one or more `blocker` validations | "Fix N issues to continue." | UI highlights offending fields |
| 422 | `MATCH_UNRESOLVED` | supplier or any item still unresolved | "Pick a supplier / item to continue." | open picker |
| 429 | `WORKSPACE_QUOTA_EXCEEDED` | per-business daily scan cap | "You've hit today's scan limit. Try tomorrow or contact admin." | retry tomorrow |
| 429 | `RATE_LIMIT` | per-IP rate limiter | "Too many requests. Try again in a minute." | retry |
| 502 | `SCAN_PROVIDERS_DOWN` | all providers failed | "Couldn't read the image. Try a clearer photo or type manually." | type manually CTA |
| 502 | `LLM_PARSE_FAILED` | OCR ok but LLM failed every time | "We read the image but couldn't structure it. Type manually." | type manually CTA |
| 503 | `BACKEND_DEGRADED` | DB/disk degraded | "Service degraded. We'll come back shortly." | retry later |
| 504 | `LLM_TIMEOUT` | LLM > timeout | "Server is slow. Try again." | retry |

`MISSING_API_KEY` is **not** a user error: when no provider is configured at all, the endpoint returns 503 `BACKEND_DEGRADED`. Health endpoint surfaces missing keys for ops; the user only sees a generic message.

---

## 3. Server-side handlers

`backend/app/services/scanner_v2/pipeline.py`:

```python
class ScanError(RuntimeError):
    def __init__(self, status: int, code: str, detail: str, params=None):
        super().__init__(detail)
        self.status = status; self.code = code; self.detail = detail; self.params = params or {}

@router.post("/scan-purchase-v2", …)
async def scan_purchase_v2(…):
    try:
        return await pipeline.run(image, ctx)
    except ScanError as e:
        raise HTTPException(e.status, detail={"detail": e.detail, "code": e.code, "params": e.params})
```

The pipeline raises `ScanError` at every clearly attributable failure. Unknown errors are logged with `logger.exception` and re-raised as `BACKEND_DEGRADED` 503.

---

## 4. Client-side mapping

`flutter_app/lib/features/purchase/state/scan_v2_provider.dart` translates server codes to UI states:

```dart
enum ScanErrorKind {
  emptyImage, tooLarge, unsupportedFormat, blurry,
  unauthorized, forbidden, timeout, duplicate,
  ocrNoText, validationBlocked, matchUnresolved,
  quota, rateLimit, providersDown, parseFailed,
  backendDegraded, llmTimeout, unknown
}

ScanErrorKind kindOf(String code) => switch (code) {
  'EMPTY_IMAGE' => ScanErrorKind.emptyImage,
  'IMAGE_TOO_LARGE' => ScanErrorKind.tooLarge,
  'UNSUPPORTED_FORMAT' => ScanErrorKind.unsupportedFormat,
  'BLURRY_IMAGE' => ScanErrorKind.blurry,
  'UNAUTHORIZED' => ScanErrorKind.unauthorized,
  'FORBIDDEN_BUSINESS' => ScanErrorKind.forbidden,
  'OCR_TIMEOUT' || 'LLM_TIMEOUT' => ScanErrorKind.timeout,
  'DUPLICATE_PURCHASE' => ScanErrorKind.duplicate,
  'OCR_NO_TEXT' => ScanErrorKind.ocrNoText,
  'VALIDATION_BLOCKED' => ScanErrorKind.validationBlocked,
  'MATCH_UNRESOLVED' => ScanErrorKind.matchUnresolved,
  'WORKSPACE_QUOTA_EXCEEDED' => ScanErrorKind.quota,
  'RATE_LIMIT' => ScanErrorKind.rateLimit,
  'SCAN_PROVIDERS_DOWN' => ScanErrorKind.providersDown,
  'LLM_PARSE_FAILED' => ScanErrorKind.parseFailed,
  'BACKEND_DEGRADED' => ScanErrorKind.backendDegraded,
  _ => ScanErrorKind.unknown,
};
```

Each kind has a dedicated UI affordance per [AI_SCANNER_UI_FLOW.md](AI_SCANNER_UI_FLOW.md) §12.

---

## 5. Network resilience

- Dio's existing `DioAutoRetryInterceptor` retries idempotent GETs.
- Scan POST is **not idempotent** at the wire level (we don't want double charging the LLM), so we do **not** auto-retry on 5xx. The user retries manually.
- On `connection_error_before_first_byte` (Dio reports it), Dio may retry once because the LLM did not yet receive the image.

---

## 6. Offline / no-network

- Detected via `connectivity_plus`. The Scan button is disabled when offline; we show a banner: "Scan needs internet — connect and try again."
- An offline draft of the legacy wizard is still possible; offline scanning is not.

---

## 7. Logging & observability

- Every scan call writes `usage_logging` row with `(business_id, user_id, provider_used, failover, status_code, error_code, duration_ms)`.
- Sentry breadcrumb for failed scans includes `image_bytes_in`, `ocr_chars`, `provider_used`, `failover` (no PII, no raw text).
- `/health` exposes counts per provider for the last 1h to aid ops.

---

## 8. Test coverage

`backend/tests/scanner_v2/test_endpoint_v2_errors.py` covers each status/code path with a mocked provider (e.g. force timeout, empty OCR, all-providers-fail). Flutter widget tests assert the correct error UI for each kind.
