# Bug: `make status` does not report ApplicationSet values-branch drift

**Branch:** `k3d-manager-v1.18.0`
**Files (edit ONLY these two):**
- `bin/cluster-status`
- `scripts/tests/bin/cluster_status_values_branch.bats` (new)

**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- `git pull origin k3d-manager-v1.18.0`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the "wire
  `argocd_check_values_branch` into `make status`" follow-on to the drift detector that
  landed in `3e847b26`.
- Read IN FULL before editing:
  - `bin/cluster-status` — the whole script, especially the `=== ArgoCD ApplicationSets ===`
    and `=== ArgoCD Image Updater ===` sections; you are inserting between them
  - `scripts/tests/bin/cluster_status_image_updater.bats` — the house test pattern for this
    file is **pure `grep` assertions against the script text**, no execution, no kubectl mock
  - `scripts/plugins/argocd.sh` — the function `argocd_check_values_branch` you are calling
    (landed `3e847b26`); note it returns **0** clean, **1** on drift, **2** when Applications
    cannot be read
- Branch: `k3d-manager-v1.18.0` — do NOT commit to `main`.

---

## Problem

`argocd_check_values_branch` was added in `3e847b26` to detect the silent failure where an
ApplicationSet's `$values` source is frozen on a stale branch, leaving committed config
inert. But nothing calls it. `make status` (→ `bin/cluster-status`) already prints ArgoCD
Apps, ApplicationSets, and Image Updater health, yet a values-branch drift — the exact
condition that went unnoticed for two releases — is still invisible in the one command
people run to check cluster health.

Wire the detector into `bin/cluster-status` so `make status` surfaces drift as a first-class
line alongside the other ArgoCD sections.

---

## Why the dispatcher, not a direct source — do NOT "simplify" to `source argocd.sh`

`bin/cluster-status` runs under `set -euo pipefail` and sources only `system.sh`,
`provider.sh`, and `observability.sh`. `scripts/plugins/argocd.sh` **cannot** be sourced
directly here: its top-of-file load block references `PLUGINS_DIR` (unbound under `set -u`)
and eagerly sources `vault.sh` and `eso.sh`. Sourcing it standalone aborts with
`PLUGINS_DIR: unbound variable`.

The dispatcher (`scripts/k3d-manager`) exists precisely to set `SCRIPT_DIR`/`PLUGINS_DIR`
and lazy-load the plugin correctly. So the wiring invokes the function **through the
dispatcher as a subprocess** and interprets its exit code. This also isolates the check: a
failure inside it can never abort the status report.

---

## Fix

### Change 1 — `bin/cluster-status`: add the values-branch section

Insert a new section between `=== ArgoCD ApplicationSets ===` and
`=== ArgoCD Image Updater ===`.

**Exact old block** (this anchor is unique — it pairs the ApplicationSets `kubectl` line
with the Image Updater header):

```bash
echo "=== ArgoCD ApplicationSets ==="
kubectl get applicationsets.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster or ArgoCD CRDs not installed"

echo ""
echo "=== ArgoCD Image Updater ==="
```

**Exact new block:**

```bash
echo "=== ArgoCD ApplicationSets ==="
kubectl get applicationsets.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster or ArgoCD CRDs not installed"

echo ""
echo "=== ArgoCD Values-Branch Drift (${INFRA_CONTEXT}) ==="
_vb_out=""
_vb_rc=0
_vb_out="$("${REPO_ROOT}/scripts/k3d-manager" argocd_check_values_branch '' "${INFRA_CONTEXT}" 2>&1)" || _vb_rc=$?
printf '%s\n' "${_vb_out}" | grep -vF 'running under bash version' || true
case "${_vb_rc}" in
  0) : ;;
  1) echo "WARN ApplicationSet values-branch drift — reapply the sets with the current K3D_MANAGER_BRANCH (see above)" ;;
  2) echo "Cannot read Applications — values-branch check skipped" ;;
  *) echo "values-branch check exited ${_vb_rc}" ;;
esac

echo ""
echo "=== ArgoCD Image Updater ==="
```

**Why it is shaped this way — do NOT change these four points:**

1. **`_vb_rc` is captured with `|| _vb_rc=$?`, not a bare call.** Under `set -e`, a bare
   `argocd_check_values_branch` returning 1 (drift) or 2 (unreadable) would abort the whole
   status report. The `|| _vb_rc=$?` guard is what lets a drift finding be *reported*
   instead of killing `make status`.
2. **Output is captured with `2>&1` then reprinted.** The function writes its `INFO`
   lines, the `checked N values references` line, and the drift table to **stderr**.
   Capturing both streams keeps that human-readable detail; dropping `2>&1` would silently
   swallow it.
3. **`grep -vF 'running under bash version' || true`.** The dispatcher prints a
   `running under bash version …` banner on every invocation; it is noise in a status
   section, so it is filtered. The `|| true` is required because `grep -v` returns non-zero
   if it selects no lines, which under `pipefail` would abort.
4. **The empty first argument `''`.** `argocd_check_values_branch`'s first parameter is the
   expected branch; empty means "use `K3D_MANAGER_BRANCH`, else the checked-out branch."
   That is the intended default for a status check. The second argument pins the context to
   `INFRA_CONTEXT` so the check reads the hub regardless of the function's own default.

### Change 2 — new test: `scripts/tests/bin/cluster_status_values_branch.bats`

**Exact new file contents:**

```bash
#!/usr/bin/env bats

@test "cluster-status surfaces the ArgoCD Values-Branch Drift section" {
  run grep -nF '=== ArgoCD Values-Branch Drift' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status calls the drift detector through the dispatcher" {
  run grep -nF 'scripts/k3d-manager" argocd_check_values_branch' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status guards the drift check so set -e cannot abort the report" {
  run grep -nF '|| _vb_rc=$?' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status distinguishes drift, unreadable, and clean outcomes" {
  run grep -nF 'values-branch drift — reapply the sets' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'values-branch check skipped' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status filters the dispatcher bash-version banner from the section" {
  run grep -nF "grep -vF 'running under bash version'" bin/cluster-status
  [ "$status" -eq 0 ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/cluster-status` | Add `=== ArgoCD Values-Branch Drift ===` section invoking `argocd_check_values_branch` via the dispatcher, guarded under `set -e` |
| `scripts/tests/bin/cluster_status_values_branch.bats` | New 5-test suite asserting the section, dispatcher call, `set -e` guard, three outcomes, and banner filter |

---

## Rules

- `bash -n bin/cluster-status` — parses clean
- `shellcheck -S warning bin/cluster-status` — **zero new warnings** (baseline: run it on
  the unmodified file first; it is **0** today, so any finding is yours)
- `shellcheck -S warning scripts/tests/bin/cluster_status_values_branch.bats` — zero warnings
- `bats scripts/tests/bin/cluster_status_values_branch.bats` — prints `1..5`, all pass.
  **Paste the `1..5` line.**
- Existing coverage must not regress:
  `bats scripts/tests/bin/cluster_status_image_updater.bats scripts/tests/bin/cluster_status_observability.bats`
- **`_agent_audit` — you MUST `git add` the two target files BEFORE running it.** Every
  check inside `_agent_audit` (`scripts/lib/agent_rigor.sh`) reads
  `git diff --cached` / `git show :<file>` — **staged content only**. Run on an unstaged
  tree it audits nothing, prints only the dispatcher banner, and returns 0 — a false green,
  not a pass. Correct order:

  ```
  git add bin/cluster-status scripts/tests/bin/cluster_status_values_branch.bats
  git diff --cached --name-only
  ./scripts/k3d-manager _agent_audit
  rc=$?
  echo "rc=$rc"
  ```

  Capture the exit code on its **own line** — never after `; echo`, never through a pipe.
  **Report it as `rc=<n>`, not as its stdout.** `running under bash version …` is the
  dispatcher's startup banner, not audit output. Paste the
  `git diff --cached --name-only` list too — it must show exactly the two files.
- No other files touched.

---

## Definition of Done

- [ ] The new section is inserted between the ApplicationSets and Image Updater sections
- [ ] `grep -cF '=== ArgoCD Values-Branch Drift' bin/cluster-status` → **1**
- [ ] `grep -cF 'argocd_check_values_branch' bin/cluster-status` → **1**
- [ ] New BATS suite passes → `1..5`
- [ ] `bash -n` clean; `shellcheck -S warning bin/cluster-status` shows zero new warnings
- [ ] Existing `cluster_status_*` suites still pass
- [ ] `_agent_audit` **`rc=0`** (staged first)
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
- [ ] memory-bank updated with the commit SHA and task status, in a **separate commit**,
      then pushed — do NOT report done until BOTH commits are on
      `origin/k3d-manager-v1.18.0`

**Commit message — use the ENTIRE block below, subject AND body:**

```
feat(status): report ApplicationSet values-branch drift in make status

argocd_check_values_branch landed in 3e847b26 but nothing called it, so
the drift it detects stayed invisible in the one command people run to
check cluster health. Wire it into bin/cluster-status as an ArgoCD
Values-Branch Drift section, invoked through the dispatcher so the plugin
loads correctly and guarded under set -e so a drift or unreachable result
reports instead of aborting the status run.
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`
- Do NOT `source scripts/plugins/argocd.sh` into `bin/cluster-status` — it breaks under
  `set -u` (see the "Why the dispatcher" section). Call it through the dispatcher.
- Do NOT drop the `|| _vb_rc=$?` guard or the `|| true` after the `grep -v` — both are
  load-bearing under `set -euo pipefail`
- Do NOT drop `2>&1` on the capture — it would swallow the function's stderr detail
- Do NOT run `make status` against a live cluster to "verify" — the BATS text assertions
  are your whole test surface; **Claude runs the live `make status` check**
- Do NOT add an `_agent_audit` allowlist entry or raise `AGENT_AUDIT_MAX_IF`

---

## Out of Scope

1. **Running the live `make status`** to confirm the section renders against the real hub —
   Claude's step.
2. **The `loki` → `acg-loki` rename** — a separate spec
   (`docs/bugs/2026-07-24-observability-acg-loki-app-name-inconsistent.md`).
