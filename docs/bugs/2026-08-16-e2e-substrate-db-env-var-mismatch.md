# e2e substrate: order/product-catalog use stale DB env vars → crash-loop on localhost

**Filed:** 2026-08-16
**Component:** `scripts/etc/e2e/order.yaml`, `scripts/etc/e2e/product-catalog.yaml`
(Tier 1 harness substrate bundle, applied by `scripts/plugins/e2e.sh`)
**Severity:** high (blocks a green live e2e smoke — the last blocker after the vCluster
connection/datastore saga was fixed)
**Found by:** live inspection of the still-running vCluster from smoke run #6 (`e2e-1786925108-25444`).
The teardown `vcluster delete` failed ("parent context unreachable"), so the workload pods survived
and could be inspected directly on the hub (`k3d-k3d-cluster`, ns `vclusters`).

## Problem

After the connection/readiness/datastore fixes landed (tmpfs datastore + soft readiness probe), smoke #6
became the **first** run to pass readiness, apply the substrate, and reach the rollout-wait phase.
`SMOKE_EXIT=1` — `kubectl rollout status deployment/postgres` timed out at 300s. But live pod state told
the real story:

```
e2e-...-74f8k (control plane)    1/1 Running   RESTARTS 0     # tmpfs worked — no crash-loop
postgres-...spdxk                1/1 Running   RESTARTS 1     # healthy, just slower than 300s to first-ready
basket-...                       1/1 Running   RESTARTS 0
redis-...                        1/1 Running   RESTARTS 0
order-...                        0/1 CrashLoopBackOff (10)    # <-- real bug
product-catalog-...              0/1 CrashLoopBackOff (9)     # <-- real bug
```

Both crash-looping pods fail to reach postgres — **at `localhost`, not the `postgres` service:**

```
order (Go):  fatal "failed to connect to postgres" ...
             dial tcp 127.0.0.1:5432: connect: connection refused   (database=orders)
product-catalog (Py): sqlalchemy OperationalError: connection to server at
             "localhost" (127.0.0.1), port 5432 failed: Connection refused
```

## Root cause

The substrate manifests feed **stale env var names the current images do not read**, so each app falls
back to its `localhost` default:

- **order** is now a **Go** service (`shopping-cart-order/go`, the Go rewrite). Its config
  (`internal/config/config.go`) reads `DB_HOST` (default `localhost`), `DB_PORT`, `DB_NAME`,
  `DB_USERNAME`, `DB_PASSWORD`, `DB_SSLMODE`. The manifest sets **`SPRING_DATASOURCE_URL` /
  `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD`** — leftovers from the old Java/Spring
  order service. The Go binary ignores them → `DB_HOST` defaults to `localhost`.
- **product-catalog** (Python, pydantic `BaseSettings`, `config.py`) reads `DB_HOST` (default
  `localhost`), `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` and builds its own `database_url`
  property from them. The manifest sets a single **`DATABASE_URL`** env var, which the app never reads →
  `DB_HOST` defaults to `localhost`.

Both manifests *look* correct (they name the `postgres` service in the URL), but the variable **names**
are wrong for the current images, so the service DNS name is never applied.

## Fix (exact-match, grounded in the app source read this session)

**`scripts/etc/e2e/order.yaml`** — replace the three `SPRING_DATASOURCE_*` env entries with the DB_* names
the Go config reads:

```yaml
        - name: DB_HOST
          value: postgres
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: orders
        - name: DB_USERNAME
          value: postgres
        - name: DB_PASSWORD
          value: postgres
        - name: DB_SSLMODE
          value: disable
```

Keep `SERVER_PORT`, `OAUTH2_ENABLED`. (`VAULT_ENABLED` / `SPRING_CLOUD_VAULT_ENABLED` are Spring-era
no-ops for the Go app — harmless; leave or drop.)

**`scripts/etc/e2e/product-catalog.yaml`** — replace `DATABASE_URL` with the DB_* aliases:

```yaml
        - name: DB_HOST
          value: postgres
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: products
        - name: DB_USERNAME
          value: postgres
        - name: DB_PASSWORD
          value: postgres
```

Keep `OAUTH2_ENABLED`. Port is fine: the image `CMD` forces `uvicorn --port 8080`, matching the
manifest `containerPort: 8080` and the readiness probe — **not** a bug (verified against the Dockerfile).

## Open items to observe on the next run (do NOT pre-fix — verify first)

1. **RabbitMQ.** The substrate has no rabbitmq. `order` creates a Rabbit publisher after the postgres
   connect, but its readiness probe checks only the postgres store (`health.NewHandler(store, …)`), so
   readiness should not block on Rabbit. `product-catalog` has rabbitmq config but crashed at the DB
   engine first. If either still crash-loops after the DB fix with a Rabbit dial error at startup, add a
   minimal rabbitmq to the substrate (or set a "publisher optional/lazy" flag) — decide from the logs,
   not by guessing now.
2. **postgres rollout timing.** postgres itself is healthy but was slower than the 300s rollout deadline
   to first-ready on a cold node. Consider bumping the postgres rollout wait, or waiting on
   `postgres` last / in parallel, so a slow-but-healthy datastore doesn't trip the gate.

## Also (separate, already known)

- **Teardown does not run on failure.** `_e2e_teardown`'s `vcluster delete` failed with "parent context
  unreachable" and left the vCluster + workloads running (this is what let us inspect them). Orphaned
  vClusters accumulate and add hub pressure. Track/fix the EXIT-trap teardown separately.

## Verification

1. `kubectl apply --dry-run=client -k scripts/etc/e2e` renders cleanly.
2. Live re-run of `e2e_verify_vcluster`: order + product-catalog reach `1/1 Running`, the substrate
   rollout completes, and the Playwright Job writes a pass/fail JSON summary. This is the run that must
   go green.

## What NOT to do

- Do NOT edit the shopping-cart repos — the app env var names are correct; the k3d-manager substrate
  manifests are what's stale. Fix only `scripts/etc/e2e/*.yaml`.
- Do NOT create a PR; do NOT commit to `main`. Commit to `k3d-manager-v1.25.0`.
