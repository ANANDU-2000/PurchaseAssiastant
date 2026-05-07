# Purchase History QA checklist

## Data scenarios

- [ ] Sugar / rice **bags** — card shows **bags + kg**; month strip kg increases.
- [ ] **Boxes** — count only, **no kg** on card or month kg total.
- [ ] **Tins** — count only.
- [ ] **Mixed** bag + box + tin — summary shows all relevant segments joined with ` • `.
- [ ] **Overdue / due soon / paid / draft** — chips and filters match server state.

## UX

- [ ] No tall red payment banner; metric pills fit on one row (scroll if needed).
- [ ] Search + filter icon on **one** row; quick chips **All / Due / Paid / Draft** only.
- [ ] Filter sheet: sort, dates, package, supplier/broker, clear advanced.
- [ ] **Latest first** default; toggle oldest first in sheet.
- [ ] Truncation hint when `≥ kTradePurchasesHistoryFetchLimit` rows loaded.

## Realtime

- [ ] After create / edit / delete / mark paid / **PDF share**, list updates without manual refresh.

## Devices

- [ ] iPhone 14 / 16 Pro, small Android, tablet — no horizontal page scroll; chips row may scroll horizontally.

## Search

- [ ] Supplier, PUR id, item name, broker; typos (`sugr`); compact item name (`SUGAR50KG`).
