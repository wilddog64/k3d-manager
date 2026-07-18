# Bug: `provider_contract.bats` test 17 asserts the pre-rename `data-layer` Application name

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/tests/lib/provider_contract.bats` (ONLY)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "provider_contract test 17 stale assertion" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/tests/lib/provider_contract.bats` — the test at lines ~460-502 (the file you are fixing)
  - `scripts/etc/argocd/applicationsets/data-git.yaml` — what the Application name is NOW
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

`f03df202` renamed the generated Application in `data-git.yaml` to fix a multi-cluster
name collision:

```yaml
name: data-layer            →   name: '{{.name}}-data-layer'
```

`provider_contract.bats` test 17 still asserts the pre-rename literal at line 495, so it
fails on the current branch.

**Verified by worktree bisect 2026-07-18:**

```
f03df202^ (before rename):  1..52  all ok
f03df202  (the rename):     51/52  — not ok 17
```

Failure output:

```
not ok 17 _hostinger_reapply_gitops_applicationsets reapplies data, services, and platform
          appsets from the current branch
# (in test file scripts/tests/lib/provider_contract.bats, line 495)
#   `[[ "$output" == *"name: data-layer"* ]]' failed
```

**Root cause:** the Phase 3 rename spec's gate list was `grep` + `yq` + `_agent_audit` on
the YAML, with **no BATS suite**. No search was done for tests consuming the renamed string.
This is the **third** occurrence of the same root cause on this branch (`4c89dabb` trivy
split → `argocd_metrics_servicemonitor.bats`; `f03df202` → this).

**Note:** the correct idiom already exists six lines below, at line 501
(`name: '{{.name}}-platform'`) — the rendered manifest keeps Go templates literal, so the
assertion asserts the template text, not an expanded value.

**Confirmed scope:** `grep -rn 'name: data-layer' scripts/tests/` returns exactly ONE hit —
line 495. No other suite is affected.

---

## Fix

### Change 1 — retarget the assertion and add a disappearance guard

**Exact old block (line 495):**

```bash
  [[ "$output" == *"name: data-layer"* ]]
```

**Exact new block:**

```bash
  [[ "$output" == *"name: '{{.name}}-data-layer'"* ]]
  [[ "$output" != *"name: data-layer"* ]]
```

The second line proves the collision-prone bare name has not come back — without it the
test would pass again if someone reverted the rename and added the templated name elsewhere.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/tests/lib/provider_contract.bats` | retarget line 495 to the post-rename name + add disappearance guard |

---

## Rules

- `bats scripts/tests/lib/provider_contract.bats` → **`1..52`, all 52 ok**
- `grep -c "name: data-layer" scripts/tests/lib/provider_contract.bats` → **`1`**
  (the disappearance assertion is the only remaining occurrence)
- `grep -c "name: '{{.name}}-data-layer'" scripts/tests/lib/provider_contract.bats` → **`1`**
- `./scripts/k3d-manager _agent_audit` — exit 0
- **No file other than the one BATS file may be touched.** In particular: do NOT edit
  `scripts/etc/argocd/applicationsets/data-git.yaml`. The YAML is correct; the assertion is stale.

---

## Definition of Done

- [ ] `provider_contract.bats` passes `52/52`
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
test(provider): retarget data-layer assertion after per-cluster rename
```

---

## What NOT to Do

- Do NOT edit `data-git.yaml` to restore `name: data-layer`. That would reintroduce the
  multi-cluster Application name collision that `f03df202` fixed, and it is live on the hub
  right now (`ubuntu-hostinger-data-layer` and `ubuntu-k3s-data-layer` both Synced/Healthy).
  Making a test pass that way would take down a working two-cluster deployment.
- Do NOT delete or skip test 17. Retarget it. A deleted test is not a passing test.
- Do NOT weaken the assertion to `[ true ]` or drop the disappearance line.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Pre-validation (already done by Claude — you should reproduce it)

Both directions were verified before this spec was written:

- With Change 1 applied: `bats scripts/tests/lib/provider_contract.bats` → `1..52` all ok.
- Mutation test: with Change 1 applied AND `data-git.yaml` reverted to `name: data-layer`,
  test 17 **fails**. So the new assertion is real, not vacuous.

---

## Process Note (why this keeps happening)

Three regressions on this branch share one cause: a spec moved or renamed content between
files, and its gate list was written from the files that came to mind rather than derived
from a search for consumers of the changed string.

**Standing rule (already recorded, restated here because it was violated again):** when a
spec moves or renames content, the gate list MUST be derived from
`grep -rln '<the changed string>' scripts/tests/` — and the resulting suites listed
individually in `## Rules`. A rename spec whose gates are only `grep`/`yq` on the changed
file itself is incomplete by construction.
