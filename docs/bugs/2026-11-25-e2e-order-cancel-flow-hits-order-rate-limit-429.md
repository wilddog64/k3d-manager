# Bug: e2e "should not cancel completed order" fails with HTTP 429 from the order service rate limiter

**Status:** OPEN — capture
**Priority:** P3 (proposed) — one e2e test fails on the order service's own rate limit; 85 of 86 run tests passed
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — The e2e suite fails on the order cancellation flow by tripping the order service's HTTP 429 rate limiter
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** investigation
**Prior art:** `make find-similar-docs` not run (vector store unavailable); grep for `RATE_LIMIT_EXCEEDED`/429 in `docs/bugs` and `docs/issues` found no e2e or order-service match
**Filed:** 2026-11-25
**Detected by:** Claude, reading the final result of e2e job `853b827f` (the approved request in v1.46.0 plan 1 E-P1-live)

## Observed

Hub m5, 2026-11-26T01:54Z, run `1795657602-1952` (commit `cf653419`, tier vcluster, project api+flows): 85 passed,
1 failed, total 102. `make e2e` exited 2 (Playwright job exit 1). Failure (from `~/.k3dm/e2e/1795657602-1952.json` on m5):

- `flows/order-management.spec.ts` "should not cancel completed order":
  `HTTP 429 http://order.shopping-cart-apps.svc:8080/api/orders/<id>: {"code":"RATE_LIMIT_EXCEEDED","message":"Too many requests. Please retry later."}`

## Open questions (investigation)

- Is this deterministic (the suite exceeds the order service's per-client limit at this point) or a flake? Check the
  previous runs' summaries in `~/.k3dm/e2e/` for the same test.
- Should the e2e tier raise the limit for the test client, or should the flow test back off on 429?
