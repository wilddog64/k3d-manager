# Bug: Make target lifecycle is inconsistent across cloud providers

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `Makefile`, `scripts/plugins/gcp.sh`, `scripts/plugins/shopping_cart.sh`, provider docs

---

## Summary

AWS uses one lifecycle pattern:

```bash
make up
make sync-apps
```

GCP uses another:

```bash
make up CLUSTER_PROVIDER=k3s-gcp
make provision CLUSTER_PROVIDER=k3s-gcp
```

This leaks provider-specific implementation details into the user interface. `make up` and the
post-cluster bootstrap target should behave consistently across AWS, GCP, and future Azure.

---

## Root Cause

Provider dispatch was added for core targets (`up`, `down`, `status`, etc.), but no single
cross-provider lifecycle contract was defined for the application/bootstrap step. AWS retained
`sync-apps`; GCP introduced `provision` for full-stack deployment.

---

## Expected Behavior

All providers should share the same command contract:

- `make up [CLUSTER_PROVIDER=...]` — provision the full cluster infrastructure
- one consistent post-cluster target across all providers (`make sync-apps` or `make provision`)

The command sequence should not vary by provider.

---

## Proposed Fix

1. Choose a single cross-provider bootstrap target (`sync-apps` or `provision`).
2. Align AWS, GCP, and future Azure to that same post-cluster command.
3. Update docs/help output to present one standard workflow.
4. Add regression tests for the Makefile dispatch so all providers expose the same lifecycle.

---

## Impact

Users must memorize different workflows for different providers even though only one sandbox is
active at a time. This undermines the project goal of making cloud provider choice an internal
implementation detail.
