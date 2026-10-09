# Bug: Vault Kubernetes auth mount is single-target

**Status:** CLOSED — doc merged to main in PR #104; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Filed:** 2026-07-07
**Source:** /ask agent observation

## Description

`scripts/plugins/vault.sh` configures app-cluster auth on the fixed mount `kubernetes-app` via `configure_vault_app_auth_for_context`. That mount stores one cluster API server and CA, so the last cluster configured wins; a second cluster will invalidate the first cluster’s ESO auth path.

**Consolidated into:** [App-cluster Vault portability design spec](./2026-07-07-app-cluster-vault-portability.md) — see there for verified findings, phased plan, and open decisions.
