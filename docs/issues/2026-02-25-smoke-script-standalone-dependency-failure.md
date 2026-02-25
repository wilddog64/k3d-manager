# Smoke Script Fails Due to Unbound Variables and Incorrect Paths

**Date:** 2026-02-25
**Status:** Open (Regressed/Incomplete Fix)

## Description

The Jenkins smoke test script (`bin/smoke-test-jenkins.sh`) and its dependency `scripts/plugins/vault.sh` fail due to environment mismatches and unbound variables when invoked via the standard `deploy_jenkins` flow or standalone.

### 1. Unbound `PLUGINS_DIR` in `vault.sh`
When `bin/smoke-test-jenkins.sh` is sourced by `deploy_jenkins`, it attempts to source `scripts/plugins/vault.sh`. However, `vault.sh` contains the following line:

```bash
ESO_PLUGIN="$PLUGINS_DIR/eso.sh"
```

Because `scripts/k3d-manager` does not `export PLUGINS_DIR`, and `bin/smoke-test-jenkins.sh` does not define it, the script crashes immediately if `set -u` (nounset) is active (which it is in `smoke-test-jenkins.sh` via `set -euo pipefail`).

### 2. Silent Failure due to Redirection
The smoke script uses:
```bash
source "${SCRIPT_DIR}/../scripts/plugins/vault.sh" 2>/dev/null || true
```
This masks the "unbound variable" error, but because `source` is executed in the same shell, the `set -e` in `smoke-test-jenkins.sh` causes the entire script to exit with code 1 immediately upon the failure of the `source` command, before it can even reach the `|| true` or the `_kubectl` guard.

### 3. `SCRIPT_DIR` Mismatch
In `scripts/plugins/vault.sh`, `VAULT_PKI_HELPERS` is defined as:
```bash
VAULT_PKI_HELPERS="$SCRIPT_DIR/lib/vault_pki.sh"
```
When sourced from `bin/smoke-test-jenkins.sh`, `SCRIPT_DIR` is `/.../bin`. However, the `lib` directory is under `/.../scripts/lib`. This causes `vault.sh` to fail to find its own helpers when sourced from the `bin/` directory.

## Impact

- `deploy_jenkins` always reports `WARN: [jenkins] smoke test failed; inspect output above` on macOS/OrbStack.
- The smoke test never actually executes its logic because it crashes during the library initialization phase.
- Standalone runs of `bin/smoke-test-jenkins.sh` fail silently even if `_kubectl` is present in the environment.

## Verification of Failure

Run:
```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault
```
Observe the warning at the end.

Run standalone trace:
```bash
bash -x ./bin/smoke-test-jenkins.sh
```
Observe exit immediately after `source ...vault.sh`.

## Proposed Fix (Research Only)

1.  **Export Variables**: `scripts/k3d-manager` should `export SCRIPT_DIR` and `export PLUGINS_DIR` so they are available to all sub-scripts and sourced plugins.
2.  **Robust Pathing**: `scripts/plugins/vault.sh` should check for `PLUGINS_DIR` and `SCRIPT_DIR` more robustly or use relative paths that are resolved against its own location if possible.
3.  **Smoke Script Fix**: `bin/smoke-test-jenkins.sh` should define `PLUGINS_DIR` before sourcing `vault.sh` if it wants to be semi-standalone.

## Resolution

Pending directive.
