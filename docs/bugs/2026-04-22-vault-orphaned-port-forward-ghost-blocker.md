# Bug: Vault Seeding Failure (Error 22) due to Orphaned Port-Forward

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `bin/acg-up`, `scripts/plugins/vault.sh`

---

## Summary

When running `make up`, Step 9 (Seeding Vault KV) fails with `make: *** [up] Error 22`. This happens even if the Vault pod is running and unsealed. Investigation reveals that an orphaned `kubectl port-forward` process is "holding" port 8200 on the host Mac and routing traffic to a non-existent pod from a previous session.

---

## Reproduction Steps

1. Run `make up` to establish a working Vault port-forward.
2. Force a restart of the `vault-0` pod or the entire infra cluster.
3. Run `make up` again.
4. Observe failure at Step 9: `INFO: [acg-up] Seeding Vault KV with sandbox static secrets... make: *** [up] Error 22`.
5. Run `lsof -i :8200`. Observe an active `kubectl` process that was not started by the current script.

---

## Root Cause

`bin/acg-up` attempts to kill the Vault port-forward using a `.pid` file. If the previous script execution was cancelled or crashed, the PID file may be missing or stale, while the background `kubectl port-forward` process remains alive (orphaned). 

The new script's attempt to bind to port 8200 fails silently (port busy). Subsequent `curl` commands hit the **Ghost Process**, which returns a `503 Service Unavailable` because its target pod is dead.

---

## Proposed Fix

Harden the "Vault Readiness Gate" in `bin/acg-up`:
1. **Aggressive Cleanup:** Use `pkill -f "port-forward svc/vault"` or `lsof -ti:8200 | xargs kill` to ensure port 8200 is truly free before starting a new forward.
2. **Health Probe:** Add a `curl -sf http://localhost:8200/v1/sys/health` loop to ensure Vault is responsive and **Unsealed** before attempting to seed.
3. **Auto-Recovery:** If the health probe reports 503 (Sealed), automatically invoke `deploy_vault --re-unseal`.

---

## Impact

Medium. Causes consistent deployment failures after pod restarts or Mac sleep cycles, requiring manual process cleanup.
