# Bug: release config stays inert until someone remembers to reapply the ApplicationSets

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's "I don't see any" (the
*k3dm Alertmanager Delivery* dashboard)
**Status:** FIXED — committed; SHA reported in the completion handoff (brief below; amended 2026-09-30 after plan review: the non-release checkout is healthy/skipped, not unknown)
**Classification:** Bugfix in `docs/bugs/` (v1.40.0 already has five plan docs).
**Severity:** Medium. Nothing fails; config merged and green in CI never reaches a cluster.
**Related:** `2026-07-24-make-status-values-branch-drift-wiring.md` (the same check in `make status`,
which only runs when someone asks), CLAUDE.md "Reapply the ApplicationSets on every release".

## Evidence

- 2026-09-30: the *k3dm Alertmanager Delivery* dashboard (`1e063919`) and the vectordb Ingestion row
  and alerts (`e835ad86`) were on `k3d-manager-v1.40.0` but absent from Grafana. `grafana-dashboards-hub`
  still read `k3d-manager-v1.39.0`. `deploy_argocd_applicationsets --confirm` fixed it: 19 references
  moved to v1.40.0. `loki` and `acg-trivy-operator` lagged on the first check and were clean a minute
  later (reconcile lag, same as the v1.39.0 reapply on 2026-09-26).
- CLAUDE.md records the same class persisting for two releases: hub `trivy-operator` still on
  `k3d-manager-v1.16.0` as of 2026-07-24.

## Root cause

Each ApplicationSet renders `targetRevision: ${K3D_MANAGER_BRANCH}` at apply time, so the branch is
frozen until the next apply. A release creates a new branch and never touches the cluster. The
drift check (`argocd_check_values_branch`) exists but runs only on demand (`make status`, or at the
end of a reapply), so nothing notices when the step is skipped.

## Decision (operator, 2026-09-30)

Make it loud rather than change the tracking model: a Hermes sensor plus an approval-gated repair.
Pointing the sets at a fixed moving ref (for example `k3dm-live`) is a v1.41.0 design question and is
out of scope here.

## Codex brief

**Goal:** within about 15 minutes of the M4 checkout moving to a new release branch, Hermes reports
which Applications still read an older branch, and proposes the reapply through the Slack Approve
flow. Reconcile lag right after a reapply never alerts.

**Runs where:** Codex web is fine. Offline only: stub the runner; no ArgoCD, cluster or git remote.

**Files to touch (only these):**
- `scripts/lib/hermes/sensors.py`: new `values_branch(run, argocd_run, state, token=None,
  expected=None, threshold=3, server="argocd.3ai-talk.org")`.
  - **Expected branch:** `expected`, else env `K3DM_RELEASE_BRANCH`, else
    `run(["git", "rev-parse", "--abbrev-ref", "HEAD"], {})` (Hermes runs from the M4 checkout). It must
    fully match `k3d-manager-v\d+\.\d+\.\d+`. Otherwise **`healthy`** with evidence
    `skipped: checkout on <branch>, not a release branch` and `data.skipped = True`, and no ArgoCD call.
    It must not be `unknown`: the pager pages any sensor unknown for 6 cycles
    (`pager.SENSOR_UNKNOWN_CYCLES`), and a feature-branch checkout is a normal state, not an outage.
    A git failure is still `unknown`.
  - **Apps:** the same call and credential as `argocd` (`argocd app list -o json --grpc-web` through
    `argocd_run`, `ARGOCD_SERVICE` token). No token → `_unavailable("values_branch", ARGOCD_SERVICE)`;
    `Unauthenticated` → `unknown` with the same re-mint hint as `argocd`.
  - **Check:** mirror `_argocd_values_branch_drift` in `scripts/plugins/argocd.sh`. For each app's
    `spec.sources` (or `[spec.source]`), consider only sources whose `repoURL` contains
    `github.com/wilddog64/k3d-manager`; skip `targetRevision == "HEAD"` (the rollout demo, intended);
    every other revision must equal the expected branch. Zero sources inspected → `unknown`
    ("no k3d-manager references found"), never `healthy`: the 2026-09-26 bug
    (`2026-09-26-check-values-branch-false-clean-under-dry-run.md`) was a false clean on zero.
  - **Status:** `healthy` with `"<n> references on <expected>"`; `degraded` when any are stale, debounced
    with `_debounced("values_branch", …, threshold, state)` (3 cycles ≈ 15 min, so post-reapply lag
    never degrades). Evidence: `"<k> apps not on <expected>: <app>@<rev>, …"` (first 3, then `(+N more)`).
    `data = {"expected": …, "stale": [{"app", "revision"}…], "checked": n, "tracking_head": m}`.
- `bin/k3dm-hermes`: register `values_branch(_probe_run, _argocd_run, state, token=argo_token)` next to
  `argocd`, and add the import.
- `scripts/lib/hermes/repairs.py`: `r9` "Reapply ApplicationSets on the release branch".
  - Precondition: `values_branch` degraded, `data.expected` matches the release pattern, and
    `data.stale` is non-empty.
  - Command `["./scripts/k3d-manager", "deploy_argocd_applicationsets", "--confirm"]`, `cwd: ROOT`, env
    `{"K3D_MANAGER_BRANCH": data.expected}` so it cannot pick up a different checkout branch.
  - blast_radius: "every k3d-manager-sourced Application on the hub and app cluster re-targets the
    release branch and syncs it". `reversible: False`: synced changes, including prunes, are not undone
    by reapplying the old branch. needs_scope: "local hub kubeconfig".
  - Add `"r9": ("values_branch",)` to `_evidence`. Approval-gated like R1–R8: no auto-execution path.
- `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`: `target_scopes` add
  `"values_branch": "cicd"`.
- `docs/architecture/hermes-phase2-repair-scope.md` (R9 row); `docs/guides/hermes.md` (sensor list);
  `CHANGELOG.md`; `memory-bank/activeContext.md`, `memory-bank/progress.md`; this doc (Status → FIXED with SHA).
- Tests: `scripts/tests/hermes/test_hermes.py`, `scripts/tests/hermes/test_repairs.py`.

**Tests (offline; the ArgoCD fixture is realistic: at least 40 Applications in the real
`argocd app list -o json` shape with full `status` blocks, over 200 KB, mixing `source` and `sources`,
helm-chart sources from other repos, and two `HEAD` sources):**
1. All k3d-manager references on the expected branch → `healthy`, evidence counts them; `HEAD` and
   other-repo sources are not counted and not flagged.
2. Two apps on `k3d-manager-v1.39.0` → healthy on cycles 1–2, degraded on cycle 3; evidence names both
   as `app@rev`; `data.stale` lists them. They clear before cycle 3 → never degraded (lag case).
3. Expected-branch resolution: explicit arg beats `K3DM_RELEASE_BRANCH`, which beats the checkout;
   a checkout on `main` or `claude/foo` → `healthy` with `skipped:` evidence, `data.skipped` true, and
   **no** ArgoCD call; git failure → `unknown`. Six polls on `main` fire no page (run the pager over them).
4. Zero k3d-manager sources (only HEAD and other repos) → `unknown`, not healthy.
5. No token → unavailable; `Unauthenticated` → unknown with the re-mint hint; invalid JSON → unknown.
6. R9 proposed only when `values_branch` is degraded with stale apps; not when healthy, unknown, or
   degraded with an empty `stale`. Command and env exactly as specified; `reversible` is `False`.
7. `approve()` for R9 runs that command with `K3D_MANAGER_BRANCH` set and nothing else (stubbed).

**Mutations (paste each red run, then green; six in total):** count `HEAD` sources as stale → test 1 red; drop the
debounce → test 2 red; return healthy on zero references → test 4 red; accept any branch name as
expected → test 3 red; return `unknown` for a non-release checkout → test 3 red (the page fires); omit `K3D_MANAGER_BRANCH` from R9's env → test 6 red.

**Gates (paste output):** `make test-pytest`; `python3 scripts/check-doc-links.py`; `git diff --stat`
lists only the files above.

**Lessons from earlier reviews (2026-09-29/30):** realistic input sizes; never pass cluster JSON as a
command-line argument; every early-return path has a test; do not re-indent or restructure YAML you
were not asked to touch (`29b7f55c` moved an alert's `annotations` under `labels` and invalidated the
whole PrometheusRule); cover every numbered test or say which one you skipped and why.

**Do not change:** `scripts/plugins/argocd.sh` (the shell check stays the source of truth), the
ApplicationSet templates, R1–R8, `approve()`, `scripts/lib/foundation/`. No live commands.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(hermes): detect ApplicationSets left on an old release branch and propose the reapply as R9`.
No PR, no merge, no force-push, no `--no-verify`.
