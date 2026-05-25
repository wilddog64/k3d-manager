# Issue: product-catalog schema-mismatch task blocked by pre-existing mypy errors in unrelated modules

**Date:** 2026-05-25
**Repo:** `shopping-cart-product-catalog`
**Task:** `fix(product-catalog-schema-mismatch)`

## What Was Tested

Ran the required validation suite after implementing the schema-mismatch guard in `src/product_catalog/database.py` and adding `tests/unit/test_database.py`:

```bash
/private/tmp/product-catalog-venv/bin/python -m pytest tests/unit/test_database.py -v
/private/tmp/product-catalog-venv/bin/ruff check src/ tests/
/private/tmp/product-catalog-venv/bin/mypy src/
```

## Actual Output

`pytest` and `ruff` passed. `mypy src/` failed with pre-existing errors in unrelated modules:

```text
src/product_catalog/events.py:95: error: Unexpected keyword argument "product_id" for "InventoryUpdatedData"; did you mean "productId"?  [call-arg]
src/product_catalog/events.py:95: error: Unexpected keyword argument "previous_quantity" for "InventoryUpdatedData"; did you mean "previousQuantity"?  [call-arg]
src/product_catalog/events.py:95: error: Unexpected keyword argument "new_quantity" for "InventoryUpdatedData"; did you mean "newQuantity"?  [call-arg]
src/product_catalog/events.py:103: error: Unexpected keyword argument "correlation_id" for "EventEnvelope"; did you mean "correlationId"?  [call-arg]
src/product_catalog/events.py:129: error: Unexpected keyword argument "product_id" for "InventoryLowData"; did you mean "productId"?  [call-arg]
src/product_catalog/events.py:129: error: Unexpected keyword argument "current_quantity" for "InventoryLowData"; did you mean "currentQuantity"?  [call-arg]
src/product_catalog/events.py:129: error: Unexpected keyword argument "product_name" for "InventoryLowData"; did you mean "productName"?  [call-arg]
src/product_catalog/events.py:136: error: Unexpected keyword argument "correlation_id" for "EventEnvelope"; did you mean "correlationId"?  [call-arg]
src/product_catalog/events.py:161: error: Unexpected keyword argument "reservation_id" for "InventoryReservedData"; did you mean "reservationId"?  [call-arg]
src/product_catalog/events.py:161: error: Unexpected keyword argument "product_id" for "InventoryReservedData"; did you mean "productId"?  [call-arg]
src/product_catalog/events.py:161: error: Unexpected keyword argument "order_id" for "InventoryReservedData"; did you mean "orderId"?  [call-arg]
src/product_catalog/events.py:161: error: Unexpected keyword argument "expires_at" for "InventoryReservedData"; did you mean "expiresAt"?  [call-arg]
src/product_catalog/events.py:168: error: Unexpected keyword argument "correlation_id" for "EventEnvelope"; did you mean "correlationId"?  [call-arg]
src/product_catalog/routers/products.py:130: error: Incompatible types in assignment (expression has type "bool", variable has type "Column[bool]")  [assignment]
src/product_catalog/routers/products.py:158: error: Incompatible types in assignment (expression has type "int", variable has type "Column[Decimal]")  [assignment]
src/product_catalog/routers/products.py:173: error: Argument "sku" to "publish_inventory_updated" of "ProductEventPublisher" has incompatible type "Column[str]"; expected "str"  [arg-type]
src/product_catalog/auth.py:85: note: By default the bodies of untyped functions are not checked, consider using --check-untyped-defs  [annotation-unchecked]
src/product_catalog/auth.py:226: error: Missing named argument "email" for "CurrentUser"  [call-arg]
src/product_catalog/auth.py:226: error: Missing named argument "name" for "CurrentUser"  [call-arg]
Found 18 errors in 3 files (checked 13 source files)
```

## Root Cause

These `mypy` failures are in pre-existing modules (`events.py`, `routers/products.py`, `auth.py`) and are unrelated to the schema-mismatch guard added in `src/product_catalog/database.py`.

## Recommended Follow-up

Separate type-cleanup work is needed for the existing `mypy` violations before `mypy src/` can pass cleanly.
