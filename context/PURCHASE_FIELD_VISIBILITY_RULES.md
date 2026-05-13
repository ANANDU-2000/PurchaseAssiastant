# Purchase field visibility rules

## Primary (always)

| Field / control | Visible |
|-----------------|---------|
| Item search | Yes |
| Qty | Yes |
| Unit (or read-only unit chip) | Yes |
| Kg per bag | Only when bag family **and** kg required |
| ₹/kg vs ₹/bag rate toggle | Only when bag economics |
| Purchase rate | Yes |
| Selling rate | Yes (optional empty) |
| Tax OFF / ON | Yes |
| Preview card | Yes |
| Save / Save & add more | Yes |

## Advanced (collapsed)

| Field | Visible |
|-------|---------|
| Discount % | Yes |
| Tax % (override) | Yes when Tax ON; hidden when Tax OFF |
| Freight type/value | When line carries freight |
| Delivered / Billty | Same |
| Notes | Yes |
| HSN / item code meta | Footer meta when set |
| Legacy purchase/selling GST basis | Only for migration / power users |

## Tax OFF

- Hide tax % from primary; force saved `tax_percent = 0`.
- Preview shows “Tax —”.

## Tax ON

- Use catalog default into Tax % when empty (existing autofill).
- Preview shows “Tax ₹…” using `lineTaxAmount`.
