# Export and print layout guide

## Trade purchases statement (`buildTradeStatementSsotPdfBytes`)

- **Paper**: A4 (`PdfPageFormat.a4`), margins 26pt.
- **Header**: Business title, subtitle, date span.
- **Table**: Date, Supplier, Item, Qty, Unit, Kg, Rate, Amount.
- **Footer**: SSOT totals block (see `REPORT_PDF_SUMMARY_SYSTEM.md`) + period + generated timestamp.

## Other PDFs

- **Summary PDF** (`shareReportsSummaryPdf`) already supported optional `totalBags`, `totalBoxes`, `totalTins`, `totalKg` — keep using that path for analytics PDFs.
- **Purchase invoice / receipt** (`purchase_pdf.dart`) — unchanged in this pass; do not mix statement totals with invoice header freight/GST without explicit product spec.

## Print / share

- `Printing.layoutPdf` for preview (`layoutTradeStatementSsotPdf`).
- Ensure filenames for share flows stay ASCII-safe (`purchase_pdf.dart` patterns).

## Cross-links

- `REPORT_PDF_SUMMARY_SYSTEM.md`
- `FINAL_TRADER_UX_PRODUCTION_READINESS.md`
