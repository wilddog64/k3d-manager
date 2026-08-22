# vCluster E2E Harness (Tier 1)

A learning-oriented guide to the **Tier 1 end-to-end verification harness** — how
`e2e_verify_vcluster` stands up the shopping-cart stack in a throwaway
[vCluster](https://www.vcluster.com/), runs the Playwright suite against it as an
in-cluster Job, and reports a machine-readable pass/fail. Grounded in
`scripts/plugins/e2e.sh` and `scripts/etc/e2e/`.

> **Scope.** This is Tier 1 of the two-tier model in
> `docs/plans/v1.25.0-e2e-verification-harness.md`. Tier 1 is the **fast, cheap,
> per-candidate** gate. Tier 2 (the ACG full-stack sandbox with real OIDC and the
> live Stripe path) is a separate, periodic job. Tier 1 deliberately runs with
> `OAUTH2_ENABLED=false` and no ESO/Vault/ArgoCD.

---

## What a vCluster is (and why we use one)

A **vCluster** is a fully functional Kubernetes control plane (its own API server,
scheduler view, and syncer) running *inside a namespace* of a host cluster. To a
client it behaves like a real cluster — you get your own `kubeconfig`, your own
namespaces, your own RBAC — but it is created and destroyed in seconds and shares
the host's nodes. That makes it the ideal substrate for a **per-candidate** e2e run:

- **Isolation** — the run cannot touch the live app cluster or Hostinger prod.
- **Speed / cost** — no cloud provisioning; create → test → destroy in one command.
- **Disposability** — every run gets a *uniquely named* vCluster and is torn down
  on success **and** on failure (via an `EXIT` trap), so nothing leaks.

The harness builds on the existing `vcluster.sh` plugin
(`vcluster_create` / `vcluster_destroy` / `_vcluster_kubeconfig_path`), which requires
a host cluster context (`VCLUSTER_HOST_CONTEXT` or the current kube-context).

**Prerequisite:** run `make e2e`; the foundation contract resolves the pinned vCluster
CLI under `${XDG_DATA_HOME:-$HOME/.local/share}/lib-foundation/vcluster/<version>/`.
No manual vCluster CLI installation is supported.

---

## The self-contained substrate bundle (`scripts/etc/e2e/`)

The existing `shopping_cart_reconcile_*` functions are hardcoded to the **live** app
cluster — they assume ArgoCD, ESO, Vault, and a running Postgres. They are *not*
reusable to stand up three bare services in a scratch vCluster. So Tier 1 ships its
own **self-contained kustomize overlay** that is essentially the e2e
`docker-compose.yml` translated to Kubernetes manifests, with **zero** dependency on
Vault / ESO / ArgoCD:

| Manifest | Brings up | Notes |
|---|---|---|
| `postgres.yaml` | `postgres:5432` + initdb | one Postgres, an initdb ConfigMap creates **both** `products` and `orders` DBs |
| `redis.yaml` | `redis:6379` | `--requirepass testredis123` |
| `product-catalog.yaml` | `product-catalog` service | `DATABASE_URL=…/products`, `OAUTH2_ENABLED=false` |
| `basket.yaml` | `basket` service | `REDIS_HOST=redis`, `OAUTH2_ENABLED=false` |
| `order.yaml` | `order` service | `SPRING_DATASOURCE_URL=…/orders`, `OAUTH2_ENABLED=false` |
| `seed-configmap.yaml` + `seed-job.yaml` | product seed | seeds 1,000 products once the catalog is up |
| `kustomization.yaml` | ties it together | namespace `shopping-cart-apps`, pinned images, `k3dm.k3d.io/e2e-substrate` label |

**Contract, not convenience** — every value is derived from the authoritative
`shopping-cart-e2e-tests/docker-compose.yml` and each service's `k8s/base`.

### The port-decoupling detail worth knowing

The e2e tests and the compose contract address product-catalog on **:8000**, but the
published container image actually listens on **:8080** (`uvicorn --port 8080`). The
bundle resolves this cleanly in the **Service**, not the Deployment:

```
Service product-catalog  port 8000  ->  targetPort http (8080)   # container's real port
Service basket           port 8083  ->  targetPort http (8083)
Service order            port 8080  ->  targetPort http (8080)
```

So the test-facing DNS name/port (`product-catalog…svc:8000`) is stable regardless of
the container's internal port.

### Image pinning (A08)

All images are pinned — no `:latest`. The three service images default to their
last-known-good immutable `sha-<gitsha>` tags (mirrored from each service's own
`k8s/base/kustomization.yaml`); datastores pin `postgres:16.4-alpine`,
`redis:7.4-alpine`. When a candidate is under test, the harness **overrides the
service-under-test image** with the candidate digest at deploy time.

---

## The in-cluster Playwright Job model

Rather than port-forwarding services to the host and running Playwright locally, the
harness ships the tests **as a container image** and runs them **inside** the
vCluster as a `Job`:

```
   build+publish                 vcluster_create
 e2e image (GHCR)  ─────►  ┌────────────────────────────┐
                          │  vCluster (throwaway)        │
  candidate digest ─────► │   substrate bundle (kustomize)│
                          │   ├─ postgres / redis         │
                          │   ├─ product-catalog/basket/order
                          │   └─ seed Job                 │
                          │   Playwright Job ─┐           │
                          │     env → ClusterIP DNS:      │
                          │       product-catalog:8000    │
                          │       basket:8083 order:8080  │
                          │     npx playwright test        │
                          │       --project=api --project=flows
                          └───────────┬───────────────────┘
                                      │ logs + results.json
                                      ▼
                        exit code + JSON summary  → $E2E_REPORT_DIR/<run_id>.json
```

The Job talks to the services over **ClusterIP DNS** — no host port-forward. It uses
`restartPolicy: Never`, `backoffLimit: 0` (one shot, honest exit code), and pulls
from GHCR with the `ghcr-pull-secret` the harness provisions in the vCluster.

---

## The gate-consumable contract

Two outputs matter, and both are **exit-code-faithful**:

1. **Exit code** — `e2e_verify_vcluster` returns non-zero on *any* failure
   (substrate didn't come up, seed failed, or a test failed). Zero means the api +
   flows projects passed.
2. **JSON summary** — written to `$E2E_REPORT_DIR/<run_id>.json`:

```json
{
  "run_id": "…", "tier": "vcluster", "service": "product-catalog",
  "candidate_digest": null, "project": "api+flows",
  "passed": 42, "total": 42, "failed": 0,
  "duration_seconds": 31.2, "timestamp": "…", "commit": "…",
  "exit_code": 0, "result": "pass"
}
```

This is the contract the **v1.26.0 promotion gate** consumes: a candidate image is
only promoted when its Tier 1 run reports `result: pass`. (The event-ConfigMap
exporter and Grafana dashboard that turn these summaries into observability are plan
#2, not Tier 1 — but the JSON is emitted in the same shape so they drop in.)

---

## Running it

```bash
# Requires a host cluster context (VCLUSTER_HOST_CONTEXT or current kube-context).
./scripts/k3d-manager e2e_verify_vcluster

# Test a specific candidate image (overrides the service-under-test):
E2E_SERVICE_UNDER_TEST=product-catalog \
  ./scripts/k3d-manager e2e_verify_vcluster \
  ghcr.io/wilddog64/shopping-cart-product-catalog@sha256:<digest>
```

Useful knobs (all env-overridable): `E2E_IMAGE` / `E2E_IMAGE_TAG` (the test-runner
image), `E2E_NAMESPACE`, `E2E_JOB_TIMEOUT`, `E2E_ROLLOUT_TIMEOUT`, `E2E_REPORT_DIR`,
`E2E_SERVICE_UNDER_TEST`.

> **The test-runner image** (`ghcr.io/wilddog64/shopping-cart-e2e-tests`) is built and
> published from the `shopping-cart-e2e-tests` repo (Part 1 of the Tier 1 spec:
> `Dockerfile` + `publish-image.yml` + a `workflow_call` surface on `e2e-tests.yml`).
> Pin `E2E_IMAGE_TAG` to a `sha-<gitsha>` tag for reproducible runs.

---

## Safety rules baked in

- **Never** points at live Hostinger prod — ephemeral vCluster only.
- **Always** tears down via an `EXIT` trap — success or failure — with a unique name
  per run. (The trap references the run name through a global so it stays valid under
  `set -u` even after the function's locals go out of scope.)
- **Secrets** — the GHCR PAT is resolved via `shopping_cart_resolve_ghcr_pat`
  (env → Vault → gh) and confined to a function-local; never in argv or logs.
  Postgres/Redis creds are dev-only, e2e-substrate only.
- **Pin everything** — Playwright base image to the locked version, datastore tags,
  service images by immutable tag/digest.

---

## Where to look next

- `scripts/plugins/e2e.sh` — the harness (`e2e_verify_vcluster` + `_e2e_*`).
- `scripts/etc/e2e/` — the substrate bundle.
- `scripts/tests/plugins/e2e.bats` — structural + exit-code-contract tests.
- `docs/howto/vcluster.md` — vCluster lifecycle basics.
- `docs/plans/v1.25.0-e2e-verification-harness.md` — the two-tier design.
