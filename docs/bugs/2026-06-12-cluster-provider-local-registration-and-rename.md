# k3d-manager: register cloud providers locally + redo `k3s-azure`→`k3s-az` rename (no subtree edit)

**Date:** 2026-06-12
**Repo (work):** `k3d-manager`
**Branch:** `k3d-manager-v1.6.5`
**Status:** **WITHDRAWN (2026-06-12).** Built on a false premise — that `scripts/lib/core.sh` is
the lib-foundation subtree. It is not: the subtree lives at `scripts/lib/foundation/`, and the
local `scripts/lib/core.sh` (sourced last by `scripts/k3d-manager`) shadows the foundation
`_cluster_provider` at runtime. So registering `_cluster_provider_is_extra_supported` would never
be consulted, and the prerequisite gate (`git grep 'k3s-aws…' -- scripts/lib/core.sh` → empty)
can never be met by a subtree pull. The rename is done instead via the local-edit spec
`docs/bugs/2026-06-12-rename-k3s-azure-to-k3s-az.md` (REINSTATED). The lib-foundation hook shipped
separately as PR #30 (library improvement only). **Do NOT implement this file.**

---

## Why

This replaces the backed-out commit `976a9617`, which renamed `k3s-azure`→`k3s-az` by editing the
**subtree** `scripts/lib/core.sh` directly (discipline violation). The correct approach:

1. lib-foundation gains an extensibility hook (companion spec) — **done first, separately**.
2. k3d-manager's subtree `core.sh` is refreshed from lib-foundation so it returns to **pristine ==
   upstream** (no hardcoded cloud providers) — **Claude drives this subtree pull**.
3. k3d-manager **registers** its cloud providers in the local (non-subtree) file
   `scripts/lib/cluster_provider.sh` via the hook — **this spec**.
4. The `k3s-azure`→`k3s-az` rename is redone touching **only** `bin/` files and the provider file —
   **this spec**. `core.sh` is NEVER edited here.

---

## Prerequisites (Claude confirms before handing this to Codex)

- [ ] Companion lib-foundation spec merged to lib-foundation + tagged.
- [ ] **Claude** has run `git subtree pull --squash` to refresh `scripts/lib/core.sh` from
      lib-foundation. After this, `scripts/lib/core.sh` validation reads `k3d|orbstack|k3s)` with
      the `*)` hook fallback, and contains **no** `k3s-aws/k3s-gcp/k3s-oci/k3s-azure/k3s-az`
      literals. Codex must NOT do the subtree pull.
- [ ] Verify gate: `git grep -n 'k3s-aws\|k3s-gcp\|k3s-az' -- scripts/lib/core.sh` → **empty**.

Once all three hold, hand this spec to Codex.

---

## Before You Start

- Repo: `k3d-manager` (single repo)
- Branch: `k3d-manager-v1.6.5` — `git pull origin k3d-manager-v1.6.5`
- Read in full: `scripts/lib/cluster_provider.sh`, `bin/acg-up`, `bin/acg-down`, `bin/k3dm-webhook`,
  `scripts/lib/providers/k3s-azure.sh`
- Confirm the prerequisite gate above is already satisfied (core.sh has no cloud-provider literals).
  If it is NOT, STOP and report — do not proceed.

---

## Change Set 1 — register cloud providers in `scripts/lib/cluster_provider.sh`

Add the hook function (4-space indent to match the file). Place it immediately **after**
`_cluster_provider_reset_active()`:

**Exact new block to insert:**
```bash
function _cluster_provider_is_extra_supported() {
    case "${1:-}" in
        k3s-aws|k3s-gcp|k3s-oci|k3s-az)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
```

This is the consumer hook lib-foundation's `_cluster_provider` consults via `declare -f`. It is the
**single source of truth** for which cloud providers k3d-manager supports. Note it already uses the
renamed `k3s-az` (not `k3s-azure`) — consistent with Change Set 2.

---

## Change Set 2 — redo the rename `k3s-azure`→`k3s-az` (bin/ + provider file ONLY)

In each file below replace **every literal `k3s-azure` with `k3s-az`**. **Do NOT touch
`scripts/lib/core.sh`.** Do NOT touch `plugins/azure.sh`, `ubuntu-azure`, `k3d-azure-node`,
`k3d-manager-azure-key`, or any `azure` substring that is not the literal `k3s-azure`.

### 2A — `bin/acg-up` (6 occurrences: lines ~68, 70, 73, 185, 215, 569)
Includes the `case` label, the `source` path, the unsupported-provider error message, and two
string conditionals. The `source` line must point at the renamed file:
```
source "${REPO_ROOT}/scripts/lib/providers/k3s-azure.sh"  → .../k3s-az.sh
```

### 2B — `bin/acg-down` (3 occurrences: lines ~11, 77, 79)
Header comment, `case` label, and the `source` path (→ `k3s-az.sh`).

### 2C — rename the provider file + its internals
```
git mv scripts/lib/providers/k3s-azure.sh scripts/lib/providers/k3s-az.sh
```
Then in the renamed `scripts/lib/providers/k3s-az.sh`, replace **every literal `k3s-azure` with
`k3s-az`** — header comment, the kubeconfig path `_AZ_KUBECONFIG="${HOME}/.kube/k3s-azure.yaml"` →
`k3s-az.yaml`, all `[k3s-azure]` log prefixes, and the two `CLUSTER_PROVIDER=k3s-azure` usage
strings. **Do NOT** touch `ubuntu-azure`, `k3d-azure-node`, `k3d-manager-azure-key`.

### 2D — `bin/k3dm-webhook` slack arg `azure` → `az` (exactly 5 lines)
Do NOT blanket-replace `azure` — other `azure` text comes from the `provider` f-string variable and
must stay.

**Provider map (2 lines, identical) — old:**
```python
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "azure": "k3s-azure"}
```
**New:**
```python
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "az": "k3s-az"}
```

**Validation tuples (3 lines: `_resume_parts`, `_down_parts`, `_up_parts`)** — change the membership
tuple `("aws", "gcp", "azure")` to `("aws", "gcp", "az")` on each; leave the surrounding code as-is.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/cluster_provider.sh` | add `_cluster_provider_is_extra_supported` hook |
| `scripts/lib/providers/k3s-azure.sh` → `k3s-az.sh` | `git mv` + literal `k3s-azure`→`k3s-az` |
| `bin/acg-up` | `k3s-azure`→`k3s-az` (6×, incl. `source` path) |
| `bin/acg-down` | `k3s-azure`→`k3s-az` (3×, incl. `source` path) |
| `bin/k3dm-webhook` | map value + slack arg key `azure`→`az` (5 lines) |

**`scripts/lib/core.sh` is NOT in this list — do not modify it.**

---

## Rules

- `shellcheck -S warning scripts/lib/cluster_provider.sh scripts/lib/providers/k3s-az.sh bin/acg-up bin/acg-down` — zero new warnings
- `python3 -m py_compile bin/k3dm-webhook` — must pass
- **Residual checks (must be empty):**
  - `git grep -n 'k3s-azure' -- scripts/lib bin/` → no output
  - `git grep -n '"azure"' -- bin/k3dm-webhook` → no output
- **core.sh untouched:** `git diff --name-only | grep -q 'scripts/lib/core.sh'` → must be FALSE
- Smoke: `make status CLUSTER_PROVIDER=k3s-az` does not error on "unsupported provider"
  (validates the hook + core.sh fallback wiring end-to-end)
- Do NOT touch `plugins/azure.sh`, `ubuntu-azure`, `k3d-azure-node`, or historical docs

---

## Definition of Done

- [ ] `_cluster_provider_is_extra_supported` added to `cluster_provider.sh`
- [ ] Change Set 2 applied; provider file renamed via `git mv` (history preserved)
- [ ] `bin/k3dm-webhook` changed on exactly the 5 lines (no blanket `azure` replace)
- [ ] `scripts/lib/core.sh` NOT modified
- [ ] `shellcheck -S warning` passes on all shell targets
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Both residual `git grep` checks empty
- [ ] `make status CLUSTER_PROVIDER=k3s-az` smoke passes
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**After merge/verify (operator step — note in completion report):** run `make restart-webhook`
so the slack handler picks up the new `az` arg + map.

**Commit message (exact):**
```
refactor(provider): register cloud providers locally + rename k3s-azure → k3s-az
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT run the subtree pull (Claude does that; it is a prerequisite, not part of this task)
- Do NOT edit `scripts/lib/core.sh` — it is subtree-managed and already refreshed
- Do NOT add an alias for `k3s-azure` / `azure` — this is a hard rename
- Do NOT blanket-replace `azure` in `bin/k3dm-webhook` — only the 5 specified lines
- Do NOT modify `plugins/azure.sh`, `ubuntu-azure` context, VM/SSH/key names, or any historical doc
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
