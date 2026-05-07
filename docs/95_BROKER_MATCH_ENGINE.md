# 95 — BROKER_MATCH_ENGINE

## Goal

Broker detection must be reliable and easy to correct.

## Backend matching

Same pipeline as supplier:

- `backend/app/services/scanner_v2/pipeline.py::_match_supplier_broker`

## Required behavior

- If broker is missing:
  - show “Broker missing” (not a generic scan failure)
  - suggest top broker candidates
  - allow quick create from scan screen

## Alias learning

When user corrects a broker name, persist as an alias so the next scan auto-matches.

