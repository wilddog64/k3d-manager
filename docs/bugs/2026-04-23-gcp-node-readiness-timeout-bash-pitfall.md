# Bug: GCP Provisioning Fails with Error 1 due to Bash Arithmetic Pitfall

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

GCP cluster provisioning fails immediately after the "Waiting for node to be Ready..." message with `make: *** [up] Error 1`. This is caused by a Bash arithmetic evaluation returning a non-zero exit code, which triggers `set -e`.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Observe the logs until the GCP instance is created and the kubeconfig is merged.
3. Observe the immediate exit with `Error 1` when entering the "Wait for Node" loop.

---

## Root Cause

The script `scripts/lib/providers/k3s-gcp.sh` contains two loops using the following pattern:

```bash
local attempts=0
until ...; do
  (( attempts++ ))
  ...
done
```

In Bash, `(( variable++ ))` evaluates to the *previous* value of the variable. When `attempts` is `0`, the expression evaluates to `0`. Bash treats a result of `0` in an arithmetic expression as a **failure** (exit code 1).

Because `bin/acg-up` sources the provider and runs with `set -e`, the shell terminates the script the moment it hits `(( 0 ))`.

---

## Proposed Fix

Replace the post-increment `(( attempts++ ))` with a pre-increment or an explicit assignment that ensures a non-zero exit status, or append `|| true`:

```bash
# Option 1 (Recommended)
(( ++attempts ))

# Option 2
(( attempts += 1 ))

# Option 3
(( attempts++ )) || true
```

---

## Impact

Critical. Completely blocks GCP provisioning on all platforms where `set -e` is active.
