# Scan Validation (v2)

## Server-side (authoritative)
- **Required**: supplier match state, at least one valid item row
- **Qty sanity**: qty > 0, bag kg from allowed list when applicable
- **Rates**: > 0, outlier warnings (not blockers unless extreme)
- **Units**: only `KG|BAG|BOX|TIN|PCS`; BOX/TIN count-only defaults
- **Duplicates**: run duplicate check before confirm create

## Client-side (UI guidance)
- Highlight low-confidence fields
- Prevent “Create” when blockers exist (server returns blockers)

