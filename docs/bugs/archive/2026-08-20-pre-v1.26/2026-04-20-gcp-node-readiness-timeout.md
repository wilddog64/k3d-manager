# Bug Fix: extend GCP node readiness timeout from 150s to 300s

**Branch:** `k3d-manager-v1.1.0`
**File:** `scripts/lib/providers/k3s-gcp.sh`

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/lib/providers/k3s-gcp.sh` lines 208–217 (the readiness loop)

---

## Problem

`_provider_k3s_gcp_deploy_cluster` polls for node Ready with 30 attempts × 5s = 150s max.
Fresh GCE instances running k3s typically take 180–300s to reach Ready. The loop exits with
an error before the API server is responsive.

```bash
# current — scripts/lib/providers/k3s-gcp.sh lines 209–216
  local attempts=0
  until KUBECONFIG="${_GCP_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( attempts++ ))
    if (( attempts >= 30 )); then
      printf 'ERROR: %s\n' "[k3s-gcp] Node did not become Ready after 150s" >&2
      return 1
    fi
    sleep 5
  done
```

---

## Fix

Change `30` → `60` and update the error message to `300s`:

```bash
# replacement — scripts/lib/providers/k3s-gcp.sh lines 209–216
  local attempts=0
  until KUBECONFIG="${_GCP_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( attempts++ ))
    if (( attempts >= 60 )); then
      printf 'ERROR: %s\n' "[k3s-gcp] Node did not become Ready after 300s" >&2
      return 1
    fi
    sleep 5
  done
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-gcp.sh` | Lines 212–213: `30` → `60`, `150s` → `300s` |

---

## Rules

- `shellcheck scripts/lib/providers/k3s-gcp.sh` must pass with zero warnings
- Only `scripts/lib/providers/k3s-gcp.sh` may be touched

---

## E2E Verification

### Test T1 — shellcheck
```bash
shellcheck scripts/lib/providers/k3s-gcp.sh
```
Expected: exit 0, no output.

### Test T2 — bash parse check
```bash
bash -n scripts/lib/providers/k3s-gcp.sh && echo "parse OK"
```
Expected: `parse OK`.

### Test T3 — confirm new values in file
```bash
grep -n "attempts >= 60" scripts/lib/providers/k3s-gcp.sh && \
grep -n "300s" scripts/lib/providers/k3s-gcp.sh
```
Expected: both lines found.

---

## Definition of Done

- [ ] `scripts/lib/providers/k3s-gcp.sh` line 212: `attempts >= 60`
- [ ] `scripts/lib/providers/k3s-gcp.sh` line 213: error message says `300s`
- [ ] Tests T1–T3 all pass — paste actual outputs
- [ ] Committed and pushed to `k3d-manager-v1.1.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(gcp): extend node readiness timeout from 150s to 300s
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/providers/k3s-gcp.sh`
- Do NOT commit to `main`
- Do NOT change the sleep interval — only the attempt count and error message
