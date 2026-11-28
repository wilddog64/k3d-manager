# Bug: e2e "should not cancel completed order" fails with HTTP 429 from the order service rate limiter

**Status:** OPEN — capture
**Priority:** P2 (Fable + Neon blind reviews 2026-11-28 and Argon agree; Claude's P3 proposal withdrawn; operator to confirm) — one e2e test fails on the order service's own rate limit; 85 of 86 run tests passed
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — The e2e suite fails on the order cancellation flow by tripping the order service's HTTP 429 rate limiter
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation")
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-28 (read m5 `~/.k3dm/e2e/*.json` after the dr-drill; then fix spec)
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

## Blind reviews (2026-11-28): Fable and Neon, both P2

Brief `docs/plans/review-e2e-order-429.md`. Both confirmed the root-cause claims against `origin/main` and the deployed
pin `sha-56033880` (limiter, config and main identical). Verdict P2: the e2e gate itself is degraded (exits 2 on a healthy
system; workaround is a rerun or hand-reading the JSON) and is unreliable in both directions. Findings to carry into the fix spec:

1. **Test defect is worse than stated (Fable, Neon BLOCKER):** `expect(true).toBe(false)` sits inside the `try`, so its own
   failure is caught: the try/catch passes even on a successful cancel (200). Affected: `flows/order-management.spec.ts`
   both "should not cancel" tests, **`api/orders.spec.ts:193-212` (no follow-up read: can never fail)**, and
   `api/cross-service.spec.ts:299-318` (any outcome passes). Fix: assert status 400 + `INVALID_STATE` outside any try/catch
   (typed `HttpError` from `api-client.ts` or direct `request.post`).
2. **Siblings share the defect (both):** `payment` 10/s burst 20 (has `RATE_LIMIT_ENABLED`), `product-catalog` 20/s burst
   50, `basket` `RATE_LIMIT_RPS=100` burst 50; no `scripts/etc/e2e/*.yaml` sets any of them. Fix A covers all four with
   each service's verified env names, or scopes to order and captures the rest.
3. **Proof the override took effect (both):** offline must_not red today (rendered e2e manifests lack positive limits above
   the defaults), guard against `0`/negative (order has no enable switch: `BURST=0` rejects every request; a bad integer
   silently falls back to 20/50), production configmap untouched (positive control), and live proof beyond a green run:
   read the running env + zero `RATE_LIMIT_EXCEEDED` in the whole run JSON including retries.
4. **Two repos, two schedules (both):** A in k3d-manager needs a hub promote; C in `shopping-cart-e2e-tests` reaches the hub
   through the floating `E2E_IMAGE_TAG=latest` (stale-image bug 2026-10-06), so C gets its own spec and a pinned live check.
5. **Mechanism unproven (both):** read `~/.k3dm/e2e/*.json` on m5 first: per-attempt errors (2 retries), flaky passes hidden
   in the 85, the 16 uncounted tests, and whether the cancel also hit 429. Neon: the order-management file alone makes ~36
   order calls, so exhaustion likely starts in `checkout-flow.spec.ts` before it.
6. **Side findings (P3 candidates):** Go order ignores `RATE_LIMIT_PER_MINUTE` (also product-catalog); `ttl: time.Hour`
   dead code in the order limiter; `afterEach` cleanup swallows 429s and leaves orders behind.

**Timing (both):** fix in v1.47.0 (carried P2; bugs do not count toward the cap), after reading the m5 run JSONs; Neon notes
the 2026-11-29 groom's shopping-cart retirement question could change how much to invest in C and the siblings.

## Open questions (investigation)

- Is this deterministic (the suite exceeds the order service's per-client limit at this point) or a flake? Check the
  previous runs' summaries in `~/.k3dm/e2e/` for the same test.
- Should the e2e tier raise the limit for the test client, or should the flow test back off on 429?
