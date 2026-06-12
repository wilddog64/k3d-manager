# Bugfix: k3s-az provider — rename dispatch function names `k3s_azure` → `k3s_az`

**Date:** 2026-06-12
**Branch:** `k3d-manager-v1.6.5`
**Files:** `scripts/lib/providers/k3s-az.sh`, `bin/acg-down`

---

## Problem

After the `k3s-azure`→`k3s-az` rename (commit `46d9b360`), `make up CLUSTER_PROVIDER=k3s-az`
fails at Step 2/12:

```
INFO: Using cluster provider: k3s-az
ERROR: Cluster provider 'k3s-az' does not implement action 'deploy_cluster'
```

**Root cause:** `_cluster_provider_call` in `scripts/lib/provider.sh` derives the provider
function name by replacing hyphens with underscores:

```bash
local provider_slug="${provider//-/_}"            # k3s-az → k3s_az
local func="_provider_${provider_slug}_${action}" # → _provider_k3s_az_deploy_cluster
```

The rename spec did a literal find-replace of `k3s-azure` (hyphen form) only, so the function
**identifiers** still use the underscore form `_provider_k3s_azure_deploy_cluster` /
`_destroy_cluster`. The dispatcher looks up `_provider_k3s_az_deploy_cluster`, which does not
exist → the error above.

---

## Reproduction

```
make up CLUSTER_PROVIDER=k3s-az
# → ERROR: Cluster provider 'k3s-az' does not implement action 'deploy_cluster'
```

---

## Fix

Rename the two function identifiers (drop `ure` from `azure`) and the one direct caller.
Exactly 3 occurrences — confirmed by `git grep -n 'k3s_azure' -- scripts/ bin/`.

### Change 1 — `scripts/lib/providers/k3s-az.sh` line 155

**Old:**
```bash
function _provider_k3s_azure_deploy_cluster() {
```
**New:**
```bash
function _provider_k3s_az_deploy_cluster() {
```

### Change 2 — `scripts/lib/providers/k3s-az.sh` line 240

**Old:**
```bash
function _provider_k3s_azure_destroy_cluster() {
```
**New:**
```bash
function _provider_k3s_az_destroy_cluster() {
```

### Change 3 — `bin/acg-down` line 81 (direct caller)

**Old:**
```bash
    _provider_k3s_azure_destroy_cluster --confirm
```
**New:**
```bash
    _provider_k3s_az_destroy_cluster --confirm
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-az.sh` | rename 2 function defs `k3s_azure`→`k3s_az` |
| `bin/acg-down` | rename direct call `k3s_azure`→`k3s_az` |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-az.sh bin/acg-down` — zero new warnings
- **Residual check (must be empty):** `git grep -n 'k3s_azure' -- scripts/ bin/` → no output
- No file other than the 2 listed targets touched
- Do NOT touch `plugins/azure.sh`, `ubuntu-azure`, `k3d-azure-node`, `scripts/lib/foundation/`,
  or historical docs

---

## Definition of Done

- [ ] 3 occurrences renamed (2 defs + 1 caller)
- [ ] `shellcheck -S warning` passes on both targets
- [ ] `git grep -n 'k3s_azure' -- scripts/ bin/` returns empty
- [ ] `make up CLUSTER_PROVIDER=k3s-az` gets past "does not implement action 'deploy_cluster'"
      (dispatch resolves the function — it may still fail later on real cloud steps; that is fine)
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**After verify (operator step — note in completion report):** run `make restart-webhook`.

**Commit message (exact):**
```
fix(provider): rename k3s-az dispatch functions k3s_azure → k3s_az
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the 2 listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
