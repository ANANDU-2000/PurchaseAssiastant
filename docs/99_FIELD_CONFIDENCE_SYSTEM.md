# 99 — FIELD_CONFIDENCE_SYSTEM

## Goal

Replace “0% confidence” style UX with trader-friendly confidence bands:

- **HIGH**
- **MEDIUM**
- **LOW**

## Rule

- Never show numeric confidence as the primary UI.
- Use numeric only internally for sorting/thresholding.

## Mapping

- \(c \ge 0.85\) → **HIGH**
- \(0.55 \le c < 0.85\) → **MEDIUM**
- \(c < 0.55\) → **LOW**

## Targets

- Supplier
- Broker
- Each detected item row (name, qty/unit, rates)
- Payment days

