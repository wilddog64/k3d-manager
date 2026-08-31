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
