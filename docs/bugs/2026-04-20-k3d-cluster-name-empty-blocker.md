# Bug Fix: add safe default for CLUSTER_NAME in deploy_cluster

**Branch:** `k3d-manager-v1.1.0`
**File:** `scripts/lib/core.sh`

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/lib/core.sh` line 796 (the `cluster_name_value` assignment in `deploy_cluster`)
3. Read `scripts/etc/cluster.yaml.tmpl` — confirm `name: "${CLUSTER_NAME}"` is the field that fails

---

## Problem

`make up` fails with:
```
FATA[0000] Schema Validation failed for config file /tmp/k3d-cluster.TWD6qg.yaml:
  - metadata.name: Does not match format 'hostname'
```

Root cause chain:
1. `deploy_cluster` in `core.sh` line 796: `local cluster_name_value="${positional[0]:-${CLUSTER_NAME:-}}"` — no default fallback
2. When no positional arg is passed and `$CLUSTER_NAME` is not pre-exported, `cluster_name_value` is empty
3. `cluster.yaml.tmpl` renders `name: ""` — k3d rejects it (hostname format required)

`bin/acg-up` is not the cause — its provider dispatch is correct.

---

## Fix

**One-line change in `scripts/lib/core.sh` line 796:**

```bash
# current
   local cluster_name_value="${positional[0]:-${CLUSTER_NAME:-}}"
```

```bash
# replacement
   local cluster_name_value="${positional[0]:-${CLUSTER_NAME:-k3d-cluster}}"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/core.sh` | Line 796: add `k3d-cluster` as default for `CLUSTER_NAME` |

---

## Rules

- `shellcheck scripts/lib/core.sh` must pass with zero new warnings
- Only `scripts/lib/core.sh` may be touched

---

## E2E Verification

### Test C1 — shellcheck
```bash
shellcheck scripts/lib/core.sh
```
Expected: exit 0, no new warnings.

### Test C2 — grep confirm
```bash
grep -n 'cluster_name_value=.*k3d-cluster' scripts/lib/core.sh
```
Expected: one match at line 796.

### Test C3 — live smoke test (run with active sandbox)
```bash
make up
```
Expected: k3d cluster creation proceeds past the YAML template step without the `Schema Validation failed` error.

---

## Definition of Done

- [ ] `scripts/lib/core.sh` line 796: `${CLUSTER_NAME:-k3d-cluster}` (not empty string)
- [ ] Tests C1 and C2 pass — paste actual outputs
- [ ] Test C3 — paste the relevant log lines showing cluster creation proceeds
- [ ] Committed and pushed to `k3d-manager-v1.1.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(core): add k3d-cluster default for CLUSTER_NAME to prevent empty hostname error
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/core.sh`
- Do NOT commit to `main`
- Do NOT change any other logic in `deploy_cluster` — one line only
