# AI Confidence Engine

## Levels
- **High**: auto-select; minimal UI friction
- **Review**: show candidates; require user confirmation
- **Low**: highlight field; block create if critical fields unresolved

## Sources
- OCR clarity signals
- LLM parse certainty
- Fuzzy match score to directory/catalog
- Validation consistency (qty × rate ≈ total, unit rules)

## Output
- `confidence` per supplier/broker/item row
- `confidence_score` overall
- `warnings[]` with severity `info|warn|blocker`

