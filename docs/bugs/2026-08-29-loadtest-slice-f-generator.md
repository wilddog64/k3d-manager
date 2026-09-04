# Slice F — adaptive checkout load generator (k6 + metrics + live run)

**Filed:** 2026-08-29
**Area:** `scripts/plugins/loadtest.sh` (wire the Slice E stubs), new k6 generator, Grafana dashboard
**Type:** enhancement (implements `docs/plans/v1.27.0-adaptive-checkout-load-testing.md`, Slice F)
**Builds on:** Slice E controller `17be2e69` (pure decision logic + two explicit stubs)

## Grounded contract (verified live on hostinger 2026-08-29)

**Checkout entry:** `POST /api/orders` on `order-service` (ns `shopping-cart-apps`,
ClusterIP `:8081` → targetPort http; also `order-service-nodeport` NodePort `30081`).
Body (`CreateOrderRequest`, from `wilddog64/shopping-cart-order`
`OrderController.java` / `dto/CreateOrderRequest.java`):

```json
{
  "customerId": "<non-blank string>",
  "items": [
    {"productId": "<non-blank>", "productName": "<non-blank>",
     "quantity": <int>, "unitPrice": <positive decimal>}
  ],
  "shippingAddress": {"street","city","state","postalCode","country"},
  "currency": "USD"
}
```

Key simplification: the order records `productId/productName/unitPrice` **from the request
body** — so the generator can send **deterministic synthetic items** and does NOT need real
seeded product IDs. Payment is downstream (order → payment-service via queue, Stripe **test
mode**); confirm order/payment state by polling `GET /api/orders/{orderId}`.

Other endpoints: `GET /api/orders/{id}`, `GET /api/orders?customerId=`,
`PUT /api/orders/{id}/status`, `POST /api/orders/{id}/cancel` (headers `X-Correlation-ID`,
`X-User-ID`).

**AUTH GATE — recipe fully mapped (2026-08-29):** `POST /api/orders` returns **401
`{"code":"UNAUTHORIZED","message":"Authorization header required"}`** without a bearer
token. The order-service (`order-service-config` CM) validates against:
- `OAUTH2_ISSUER_URI = https://keycloak.3ai-talk.org/realms/shopping-cart`
- `OAUTH2_JWK_SET_URI = .../protocol/openid-connect/certs`

This issuer is the **public** Keycloak URL (well-known returns 200, `password` grant
supported), so a token minted from the laptop validates — **no in-cluster issuer trick
needed** (the `reference_local_go_and_oauth_testing` concern applied to in-cluster issuers).

Realm `shopping-cart` clients (`shopping-cart-infra`
`identity/keycloak/realm-shopping-cart.json`):
- `order-service` — confidential, `directAccessGrantsEnabled=true` → **use this for the
  password grant.**
- `product-catalog` — same.
- `frontend` — public, directAccessGrants=false (SPA auth-code only; can't password-grant).

Token recipe:
```
POST https://keycloak.3ai-talk.org/realms/shopping-cart/protocol/openid-connect/token
  grant_type=password client_id=order-service client_secret=<...>
  username=<LDAP user> password=<...>
```
**Two values still to fetch (both on the cluster):** (1) the `order-service` client secret —
the realm JSON has a `${ORDER_SERVICE_CLIENT_SECRET}` placeholder resolved from Vault at
import; read it from Vault or the k8s secret the client uses. (2) A valid user + password —
the realm has **no local users** (`users: []`); principals are federated from **OpenLDAP**
(dev creds like `alice/password`, per CLAUDE.md — confirm against the live directory).
Then: mint token → `Authorization: Bearer <access_token>` on `POST /api/orders` → expect
201 + order id. That single working authenticated checkout unblocks the k6 script.

## Reachability + metrics (verified)
- **Generator placement:** run k6 on the laptop (OFF the measured node, per the plan) and
  reach the service via `kubectl port-forward svc/order-service -n shopping-cart-apps
  18081:8081 --context ubuntu-hostinger`. (NodePort 30081 may be firewalled externally;
  port-forward is guaranteed.)
- **Metrics sink:** `prometheus-pushgateway` (ns `monitoring`, `:9091`) is deployed.
  Prometheus CR `enableRemoteWriteReceiver` is unset. Path A (preferred): enable
  `enableRemoteWriteReceiver` + k6 `--out experimental-prometheus-rw` → hostinger
  Prometheus. Path B: push k6 summary to the pushgateway. Path A gives proper histograms
  (`checkout_load_latency_seconds`).

## Build steps
1. **JWT helper** — a `_loadtest_mint_token` (in-cluster Keycloak grant) resolving the
   issuer the order-service accepts. Gate everything else on this working for one manual
   authenticated `POST /api/orders` (201 + order id).
2. **k6 script** (`scripts/etc/loadtest/checkout.js`): per-VU loop = mint/refresh token →
   `POST /api/orders` (unique `customerId` + idempotency key) → poll `GET /{id}` for
   order/payment state. Emit `checkout_load_*` metrics (plan §2) with `run_id`/`stage`
   labels. Stages driven by env from the controller.
3. **Wire `loadtest.sh`**: implement `_loadtest_fetch_metrics` (query hostinger Prometheus
   for error_rate/p95/cpu + the five flags) and `loadtest_run` (per stage: launch k6 at
   target concurrency, poll, `_loadtest_evaluate_gates` → `_loadtest_decide`, write the
   immutable stage summary; back off/stop on breach). Keep `--confirm`/`LOADTEST_CONFIRM`
   gate.
4. **Grafana dashboard** (`scripts/etc/loadtest/dashboard.json` or via `observability.sh`):
   throughput, p50/p95/p99, errors, node/service saturation, safe-max concurrency; alerts
   only for an active run + stale-run detection.
5. **Live run (Claude, Stripe test mode):** validate at LOW concurrency first (1 stage,
   ~10 VUs) to prove the pipeline (auth → order → payment test-mode → metrics → dashboard),
   THEN the staged ladder `LOADTEST_STAGES` with health-gated backoff. Capture the immutable
   per-stage JSON + a capacity report. Node is single, constrained, and now also runs
   Kyverno — cap stages and honor the CPU/eviction/error stop-gates.

## Safety (plan §Safety boundaries)
- Stripe `sk_test` / test PaymentMethods only; never real cards.
- Generator CPU stays on the laptop (port-forward), not the measured node.
- Deliberately saturating a live shared payment cluster: staged, health-gated, abort on the
  Slice-E stop conditions. Roll back = stop k6; no persistent cluster change from the run
  itself (orders are test data in the app DB).

## Status 2026-08-29
Contract + reachability + metrics infra + full auth recipe discovered and verified. No code
written yet — this spec is the build blueprint. **Immediate next step:** fetch the
`order-service` client secret (Vault / k8s secret) + confirm an OpenLDAP test user, mint a
token, prove ONE authenticated `POST /api/orders` → 201, then build the k6 script and wire
the Slice E stubs.

## Status 2026-08-31 — CODE COMPLETE (live-run gated)
All deterministic artifacts built + validated:
- `scripts/etc/loadtest/checkout.js` — k6 generator: per-VU `POST /api/orders` with
  deterministic synthetic items + unique `customerId`/idempotency key, optional order poll,
  `checkout_load_*` custom metrics tagged `{stage,run_id,result,state}` (remote-write → `k6_`
  prefix). `node --check` clean.
- `scripts/plugins/loadtest.sh` — wired the two Slice E stubs + helpers:
  `_loadtest_mint_token` (Keycloak password grant, secrets via a 0600 curl `--config` file so
  they never hit argv/`ps`), `_loadtest_token_endpoint` (pure), `_loadtest_prom_query`/
  `_loadtest_prom_flag`/`_loadtest_fetch_metrics` (emit the 8-positional snapshot
  `_loadtest_evaluate_gates` consumes; PromQL overridable via `LOADTEST_PROMQL_*`),
  `_loadtest_k6_stage`, and a real staged `loadtest_run` loop (mint→k6→fetch→evaluate→decide→
  immutable per-stage JSON; `--confirm`/`LOADTEST_CONFIRM` gate kept; `--dry-run` exercises the
  whole ladder with `LOADTEST_DRY_METRICS`, no cluster).
- `scripts/etc/grafana/dashboards/checkout-loadtest-configmap.yaml` — 7 panels (throughput,
  p50/p95/p99, error %, orders/payments by state, CPU-of-limits, idempotency failures, peak VUs),
  `run_id` template var; `grafana_dashboard: "1"` sidecar convention.
- BATS 16/16 (was 9), shellcheck + `bash -n` clean, dashboard JSON valid, dispatcher loads.

**Live-run GATE (remaining):** needs Vault read for the `order-service` client secret
(`secret/keycloak/clients` → `order_service_client_secret`, hub Vault ns `secrets`) + an
OpenLDAP user — both are classifier-gated secret reads. Live steps once secrets are available:
(1) export `LOADTEST_CLIENT_SECRET`/`LOADTEST_USERNAME`/`LOADTEST_PASSWORD`; (2) prove ONE
authed `POST /api/orders` → 201 (blueprint gate); (3) `kubectl port-forward svc/order-service
-n shopping-cart-apps 18081:8081 --context ubuntu-hostinger` + a Prometheus port-forward on
`:19090`; (4) `k6` install; (5) low-concurrency validation (~10 VUs, 1 stage) then the staged
ladder with health-gated backoff; capture the immutable per-stage JSON + capacity report.
k6 is NOT installed locally yet (`brew install k6`).

## Status 2026-08-31 (session 2) — LIVE RUN DONE + two gate bugs fixed

Drove the full live run directly (auth → validation → staged ladder). Two defects were found
and fixed that had silently disabled the health gate; both are now verified end-to-end.

### Bug 1 — dead PromQL gate queries (`${VAR:-default}` brace-termination)
All `LOADTEST_PROMQL_*` defaults with a `{...}` label selector were corrupted at source time.
In `LOADTEST_PROMQL_ERROR_RATE="${LOADTEST_PROMQL_ERROR_RATE:-...{result="error"}[1m]...}"`,
the **first literal `}`** (closing the label selector) terminates the parameter expansion, so
everything after it is appended as literal text — yielding invalid PromQL
(`...{result="error"[1m]...))}`). Prometheus rejects it (`parse error: unexpected character
inside braces: '['`, HTTP 400); `_loadtest_prom_query` runs `curl -sf`, the 400 fails the
curl, and the function returns its `0` fallback. Result: error_rate/cpu/db_pool/control_plane/
eviction/memory gates all read 0 → `breaches=[]` every stage even at 88% real HTTP-429 errors.
Only p95 and stripe (no braces) survived. **BATS never caught it** because every prom test
stubs `_loadtest_curl` — the malformed query string was never sent to a real parser.
**Fix:** `_loadtest_promql_default <var> '<single-quoted default>'` helper (`printf -v`), which
keeps every `}` literal. All 8 defaults converted. New BATS test pins the well-formed strings
(`loadtest: default PromQL gate queries are well-formed`); suite now 17/17.

### Bug 2 (operational, not committed code) — wrong Prometheus on :19090
A stale `kubectl port-forward svc/prometheus-operated 19090:9090 --context k3d-k3d-cluster`
(the **hub** Prometheus) was squatting on :19090, so every hostinger forward silently failed
(`address already in use`). The controller then gated against — and k6 remote-wrote to — the
hub Prometheus, which has no remote-write receiver (POST /api/v1/write → 404) and no k6 series.
First confirmation run still showed `breaches=[]` until this was found. **Fix:** kill the hub
squatter, bind the hostinger pod to :19090 (`kubectl port-forward pod/prometheus-acg-...-0`),
confirm `runtimeinfo.startTime` matches the hostinger pod and POST /api/v1/write → 415 (enabled,
rejects only the empty body). Lesson: the run driver must verify :19090 actually serves the
target-cluster Prometheus before trusting a green ladder.

### Bug 3 (latent, fixed) — checkout.js status-0 mistag
`result: res.status < 400 ? 'ok' : 'error'` tagged status 0 (timeout/conn-refused) as `ok`.
Did not bite this run (errors were 429, status ≥ 400) but would under-report on network faults.
Fixed to `res.status >= 200 && res.status < 400`.

### Also fixed — stage summary now records real throughput
`loadtest_run` passed a literal `0` for `actual_throughput` in every per-stage JSON. Added
`LOADTEST_PROMQL_THROUGHPUT` (`sum(rate(k6_..._requests_total_total{result="ok"}[1m]))`) and
threaded it into the summary (dry-run stays 0). Verified: a green 15-VU stage recorded
`actual_throughput: 10.64`.

### Gate verification (end-to-end, against hostinger Prometheus)
- 2-stage confirm (25 → 200 VUs, thresholds err 2% / p95 2s, hysteresis 2): stage 25
  `hold breaches=[error_rate]` (first breach), stage 200 `stop breaches=[error_rate]` (second
  consecutive → ladder stopped). Gate fires, records breaches, hysteresis works.
- 1-stage green (15 VUs, err 5%): `hold breaches=[]`, `actual_throughput: 10.64` (terminal-rung
  healthy `increase`→`hold` is expected, loadtest.sh:71-73).

### Capacity finding — order-service checkout ceiling ≈ 20–21 req/s (app rate limiter)
Successful order throughput plateaus at **~20.7 orders/s** regardless of offered load
(25 → 200 VUs). The order-service (`httpx/middleware.go`) enforces an app-level rate limit
~20–21 req/s; excess is shed as HTTP 429 in ~5µs. The hostinger node (srv1754834, 2 CPU / 8Gi)
is **never** the constraint — memory plateaued ~88% (MemoryPressure=False), CPU was not the
limiter. Per-stage (50/100/200 VUs): throughput 20.8 / 20.7 / 20.7 orders/s; POST p95 latency
0.16 / 0.21 / 0.88 s; error (429-shed) rate 54.5% / 76.9% / 87.6%. CQRS read-after-write lag
makes an immediate `GET /api/orders/{id}` after `POST` return 404 (poll disabled for the run).
**Takeaway:** the checkout path degrades gracefully by shedding, not collapsing; a durable
capacity increase means raising the app rate limit (and validating DB/Stripe headroom), not
adding node CPU.

**Files changed this session:** `scripts/plugins/loadtest.sh` (brace-safe PromQL helper + 8
defaults + throughput query/threading), `scripts/etc/loadtest/checkout.js` (status-tag),
`scripts/tests/plugins/loadtest.bats` (well-formed-query regression test, 17/17).
