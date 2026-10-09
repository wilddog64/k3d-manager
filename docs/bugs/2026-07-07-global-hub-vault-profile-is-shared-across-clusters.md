# Bug: Global hub-Vault profile is shared across clusters

**Status:** CLOSED — doc merged to main in PR #104; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Filed:** 2026-07-07
**Source:** /ask agent observation

## Description

`scripts/etc/vault/vars.sh` reads and exports a single `HUB_VAULT_PROFILE` and derives a single `HUB_VAULT_CSS_SERVER`/`HUB_VAULT_CSS_AUTH` for every app-cluster run. That design prevents Hostinger and ACG AWS from having independent Vault connectivity settings at the same time.

**Consolidated into:** [App-cluster Vault portability design spec](./2026-07-07-app-cluster-vault-portability.md) — see there for verified findings, phased plan, and open decisions.
