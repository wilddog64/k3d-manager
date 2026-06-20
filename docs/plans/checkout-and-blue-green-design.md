# Design Discussion — Cart Persistence, Simulated Checkout, and Blue/Green via vCluster + Grafana

**Status:** DESIGN / DISCUSSION — not an implementation spec. Splits into k3d-manager specs +
shopping-cart (Codex) specs after review. No code changes until the split is agreed.
**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`)
**Related:** `docs/plans/v1.9.0-blue-green-argo-rollouts.md` (existing blue/green plan),
`docs/plans/v1.7.2-hostinger-grafana-federation.md` (cross-cluster Grafana),
`docs/plans/v1.8.0-self-healing-alertmanager-webhook.md` (alert→webhook loop),
`docs/plans/v1.4.6-frontend-browser-access-via-istio-ingress.md` (frontend Istio ingress),
`docs/plans/shopping-cart-payment-go-rewrite-pr1.md` (mock payment gateway).

This captures four observed issues so we can split them into the right specs. Two are **app-layer**
(shopping-cart repos), two are **platform** (k3d-manager). They are interdependent: durable cart
state is a prerequisite for a safe blue/green switch, and the simulated checkout is what makes a
blue/green demo show something real.

---

## Issue 1 — No sticky session → cart does not persist across visits

**Symptom:** items added to the cart disappear after a while / across days.

This is two distinct sub-problems that must not be conflated:

**1a. Session affinity at the mesh (infra — k3d-manager).** The frontend is served through the
Istio ingress gateway (`frontend.shopping-cart.local` → `istio-ingressgateway` → `svc/frontend`,
per v1.4.6) and runs multiple replicas. There is **no `DestinationRule` with `consistentHash`
cookie affinity** for `svc/frontend`, so consecutive requests can land on different frontend pods.
If the Node frontend keeps any cart/session state in-process, the cart appears to reset between
requests.

**1b. Session/cart durability (app — shopping-cart-frontend).** Even with affinity, in-memory
session is lost on pod restart or redeploy and cannot survive "multiple days." The durable fix is
to externalize the cart to **basket-service (Go) + `redis-cart`** — the intended store — keyed by a
**stable session/customer id carried in a cookie**, not pod-local memory, with a multi-day cookie
`Max-Age`.

**Diagnosis needed before writing specs** (read `shopping-cart-frontend`): does the frontend hold
the cart in-process or call basket-service? Is it keyed by a persistent cookie/customerId? Confirm
the current replica count and whether a frontend `DestinationRule` already exists in
`shopping-cart-infra`.

**Two slices:**
- *infra (k3d-manager):* Istio `DestinationRule` with `consistentHash` on a session cookie for
  `svc/frontend`. Deterministic affinity — and a prerequisite for blue/green so a color switch
  doesn't strand in-flight sessions.
- *app (shopping-cart-frontend):* carry a stable session cookie; persist cart to basket/Redis (not
  pod memory); set a multi-day cookie `Max-Age`.

> **Note:** 1b is the load-bearing fix. Affinity (1a) only masks the symptom; pod-local state still
> dies on redeploy. Externalizing to Redis is what gives both multi-day persistence **and** survival
> across a blue/green switch.

---

## Issue 2 — No checkout / no card entry → the money path can't be exercised

**Symptom:** no UI field to enter credit-card info; no way to run a checkout.

**Goal:** a **simulated** checkout — collect card details in a form, POST to the payment service,
get a result, show a confirmation — **without charging anything real.** This is exactly what the
**mock gateway** provides (`shopping-cart-payment-go-rewrite-pr1.md`, or the current Java payment
with the mock gateway): `MOCK_GATEWAY_FAILURE_RATE=0.0` deterministically "succeeds," returns a
synthetic transaction id, and persists a `payments` row. No external API call, no real money.

This also unlocks the **e2e acceptance contract** — Playwright must be able to drive
add-to-cart → checkout → payment-confirmed.

**App slices (shopping-cart):**
- *frontend:* checkout page with an order summary + card form (number / exp / cvc / cardholder
  name); calls order-service to create the order, then payment-service `POST /api/v1/payments` to
  process via the mock gateway; renders a confirmation page. Card fields are **simulation-only** —
  never persisted as PAN/CVV (the payment service already reduces to `card_last4`/`card_brand`).
- *order/payment:* contract already exists. Define a small **test-card table** (e.g. `4242…` →
  success, a designated number → decline) mapped to deterministic mock outcomes, so the demo can
  show both the happy path and a decline without real gateways.

**Deferred:** real Stripe/PayPal is payment go-rewrite **PR2**. PR1's mock gateway is enough to
build and demo the full simulated checkout now.

---

## Issue 3 — Blue/green via vCluster (two models)

We already have a blue/green plan, but it uses vCluster differently than this question implies.
Both models are documented here so we can pick deliberately.

| | **Model A — Argo Rollouts (already specced, v1.9.0)** | **Model B — vCluster-as-color (this discussion)** |
|---|---|---|
| Blue/green unit | two ReplicaSets in the prod namespace | two full vClusters (`blue-vc`, `green-vc`) on one host |
| vCluster's role | ephemeral **stress-test sandbox** only | the **live colors themselves** |
| Switch mechanism | Argo Rollouts active/preview Service selector swap | repoint the parent ingress (Istio route / cloudflared / MetalLB) from blue-vc to green-vc |
| Isolation | namespace-level (shared control plane) | total — separate control planes, CRDs, can soak with prod-like data |
| Rollback | Rollouts abort | repoint the parent route back (instant) |
| Cost | one stack + ephemeral test vCluster | **two full stacks running** |
| Hard part | analysis thresholds | **state/data sync between colors** |
| Maturity | mature controller, analysis gates | bespoke; we build the switch tooling |

**Model B switch point.** The external entry is `*.shopping-cart.local` → Istio ingressgateway
(in prod: Cloudflare tunnel → MetalLB → Istio). The "switch" is changing which vCluster's ingress
the **parent route** forwards to — one field in a parent Istio `VirtualService` (or the cloudflared
config) flipped from `blue-vc-ingress` to `green-vc-ingress`, then synced. A small
`bluegreen_switch <color>` plugin function would own that flip + verify.

**The hard part — state.** Postgres (orders/payments) and `redis-cart` live *inside* each vCluster
by default, so a naive flip strands every blue cart/order/payment. Two options:
- **(i) Shared data layer (recommended):** keep Postgres + Redis **outside** the vClusters (host
  level), and color **only the stateless tiers** (frontend, basket, order, payment,
  product-catalog), both colors pointing at the shared data layer. This is also *why Issue 1b
  matters* — pod-local cart state cannot survive a color switch; it must be in the shared Redis.
- **(ii) Per-color DB + migrate/replicate at cutover** — much harder; avoid unless we specifically
  want data isolation per color.

**Recommendation.** Keep **Model A (Rollouts)** as the eventual **production** promotion mechanism
on OCI (it's already specced, controller-managed, has analysis gates). Use **Model B
(vCluster-as-color)** as a **demo/dev** blue/green we can show end-to-end on the warm Hostinger host
using the preflight machinery we already have (the `green1`/`greenN` vclusters) — a strong visual
that reuses existing tooling. Don't build two production blue/green systems; pick A for prod, B for
the demo, with the shared data layer (option i).

---

## Issue 4 — Grafana for the blue/green switch

Grafana's role is **decision support + audit + automation trigger** — not the traffic mechanism
itself. Three concrete uses, all reusing patterns we already have:

**4a. Blue-vs-green compare dashboard.** The federation work (v1.7.2 + acg/oci) already aggregates
per-cluster metrics under a `cluster` label. Add a compare dashboard: golden signals (RPS, error
rate, p95 latency, saturation) for blue vs green side by side, with a `$color`/`$cluster` template
variable. This is the **human gate** — watch green against blue during the soak.

**4b. Switch annotations.** Mark cutover/rollback events on all dashboards (Grafana annotation via
API at switch time) so latency/error movement lines up with the switch and rollback decisions are
auditable.

**4c. Grafana-alert-driven switch (automation).** Grafana **alert rules** on green's golden signals
→ contact point = **webhook** → the existing **k3dm-webhook** (v1.6.0 webhook-as-runner) → it runs
the cutover or rollback. e.g. "green error-rate < 1% AND p95 < 500ms for 10m" fires a *healthy*
alert → webhook promotes (flips the parent route to green); a *breach* alert → webhook aborts /
rolls back to blue. This is the **same pattern as v1.8.0 self-healing-alertmanager-webhook** —
Grafana/Alertmanager → webhook → action.

**Overlap to note.** Model A's v1.9.0 already queries **Prometheus directly** via an Argo Rollouts
`AnalysisTemplate` for its gate. Grafana-driven adds the **human-visual gate + alerting contact
point** on top, and is the *natural controller for Model B*, which has no Rollouts controller — in
Model B, **Grafana alert → k3dm-webhook becomes the promotion controller.**

---

## Prerequisite ordering (these gate each other)

1. **(1b app)** externalize cart to basket/Redis + stable session cookie — without this, neither
   multi-day persistence **nor** blue/green state survival works. *Load-bearing; do first.*
2. **(1a infra)** Istio `DestinationRule` consistentHash affinity for `svc/frontend`.
3. **(2 app)** checkout UI + simulated card form → order + payment mock gateway + test-card table.
4. **(3/4)** blue/green: Model A is specced (v1.9.0). Model B (vCluster-as-color demo) + Grafana
   compare/annotation/alert→webhook switch — new design, only after the data layer is shared (3.i).

---

## Proposed work breakdown (becomes specs/issues after review)

**k3d-manager specs (Claude writes → Codex):**
- Istio `DestinationRule` sticky-session for `svc/frontend` (infra slice of Issue 1a).
- Grafana blue/green compare dashboard + switch annotations (4a/4b) — extends v1.7.2 federation.
- Grafana-alert → k3dm-webhook cutover/rollback contact point + handler (4c) — extends the v1.8.0
  webhook pattern.
- Model B vCluster-as-color switch: parent Istio route / cloudflared repoint + a `bluegreen_switch`
  plugin function — amendment to v1.9.0 (or a new v1.9.x), with the shared data layer (3.i).

**shopping-cart specs (Claude writes spec → Codex; per spec-only discipline):**
- frontend: externalize cart to basket-service + stable session cookie + multi-day `Max-Age`
  (Issue 1b).
- frontend: checkout page + simulated card form → order + payment; confirmation; test-card table
  (Issue 2).

---

## Open questions (need your call before splitting into specs)

1. **Model A vs B:** confirm the plan — keep **Rollouts (A)** as the eventual OCI **production**
   blue/green, and wire **vCluster-as-color (B)** as a visible **demo on Hostinger** reusing the
   preflight vclusters? (my recommendation: yes — different purposes, not redundant.)
2. **State for Model B:** shared host-level data layer (option i, recommended) vs per-color DB
   (option ii)?
3. **Checkout scope:** simulated-only for the foreseeable future (mock gateway), or mock-now /
   real-Stripe-later (payment PR2) — does the checkout UI need to anticipate real gateways?
4. **Sticky session:** do you want the quick infra affinity fix (1a) shipped first as a stopgap
   while the durable Redis externalization (1b) is built, or go straight to 1b?
