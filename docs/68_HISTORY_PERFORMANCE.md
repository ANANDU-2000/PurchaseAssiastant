# History performance

## Current limits

- **`kTradePurchasesHistoryFetchLimit`** / **`kTradePurchasesAlertFetchLimit`**: **4000** rows each, fetched via existing 50-row paging in `HexaApi.listTradePurchases`.

## UI

- `ListView.separated` for the visible list (after search/filter/sort).
- For **10k+** active rows, next steps: server cursor pagination + `ScrollablePositionedList` / Sliver child builder, and push search/filter to the API where possible.

## Client work per frame

- Fuzzy search caps ranked results (`catalogFuzzyRank` `limit: 400`).
- Sort is in-memory on the filtered list only.
