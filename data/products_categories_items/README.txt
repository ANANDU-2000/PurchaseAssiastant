Products list (optional Excel bootstrap)
-----------------------------------------

When you add `Products list.xlsx` in this folder, you can implement or extend
`backend/scripts/seed_products_from_xlsx.py` to create ItemCategory, CategoryType,
and CatalogItem rows in line with your spreadsheet columns. The repo’s primary
idempotent path today is `python -m scripts.seed_catalog_and_suppliers` (JSON
under `data/files/` or `backend/scripts/data/`).

Planned column mapping (adjust to your file when it lands in-repo):
- Category / subcategory or type
- Product name, unit, HSN, default supplier (name or id)

Until the file exists, this directory is a documented placeholder.
