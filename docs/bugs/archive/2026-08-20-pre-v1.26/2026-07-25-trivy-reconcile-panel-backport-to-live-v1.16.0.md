# Bug: trivy reconcile panel fix is live-inert — backport `9fde2c43` to the tracked release branch `k3d-manager-v1.16.0`

**Repo:** k3d-manager
**Branch (do the work here):** `k3d-manager-v1.16.0`  ← the live-tracked release branch, NOT the current dev branch
**Files:** `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`, `scripts/tests/plugins/trivy_operator_observability.bats`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5 plan limit).

---

## Before You Start

- `git fetch origin`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` for the Trivy panel + appset-branch-drift context.
- Read the **origin** spec this backports: `docs/bugs/2026-07-24-trivy-reconcile-panel-query-matches-zero-lines.md` (it documents the exact query fix + why the field names must not be "simplified").
- **Branch: `k3d-manager-v1.16.0`** — do NOT commit to `main` and do NOT commit to `k3d-manager-v1.18.0`.

---

## Problem

The "Trivy Operator Job Reconcile Errors" hub dashboard panel renders **No data** on the
**live** cluster. The query fix already exists — commit `9fde2c43`
(`fix(observability): trivy reconcile panel query matched zero lines`) — but it is on
`k3d-manager-v1.18.0`, and the live hub ApplicationSet `grafana-dashboards-hub` is frozen
to `targetRevision: k3d-manager-v1.16.0`. Config committed to a newer branch is **inert**
on the cluster until the tracked branch carries it. `selfHeal: true` + `prune: true` mean a
manual `kubectl edit` of the ConfigMap is reverted, so the change **must** arrive through
git on the tracked branch.

**Root cause of the live-blank:** branch drift — the fix lives on v1.18.0, the cluster
tracks v1.16.0. This spec backports the exact same fix onto v1.16.0 so ArgoCD auto-sync
serves it to the running Grafana before v1.18.0 ships.

Verified live (2026-07-25, hub Loki, 30-day window): the corrected query
`{namespace="trivy-system",pod=~"trivy-operator.*"} | json | level="error"` returns rows;
the old `... | controller="job" | msg="Reconciler error"` returns 0.

---

## Fix

### Change 1 — cherry-pick the existing fix commit onto `k3d-manager-v1.16.0`

```bash
git checkout k3d-manager-v1.16.0
git pull origin k3d-manager-v1.16.0
git cherry-pick 9fde2c438218e595f374fe17b17fcb2d85c0d51e
```

The cherry-pick applies **cleanly** — v1.16.0 has byte-identical pre-fix content at both
touched spots (dashboard `expr` at line 230, bats pin at line 63). It changes exactly two
files (dashboard `+1/-1`, bats `+5/-2`) and no others.

If — and only if — the cherry-pick reports a conflict, do NOT force it: stop and report.
Do not hand-edit around a conflict, and do not pull in any other v1.18.0 change.

**Resulting expr on line 230 must be exactly (14-space indent):**

```
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | level=\"error\" | line_format \"{{.logger}}: {{.msg}} job={{.job_extracted}} container={{.container_extracted}} reason={{.status_reason}}\"",
```

Do NOT "simplify" `.job_extracted`→`.job` or `.container_extracted`→`.container` — the
LogQL json parser renames those keys to avoid collision with the stream labels; the short
forms resolve to `fluent-bit`/`trivy-operator` (wrong). See the origin spec's table.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | Panel 12 `expr`: filter `level="error"`, real parser field names (backport of `9fde2c43`) |
| `scripts/tests/plugins/trivy_operator_observability.bats` | Retarget the pinned expr assertion + disappearance gate for the old filter (backport of `9fde2c43`) |

---

## Rules

- Cherry-pick only — do NOT re-author the edits by hand unless the cherry-pick conflicts (then stop and report).
- Run the BATS suite: `bats scripts/tests/plugins/trivy_operator_observability.bats` — all tests pass.
- YAML parses: `python3 -c "import yaml; yaml.safe_load(open('scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml'))"`
- `_agent_audit` before reporting done — capture its exit code on its **own line** (never after `; echo`, never through a pipe).
- No files other than the two the cherry-pick touches.

---

## Definition of Done

- [ ] `git branch -r --contains <new-sha>` shows `origin/k3d-manager-v1.16.0` (and NOT only v1.18.0)
- [ ] `grep -c 'msg=\\"Reconciler error\\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **0**
- [ ] `grep -c 'controller=\\"job\\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **0**
- [ ] `grep -c 'level=\\"error\\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **≥1**
- [ ] BATS suite passes
- [ ] YAML parses
- [ ] `_agent_audit` exit code is 0
- [ ] Cherry-picked and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with the new commit SHA and task status, in a **separate commit**

**Commit message:** inherited from the cherry-pick (unchanged) —
`fix(observability): trivy reconcile panel query matched zero lines`

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the two the cherry-pick touches.
- Do NOT commit to `main` or to `k3d-manager-v1.18.0` — the target is `k3d-manager-v1.16.0`.
- Do NOT repoint the ApplicationSet, run `argocd sync`, apply the ConfigMap, or otherwise
  touch the live cluster — **Claude owns all live-cluster action and verification.**
- Do NOT pull any other v1.18.0 change along with the cherry-pick.
- Do NOT rename the panel title or change its `id`/`gridPos`.

---

## Claude-only (do NOT delegate)

After Codex pushes, Claude confirms ArgoCD auto-sync applied the corrected ConfigMap to the
live hub, then verifies the "Trivy Operator Job Reconcile Errors" panel renders the trivy
scan-failure log lines (no longer "No data").
