# Bug Fix: register k3s-gcp in core dispatcher + skeleton provider module

**Branch:** `recovery-v1.1.0-aws-first`
**Files:** `scripts/lib/core.sh`, `scripts/lib/providers/k3s-gcp.sh` (new)
**Depends on:** `bin/acg-up` provider dispatch fix merged (`5cb4c68c`)

---

## Before You Start

1. `git pull origin recovery-v1.1.0-aws-first`
2. Read `scripts/lib/core.sh` lines 1–26 and lines 770–790
3. Read `scripts/lib/providers/k3s-aws.sh` lines 1–20 (understand provider module structure)
4. Note: `scripts/lib/providers/k3s-gcp.sh` does NOT exist — you will create it

---

## Problem

`CLUSTER_PROVIDER=k3s-gcp make up` fails at Step 2 (provisioning) with:

```
ERROR: Unsupported cluster provider: k3s-gcp
```

Two places in `scripts/lib/core.sh` have a hardcoded provider allowlist that only permits
`k3d|orbstack|k3s|k3s-aws`. Additionally, `scripts/lib/provider.sh` expects a module at
`scripts/lib/providers/k3s-gcp.sh` — this file does not exist.

---

## Fix

### Change 1 — Add k3s-gcp to `_cluster_provider` allowlist

**Exact old line (line 19):**

```bash
      k3d|orbstack|k3s|k3s-aws)
```

**Exact new line:**

```bash
      k3d|orbstack|k3s|k3s-aws|k3s-gcp)
```

### Change 2 — Add k3s-gcp to `deploy_cluster` allowlist

**Exact old line (line 779):**

```bash
      k3d|orbstack|k3s|k3s-aws)
```

**Exact new line:**

```bash
      k3d|orbstack|k3s|k3s-aws|k3s-gcp)
```

### Change 3 — Create skeleton provider module

Create `scripts/lib/providers/k3s-gcp.sh` with the following exact content:

```bash
# shellcheck shell=bash
# scripts/lib/providers/k3s-gcp.sh — k3s on ACG GCP sandbox (v1.1.0: credential flow only)
#
# Provider actions:
#   deploy_cluster  — placeholder; full GCP provisioning is not yet implemented
#   destroy_cluster — placeholder; not yet implemented

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/gcp.sh"

function _provider_k3s_gcp_deploy_cluster() {
  _info "[k3s-gcp] GCP cluster provisioning is not yet implemented (v1.1.0 recovery scope: credential flow only)."
  _info "[k3s-gcp] acg-up will exit after this step — use 'kubectl get nodes' to verify once a cluster is available."
}

function _provider_k3s_gcp_destroy_cluster() {
  _info "[k3s-gcp] GCP cluster teardown is not yet implemented."
}
```

The file must be executable: `chmod +x scripts/lib/providers/k3s-gcp.sh`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/core.sh` | 2 line edits — add `k3s-gcp` to both provider allowlists |
| `scripts/lib/providers/k3s-gcp.sh` | New file — skeleton with placeholder deploy/destroy functions |

---

## Rules

- `shellcheck scripts/lib/core.sh` — must pass with zero warnings
- `shellcheck scripts/lib/providers/k3s-gcp.sh` — must pass with zero warnings
- Only the two listed files may be touched
- Do NOT implement actual GCP provisioning logic — placeholder only
- Do NOT modify `scripts/lib/provider.sh`

---

## E2E Verification (must all pass before committing)

### Test E1 — shellcheck both files

```bash
shellcheck scripts/lib/core.sh
shellcheck scripts/lib/providers/k3s-gcp.sh
```
Expected: exit 0, no output for both.

### Test E2 — k3s-gcp accepted by `_cluster_provider`

```bash
source scripts/lib/system.sh
source scripts/lib/core.sh
CLUSTER_PROVIDER=k3s-gcp _cluster_provider
```
Expected: prints `k3s-gcp`, no error.

### Test E3 — unsupported provider still rejected

```bash
source scripts/lib/system.sh
source scripts/lib/core.sh
CLUSTER_PROVIDER=k3s-azure _cluster_provider 2>&1 | head -2
```
Expected: stderr contains `Unsupported cluster provider: k3s-azure`.

### Test E4 — provider module file exists and is executable

```bash
test -x scripts/lib/providers/k3s-gcp.sh && echo "OK"
```
Expected: `OK`.

### Test E5 — AWS allowlist unchanged

```bash
grep -n "k3d|orbstack|k3s|k3s-aws|k3s-gcp" scripts/lib/core.sh
```
Expected: lines 19 and 779 both show `k3d|orbstack|k3s|k3s-aws|k3s-gcp`.

---

## Definition of Done

- [ ] `scripts/lib/core.sh` line 19: `k3d|orbstack|k3s|k3s-aws|k3s-gcp`
- [ ] `scripts/lib/core.sh` line 779: `k3d|orbstack|k3s|k3s-aws|k3s-gcp`
- [ ] `scripts/lib/providers/k3s-gcp.sh` created with exact content above, executable
- [ ] Tests E1–E5 all pass — paste actual outputs
- [ ] `shellcheck` passes on both files with zero warnings
- [ ] Committed and pushed to `recovery-v1.1.0-aws-first`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(core): register k3s-gcp provider — add to allowlist and skeleton module
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed above
- Do NOT commit to `main` — work on `recovery-v1.1.0-aws-first`
- Do NOT implement actual GCP provisioning — placeholder functions only
- Do NOT modify `scripts/lib/provider.sh`
- Do NOT reformat or refactor unrelated lines in `core.sh`
