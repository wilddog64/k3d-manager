# M2 E2E acceptance: current image/API contract mismatch

## What was attempted

On 2026-08-25, after M2 bootstrap and preflight passed, the required passing
run was retried with:

```text
E2E_M2_SSH_HOST=m2-air.local E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local \
E2E_M2_PUBLISH_BACK_KEY=$HOME/.ssh/e2e-m4-publisher \
make e2e-remote RUNNER=m2
```

The stale vCluster left by the previous attempt was removed by its exact name
before retrying. The E2E image cold-pulled successfully on M2 (about 890 MB),
and the Playwright job started.

## Actual result

The run published this result to the M4 hub:

```text
INFO: [e2e] Summary written to /Users/cliang/.k3dm/e2e/1787708603-5833.json (exit_code=1)
INFO: [e2e-publish] applied result for run 1787708603-5833 (runner=m2, result=fail)
INFO: [e2e-remote] result 1787708603-5833.json published to M4 hub
INFO: [e2e-remote] dispatch exit 1; transcript: /Users/cliang/.k3dm/e2e/dispatch/m2-20260826T014322Z.log
make: *** [e2e-remote] Error 1
```

The retained summary was:

```json
{
  "candidate_digest": null,
  "commit": "f5a40988d11f00e579d5bad521b13aa8d189ce40",
  "duration_seconds": 67.869,
  "exit_code": 1,
  "failed": 45,
  "passed": 12,
  "phase": "recording-result",
  "project": "api+flows",
  "result": "fail",
  "run_id": "1787708603-5833",
  "runner": "m2",
  "service": "product-catalog",
  "tier": "vcluster",
  "total": 102
}
```

Representative failures show the deployed APIs return the standard `{data: …,
success: true}` envelope while the current E2E client/tests assert fields at the
top level:

```text
Expected path: "id"
Received value: {"data": {"createdAt": "2026-08-26T01:50:53.210812208Z", "currency": "USD", "customerId": "e2e-1787709053208-blvpa", "expiresAt": "2026-09-02T01:50:53.210812208Z", "id": "352e4947-0cd0-4143-9dfc-a12a3c749a74", "itemCount": 0, "items": [], "totalAmount": 0, "updatedAt": "2026-08-26T01:50:53.210812208Z"}, "success": true}
    at /e2e/tests/api/cart.spec.ts:32:20
```

```text
Expected: "number"
Received: "string"
    at /e2e/tests/api/products.spec.ts:86:38
```

The log also contains repeated `Order cleanup skipped: orders is not iterable`
messages, consistent with the same envelope mismatch. This is not an M2
transport or publisher failure.

## Publication and cleanup checks

The latest M2 result is present once in `platform-ops`:

```text
{"run_id": "1787708603-5833", "tier": "vcluster", "runner": "m2", "service": "product-catalog", "project": "api+flows", "candidate_digest": "", "passed": "false", "total": "102", "failed": "45", "duration_seconds": "67.869", "timestamp": "2026-08-26T01:52:03.423304+00:00", "commit": "f5a40988d11f00e579d5bad521b13aa8d189ce40"}
```

The intentional invalid-digest run also published as a failed result. Both
required result paths therefore exercised publication, but the passing gate is
blocked by the test/image contract mismatch.

## Follow-up

Align the E2E image's API client/tests with the deployed response envelope and
numeric price contract, rebuild/publish `:latest`, then rerun the passing M2
acceptance. Do not treat this run as a passing acceptance result.

---

## Update 2026-08-29 — Tier-1 rerun with the aligned image: still FAILS (fix was incomplete)

Reran the gate on the hub via `E2E_IMAGE_TAG=sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00
./scripts/k3d-manager e2e_verify_vcluster` (the client-fix commit `0c2505bb` on
`feat/e2e-image-multiarch`; image confirmed in GHCR). Result (`~/.k3dm/e2e/1788032108-14707.json`):

```
total=102  passed=26  failed=31  skipped=45  exit_code=1  tier=vcluster  runner=local-m4
```

Failure spread by spec (✘ lines incl. retries): orders 42, payments 27, cross-service 21,
cart 3. Two findings — one CONFIRMED, one NOT yet root-caused:

1. **Payment-service absent from the Tier-1 substrate (CONFIRMED, structural — not a
   contract bug).** `scripts/etc/e2e/` deploys postgres/redis/product-catalog/basket/order
   but has **no payment manifest**, so payments.spec (27) and payment-dependent
   cross-service tests cannot pass in the vcluster Tier-1 gate. Full payment/Stripe-test
   coverage is the Tier-2/ACG substrate's job — the Tier-1 vcluster gate is NOT expected to
   green the payment specs. (Either add a payment manifest to the Tier-1 substrate, or scope
   Tier-1 acceptance to the non-payment specs and gate payment on Tier-2.)

2. **orders.spec failures — root cause NOT confirmed.** The recurring
   `Order cleanup skipped: orders is not iterable` (136×) is a teardown SYMPTOM, not a proven
   cause: the client's `getOrdersByCustomer` (`tests/helpers/api-client.ts`) DOES route
   through the `responseData<Order[]>` `{data}`-envelope unwrap, so the earlier "list envelope
   not unwrapped" hypothesis is unlikely. The primary per-test assertion errors were lost when
   the vcluster torn down (`~/.k3dm/e2e/1788032108-14707.log` came back empty; pod gone).
   **To root-cause: rerun capturing the Playwright reporter output to a file (or `kubectl logs`
   before teardown) and read the actual createOrder/list assertion, rather than the cleanup
   symptom.** Do not assume a list-unwrap fix without that evidence.

**So the gate is NOT green.** Next: (a) capture the real orders.spec errors and fix the
actual cause in `shopping-cart-e2e-tests` (+ rebuild image), and (b) decide payment coverage —
Tier-1 substrate gains a payment manifest, or payment/cross-service acceptance moves to
Tier-2 (ACG, payment deployed, Stripe test). Only then is M2 acceptance passable.

---

## Update 2026-08-29 (later) — orders.spec ROOT-CAUSED and FIXED; rerun 45/12/45

The orders.spec cause was **not** a client-contract bug. Captured the Playwright
`results.json` from the live pod before teardown and replayed the payload directly: the
deployed order image `sha-56033880` is the **Go** rewrite (commit `5603388`) with **no
runtime migration**, and the substrate created the `orders` database but never its
`orders`/`order_items` tables → HTTP 500 `relation "orders" does not exist` (42P01) on every
order DB op. Fixed in k3d-manager `aa2f2190` (`20-orders-schema.sql` in
`scripts/etc/e2e/postgres.yaml`, DDL matched to the deployed commit — order_items **without**
`total_price`). See `k3d-manager/docs/bugs/2026-08-29-e2e-order-schema-missing.md`.

Confirming rerun (`~/.k3dm/e2e/1788051374-25838.json`, commit `86298144`):

```
total=102  passed=45  failed=12  skipped=45  (was 26/31/45)
```

Cross-service fully greened (21 → 0); orders 42 → 2. **The residual 12 contain zero
substrate bugs**, in three classes:

1. **Payment absent (9)** — `payments.spec` all fail `connect ECONNREFUSED ::1:8084`; no
   payment service in Tier-1. Structural → Tier-2/ACG (Stripe test).
2. **Order status-update (2)** — `orders.spec:149/163` send status **`CONFIRMED`**, which is
   **not in the deployed service's `OrderStatus` enum** (PENDING/PAID/PROCESSING/SHIPPED/
   COMPLETED/CANCELLED), and assume free transitions the service forbids (PENDING → only
   PAID/CANCELLED). PATCH returns 400 → `updatedOrder.status` undefined. **E2E-test bug** in
   `shopping-cart-e2e-tests` — align to the real enum + `CanTransitionTo` rules (or the
   service must add CONFIRMED). Not a substrate issue.
3. **Cart remove-qty-0 (1)** — `cart.spec:98`: after setting qty 0, `cart.items` is undefined
   → `toHaveLength(0)` throws. Basket/e2e contract mismatch, pre-existing (cart failed
   pre-fix too). E2E-test/basket concern, not substrate.

**To reach a green Tier-1 gate**, the substrate fix is done; remaining is cross-repo/strategy:
fix the 3 test-contract bugs in `shopping-cart-e2e-tests` (+ rebuild image), and decide
payment (Tier-1 payment manifest vs. scope Tier-1 to non-payment and gate payment on Tier-2).
Optionally quarantine the 3 known test-contract bugs so Tier-1 greens on what it covers now.
