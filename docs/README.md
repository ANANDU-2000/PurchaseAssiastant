# Docs index

This folder contains product, architecture, and QA docs for Purchase Assistant.

## Strict docs standard

All new “system rebuild” docs must follow the strict 20-section structure in:

- `docs/_STRICT_MD_TEMPLATE.md`

## Generating required strict docs

Run:

```bash
python scripts/generate_strict_docs.py
```

This creates missing docs for:

- Terms rebuild (`110–118`)
- WhatsApp rebuild (`120–130`)
- System rebuild (`201–220`)

