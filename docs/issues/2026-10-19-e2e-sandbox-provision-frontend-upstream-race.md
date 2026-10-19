# Issue: e2e-sandbox-provision timed out on frontend upstream DNS race

**Filed:** 2026-10-19 (Codex investigation of Slack job `8417cf04`)
**Status:** OPEN — root cause identified; implementation not requested or applied
**Priority:** P2 — Tier 2 live verification fails until the sandbox is repaired or reprovisioned
**Severity:** medium
**Component:** sandbox app bootstrap / ArgoCD Application convergence / shopping-cart frontend
**Related:** `docs/issues/2026-05-26-acg-sandbox-expiry-remote-cluster-rebuild-shopping-cart-bootstrap-gap.md`
**Dashboard bug record:** `docs/bugs/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md`

## Job

- Slack job: `8417cf04`
- Target: `make e2e-sandbox-provision`
- E2E run: `1792410757-29778`
- Recorded commit: `9998c6b9c22fffa015fc876714b939670ae63e4b`
- Result: exit 2 from the Make wrapper; underlying e2e exit 1
- Phase: `checking-hub-apps`
- Environment: local M4 runner, hub `k3d-k3d-cluster`, sandbox `ubuntu-k3s`

## Actual output

The job preflight passed:

```text
INFO: [e2e] ACG preflight: service=k3dm-acg-pluralsight credentials_loadable=true K3DM_ACG_REQUIRE_CREDENTIALS=1
INFO: [e2e] sandbox preflight: context=ubuntu-k3s readyz=ok
INFO: [e2e] hub preflight: context=k3d-k3d-cluster readyz=ok
```

The hub gate then reported the same two Applications for the full 420-second timeout:

```text
INFO: [e2e] hub Applications for ubuntu-k3s still converging: ubuntu-k3s-shopping-cart-frontend Synced Degraded;ubuntu-k3s-shopping-cart-product-catalog OutOfSync Healthy; — rechecking in 10s
ERROR: [e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy after 420s: ubuntu-k3s-shopping-cart-frontend Synced Degraded;ubuntu-k3s-shopping-cart-product-catalog OutOfSync Healthy;
INFO: [e2e] Summary written to /Users/cliang/.k3dm/e2e/1792410757-29778.json (exit_code=1)
make: *** [e2e-sandbox-provision] Error 1
```

The recorded summary was:

```json
{
  "commit": "9998c6b9c22fffa015fc876714b939670ae63e4b",
  "phase": "checking-hub-apps",
  "project": "stripe",
  "result": "fail",
  "run_id": "1792410757-29778",
  "runner": "local-m4",
  "service": "product-catalog",
  "tier": "sandbox"
}
```

## Live diagnosis

Read-only inspection of the live cluster after the failed gate found:

```text
ubuntu-k3s-shopping-cart-frontend  Synced  Degraded
ubuntu-k3s-shopping-cart-product-catalog  Synced  Healthy
```

The frontend pod was in `CrashLoopBackOff` with exit code 1. Its container log contained:

```text
2026/10/19 12:04:38 [emerg] 1#1: host not found in upstream "product-catalog.shopping-cart-apps.svc.cluster.local" in /etc/nginx/conf.d/default.conf:46
nginx: [emerg] host not found in upstream "product-catalog.shopping-cart-apps.svc.cluster.local" in /etc/nginx/conf.d/default.conf:46
```

The pod's Deployment condition was:

```text
ReplicaSet "frontend-bfb7667c" has timed out progressing.
```

ArgoCD timestamps establish the ordering:

```text
frontend operation started 2026-10-19T11:38:24Z, finished 11:38:32Z, health Degraded at 11:48:17Z
product-catalog operation started 2026-10-19T12:04:56Z, finished 12:05:55Z, health Healthy at 12:05:39Z
```

The product-catalog Service and Deployment were therefore not available when the frontend Nginx process first resolved its static upstream. Product-catalog later synced and became healthy, but the already-crashlooping frontend was not restarted by that recovery.

## Root cause

The live failure is a bootstrap ordering race, not an ACG credential or Kubernetes API outage:

1. ACG credentials, the sandbox API, and the hub API were healthy.
2. The frontend Deployment started before the product-catalog Service existed.
3. Nginx resolves the product-catalog upstream during startup and exits when DNS returns NXDOMAIN.
4. Product-catalog eventually synced and became healthy, but that did not restart the frontend.
5. The 420-second gate correctly failed because frontend remained Degraded and product-catalog was still OutOfSync during the observation window.

This is related to the prior post-rebuild bootstrap-gap issue, but the evidence here specifically identifies the missing product-catalog Service / frontend startup race. No live mutation was performed during this investigation.

## Recommended follow-up

Choose and specify one bounded fix:

- enforce an ArgoCD dependency/order so the product-catalog Service is present before frontend is rolled out; or
- make the frontend proxy tolerate a temporarily absent upstream and retry DNS without exiting; or
- add an explicit app-layer readiness/bootstrap gate that restarts dependent workloads after required Services appear.

The chosen fix needs a red-first test and a fresh `e2e-sandbox-provision` live verification. Do not mark this issue fixed or live-verified from the post-failure product-catalog recovery alone.
