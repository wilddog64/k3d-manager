# Bug: e2e-sandbox-provision frontend starts before product-catalog Service

**Filed:** 2026-10-19 (Slack job `8417cf04` investigation)
**Branch:** k3d-manager-v1.43.5
**Status:** IMPLEMENTED — 2026-10-19: dispatched implementation landed in `4ebaaec5`; Slack live verification is still in progress. Do not close this bug yet.
**Priority:** P2
**Severity:** Tier 2 live verification fails until the sandbox is repaired or reprovisioned
**Component:** sandbox app bootstrap / ArgoCD Application convergence / shopping-cart frontend
**Related:** `docs/issues/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md`, `docs/issues/2026-05-26-acg-sandbox-expiry-remote-cluster-rebuild-shopping-cart-bootstrap-gap.md`
**Fix commit:** `4ebaaec5`

## Files

| File | Scope |
|---|---|
| `scripts/plugins/e2e.sh` | Add the bounded sandbox convergence/recovery behavior needed to prevent the frontend upstream race from leaving the gate degraded. |
| `scripts/tests/plugins/e2e_sandbox_preflight.bats` | Add focused offline coverage for the selected behavior. |

Do not modify shopping-cart application manifests or unrelated providers. Do not mark this
bug verified from offline tests; a fresh `e2e-sandbox-provision` run is required.

## Symptom / evidence

Slack job `8417cf04` ran `make e2e-sandbox-provision` and failed at the 420-second hub-Application gate. The preflight passed, but the gate repeatedly reported:

```text
ubuntu-k3s-shopping-cart-frontend Synced Degraded
ubuntu-k3s-shopping-cart-product-catalog OutOfSync Healthy
```

E2E run: `1792410757-29778`. The full terminal output and live read-only evidence are recorded in the related `docs/issues` document.

Live inspection found the frontend pod in `CrashLoopBackOff`; Nginx exited with:

```text
host not found in upstream "product-catalog.shopping-cart-apps.svc.cluster.local"
```

The frontend Application started syncing at `2026-10-19T11:38:24Z`, while product-catalog did not start syncing until `2026-10-19T12:04:56Z`. Product-catalog eventually became `Synced/Healthy`, but frontend remained degraded.

## Root cause

The app bootstrap has no dependency or retry boundary for this frontend upstream. Frontend Nginx resolves the product-catalog Service during startup and exits when the Service is not yet present. Later product-catalog reconciliation does not restart the already-crashlooping frontend.

This is a bootstrap ordering race, not an ACG credential or Kubernetes API outage.

## Expected behavior

The sandbox app bootstrap must not leave frontend permanently degraded when product-catalog is still converging. Either the required Service must exist before frontend starts, or frontend must retry an absent upstream without exiting.

## Acceptance

- [ ] A fresh sandbox run proves frontend does not enter `CrashLoopBackOff` when product-catalog reconciliation is slower.
- [ ] The hub gate reaches all target Applications `Synced` and `Healthy` without manual restarts.
- [x] Offline tests cover the selected dependency-order or upstream-retry behavior.
- [ ] No fix is marked `VERIFIED` or `LIVE-VERIFIED` until live verification is complete.
