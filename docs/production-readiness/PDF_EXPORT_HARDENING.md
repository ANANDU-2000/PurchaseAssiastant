# PDF export hardening

## Goals

- PDF build, save, share, and print must **not** throw unhandled exceptions into `FlutterError.onError` / the global boundary.  
- Callers get a **boolean** outcome for user-visible SnackBar + Retry.  
- Exported artifact should include human-relevant header metadata and a sensible filename.

## Service layer

**File:** [`flutter_app/lib/core/services/purchase_pdf.dart`](../../flutter_app/lib/core/services/purchase_pdf.dart)

- **`buildPurchaseDoc`** — async document build via `buildProfessionalPurchaseInvoiceDoc` (layout module).  
- **`sharePurchasePdf` / `printPurchasePdf` / `downloadPurchasePdf` / `sharePurchaseFullInvoicePdf`** — each wrapped in `try/catch`; failures logged in debug via `_logPdfFailure`; return **`false`** on failure, **`true`** on success.  
- **`buildPurchaseSharePdfFileName`** — filename helper (includes structured segments; full-invoice variant supported).  
- **`_dateTimePdf`** — `DateFormat('dd MMM yyyy · hh:mm a')` used in visible header lines where applicable.

## Layout / content

**File:** [`flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart`](../../flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart)

- Professional invoice layout including purchase **date and time** on the header line (see in-file implementation).

## Call sites (must check `ok`)

- [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart)  
- [`purchase_detail_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart)  
- [`purchase_saved_sheet.dart`](../../flutter_app/lib/features/purchase/presentation/widgets/purchase_saved_sheet.dart)

Pattern: `final ok = await sharePurchasePdf(p, biz);` then `if (!mounted) return;` and SnackBar with optional **Retry** calling the same closure.

## Dio / HTTP

Client-side PDF path uses local `pdf` + `printing` after purchase data is already loaded. Server **500** during **fetch** of purchase data is handled at API/provider layer; PDF generation itself still must never leak raw exceptions to the global boundary.

## Verification

1. Turn on airplane mode **before** share: expect `false` and SnackBar, no app-wide error screen.  
2. Corrupt logo URL (if applicable): document should still build or fail gracefully with `false`.  
3. Open saved PDF: confirm supplier / PUR id / date-time / totals match SSOT screen.

## Related

- [CRITICAL_RUNTIME_FAILURES.md](CRITICAL_RUNTIME_FAILURES.md)  
- [FLUTTER_ERROR_BOUNDARY_FIX.md](FLUTTER_ERROR_BOUNDARY_FIX.md)
