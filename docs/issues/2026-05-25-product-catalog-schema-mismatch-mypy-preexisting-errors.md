# Issue: pre-existing mypy errors in product-catalog (not introduced by schema mismatch fix)

**Date:** 2026-05-25
**PR:** #31 — fix(db): recreate products table on schema mismatch

## Summary

`mypy src/` reports errors in three files that predate this PR. These errors existed before
the schema mismatch fix and are not introduced by it.

## Affected Files

- `src/product_catalog/events.py`
- `src/product_catalog/routers/products.py`
- `src/product_catalog/auth.py`

## Status

Pre-existing — tracked as follow-on type annotation cleanup work. Not blocking this PR.
