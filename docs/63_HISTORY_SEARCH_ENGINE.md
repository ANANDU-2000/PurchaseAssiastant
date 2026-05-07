# History search engine

## Haystack (`_purchaseSearchHaystack`)

Concatenates (space-separated):

- `id`, `humanId`, `invoiceNumber`, formatted `purchaseDate`
- `supplierName`, `brokerName`
- Each line: `itemName`, **compact** `itemName` (spaces/underscores/dashes removed, lowercased for `SUGAR50KG`-style queries)
- `itemCode` when present
- `itemsSummary`

## Matching

- **`catalogFuzzyRank`** — typo-tolerant scoring; `minScore` scales with query length (short queries stricter).
- Malayalam / Manglish / aliases benefit from fuzzy + normalized tokens in the haystack; extend haystack with catalog aliases when those APIs are wired.

## Normalization

- Whitespace collapsed in fuzzy layer (`normalizeCatalogSearch`).
- Item naming variants: extra compact token in haystack (see above).
