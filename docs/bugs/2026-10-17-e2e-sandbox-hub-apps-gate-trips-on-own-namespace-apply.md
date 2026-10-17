# e2e-sandbox hub-apps gate trips on the harness's own namespace apply

**Status:** LIVE-VERIFIED — 2026-10-17 run `1792198836-11122` (gate: 15 Synced and Healthy), branch `k3d-manager-v1.43.4`
**Live evidence:** 2026-10-17 · run 1792198836-11122 · env sandbox/local-m4 · scenario stripe/product-catalog · commit 1e554a42 · proves fix
**Priority:** P1
**Severity:** High — every `make e2e-sandbox` run fails before Stripe or Playwright
**Found by:** Claude, live run `1792198645-28764` (2026-10-17T00:57:28Z)
**Introduced by:** `4b510350` (v1.43.4 Tier 2 hub Stripe profile)

## Symptom

```
ERROR: [e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy: ubuntu-k3s-data-layer OutOfSync Healthy;ubuntu-k3s-shopping-cart-namespace OutOfSync Healthy;
```

Both Applications were `Synced Healthy` again by 00:57:29Z / 00:57:39Z — self-heal operations that
finished a second after the gate recorded the failure.

## Cause

`e2e_verify_sandbox` ran `provisioning-secrets` immediately before `checking-hub-apps`.
`_e2e_sandbox_provision_secrets` client-side applies `namespace/shopping-cart-apps` (the run logged
`namespace/shopping-cart-apps configured`). That namespace's metadata is owned by Argo CD —
`ubuntu-k3s-shopping-cart-namespace` and `ubuntu-k3s-data-layer` (`managedNamespaceMetadata`) — so the
apply drifts both Applications, and the single-shot gate reads them in the same second, before
self-heal. The gate was failing on drift the harness itself had just caused.

## Fix

`scripts/plugins/e2e.sh` — run `checking-hub-apps` before `provisioning-secrets`, so the gate reads
GitOps state before the harness touches the cluster. New BATS test
`sandbox checks hub Applications before provisioning secrets` asserts the order; it fails against
the pre-fix source.

The later self-heal of the namespace is harmless: nothing after provisioning reads the
Applications' sync status.

## Follow-up (not in this fix)

The gate still samples once. A fresh sandbox can be minutes from converged (run
`1792194213-3567`); a bounded wait would turn that into a pass instead of an operator rerun.

## Recurrence (2026-10-17, run `1792200825-26862`, after the fix)

```
ERROR: [e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy: ubuntu-k3s-data-layer OutOfSync Healthy;
```

The reorder held: the run reached the gate before provisioning, and no namespace apply was logged.
This time the drift came from outside the harness. The run started right after `make up` finished,
and `ubuntu-k3s-data-layer` was still converging. A read minutes later showed it `Synced`, with the
last operation `Succeeded` and no out-of-sync resources.

This makes the bounded wait in the follow-up above the real fix. `checking-hub-apps` should re-poll,
for example every 10s for up to 3 minutes, and fail only on a state that persists. Keep the failing
Application list from the last poll in the error message. That fix gets its own spec on the next
patch release. This doc stays LIVE-VERIFIED for the reorder.
