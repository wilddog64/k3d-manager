# Bug: `acg-down` only tears down remote state and leaves stale local Hub state behind

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `bin/acg-down`, `bin/acg-up`

---

## Summary

`bin/acg-down` currently stops the tunnel and tears down the remote sandbox resources, but it does not destroy the local Hub / infra cluster. That leaves stale local state behind across many rebuild cycles.

Because the local Hub is often preserved while the remote app cluster is recreated repeatedly, stale ArgoCD, Vault, and orchestration assumptions can survive for days or weeks and only surface later when the local Hub is finally rebuilt.

---

## Why this is a bug

- The current workflow creates the appearance of a "full reset" while retaining important local state.
- In this environment, rebuilding the local OrbStack-backed Hub is cheaper than rebuilding the remote CloudFormation resources.
- Preserving local Hub state is therefore the wrong optimization: it hides drift instead of saving meaningful time.

---

## Observed Effect

- Remote sandbox/app-cluster rebuilds happen frequently due to ACG TTL expiration.
- Local Hub state survives those cycles.
- Stale local assumptions (ArgoCD apps, Vault state, helper expectations) can keep working or remain hidden until a true local reset finally occurs.
- When the local Hub is eventually rebuilt, multiple previously masked issues appear at once.

---

## Root Cause

- `bin/acg-down` does not destroy the local `k3d-k3d-cluster` / Hub state.
- `bin/acg-up` therefore often runs against a mixture of fresh remote state and old local infrastructure state.
- That mixed-state model delays detection of real end-to-end orchestration bugs.

---

## Proposed Fix

1. Make `acg-down` tear down both:
   - remote app-cluster resources, and
   - local Hub / infra cluster state.
2. Ensure `make up` / `bin/acg-up` rebuilds from a truly clean local+remote baseline.
3. If a partial teardown mode is still needed, make it an explicit opt-in rather than the default behavior.

---

## Impact

Medium to High. Preserving stale local state makes the workflow less trustworthy and delays detection of orchestration drift until much later than necessary.
