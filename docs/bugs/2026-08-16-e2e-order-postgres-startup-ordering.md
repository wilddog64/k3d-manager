# e2e substrate: order CrashLoopBackOff + postgres first-boot restart (startup ordering)

**Filed:** 2026-08-16
**Component:** `scripts/etc/e2e/order.yaml`, `scripts/etc/e2e/postgres.yaml` (Tier 1 harness substrate)
**Severity:** high (blocks a green Tier 1 e2e smoke — order never reaches Ready within the rollout timeout)
**Found by:** live smoke run #9 — the readiness race guard (`vcluster.sh`) and the DB env-var fix both held;
the run rolled out postgres, redis, product-catalog, and basket green, then failed waiting on `order`.

## Problem

`kubectl -n shopping-cart-apps rollout status deployment/order --timeout=300s` never completes; the `order`
pod sits in `CrashLoopBackOff`. Its logs show the real cause:

```
fatal  failed to connect to postgres:
  failed to connect to `user=postgres database=orders`:
  10.43.67.36:5432 (postgres): dial error: connect: connection refused
```

`order` (Go) has **no DB-connect retry** — a single failed connect at boot is `log.Fatal` → process exits →
Kubernetes restarts it → exponential CrashLoopBackOff. A *later* restart did come up clean
(`starting order service` → `/actuator/health/readiness` 200), proving order is not broken — it just cannot
tolerate postgres being unavailable at its own startup.

Two things make postgres unavailable exactly when order first boots:

1. **All substrate Deployments are applied at once**, so `order` and `postgres` start booting in parallel.
   order loses the race and cold-crashes until postgres is up.
2. **postgres self-restarts once on first boot.** Its liveness probe (`initialDelaySeconds: 15`,
   `pg_isready -U postgres`) fires *during* `initdb` + the two-database init-script phase and kills the
   container mid-init (observed: container Finished exit 0 "received fast shutdown request", then restarted;
   2nd container boots from an already-initialized PGDATA and stays healthy). During that ~6s restart window
   order gets `connection refused`.

The long CrashLoopBackOff wait also widened the exposure window for the pre-existing vCluster proxy-port
drift (`docs/bugs/2026-08-16-e2e-vcluster-kubeconfig-proxy-port-drift.md`): the `rollout status` call
ultimately died on `Unable to connect to the server: TLS handshake timeout`, ~35s before order's healthy
restart. Collapsing order's startup to a single fast boot removes that exposure.

## Root cause

Startup ordering, not a resource or code defect: order boots before postgres is accepting connections and
fatally exits on the first failed connect; postgres additionally restarts once on first boot because its
liveness probe does not allow enough runway for `initdb` + init scripts.

## Fix (both substrate-side, in this repo — no shopping-cart code changes)

**1. `scripts/etc/e2e/order.yaml` — add an initContainer that blocks order until postgres is reachable**, so
order starts exactly once, after postgres, and reaches Ready in ~5s:

```yaml
      initContainers:
      - name: wait-for-postgres
        image: postgres:16.4-alpine
        imagePullPolicy: IfNotPresent
        command:
        - sh
        - -c
        - until pg_isready -h postgres -p 5432 -U postgres; do echo "waiting for postgres"; sleep 2; done
```

**2. `scripts/etc/e2e/postgres.yaml` — give first-boot init enough runway** so the liveness probe does not
kill the container mid-`initdb`:

```yaml
        livenessProbe:
          ...
          initialDelaySeconds: 45   # was 15 — initdb + 2-database init scripts must finish first
```

(The readiness probe stays at `initialDelaySeconds: 5` — readiness flapping is harmless; only liveness
kills the container.)

## Why not fix order's code

order lives in the `shopping-cart-order` repo and must not be edited from k3d-manager. Adding DB-connect
retry there is a good hardening (track separately), but the substrate must be robust regardless — the
initContainer is the correct substrate-side gate.

## Verification

1. Re-run `./scripts/k3d-manager e2e_verify_vcluster`.
2. postgres comes up with `Restart Count: 0`; the order initContainer waits, then order starts once and
   `deployment/order` rolls out well within the 300s timeout.
3. The harness proceeds to the seed job and Playwright Job, which reaches `Completed`, and writes a
   pass/fail JSON summary to `~/.k3dm/e2e/<run_id>.json`. This is the run that must go green.

## What NOT to do

- Do NOT edit the `shopping-cart-order` repo from k3d-manager.
- Do NOT paper over with a blanket `sleep` before order — gate on the actual postgres readiness.
- Do NOT drop postgres liveness entirely — only widen its first-boot runway.
