Seed JSON runtime copies for backend/scripts/seed_catalog_and_suppliers.py

Authoritative copies also live under repo root data/ for editing:
  data/categories_seed.json     — not used; categories are generated into backend/scripts/data/categories_seed.json
  data/suppliers_gst_seed.json
  data/products_by_category_seed.json

After editing root data/*.json, copy suppliers + products here again (or re-run copy in your deploy pipeline).
