# Rename CLUSTER_PROVIDER `k3s-azure` → `k3s-az` (hard rename) + slack param `azure` → `az`

> **✅ REINSTATED (2026-06-12).** The earlier "subtree-discipline violation" was a misdiagnosis.
> `scripts/lib/core.sh` is **not** the lib-foundation subtree — the subtree lives at
> `scripts/lib/foundation/` (lib-foundation's `scripts/lib/core.sh` maps to
> `scripts/lib/foundation/scripts/lib/core.sh`). The dispatcher `scripts/k3d-manager` sources the
> foundation copy first, then sources this **local** `scripts/lib/core.sh` last — so the local
> `_cluster_provider` (with the cloud-provider allowlist) is what actually runs. Editing
> `scripts/lib/core.sh` directly is correct; it is the intended place for the allowlist. Commit
> `976a9617` was backed out on a false premise. **This spec is the right approach — implement it.**
>
> The two replacement specs are withdrawn:
> - `2026-06-12-cluster-provider-extensibility-libfoundation.md` — shipped anyway as lib-foundation
>   PR #30 (a fine library improvement, but the foundation hook is shadowed by the local
>   `_cluster_provider`, so it is NOT wired into k3d-manager's runtime).
> - `2026-06-12-cluster-provider-local-registration-and-rename.md` — WITHDRAWN (premise wrong).

**Date:** 2026-06-12
**Branch (k3d-manager):** `k3d-manager-v1.6.5`
**Files:** `scripts/lib/core.sh`, `scripts/lib/providers/k3s-azure.sh` (→ `k3s-az.sh`), `bin/acg-up`, `bin/acg-down`, `bin/k3dm-webhook`

---

## Goal

Shorten the Azure cluster provider identifier from `k3s-azure` to `k3s-az`, and shorten the
slack `/acg-up` (and `/acg-down`, `/acg-resume`) provider argument from `azure` to `az`.

**Hard rename** — the old `k3s-azure` value and the old slack `azure` arg stop working. No
alias. Decided by the user 2026-06-12.

**Not in scope (do NOT change):** `plugins/azure.sh`, VM name `k3d-azure-node`, SSH host /
kube context `ubuntu-azure`, SSH key `k3d-manager-azure-key`, NSG rule, and any `azure`
substring that is NOT the literal `k3s-azure` (CLI value) or the slack arg keys. Historical
docs under `docs/plans/`, `docs/bugs/`, `docs/retro/`, and the `scripts/lib/acg/` subtree are
point-in-time records — leave them untouched.

---

## Before You Start

- Repo: `k3d-manager` (single repo — all work here; NOT the `scripts/lib/acg/` subtree)
- Branch: `k3d-manager-v1.6.5`
- Run: `git pull origin k3d-manager-v1.6.5`
- Read: `memory-bank/activeContext.md` (the "Rename CLUSTER_PROVIDER" task entry)
- Read in full before editing: `scripts/lib/core.sh` (lines 19, 782), `scripts/lib/providers/k3s-azure.sh`, `bin/acg-up`, `bin/acg-down`, `bin/k3dm-webhook` (lines 284, 398, 643, 665, 687)
- Confirm: `git grep -c 'k3s-azure' -- scripts/lib/core.sh scripts/lib/providers bin/` matches the occurrence counts in Change Set A before you start replacing

---

## Change Set A — rename CLI value `k3s-azure` → `k3s-az`

In each file below, replace **every literal occurrence of `k3s-azure` with `k3s-az`**. These
files contain no other use of the string `k3s-azure`, so a literal find-replace is safe.

### A1 — `scripts/lib/core.sh` (2 occurrences: lines 19, 782)
Both are allowlist `case` patterns:
```
k3d|orbstack|k3s|k3s-aws|k3s-gcp|k3s-azure)            → ...|k3s-az)
k3d|orbstack|k3s|k3s-aws|k3s-gcp|k3s-oci|k3s-azure)    → ...|k3s-az)
```

### A2 — `bin/acg-up` (6 occurrences: lines 68, 70, 73, 185, 215, 569)
Includes the `case` label, the `source` path, the unsupported-provider error message, and
two string conditionals. The `source` line must point at the renamed file:
```
source "${REPO_ROOT}/scripts/lib/providers/k3s-azure.sh"  → .../k3s-az.sh
```

### A3 — `bin/acg-down` (3 occurrences: lines 11, 77, 79)
Header comment, `case` label, and the `source` path (→ `k3s-az.sh`).

### A4 — rename the provider file + its internals
```
git mv scripts/lib/providers/k3s-azure.sh scripts/lib/providers/k3s-az.sh
```
Then in the renamed `scripts/lib/providers/k3s-az.sh`, replace **every literal `k3s-azure`
with `k3s-az`** — this covers the header comment (line 2), the kubeconfig path
`_AZ_KUBECONFIG="${HOME}/.kube/k3s-azure.yaml"` → `k3s-az.yaml` (line 19), all `[k3s-azure]`
log prefixes, and the two `CLUSTER_PROVIDER=k3s-azure` usage strings.
**Do NOT** touch `ubuntu-azure`, `k3d-azure-node`, `k3d-manager-azure-key`, or `plugins/azure.sh`.

---

## Change Set B — rename slack arg `azure` → `az`

Scoped to **exactly these 7 lines** in `bin/k3dm-webhook` (2 map + 5 validation tuples). Do NOT
blanket-replace `azure` elsewhere — other `azure` text comes from the `provider` variable in
f-strings and must stay.

### B1 — provider map (lines 284 and 398, identical)
**Old:**
```python
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "azure": "k3s-azure"}
```
**New:**
```python
    _provider_map = {"aws": "k3s-aws", "gcp": "k3s-gcp", "az": "k3s-az"}
```

### B2 — provider validation tuples (lines 643, 665, 687, 2473, 2526)
On each of these **five** lines, change the membership tuple `("aws", "gcp", "azure")` to
`("aws", "gcp", "az")`. Change only the tuple, leave the rest of each line intact:

- **643 / 665 / 687** — slack arg parse (`_resume_parts`, `_down_parts`, `_up_parts`):
```python
... if len(_X_parts) >= 2 and _X_parts[1].lower() in ("aws", "gcp", "azure") else "aws"
                                                    → ("aws", "gcp", "az")
```
- **2473 / 2526** — REST endpoint provider guards (`/api/v1/cluster`, `/api/v1/cluster-resume`):
```python
            if provider not in ("aws", "gcp", "azure"):   → ("aws", "gcp", "az")
                provider = "aws"
```
These two were missed in the original draft; without them, `provider: "az"` to those REST
endpoints would silently fall back to `aws`, and the `"azure"` residual check below would fail.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/core.sh` | `k3s-azure` → `k3s-az` (2 case patterns) |
| `scripts/lib/providers/k3s-azure.sh` → `k3s-az.sh` | `git mv` + literal `k3s-azure` → `k3s-az` throughout |
| `bin/acg-up` | `k3s-azure` → `k3s-az` (6×, incl. `source` path) |
| `bin/acg-down` | `k3s-azure` → `k3s-az` (3×, incl. `source` path) |
| `bin/k3dm-webhook` | map value + provider arg `azure` → `az` (7 lines: 2 map + 5 tuples) |

---

## Rules

- `shellcheck -S warning scripts/lib/core.sh scripts/lib/providers/k3s-az.sh bin/acg-up bin/acg-down` — zero new warnings
- `python3 -m py_compile bin/k3dm-webhook` — must pass
- **Residual check (must be empty):**
  `git grep -n 'k3s-azure' -- scripts/lib/core.sh scripts/lib/providers bin/` → no output
  `git grep -n '"azure"' -- bin/k3dm-webhook` → no output
- No file other than the 5 listed targets touched (the provider file rename counts as one)
- Do NOT touch `plugins/azure.sh`, `ubuntu-azure`, `k3d-azure-node`, or historical docs

---

## Definition of Done

- [ ] Change Set A applied; provider file renamed via `git mv` (history preserved)
- [ ] Change Set B applied (7 lines only: 2 map + 5 tuples)
- [ ] `shellcheck -S warning` passes on all 4 shell targets
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Both residual `git grep` checks return empty
- [ ] `CLUSTER_PROVIDER=k3s-az ./scripts/k3d-manager` dispatch works (smoke: `make status CLUSTER_PROVIDER=k3s-az` does not error on "unsupported provider")
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**After merge/verify (operator step — note in completion report):** run `make restart-webhook`
so the slack handler picks up the new `az` arg + map.

**Commit message (exact):**
```
refactor(provider): rename k3s-azure → k3s-az and slack arg azure → az
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT add an alias for `k3s-azure` / `azure` — this is a hard rename
- Do NOT modify `plugins/azure.sh`, `ubuntu-azure` context, VM/SSH/key names, or any historical doc
- Do NOT blanket-replace `azure` in `bin/k3dm-webhook` — only the 7 specified lines (284, 398, 643, 665, 687, 2473, 2526)
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
