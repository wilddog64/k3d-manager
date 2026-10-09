# Bug: release config stays inert until someone remembers to reapply the ApplicationSets

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's "I don't see any" (the
*k3dm Alertmanager Delivery* dashboard)
**Status:** FIXED — R9 sensor (a92f1f1d); 2026-10-09 recurrence → make appsets-reapply/appsets-check (5542947f)
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

## Verification (Claude, 2026-09-30)

Verified independently rather than from the report. `a92f1f1d` touches only the brief's 12 files; the
exporter change is one line with no other re-indent. `make test-pytest` 430/430 as committed. The
fixture is realistic (45 Applications, over 200 KB, mixed `source`/`sources`, other-repo charts, two
`HEAD` sources). All six brief mutations went red. `approve()` re-checks the precondition against
current records, and `_repair_runner` merges R9's env over `os.environ`, so `PATH` and `KUBECONFIG`
survive the pinned `K3D_MANAGER_BRANCH`.

**Fixed in the follow-up commit:**

1. **The token was checked before the branch.** With no ArgoCD token, a feature-branch checkout
   reported `unknown` ("credential unavailable") and would page after six polls, instead of being
   skipped with no ArgoCD dependency as the brief says. The branch is now resolved and skipped first.
   New test: a non-release checkout with no token is healthy/skipped. Codex's ordering fails it.
2. **The pager assertion could not fail.** `pager.health_events([item], {})` used a fresh state dict
   every iteration, so the six-poll streak never built. Mutation 5 went red only through the adjacent
   status assert. The loop now shares one pager state for `SENSOR_UNKNOWN_CYCLES + 1` polls, with a
   positive control (an unknown streak does page). Feeding `unknown` to the pager inside the loop now
   fails on the sixth poll.
3. **One test read the real Keychain.** The no-token case called `values_branch` without a token,
   so `_keychain_secret` queried the host. On the M4, where `k3dm-hermes-argocd-token` exists, it
   would find the token and fail `make test-pytest`. `_keychain_secret` is now stubbed in both
   no-token tests.

`make test-pytest` 431/431.

## Follow-up gap (found live 2026-09-30, not in this fix)

`values_branch` detects Applications reading an **old branch**. It does not detect an ApplicationSet
whose **own definition** changed in git. The generator list is part of the applied object, so a new
element (here `hub-pushgateway`, added in `50bd3591`) produces no Application until the sets are
reapplied, and nothing reports it. `kube-prometheus-stack` had already synced its new values from
git, while `hub-pushgateway` stayed "not found" until `deploy_argocd_applicationsets --confirm`. A
candidate check: render each `scripts/etc/argocd/applicationsets/*.yaml` with the same envsubst and
compare `spec` against the live object. That is a v1.41.0 item, not widened into this fix.

## Recurrence (2026-10-09, v1.42.0) and the make targets

`hub-vectordb` and `hub-platform-ops` were still on `k3d-manager-v1.41.0` on 2026-10-09 because the
v1.42.0 sets had been applied one at a time and never as a full set. The new *Host Disk* dashboard
and the `prometheusrule.yaml` changes did not reach the hub. The operator ran
`K3D_MANAGER_BRANCH=k3d-manager-v1.42.0 ./scripts/k3d-manager deploy_argocd_applicationsets --confirm`:
13/13 sets applied, 21 references clean, and both apps showed `Synced Healthy` on v1.42.0.

The operator's first try was `make appsets-reapply`, which did not exist. The release step should
be one command that cannot pin the wrong branch.

### Implementation spec (Codex)

**Branch:** `k3d-manager-v1.42.0`. **Files (only these):** `Makefile`, new
`scripts/tests/bin/makefile_appsets.bats`, `CHANGELOG.md` (`[Unreleased]` → `### Added`, one
bullet), and this doc's Status line.

**Change 1: Makefile targets.** Add `appsets-reapply appsets-check` to the `.PHONY` list on line 31.
Put these two targets directly after the `sync-main` target (after its recipe and the blank line
following it):

```make
## Reapply every ApplicationSet pinned to a release branch (BRANCH=, default: current branch)
appsets-reapply:
	@_b='$(BRANCH)'; \
	if ! printf '%s\n' "$$_b" | grep -Eq '^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
	  echo "[appsets-reapply] ERROR: '$$_b' is not a release branch (k3d-manager-vX.Y.Z)." >&2; \
	  echo "[appsets-reapply] Check out the release branch or pass BRANCH=k3d-manager-vX.Y.Z." >&2; \
	  exit 1; \
	fi; \
	K3D_MANAGER_BRANCH="$$_b" ./scripts/k3d-manager deploy_argocd_applicationsets --confirm

## Report Applications whose k3d-manager values source is not on BRANCH (read-only)
appsets-check:
	@./scripts/k3d-manager argocd_check_values_branch '$(BRANCH)' '$(INFRA_CONTEXT)'
```

In `help`, after the `make sync-main` line, add:
```make
	@echo "    make appsets-reapply       Reapply all ApplicationSets on the release branch (BRANCH= optional; required each release)"
	@echo "    make appsets-check         Report Applications not reading BRANCH's values (read-only)"
```

**Tests (`scripts/tests/bin/makefile_appsets.bats`).** Copy the pattern of
`scripts/tests/bin/makefile_acg_watch.bats`: copy the Makefile into `${BATS_TEST_TMPDIR}/work`, write
a stub `work/scripts/k3d-manager` that logs `$@` and `K3D_MANAGER_BRANCH` to a call log, and run
`make -C "${WORK}" <target> BRANCH=…`. **Never run make against the real repo dir** (the real
dispatcher would reach the cluster).
1. `appsets-reapply BRANCH=k3d-manager-v1.42.0` → status 0; the log holds exactly one call with args
   `deploy_argocd_applicationsets --confirm` and `K3D_MANAGER_BRANCH=k3d-manager-v1.42.0`.
2. Refused branches: each of `main`, `HEAD`, `k3d-manager-v1.42`, `feat/k3d-manager-v1.42.0`,
   `k3d-manager-v1.42.0-x` → status non-zero, output contains `not a release branch`, and the call log
   is **empty**.
3. `appsets-check BRANCH=k3d-manager-v1.42.0` → log holds
   `argocd_check_values_branch k3d-manager-v1.42.0 k3d-cluster-context` when run with
   `INFRA_CONTEXT=k3d-cluster-context`.
4. Both targets are in `.PHONY`, and `make -C "${WORK}" help` lists both.

**RED gate:** run the new suite against the pre-change Makefile (`git show HEAD:Makefile` copied to a
temp path; point `MAKEFILE` at it via an env override in the test, or copy it into a temp tree). All
four tests must fail. Paste the output. Then mutate the regex to drop the `$$` end anchor. Test 2
must go red on `k3d-manager-v1.42.0-x`. Paste it and restore. Do NOT `git stash` or `git checkout`.

**Gates (paste output):** `bats scripts/tests/bin/makefile_appsets.bats`;
`bats scripts/tests/bin/makefile_*.bats`; `git diff --stat` shows only the listed files.
**Never run** `make appsets-reapply`, `make appsets-check`, or any `make` lifecycle target in the
real repo, not even with `-n`.

**Status line:** `**Status:** FIXED — R9 sensor (a92f1f1d); 2026-10-09 recurrence → make appsets-reapply/appsets-check (<sha>)`

**Commit message (exact):**
```
feat(make): add appsets-reapply and appsets-check for the release reapply step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
**Do not:** touch `scripts/plugins/argocd.sh`, the ApplicationSets, other targets, or
`scripts/lib/foundation/`. No PR, no merge, no `main`, no `--no-verify`, nothing against a cluster.
