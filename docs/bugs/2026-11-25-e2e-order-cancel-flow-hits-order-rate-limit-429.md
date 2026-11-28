# Bug: e2e "should not cancel completed order" fails with HTTP 429 from the order service rate limiter

**Status:** OPEN — capture
**Priority:** P3 (proposed) — one e2e test fails on the order service's own rate limit; 85 of 86 run tests passed
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — The e2e suite fails on the order cancellation flow by tripping the order service's HTTP 429 rate limiter
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation")
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-28 (Fable + Neon blind review; then read m5 run JSONs)
**Prior art:** `make find-similar-docs` not run (vector store unavailable); grep for `RATE_LIMIT_EXCEEDED`/429 in `docs/bugs` and `docs/issues` found no e2e or order-service match
**Filed:** 2026-11-25
**Detected by:** Claude, reading the final result of e2e job `853b827f` (the approved request in v1.46.0 plan 1 E-P1-live)

## Observed

Hub m5, 2026-11-26T01:54Z, run `1795657602-1952` (commit `cf653419`, tier vcluster, project api+flows): 85 passed,
1 failed, total 102. `make e2e` exited 2 (Playwright job exit 1). Failure (from `~/.k3dm/e2e/1795657602-1952.json` on m5):

- `flows/order-management.spec.ts` "should not cancel completed order":
  `HTTP 429 http://order.shopping-cart-apps.svc:8080/api/orders/<id>: {"code":"RATE_LIMIT_EXCEEDED","message":"Too many requests. Please retry later."}`

## Investigation (Claude, 2026-11-28, read-only: source at `origin/main` of each repo)

1. **The limiter that fired is the Go order service's, not the Java one.** The 429 body `{"code":"RATE_LIMIT_EXCEEDED",
   "message":"Too many requests. Please retry later."}` matches `shopping-cart-order` `go/internal/httpx/middleware.go:113,126`
   (the Java `RateLimitFilter` writes `{"error":"Too many requests",...}`). It is a per-client-IP `golang.org/x/time/rate`
   limiter, `NewRateLimiter(cfg.RateLimitPerSecond, cfg.RateLimitBurst)` (`go/cmd/server/main.go:45`), defaults 20 req/s,
   burst 50 (`go/internal/config/config.go:63-64`). A reservation with any delay is rejected (`middleware.go:118-129`), so
   it behaves as `Allow()`. `RATE_LIMIT_PER_MINUTE` is read (`config.go:62`) but never used by the Go limiter.
2. **The e2e tier runs the production limit against a single client.** `scripts/etc/e2e/order.yaml` sets no
   `RATE_LIMIT_*` env, so the defaults apply. Every e2e request comes from the one Playwright job pod
   (`scripts/plugins/e2e.sh:804-805`, `ORDER_URL=http://order.<ns>.svc:8080`), so the whole suite shares one 20 req/s
   bucket. With `CI=true` (`e2e.sh:828-829`) Playwright runs 1 worker with 2 retries (`playwright.config.ts:10-11`), and
   in-cluster calls take milliseconds, so a burst of sequential order calls can exceed 20/s once the 50-token burst is
   spent. The failing test makes about 8 order calls back to back (create, 4 status updates, cancel, get), after other
   order tests and the `afterEach` cleanup. Expected to be load- and timing-dependent rather than a one-off; prior
   runs' `~/.k3dm/e2e/*.json` on m5 would confirm (not read: the operator is running `make dr-drill`).
3. **The test can pass for the wrong reason (plausible-wrong).** `flows/order-management.spec.ts:140-157` wraps
   `cancelOrder` in `try { ...; expect(true).toBe(false) } catch (error) { expect(error).toBeDefined() }`: any error,
   including a 429, counts as "cancel was refused". This run failed only because the follow-up `getOrder` also hit 429;
   a 429 on the cancel alone would have passed the test without testing the business rule. `should not cancel shipped
   order` (lines 120-138) has the same shape.

**Fix options:** (A) e2e-only limits in `scripts/etc/e2e/order.yaml` (`RATE_LIMIT_PER_SECOND`/`RATE_LIMIT_BURST` high
enough for one test client; production limits unchanged); (B) the e2e client honours `Retry-After` on 429 with a bounded
backoff (hides limiter regressions if used alone); (C) the two "should not cancel" tests assert the specific business
error (status and code), not any error; (D) separately, the Go service ignores `RATE_LIMIT_PER_MINUTE` (docs and
configmap say it applies). Claude's proposal: A + C now, D captured as its own P3.

## Open questions (investigation)

- Is this deterministic (the suite exceeds the order service's per-client limit at this point) or a flake? Check the
  previous runs' summaries in `~/.k3dm/e2e/` for the same test.
- Should the e2e tier raise the limit for the test client, or should the flow test back off on 429?
