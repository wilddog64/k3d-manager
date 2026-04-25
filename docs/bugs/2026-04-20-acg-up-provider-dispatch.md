# Bug Fix: acg-up provider dispatch (unblock k3s-gcp)

**Branch:** `recovery-v1.1.0-aws-first`
**File:** `bin/acg-up`
**Depends on:** Phase C merged (`gcp.sh` exists at `scripts/plugins/gcp.sh`)

---

## Before You Start

1. `git pull origin recovery-v1.1.0-aws-first`
2. Confirm `scripts/plugins/gcp.sh` exists: `test -f scripts/plugins/gcp.sh && echo OK`
3. Read `bin/acg-up` in full (348 lines)
4. Read `scripts/plugins/gcp.sh` — understand `gcp_get_credentials` signature
5. Note: `scripts/lib/providers/k3s-gcp.sh` does NOT exist — guard GCP path accordingly

---

## Problem

`bin/acg-up` hardcodes the AWS provider in three places, making `CLUSTER_PROVIDER=k3s-gcp make up` fail immediately by sourcing the wrong plugin, extracting AWS credentials, and overriding the provider env var back to `k3s-aws`.

Hardcoded AWS lock locations:
- **Line 28**: `source .../aws.sh` — unconditional
- **Line 32**: `source .../k3s-aws.sh` — unconditional
- **Line 63**: `"Getting AWS credentials..."` + `acg_get_credentials` — unconditional
- **Line 71**: `CLUSTER_PROVIDER=k3s-aws deploy_cluster` — overrides the env var

---

## Fix

### Change 1 — Provider-aware plugin + library sourcing

**Exact old block (lines 27–32):**

```bash
source "${REPO_ROOT}/scripts/plugins/antigravity.sh"
source "${REPO_ROOT}/scripts/plugins/aws.sh"
source "${REPO_ROOT}/scripts/plugins/acg.sh"
source "${REPO_ROOT}/scripts/plugins/tunnel.sh"
source "${REPO_ROOT}/scripts/plugins/shopping_cart.sh"
source "${REPO_ROOT}/scripts/lib/providers/k3s-aws.sh"
```

**Exact new block:**

```bash
source "${REPO_ROOT}/scripts/plugins/antigravity.sh"
source "${REPO_ROOT}/scripts/plugins/acg.sh"
source "${REPO_ROOT}/scripts/plugins/tunnel.sh"
source "${REPO_ROOT}/scripts/plugins/shopping_cart.sh"

_cluster_provider="${CLUSTER_PROVIDER:-k3s-aws}"
case "${_cluster_provider}" in
  k3s-aws)
    source "${REPO_ROOT}/scripts/plugins/aws.sh"
    source "${REPO_ROOT}/scripts/lib/providers/k3s-aws.sh"
    ;;
  k3s-gcp)
    source "${REPO_ROOT}/scripts/plugins/gcp.sh"
    ;;
  *)
    _err "[acg-up] Unsupported CLUSTER_PROVIDER: ${_cluster_provider} (supported: k3s-aws, k3s-gcp)"
    ;;
esac
```

### Change 2 — Provider-aware credential extraction

**Exact old block (lines 63–68):**

```bash
_info "[acg-up] Step 1/12 — Getting AWS credentials..."
if aws sts get-caller-identity >/dev/null 2>&1; then
  _info "[acg-up] Existing AWS credentials valid — skipping extraction"
else
  acg_get_credentials ${sandbox_url:+"$sandbox_url"}
fi
```

**Exact new block:**

```bash
_info "[acg-up] Step 1/12 — Getting ${_cluster_provider} credentials..."
case "${_cluster_provider}" in
  k3s-aws)
    if aws sts get-caller-identity >/dev/null 2>&1; then
      _info "[acg-up] Existing AWS credentials valid — skipping extraction"
    else
      acg_get_credentials ${sandbox_url:+"$sandbox_url"}
    fi
    ;;
  k3s-gcp)
    gcp_get_credentials ${sandbox_url:+"$sandbox_url"}
    ;;
esac
```

### Change 3 — Remove hardcoded CLUSTER_PROVIDER override

**Exact old line (line 71):**

```bash
CLUSTER_PROVIDER=k3s-aws deploy_cluster --confirm
```

**Exact new line:**

```bash
deploy_cluster --confirm
```

### Change 4 — Guard AWS-only steps for GCP

After line 72 (after `deploy_cluster --confirm`), add a provider guard that exits early for GCP with a clear message. The steps that follow (SSH tunnel, Vault port-forward, ghcr-pull-secret, ESO, ArgoCD registration, Vault KV seed) are AWS-specific and have no GCP equivalent yet.

**Exact old line (line 73):**

```bash
_info "[acg-up] Step 3/12 — Starting SSH tunnel..."
```

**Exact new block (replace that one line with):**

```bash
if [[ "${_cluster_provider}" == "k3s-gcp" ]]; then
  _info "[acg-up] GCP cluster deployed. Steps 3–12 (SSH tunnel, Vault, ESO, ArgoCD) are AWS-only and not yet ported for GCP."
  _info "[acg-up] Run 'kubectl get nodes' to verify the cluster."
  kubectl get nodes
  exit 0
fi

_info "[acg-up] Step 3/12 — Starting SSH tunnel..."
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | 4 surgical edits — provider case dispatch at sourcing, credential extraction, deploy, and AWS-only guard |

---

## Rules

- `shellcheck bin/acg-up` — must pass with zero warnings
- Only `bin/acg-up` may be touched
- Do NOT add a shebang change or reformat unrelated lines
- The AWS path must be unchanged in behavior — test with dry-run grep, not live cluster

---

## E2E Verification (must all pass before committing)

### Test D1 — shellcheck

```bash
shellcheck bin/acg-up
```
Expected: exit 0, no output.

### Test D2 — unsupported provider rejected

```bash
CLUSTER_PROVIDER=k3s-azure bash -c 'source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/lib/provider.sh; bash bin/acg-up' 2>&1 | head -3
```
Expected: stderr contains `Unsupported CLUSTER_PROVIDER: k3s-azure`.

### Test D3 — AWS sourcing unchanged

```bash
bash -n bin/acg-up && echo "parse OK"
grep -n "k3s-aws.sh\|aws.sh\|acg_get_credentials" bin/acg-up
```
Expected: `parse OK`. AWS-specific sources appear inside `k3s-aws)` case branch, not unconditionally.

### Test D4 — GCP sourcing correct

```bash
grep -n "gcp.sh\|gcp_get_credentials" bin/acg-up
```
Expected: `gcp.sh` sourced and `gcp_get_credentials` dispatched inside `k3s-gcp)` branch.

### Test D5 — no hardcoded CLUSTER_PROVIDER=k3s-aws

```bash
grep -n "CLUSTER_PROVIDER=k3s-aws" bin/acg-up || echo "none found (OK)"
```
Expected: `none found (OK)`.

---

## Definition of Done

- [ ] `_cluster_provider` set from `${CLUSTER_PROVIDER:-k3s-aws}` before any case branch
- [ ] `case` block sources `aws.sh` + `k3s-aws.sh` for `k3s-aws`, `gcp.sh` for `k3s-gcp`, errors on unknown
- [ ] Credential extraction dispatches `acg_get_credentials` (AWS) vs `gcp_get_credentials` (GCP)
- [ ] `CLUSTER_PROVIDER=k3s-aws` prefix removed from `deploy_cluster` call
- [ ] GCP guard exits after `deploy_cluster` with informational message and `kubectl get nodes`
- [ ] Tests D1–D5 all pass — paste actual outputs
- [ ] `shellcheck bin/acg-up` passes with zero warnings
- [ ] Committed and pushed to `recovery-v1.1.0-aws-first`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA and Phase C unblocked

**Commit message (exact):**
```
fix(acg-up): provider-aware dispatch — unblock k3s-gcp make up
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `recovery-v1.1.0-aws-first`
- Do NOT reformat or refactor unrelated lines — minimal patch only
- Do NOT add `k3s-gcp.sh` provider lib — it does not exist yet; the GCP guard handles this
- Do NOT change the AWS flow behavior — AWS path must behave identically to before
