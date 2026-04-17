# Smoke Script Fails Due to Unbound Variables and Incorrect Paths

**Date:** 2026-02-25
**Status:** Fixed

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

## Resolution (2026-02-25)

- `bin/smoke-test-jenkins.sh` now derives the repo root from its own directory,
  resets `SCRIPT_DIR` to `${REPO_ROOT}/scripts`, and sets `PLUGINS_DIR` to
  `${SCRIPT_DIR}/plugins` before sourcing any helpers. This mirrors the environment that
  `scripts/k3d-manager` would normally provide and keeps `_vault_exec` accessible when
  the smoke helper runs outside the deployer.
- Because `SCRIPT_DIR` points at the real `scripts/` directory again, `vault.sh` finds
  its `lib/vault_pki.sh` helper without extra exports, and the `_kubectl` declaration is
  now available before the guard executes.
- Verification: `bash -x ./bin/smoke-test-jenkins.sh` progresses past the sourcing
  phase (no nounset errors) and now runs until it hits real cluster interactions. The
  WARN in `deploy_jenkins --enable-vault` disappears once the mac smoke tunnel succeeds.
