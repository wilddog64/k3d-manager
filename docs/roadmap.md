# k3d-manager Roadmap

> Canonical roadmap. Supersedes `docs/plans/archive/roadmap-v1.md` (archived) and the
> version numbering in the `project_roadmap` memory, whose `v1.0–v1.4` labels were an early
> vision plan that the actual release cadence outran by ~10 minor versions.
>
> **Release ledger:** `docs/releases.md` holds the full per-version history. This file holds
> the vision, the current milestone scope, and forward themes — not a per-release changelog.

---

## Vision — kops-for-k3s

k3d-manager owns **k3s/k3d clusters end-to-end**: lightweight Kubernetes at zero managed-service
cost, with an opinionated plugin stack (Vault, ESO, Istio, ArgoCD, observability) that runs
identically on a laptop, on ACG/cloud ephemeral EC2, on a permanent Hostinger VPS, on OCI Always
Free ARM64, and (planned) on a home-lab Mac Mini.

**Explicitly out of scope:** EKS / GKE / AKS. Those have dedicated tooling; k3d-manager's lane is
the self-managed k3s tier those products don't serve.

---

## Where we actually are

The project ships fast, small releases (see `docs/releases.md`). Condensed arc:

| Band | Theme delivered |
|------|-----------------|
| **v0.6–v0.9** | Core dispatcher, lib-foundation extraction, agent-rigor, vCluster, ACG sandbox plugin |
| **v1.0.x** | `k3s-aws` multi-node + CloudFormation, full-stack `make up`, ACG credential automation |
| **v1.1–v1.3** | Unified ACG (AWS + GCP), lib-acg extraction, GHCR hardening, Copilot CLI plugin |
| **v1.4.x** | Identity/SSO (Keycloak), Istio ingress, imagePullSecrets, ESO saturation fixes, tunnels |
| **v1.5.x** | **OCI Always Free ARM64 provider**, observability stack (Prometheus/Grafana/Trivy/Alertmanager), OCI object-storage backup |
| **v1.6.x** | k3dm-webhook server, Slack thread commands, AI failure analysis, CVE-scan CronJob |
| **v1.7–v1.8** | **`k3s-hostinger` permanent VPS provider**, ESO on app clusters via ApplicationSet, lib-acg absorbed into lib-foundation |
| **v1.10–v1.11** | **Provider-agnostic app-cluster Vault auth** (kube-context keyed), hub-Vault profile seam, in-cluster auto-unseal, assisted-failover watchdog |
| **v1.12** | App-image CVE auto-update pipeline (Image Updater + Trivy-gated promotion), remote operator access over Slack with RBAC + audit trail |
| **v1.13** | Webhook modularization Phase 1 (`scripts/lib/webhook/`), isolated smoke gate |
| **v1.14** | Observability fidelity/persistence + ACG lifecycle robustness + Vault per-context auth mount Phase 1 (21 bug specs; reactive hardening sprint) |
| **v1.15–v1.23** | Ongoing hardening + feature releases — see `docs/releases.md` for the per-version ledger |
| **v1.24.1** | Cluster status output contract: concise/JSON `make status`, `SERVICE=` focus, Slack emoji summary, CVE-dashboard polish |
| **v1.25.0** | Tier 1 vCluster E2E verification harness + lifecycle dry-run standardization (`DRY_RUN`, sandbox+hub deregister on `make down`) |
| **v1.26.0** | Count-agnostic k3s-aws fleet node lifecycle + E2E promotion gate (durable artifacts, Grafana/alerts) + safe reclamation of dead sandbox registrations |
| **v1.27.0** | Image signing + attestation (cosign sign/attest, three-latch BUILD/PROMOTE/ADMIT via Kyverno, Audit→Enforce) + adaptive checkout load testing |
| **v1.28.0** | Parallel multi-cloud provisioning (Phase 1–3b) + public-endpoint probe (Hermes Phase-1 first deliverable); zero-downtime rollouts deferred (hardware-gated) |

---

## Current milestone — v1.29.0 (active)

**Theme: Hermes Phase-1 — read-only operations monitoring.** An optional off-hub agent (runs on
the laptop like `bin/k3dm-webhook`, so **not** hardware-gated) that samples cluster/CI health from
existing read-only interfaces and posts a single Slack summary only on sustained, multi-signal
degradation. Hard constraints: reports-and-stops (NO mutation path in the codebase), the
k3d-manager webhook stays authoritative, least-privilege (three read-only creds, no direct
kube-apiserver credential), and LLM as last resort (non-Claude default, per-day budget, deterministic
fallback). Scope: `docs/architecture/hermes-phase1-monitoring-scope.md`.

### Workstreams — all code complete + verified

| WS | Scope | Status |
|---|---|---|
| WS0 | Read-only access model — reuse webhook bearer (GET-only) + new ArgoCD `hermes` local account (get-only) + new GitHub read-only PAT | ✅ live + DoD-verified (`can-i get`=yes, `sync`/`delete`=no; no K8s SA, no kubeconfig) |
| WS1+WS2 | Five sensors (ESO, ArgoCD per-app, reachability probe, node/data-layer via webhook, GitHub Actions) + correlator + Slack (`4e9d3e6e`) | ✅ Python stdlib-only, pytest 8/8, no mutation verb / no kubeconfig |
| WS3 | `_install_hermes_agent`/`_uninstall_hermes_agent` in lib-foundation **v0.4.15** → subtree-pulled → consumer files (`6aad603d`): launchd plist, `bin/k3dm-hermes-setup`, jitter | ✅ LaunchAgent installed, first cycle 5/5 sensors real data |
| WS4 | `docs/guides/hermes.md` (`c7fa27a8`) | ✅ passes `_doc_hygiene_check` |

### Also shipped in v1.29.0 — self-healing Vault seeders
Cluster rebuilds wipe the Vault raft; grafana + cosign KV had no bring-up seeders (`43ce7732`).
Added `observability_seed_grafana` (fresh-generate-if-absent) and fixed `signing_restore`
(`7eaaf897`: missing `_vault_login`; `ae9d8cb4`: graceful skip when the Kyverno admission namespace
is absent). Live-verified: all four remediation targets healthy. Bug doc:
`docs/bugs/v1.29.0-bugfix-signing-restore-no-login-grafana-seed-no-public-entry.md`.

### Closing condition for v1.29.0
- [x] Hermes WS0–WS4 code complete, verified, LaunchAgent installed + first cycle clean.
- [x] Vault seeder self-heal shipped + live-verified (grafana + cosign).
- [x] Reapply **all** ApplicationSets pinned to `k3d-manager-v1.29.0`, confirmed with
      `argocd_check_values_branch` — **DONE 2026-09-06**: `deploy_argocd_applicationsets --confirm`
      applied 12/12 sets; after reconcile the check reports *All Applications reference values branch
      k3d-manager-v1.29.0* (all 6 that were on `v1.28.0` flipped). Durable entrypoint added this
      release: `./scripts/k3d-manager deploy_argocd_applicationsets --confirm` (surgical reapply-all +
      self-verify; no image-updater/platform-ops redeploy).
      *Note:* the earlier scratchpad render+diff only covered `observability`/`observability-acg` —
      2 of the ~7 branch-pinned sets — so it would not have cleared all 6 drifted apps. The
      reapply-all entrypoint is what actually satisfied this condition.
- [x] Hub CPU overcommit Step 2 load-shed — **already live** (verified 2026-09-06: no loki-canary
      pods, prometheus scrape/eval 60s, retention 3d/8GB); shipped with the v1.28.0 values pin.
- [ ] `/create-pr` gate met (CI green + Copilot addressed + Gemini smoke + Claude scope), PR merged,
      tag `v1.29.0`, retro written. **Never auto-merge.**

---

## Queued milestones (scoped)

None currently queued with a committed version number. The previously queued block has all shipped
(**v1.24.1** status output contract, **v1.25.0** Tier 1 E2E harness + dry-run standardization,
**v1.26.0** fleet node lifecycle + E2E promotion gate + sandbox-registration cleanup, **v1.27.0**
image signing + adaptive checkout load) — see the arc table above and `docs/releases.md`. The
originally-queued **v1.28.0 platform zero-downtime rollouts** was deferred (hardware-gated); the
v1.28.0 tag instead shipped parallel multi-cloud provisioning + the public-endpoint probe. The next
milestone will be chosen from Forward themes below once it gets a scope doc.

### Candidate milestone — v1.42.0: k3d-manager Dot

Turn Hermes into a focused, always-on project agent that keeps operational work moving while
preserving human control. The first slice is deliberately narrow: once per day, launch the
offline `k3dm-test` suite and Tier 1 vCluster E2E independently; retain separate result,
freshness, and triage channels; investigate failures; and pause for approval before any repair
or bug-writing mutation. The two runs must never depend on each other or mask each other's
status. Accurate duration and resumable run state are part of the foundation.

Scope: [`v1.42.0-daily-offline-and-e2e-verification.md`](plans/v1.42.0-daily-offline-and-e2e-verification.md).
Tier 2 ACG/Stripe remains opt-in and is not made an unattended daily job.

Also in v1.42.0 — **Hermes alert-driven triage.** Hermes reads firing alerts from Alertmanager (read-only, through the apiserver proxy), runs a per-alert read-only
evidence recipe, links prior art, posts one Slack thread per alert, and either proposes an allowlisted repair through
the existing approval path or drafts a bug doc in its own worktree. Alerts go to a dedicated `#k3dm-alerts` channel:
`critical` and `warning` get a thread each, `info` a daily digest. No automatic code changes, PRs or silences. v1.42.0 is then at its five-plan cap;
the R10 repair (delete a failed Job superseded by a newer CronJob spec) overflows to **v1.43.0**.

Scope: [`v1.42.0-hermes-alert-driven-triage.md`](plans/v1.42.0-hermes-alert-driven-triage.md).

### Candidate milestone — v1.43.0

**Bug priority tracking.** Every bug doc gets a `**Priority:** P0`–`P3` field, which records
urgency and is separate from Severity. The vector store keeps priority and open/closed state as
non-embedded metadata, so `/ask-docs` and `find-similar-docs` label bug sources (for example
`[P1 · open]`). A `k3dm_bug_docs{priority,state}` gauge feeds a new Grafana "Bugs" dashboard (open
P0/P1, untriaged, open by priority over time), and a pre-commit check rejects new bug docs that
have no Priority. Once it lands, Claude backfills priorities on the open bugs.

Scope: [`v1.43.0-bug-priority-tracking.md`](plans/v1.43.0-bug-priority-tracking.md). Also queued
for v1.43.0: [`v1.43.0-hub-data-export-schedule.md`](plans/v1.43.0-hub-data-export-schedule.md)
(daily unattended export, 5-day retention; P1 2026-10-10, took the slot of the e2e failure-artifacts
spec, now v1.48.0),
[`v1.43.0-hub-dr-drill.md`](plans/v1.43.0-hub-dr-drill.md),
[`v1.43.0-worktree-isolated-codex-dispatch.md`](plans/v1.43.0-worktree-isolated-codex-dispatch.md)
(dispatched first: Codex work stays sequential until each spec can run in its own git worktree), and the
R10 overflow from v1.42.0, [`v1.43.0-hermes-r10-delete-superseded-failed-job.md`](plans/v1.43.0-hermes-r10-delete-superseded-failed-job.md)
(an approval-gated deletion of a failed Job whose CronJob spec has since changed, in `identity`/`monitoring`/`cicd` only).
v1.43.0 is at its five-plan cap and closed; all five plans are DONE.

### Candidate milestone — v1.43.1

**One-command hub restore and DR clean-room checks** (P1, split from v1.43.0 on 2026-10-10 so
v1.43.0 stops growing). `make hub-recover-all` rebuilds the hub, restores the data and proves it
(typed approval, resumable checkpoints that never repeat a destructive step, export compatibility,
Vault key versions and identity digests, auditable report), sharing one restore and verify engine
with the drill. The drill gains a Keychain credential allowlist (audit, then enforce) and a guard
that every destructive call targets the drill cluster. Scope:
[`v1.43.1-hub-data-recover.md`](plans/v1.43.1-hub-data-recover.md),
[`v1.43.1-dr-clean-room-checks.md`](plans/v1.43.1-dr-clean-room-checks.md). v1.43.1 is at 2 of 5
plans. Full-hub recovery on the M2 moves into the v1.47.0 candidate-hub engine.

### Candidate milestone — v1.43.2

**Bug-fix-only release, worked by parallel agents** (operator, 2026-10-10). Branch
`k3d-manager-v1.43.2`, cut from `main` after v1.43.1 merges. Each fix runs in its own dispatcher
worktree, and `land` merges them one at a time behind its lock. A batch never puts two fixes on the
same file.

- **Batch 1:** three agents in parallel, code and stubbed tests only.
  - [`offline-suite-count-floor-stale-and-partial-runs`](bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md):
    `Makefile`, `bin/k3dm-test-metrics`, `rules-acg/k3dm-tests.yaml`.
  - [`e2e-stale-alert-fires-for-an-idle-runner`](bugs/2026-10-11-e2e-stale-alert-fires-for-an-idle-runner.md):
    `prometheusrule.yaml` (`E2EVerificationStale` only), `e2e_observability.bats`.
  - [`hermes-kine-sensor-misses-dead-compaction`](bugs/2026-10-11-hermes-kine-sensor-misses-dead-compaction.md)
    (operator, 2026-10-11, **P2, dispatch first**): `bin/k3dm-hermes`, `scripts/lib/hermes/sensors.py`,
    `prometheusrule.yaml` (new `HubKineCompactionStalled`), `test_hermes.py`,
    `hermes_alert_rules.bats`, plus the operator's end-to-end regression test
    (`test_kine_compaction_stalled.py`: a stale timestamp with a healthy API and no slow queries
    fires the rule in promtool, routes to `platform-warning` and reaches the fake receiver). It lands after the e2e-stale fix because both edit
    `prometheusrule.yaml`.
  - [`hermes-kine-evidence-not-human-readable`](bugs/2026-10-11-hermes-kine-evidence-not-human-readable.md)
    (operator, 2026-10-11, P3): `scripts/lib/hermes/sensors.py` `kine` evidence only. Stall age
    first, `1.9 GiB` / `8d 9h`, so the finding survives table truncation and stops minting a
    `hermes_sensor_status` series every poll. Dispatched after the kine stall fix landed.
  - [`bug-dashboard-cannot-list-open-bugs`](bugs/2026-10-11-bug-dashboard-cannot-list-open-bugs.md)
    (operator, 2026-10-11): `bin/k3dm-vectordb-metrics`, `grafana-dashboard-bugs.yaml` and their
    tests. An "Open bugs" table under "All open bugs": Priority, Bug (title, linked), Filed, Open for.
  - [`dispatch-dashboard-landing-success-no-data`](bugs/2026-10-11-dispatch-dashboard-landing-success-no-data.md)
    (operator, 2026-10-11): `grafana-dashboard-agent-dispatch.yaml` (panel 2 only),
    `agent_dispatch_dashboard.bats`. The numerator needs `sum()` like the denominator.
  - [`checkout-loadtest-dashboard-deployed-to-hub`](bugs/2026-10-11-checkout-loadtest-dashboard-deployed-to-hub.md)
    (operator, 2026-10-11): `grafana-dashboards-acg.yaml` (in-cluster exclude),
    `grafana_dashboard_appsets.bats`, `docs/guides/grafana-dashboards.md`.
- **Batch 2:** one agent, after v1.43.1 lands, because both edit `bin/dr-drill`.
  - [`dr-drill-keep-deletes-kubeconfig`](bugs/2026-10-10-dr-drill-keep-deletes-kubeconfig.md)
  - [`dr-drill-set-u-wrappers`](bugs/2026-10-10-dr-drill-set-u-wrappers.md)
- **Not dispatched:**
  - the hub-recovery node map is deferred (superseded by `hub_data_recover`);
  - the e2e payments assertion needs only the operator's live Tier 1 rerun;
  - hub CPU overcommit (August) and data-layer `RespectIgnoreDifferences` (June) need re-triage
    against today's hub first.
- **Added at the 2026-10-15 triage** (operator-approved). Only bugs that make the release tests give
  false results:
  - [`test-all-hub-data-prune-aging-fixtures`](bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md)
    (P2, **fix first**): `hub_data.bats` test 5 uses fixed October dates against the real clock and
    5-day retention, so it has failed since about 2026-10-13. `make test` and `land --test` cannot
    pass until the test's clock is fixed.
  - [`make-test-acg-optional-context-failure`](bugs/2026-10-14-make-test-acg-optional-context-failure.md)
    (P2): probably the same test 5 failure. Rerun `make test` after the fix above and close it as a
    duplicate if it passes.
  - [`smoke-obsolete-app-prefix-fallback-m4`](bugs/2026-10-13-smoke-obsolete-app-prefix-fallback-m4.md)
    (P2): `make smoke` looks for `ubuntu-k3s-` apps and falls back to the hub, so the release gate
    fails 0/9.
- **Hub kine:** compaction resumed by itself on 2026-10-12 (288/day since). The planned hub rebuild
  is no longer needed. `hub-recover-all-rebuild` still lands, because the target itself is broken.

### Candidate milestone — v1.43.3

**Bug-fix-only patch release for the fixes that live in other repos** (operator, 2026-10-12: moved
out of v1.43.2). The k3d-manager dispatcher only works in this repo, so each fix is worked in its own
repo first. Branch `k3d-manager-v1.43.3`, cut from `main` after v1.43.2 merges.

- [`secret-store-data-puts-value-in-security-argv`](bugs/2026-10-09-secret-store-data-puts-value-in-security-argv.md)
  and [`…-reports-success-on-failed-keychain-write`](bugs/2026-10-10-secret-store-data-reports-success-on-failed-keychain-write.md):
  one agent in lib-foundation, release, then a subtree-pull on `k3d-manager-v1.43.3`.
- [`frontend-index-html-no-cache-control`](bugs/2026-10-10-frontend-index-html-no-cache-control.md):
  `shopping-cart-frontend`, branch `fix/index-html-no-cache`.
- Added 2026-10-15 (triage):
  - [`shopping-cart-frontend-keycloak-invalid-redirect-uri`](bugs/2026-10-13-shopping-cart-frontend-keycloak-invalid-redirect-uri.md)
    (P2, lowered from P1 2026-10-15): the **logout** request is rejected with "Invalid redirect uri"
    because the realm's `frontend` client has no exact post-logout URI. Login works. The fix is one
    attribute in `shopping-cart-infra`, applied by its PostSync reconcile hook.
  - [`shopping-cart-cart-lost-after-logout-login`](bugs/2026-10-13-shopping-cart-cart-lost-after-logout-login.md)
    (P2, not yet confirmed): reproduce first. It needs a working login, so it follows the P1.
- Moved from v1.43.2 (operator, 2026-10-16): never dispatched there.
  - [`dispatch-dashboard-no-per-spec-cost-or-time`](bugs/2026-10-11-dispatch-dashboard-no-per-spec-cost-or-time.md)
    (P3): `grafana-dashboard-agent-dispatch.yaml`, `bin/k3dm-dispatch-metrics` and its pytest. Readable
    token stat, a Per spec table (tokens, Codex time, time to land, runs) and two time-per-spec stats.
    This one is in k3d-manager, so it can go through the dispatcher.
- Added 2026-10-16 (operator):
  - [`cluster-up-shell-acg-watcher-writes-to-terminal`](bugs/2026-10-16-cluster-up-shell-acg-watcher-writes-to-terminal.md)
    (P3): `deploy_cluster` starts a disowned in-shell TTL watcher that keeps the operator's terminal
    as its output, and `cluster-up` then installs the launchd watcher too, so two watchers run.
    `k3s-aws.sh` and `bin/cluster-up` only; dispatcher-able.
  - [`vectordb-index-failed-by-slow-metrics-publish`](bugs/2026-10-16-vectordb-index-failed-by-slow-metrics-publish.md)
    (P3): an unguarded 120s metrics publish at the end of `index-docs.py` marks a finished index run
    failed; Hermes has the same unguarded call per poll; the bug metrics fork ~2,300 `git` processes
    per run. Guard both calls and read the bug docs with one `git cat-file --batch`. Dispatcher-able.
- Feature, added 2026-10-16 by operator call (this release is otherwise bug-fix-only; plan 1 of 5):
  - [`v1.43.3-bug-fixed-in-release`](plans/v1.43.3-bug-fixed-in-release.md): count each bug under the
    release that fixed it, derived from git (the commit that turned its Status fixed → first tag that
    contains it). Adds `k3dm_bug_fixed_in_release_docs`, a Bugs-fixed-per-release chart, a Fixed in
    column, and moves the Fixed this release tile to it. Dispatch **after** the vectordb P3 above: both
    edit `bug-tally.py` and `k3dm-vectordb-metrics`.
  - [`v1.43.3-pr-checks-dashboard`](plans/v1.43.3-pr-checks-dashboard.md) (plan 2 of 5, operator
    2026-10-16): Hermes publishes the check runs of every open k3d-manager PR each poll
    (Pushgateway job `k3dm-pr-checks`), shown on a new **k3dm PR Checks** dashboard. k3d-manager
    and lib-foundation (widened 2026-10-16, operator; shopping-cart retires after v1.50.x); Copilot
    reviews are not checks. Independent of the two above.
  - [`v1.43.3-lib-foundation-bug-tracking`](plans/v1.43.3-lib-foundation-bug-tracking.md) (plan 3
    of 5, operator 2026-10-16): lib-foundation's own `docs/bugs/` on the Bug Tracking dashboard, read
    from the lib-foundation clone at `origin/main`, a `repo` label and Repo selector, lib-foundation
    releases on its own `v0.x` tags. Claude first normalizes the 26 docs' Priority/Status headers
    in a lib-foundation PR. Dispatch **after** the PR-checks spec (both touch Hermes-side producers).

### Candidate milestone — v1.43.4 (patch)

**Bug-fix-only: AWS/ACG lifecycle reports success it has not verified** (operator, 2026-10-15). Branch
`k3d-manager-v1.43.4`, cut from `main` after v1.43.3 merges. One agent in sequence, because the fixes
share `bin/cluster-down`, `bin/cluster-up` and the e2e-sandbox path. Every fix uses mocked AWS calls,
and no test deletes a real resource.

1. [`aws-cluster-down-unverified-teardown-success`](bugs/2026-10-15-aws-cluster-down-unverified-teardown-success.md)
   (P2, first): a failed or skipped CloudFormation delete still reports green, which can leave billable
   resources behind.
2. [`acg-up-prometheus-forward-missing-after-success`](bugs/2026-10-15-acg-up-prometheus-forward-missing-after-success.md)
   (P2): cluster-up reports success while the sandbox Prometheus port-forward is down.
3. [`e2e-sandbox-argocd-crd-helm-ownership-conflict`](bugs/2026-10-15-e2e-sandbox-argocd-crd-helm-ownership-conflict.md)
   (P2): e2e-sandbox fails when the Argo CD CRDs already exist.
4. [`e2e-sandbox-does-not-provision-missing-acg-cluster`](bugs/2026-10-13-e2e-sandbox-does-not-provision-missing-acg-cluster.md)
   (P2): e2e-sandbox stops at a missing kubecontext instead of provisioning the sandbox.

### Candidate milestone — v1.43.5 (patch)

**Slack/ChatOps reliability, plus release-plan tracking** (operator, 2026-10-15; plan added
2026-10-17). Branch `k3d-manager-v1.43.5`, cut from `main` after v1.43.4 merges. No longer
bug-fix-only: plan 1 of 5 is
[`release-plan-tracking`](plans/v1.43.5-release-plan-tracking.md). It adds per-release plan rows to
the Bug Tracking dashboard, with execution, verification and dispatch kept as separate columns. It
touches the metrics producers and the dashboard, not `bin/k3dm-webhook`, so it can run in parallel
with the Slack fixes. Plan 2 of 5 is
[`release-forecast`](plans/v1.43.5-release-forecast.md). It forecasts the remaining releases to
v1.50.0 as date ranges, read from a new `docs/release-milestones.json`. A blocked release, and every
release after it, shows no date. Plan 3 of 5 is
[`dispatch-release-scope`](plans/v1.43.5-dispatch-release-scope.md). It lets the dispatch dashboard's
Window selector also pick a release, from v1.43.0 (the first ledger release) onward. Plan 4 of 5 is
[`dispatch-api-cost`](plans/v1.43.5-dispatch-api-cost.md). It prices Codex's tokens at API rates by
spec, model and landed spec, alongside the flat subscriptions. Plan 5 of 5 is
[`dispatch-claude-cost`](plans/v1.43.5-dispatch-claude-cost.md). It prices Claude's own sessions at
API-equivalent rates on the same dashboard, reusing plan 4's price file, so it dispatches after plan 4.
The release is now at the 5-plan cap; any further plan goes to v1.43.6. Most fixes edit
`bin/k3dm-webhook`, so one agent in sequence, P2s first:

- P2: [`slack-k3dm-help-no-response-during-cluster-up`](bugs/2026-10-15-slack-k3dm-help-no-response-during-cluster-up.md),
  [`slack-thread-e2e-replay-no-ack`](bugs/2026-10-14-slack-thread-e2e-replay-no-ack.md),
  [`slack-logs-explicit-job-id-mismatch`](bugs/2026-10-13-slack-logs-explicit-job-id-mismatch.md),
  [`slack-smoke-cluster-health-failure-hides-diagnostics`](bugs/2026-10-13-slack-smoke-cluster-health-failure-hides-diagnostics.md).
- P3: [`cluster-up-progress-slack-thread-missing`](bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md),
  [`cluster-down-short-job-no-slack-output`](bugs/2026-10-15-cluster-down-short-job-no-slack-output.md),
  [`e2e-slack-runner-interface-inconsistent`](bugs/2026-10-15-e2e-slack-runner-interface-inconsistent.md),
  [`slack-find-similar-docs-free-text-q-parsing`](bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md).
- Moved from v1.43.4 (operator, 2026-10-17): P2 [`hostinger-node-unresponsive-then-rebooted`](bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md)
  (no code fix; needs the hPanel activity log to say who powered the VM off) and P3
  [`frontend-cart-badge-stale-across-logout`](bugs/2026-10-17-frontend-cart-badge-stale-across-logout.md)
  (shopping-cart-frontend; approval pending).
- The 2026-10-06 Slack bugs with no Priority line go to the v1.50.1 status cleanup unless one of these
  fixes covers them.

### Candidate milestone — v1.43.6 (patch)

**Per-agent dispatch data** (operator, 2026-10-18; re-themed 2026-10-24). Branch `k3d-manager-v1.43.6`, cut from
`main` after v1.43.5 merges. Plan 1 of 5 is [`dispatch-agy-agent-ledger`](plans/v1.43.6-dispatch-agy-agent-ledger.md)
(operator, 2026-10-24): the dispatcher runs specs on agy (Gemini 4 Argon) as well as Codex, and the ledger records agent and
model for both, so per-vendor data accrues before Claude's weekly quota runs out. Split from v1.44.1's agy plan, which keeps
the dashboard. The Pod IP pool cleanup plan that was plan 1 moved to v1.43.9 to make room (Claude's call, operator-approved).

Plan 2 of 5 is [`dispatch-verified-delivery-cost`](plans/v1.43.6-dispatch-verified-delivery-cost.md)
(operator, 2026-10-18). It records the independent verifier's verdict in the dispatch ledger and
counts Codex tokens through verification, including live evidence when the spec's Acceptance block
requires it. It also adds a `review` cause to the v1.43.4 rework rate.

Plan 3 of 5 is [`dispatch-codex-solo-activity`](plans/v1.43.6-dispatch-codex-solo-activity.md)
(operator, 2026-10-18). The dispatch dashboard sees only dispatcher-launched Codex runs; this adds a row for
every Codex session (headless or interactive, by repo), and Codex's own 5-hour and weekly quota, read
from the session files. Depends on v1.43.5 plan 4's session scan. Widened 2026-10-24 (operator) to agy:
a pass-through `bin/k3dm-agy` wrapper records every agy run, dispatched or not, without reading `~/.gemini`.

Plan 4 of 5 is [`claude-context-compaction-metrics`](plans/v1.43.6-claude-context-compaction-metrics.md)
(operator, 2026-10-18). It measures what context compaction costs: compactions, files re-read after a
compaction, and Claude cost per verified spec, plus a hand tally of resumption failures and
missing-context corrections. It sets up a two-week 200K versus larger-window experiment. Depends on
v1.43.5 plan 5's Claude scan.

Plan 5, `hub-argocd-pinned-upgrade`, moved to v1.43.7 on 2026-10-24 (Claude, operator-approved). Its live
evidence is the upgrade itself, which waits for the 2026-11-03 window, and v1.43.6 should ship before then.
Plan 5 is now `agent-dashboards-split` (`docs/plans/v1.43.6-agent-dashboards-split.md`, added 2026-10-24 at the
operator's request). It splits Agent Dispatch into three linked dashboards: Dispatch, Cost and Activity.
It costs no delay, because the release waits for plan 3's E6 until ~10-26, and it lands before v1.43.7's
dashboard plans add more panels. **v1.43.6 has five plans: the cap.**

### Candidate milestone — v1.43.7 (patch)

**Cross-repo Codex dispatch** (operator, 2026-10-18). Branch `k3d-manager-v1.43.7`, cut from `main`
after v1.43.6 merges. Opened because v1.43.6 is at its five-plan cap.

First to dispatch is [`hub-argocd-pinned-upgrade`](plans/v1.43.7-hub-argocd-pinned-upgrade.md) (operator,
2026-10-18; moved from v1.43.6 on 2026-10-24). The hub ArgoCD chart floats to latest (`ARGOCD_HELM_CHART_VERSION=""`)
and has never had a planned in-place upgrade. This pins it at 10.10.5 and adds `make argocd-upgrade`, with a dry
run, before/after Application snapshots and a rollback hint. The first patch window is 2026-11-03, with 2026-11-10
as fallback. The operator runs it from the release branch. Critical (hub): needs a dispatch go.

Plan 1 of 5 is
[`codex-dispatch-cross-repo`](plans/v1.43.7-codex-dispatch-cross-repo.md). Fixes in `shopping-cart-*`,
`lib-foundation` and other repos currently go through a bare `codex exec` and never reach the dispatch
ledger. This adds `--repo`/`--branch` to `bin/k3dm-codex-dispatch`, a `repo` field on every ledger event,
and a `repo` label on the per-task series. The operator needs that data for research.

Plan 2 of 5 is [`dispatch-vendor-coordinator-model-telemetry`](plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md) (operator, 2026-10-21): record the actual agent and coordinator models on dispatch events, never inferred from a default.

Plan 3 of 5 is [`dispatch-landing-latency-human-interventions`](plans/v1.43.7-dispatch-landing-latency-human-interventions.md) (operator, 2026-10-22). It distinguishes dispatch-to-land wall-clock elapsed from the final Codex exit-to-land gap and explicitly recorded human continuation prompts, with coverage and no inferred historical zeros. It complements the cross-repo dispatch plan and helps compare coordinator autonomy without confusing waiting time with coding time.

Plan 4 of 5 is [`bug-dashboard-auto-release-selection`](plans/v1.43.7-bug-dashboard-auto-release-selection.md)
(operator, 2026-10-19). It keeps the Bug Tracking release filter on the current release automatically, without a
hard-coded version. Moved to v1.43.9 on 2026-10-24, and back on 2026-10-25 (Claude) when the operator asked for it
now; it swapped places with `dispatch-spec-and-change-complexity`, which had not started. v1.43.7 is full.

**Cut 2026-10-25, ahead of the 11-03 window** (operator, via `/create-pr`). All five plans are implemented and every
bug is fixed; the live evidence still pending carries forward without holding the release: the Vault unseal-cache
E3 and the Argo CD pin at the 10-29 rebuild, the `make argocd-upgrade` E-items in the 11-03 window (11-10
fallback), which now run from `main` or the open release branch, the cross-repo dispatch E3 at the next
shopping-cart fix, the worker/coordinator model E2 at the next `COORDINATOR=` dispatch, and the rollup-race E2
through 11-01. The `not_before` floor was removed from `docs/release-milestones.json`.

### Candidate milestone — v1.43.8 (patch)

**Release duration on Agent Dispatch** (operator, 2026-10-24). Branch `k3d-manager-v1.43.8`, cut from
`main` after v1.43.7 merges. Opened by Claude because v1.43.5, v1.43.6 and v1.43.7 are each at the
five-plan cap. Plan 1 of 5 is [`dispatch-release-duration`](plans/v1.43.8-dispatch-release-duration.md):
per release, the span from first dispatch to PR merge (recorded once in the ledger by `/post-merge`,
so the exporter stays offline) and the active time with overlapping specs counted once.
Plan 2 of 5 is [`slack-route-system-notices-to-status-channel`](plans/v1.43.8-slack-route-system-notices-to-status-channel.md)
(operator, 2026-10-24): Slack posts are routed by who started them. Alert analyses go to the status
channel (#grafana-notification), and operator- and agent-started posts stay in #acg-automation. The
operator swaps the CronJob incoming webhook so ACG expiry and rotator notices follow.

Plan 3 of 5 is [`dispatch-claude-cost-by-reference`](plans/v1.43.8-dispatch-claude-cost-by-reference.md)
(operator, 2026-10-24): each spec is charged with the Claude turns whose tool calls name it (spec file,
worktree, `SLUG=`), including spec writing, instead of all Claude usage while it was dispatched.

Plan 4 of 5 is [`hub-snapshot-weekly-schedule-and-age-retention`](plans/v1.43.8-hub-snapshot-weekly-schedule-and-age-retention.md)
(operator, 2026-10-24): a LaunchAgent runs the hub snapshot every Sunday at 02:30, and retention changes from
"newest three" to "purge verified snapshots older than 30 days, never the newest three". Dispatch go recorded 2026-10-24.

Plan 5 of 5 is [`hostinger-public-path-on-node`](plans/v1.43.8-hostinger-public-path-on-node.md)
(operator, 2026-10-24): cloudflared runs on the Hostinger node and serves `frontend.3ai-talk.org`
directly, so an M4 → Hostinger path drop is no longer a public outage (six drops 2026-10-12 to
10-22). Critical: needs a dispatch go. v1.43.8 is now full; the next plan goes to v1.43.9.

### Candidate milestone — v1.43.9 (patch)

**Pod IP pool cleanup visibility** (operator, 2026-10-18). Branch `k3d-manager-v1.43.9`, cut from `main` after v1.43.8
merges. Plan 1 of 5 is [`cni-ipam-reclaim-visibility`](plans/v1.43.9-cni-ipam-reclaim-visibility.md), moved from v1.43.6
on 2026-10-24. It publishes the sweep's per-outcome counts and the age of the oldest IP still held with no pod sandbox,
adds an alert when such an IP is held for over an hour, plus a dashboard row. Going live needs
`make refresh CLUSTER_PROVIDER=k3s-hostinger` and `make platform-ops`.

Plan 2 of 5 is [`dispatch-spec-and-change-complexity`](plans/v1.43.9-dispatch-spec-and-change-complexity.md)
(operator, 2026-10-23). It records spec size at dispatch and change size at land, and shows both per spec and
per release on Agent Dispatch, as separate columns with no combined score. Moved from v1.43.7 on 2026-10-25
(Claude), swapping with `bug-dashboard-auto-release-selection`.

Plan 3 of 5 is [`vectordb-drift-kinds-and-age`](plans/v1.43.9-vectordb-drift-kinds-and-age.md) (operator,
2026-10-24). It splits VectorDB drift into missing, stale-hash and deleted docs (the net count can read 0 while docs
are wrong) and publishes how long the oldest drift has lasted.

Plan 4 of 5 is [`vectordb-retrieval-quality-probe`](plans/v1.43.9-vectordb-retrieval-quality-probe.md) (operator,
2026-10-24). Hermes runs the v1.40.0 retrieval eval once a day against the live store and reports recall,
intrusion and outdated results; the VectorDB dashboard is reorganised into health, consistency and retrieval rows.

Plan 5 of 5 is [`orbstack-upgrade-coordinated`](plans/v1.43.9-orbstack-upgrade-coordinated.md) (operator,
2026-10-25, after an OrbStack update stopped the hub). Hermes announces an available update;
`make orbstack-upgrade` refuses while the hub is busy, updates OrbStack on a typed yes, then unseals Vault,
fixes host-network drift, refills the Pushgateway and verifies against preflight counts. Its prerequisite,
the 2026-10-12 OrbStack monitoring bug, moved from v1.44.0 to v1.43.9. v1.43.9 is now full.

### Candidate milestone — v1.43.10 (patch)

**Context threshold comparison** (operator, 2026-10-25). Branch `k3d-manager-v1.43.10`, cut from `main` after v1.43.9
merges. Plan 1 of 5 is [`context-threshold-release-comparison`](plans/v1.43.10-context-threshold-release-comparison.md):
per release, API-equivalent cost per live-verified spec (Claude, Codex and total), post-compaction re-read share with
shell reads counted, compactions, first-pass verification and continuation prompts, in one Agent Cost table. It also
fixes the verified-spec count (FIXED no longer counts; author time, not committer time). The operator asked for
v1.43.9; v1.43.9 was full, so Claude split it here (2026-10-25). Read it before changing the compaction threshold.

Plan 2 of 5 is [`claude-quota-exhaustion-availability-telemetry`](plans/v1.43.10-claude-quota-exhaustion-availability-telemetry.md)
(operator, 2026-10-25): P3 enhancement recording Claude five-hour/seven-day quota-exhaustion,
scheduled reset versus observed resumption, confirmed quota-induced wait and coordinator availability.
A provider-neutral schema permits later Codex/Gemini adapters, but this plan does not add automatic
failover. Filed after the first observed five-hour quota cap; v1.43.8 and v1.43.9 are both full.
Implementation waits for v1.43.10 and operator dispatch approval.

Plan 3 of 5 is [`spec-and-fix-quality`](plans/v1.43.10-spec-and-fix-quality.md) (operator, 2026-10-25):
P3 enhancement measuring spec quality (rework causes, review and independent-verifier results, spec
edits after dispatch, per spec) and fix quality (escaped defects linked by a `**Caused by:**` bug-doc
header, per spec and per release), as separate columns with no combined score. Depends on v1.43.9's
complexity plan. v1.43.10 has 3 of 5 plans.

### Candidate milestone — v1.44.0

**Cloud-request trust and operator acceptance.** The cloud bridge treats write access to the
`cloud-requests` branch as enough to submit a request, and `requested_by` is unsigned. v1.44.0
authenticates the submitter, lets one request route its Slack notices to an approved channel, and
turns the operator's manual acceptance checks into repeatable scenarios with evidence. Branch
`k3d-manager-v1.44.0`, cut from `main` after v1.43.2 merges.

Bug fixes carried into v1.44.0 (operator, 2026-10-12; found when the OrbStack upgrade restarted the hub):
- `docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md` (P2): the watchdog retries for up to a minute while Vault boots.
- `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (P3): a read-only `vault_seal` Hermes sensor; no repair.
- `docs/bugs/2026-10-12-orbstack-update-is-invisible-to-monitoring.md` (P3; **moved to v1.43.7 on 2026-10-25**, prerequisite of v1.43.9 plan 5): Hermes publishes OrbStack's version and `orbctl update --check` hourly; email-only `OrbStackUpdateAvailable` alert and an "OrbStack upgraded" dashboard annotation. Phase 2 (scheduled unattended `orbctl update`) waits for both Vault fixes and an operator-approved restart window.
- Added 2026-10-15 (triage):
  - `docs/bugs/2026-10-13-hermes-alert-delivery-probe-unknown-hides-error.md` (P2): `alert_delivery`
    shows `unknown` with no reason. Two later docs about the same symptom were merged into it.
  - `docs/bugs/2026-10-15-offline-suite-failing-no-email-after-40m.md` (P2): start with read-only checks
    of the rule, ALERTS and Alertmanager state.
  - `docs/bugs/2026-10-15-bug-tracking-stacked-chart-cross-comparison-readability.md` (P3): the same
    dashboard as the lifecycle row.

| Spec | What it adds |
|---|---|
| [`v1.44.0-cloud-request-submitter-authentication.md`](plans/v1.44.0-cloud-request-submitter-authentication.md) | Verify which agent submitted a request before the action and argument allowlists run. |
| [`v1.44.0-cloud-request-slack-notification-routing.md`](plans/v1.44.0-cloud-request-slack-notification-routing.md) | A request may name an approved channel alias; nothing else changes the global `SLACK_CHANNEL_ID`. |
| [`v1.44.0-operator-acceptance-automation.md`](plans/v1.44.0-operator-acceptance-automation.md) | An acceptance harness with explicit oracles; pilot on the k3dm Tests dashboard. |
| [`v1.44.0-bounded-index-metrics-diagnostics.md`](plans/v1.44.0-bounded-index-metrics-diagnostics.md) | One read-only bridge action that explains a gap in the vector-store index-age panel. |
| [`v1.44.0-bug-lifecycle-metrics.md`](plans/v1.44.0-bug-lifecycle-metrics.md) | Bug age, reopen rate and fix verification: `**Filed:**`, `**Recurred:**` and `**Verified by:**` lines, `make bug-close` (closes only after the named regression test passes), pre-commit checks, and a Lifecycle row on the Bug Tracking dashboard. Operator request 2026-10-10. |

Also in v1.44.0, as a how-to rather than a spec: an inventory of every request channel (Slack,
cloud bridge, Hermes, CLI, local agents) and how each is authorized today (see
[Engineering-contract gaps](#engineering-contract-gaps-assessed-2026-10-10)).
[`v1.44.0-bug-lifecycle-dashboard.md`](plans/v1.44.0-bug-lifecycle-dashboard.md) was folded into
v1.43.0 and is superseded. v1.44.0 is at its five-plan cap.

### Candidate milestone — v1.44.1 (patch)

**Cloud-bridge Tier 2 dispatch** (operator, 2026-10-17). Branch `k3d-manager-v1.44.1`, cut from
`main` after v1.44.0 merges. Split out because v1.43.4 is bug-fix-only, v1.43.5 and v1.44.0 are at
their five-plan caps, and this plan depends on v1.44.0's submitter authentication. Plan 1 of 5 is
[`cloud-bridge-e2e-sandbox`](plans/v1.44.1-cloud-bridge-e2e-sandbox.md): a cloud session may run
`make-e2e-sandbox` (Tier 2 against an existing sandbox; `e2e-sandbox-provision` stays refused)
under the `cloud-runner` token, with a sandbox lock on every Tier 2 entry path, no lifecycle
overlap, pattern redaction of job output, and a Slack notice per run. It reverses v1.41.0's
explicit exclusion of `e2e-sandbox`.

Plan 2 (operator, 2026-10-23: "let's do v1.44.0"; placed in v1.44.1 because v1.44.0 is at its cap and
this depends on its submitter authentication): **agents in Slack threads, first slice.**
`@codex dispatch <spec>` and `@gemini review <task>` from the operator's Slack identity run through
the relay, the webhook allowlist and `make codex-dispatch`, and each agent replies in the thread when
its step finishes. Design and limits: [agents working together in Slack
threads](#candidate-theme--v2x-agents-working-together-in-slack-threads). Spec to be written.

Plan 3 (operator, 2026-10-24: "we should also track each agent's 5-hour session comsuption in agent
dispatch dashboard in a proper rlease"): [`dispatch-agent-five-hour-window-usage`](plans/v1.44.1-dispatch-agent-five-hour-window-usage.md).
A **Session windows** row on the agent dispatch dashboard shows each agent's 5-hour and 7-day used
percent, from Codex rollout files and the statusline's usage cache (no API call, no credential),
and how much of the 5-hour window each Codex dispatch used. agy shows "no source" until it has
one. Depends on v1.43.8's Claude cost-by-reference plan.

Plan 4 (operator, 2026-10-24: add Gemini 4 Argon "into current workflow"): [`dispatch-agy-agent`](plans/v1.44.1-dispatch-agy-agent.md).
`make codex-dispatch AGENT=agy` runs a spec on `agy` (default `gemini-4-argon-medium`, validated
against `agy models`) through the same worktree, ledger and land flow as Codex. A commit by the agent
makes the task unlandable, and side-by-side runs of one spec land only one. `gemini.sh` reads its
models from `agy models` instead of a stale hardcoded list.

Plan 5 (operator, 2026-10-24: "try each agent as a primar coorindator"): [`coordinator-rotation-trial`](plans/v1.44.1-coordinator-rotation-trial.md).
Claude, Codex and agy each take the coordinator role for a period. `bin/k3dm-coord` records each
activity (bug sweep, spec writing, review, land, live check) with the agent's 5-hour and weekly used
percent at its start and end. A **Coordinator** row shows quota used per activity kind per agent,
alongside the outcomes: specs landed, bugs closed, rework rounds and defects found later. Live checks
stay with the operator or Claude, even in the agy period. Depends on plans 3 and 4.
**v1.44.1 is now at its five-plan cap.**

### Candidate milestone — v1.44.2 (patch)

**Cloud-bridge offline test diagnostics** (operator, 2026-10-23: "update docs/roadmap to include
their specs"). Branch `k3d-manager-v1.44.2`, cut from `main` after v1.44.1 merges. Plan 1 of 5 is
[`cloud-bridge-offline-test-run-diagnostics`](plans/v1.44.2-cloud-bridge-offline-test-run-diagnostics.md):
a reader-scoped cloud action returns the most recent recorded offline test run, with its failing
suites, missing stages and bounded, redacted failure reasons. No test runs remotely, and no raw log
leaves the laptop. It follows the 2026-10-20 `test-all` alerts the operator could not triage while away.

Plan 2 (operator, 2026-10-23: "go ahead") is
[`command-ledger-and-cluster-reconciliation`](plans/v1.44.2-command-ledger-and-cluster-reconciliation.md):
every webhook job gets a command id, an explicit target and a lease (retries return the first job;
a lost job is `lost`, not `failed`), and a read-only per-cluster desired/observed record reports
stale signals and drift. No auto-repair in this slice. It follows the 2026-10-23 tunnel, shared
`observability-acg` and snapshot-age bugs. Design review pending before dispatch.

Plans 3 and 4 (operator, 2026-10-24: "plan those two caveats with proper release"; specs to be
written). Both depend on v1.44.1's coordinator rotation trial, so this is the first release they can
go in:
- **Coordinator activity analysis.** Use at least one week of the trial's per-activity data to test
  the 2026-10-24 impression that a Claude bug sweep uses the weekly quota slowly. Fill any
  instrumentation gaps the first week shows. Write the spec after Claude's coordinator week.
- **Codex as coordinator.** The rules and session setup for an interactive Codex coordinator period:
  how it starts, which instruction file it follows, and how it hands live checks to the operator.
  Write the spec before Codex's period starts.

### Candidate milestone — v1.44.3 (patch)

**Cloud-bridge Vault health** (operator, 2026-10-23, same request). Branch `k3d-manager-v1.44.3`, cut
from `main` after v1.44.2 merges. Plan 1 of 5 is
[`cloud-bridge-vault-health`](plans/v1.44.3-cloud-bridge-vault-health.md): one fixed reader-scoped
action, `vault-status`, for `hub` or `hostinger` only. It separates sealed, unreachable, Kubernetes
API down and ESO failing, with no token and no unseal. It follows the 2026-10-20 Hostinger 502 incident.

Plan 2 is [`feature-flags-first-slice`](plans/v1.44.3-feature-flags-first-slice.md) (operator,
2026-10-23: "go for it"): flagd on the ACG sandbox only (stage 1; Hostinger is a later, gated one-line stage), one `basket-cart-summary` flag in
`shopping-cart-basket`, per-variant metrics and a rollout-health dashboard, and `make flag-set` recording
each flip on the v1.44.2 command ledger. Depends on v1.44.2 and on v1.43.7's cross-repo dispatch.

Plan 3 (roadmap only; spec not written) is **`dispatch-prior-art-usage`** (operator, 2026-10-24: "can we build
this ... in the future/roadmap"). It makes prior-art lookup part of the dispatcher contract and measures whether
agents use it. It waits for v1.43.7's dispatch dashboards and v1.43.9 plan 4 (retrieval quality probe), so usage is
measured against a retriever already known to be healthy.

| Step | What is recorded | Source |
|---|---|---|
| Prior-art lookup | `prior_art` ledger event: top 5 paths, scores, indexed revision; or `unavailable`/`skipped` with reason | dispatcher runs the existing `search()` on the spec's Problem text at `codex-dispatch`, excludes the spec itself, adds the list to the agent prompt |
| Documents read | paths the agent reports reading | a `Prior-art-read:` section the prompt asks for, checked against the list |
| References cited | paths named in the landed commit | `Prior-art:` commit trailer, parsed at `codex-land` |
| Outcome | resumes (rework) and the verify result | already in the ledger |

Metrics: share of tasks with a lookup, docs retrieved per task, docs read, docs cited, lookups unavailable or
skipped, and resumes plus verify-pass rate split by "cited prior art" yes/no. A **Release knowledge usage** row
goes on the Agent Dispatch dashboard, not Agent Activity, because the data exists only for dispatched tasks and
should follow the release Window.

Decisions for the spec:
- **The lookup is advisory.** An unavailable store records `unavailable` and never blocks a dispatch, the same
  rule as `make find-similar-docs`.
- **"Read" is self-reported at first.** Observing it would mean parsing tool calls in `~/.codex` session files,
  and the exporter is limited to model, usage, mode and repo. Widening that needs the operator's explicit go.
- **The rework comparison is correlation, not proof.** Tasks with obvious prior art may simply be easier, and
  dispatch volume is a few tasks a week. The panels show `n` beside every rate, and the guide says to draw no
  conclusion below about 30 tasks per group.
- **Same contract for every agent.** It applies to Luna, agy and the vendor-LLM trial, so they stay comparable.

### Candidate milestone — v1.45.0

**Docs drift detection.** Facts that can be derived from code (module tables, route tables,
make targets, line counts) move into generated blocks that `make docs-regen` rewrites and
`make docs-check` gates in CI and pre-commit. Standing docs declare the code they describe with a
`covers:` line, and a weekly Hermes digest posts to Slack each doc whose covered code has changed
substantially since the doc was last edited; far-behind docs get a drafted bug doc. Hermes never
edits a doc. Hermes also publishes per-doc drift to the hub Pushgateway for a new Grafana
"Docs Health" dashboard, with one `info` rule that fires if the check stops running. Prompted by the 2026-10-09 audit that found all four sampled docs stale.

Scope: [`v1.45.0-docs-drift-detection.md`](plans/v1.45.0-docs-drift-detection.md). Also queued for
v1.45.0: [`v1.45.0-cve-remediation-terminal-notifications.md`](plans/v1.45.0-cve-remediation-terminal-notifications.md),
[`v1.45.0-node-tunnel-fault-drill.md`](plans/v1.45.0-node-tunnel-fault-drill.md),
[`v1.45.0-alert-intake-draft-bugs.md`](plans/v1.45.0-alert-intake-draft-bugs.md) (a long-firing or recurring alert drafts a bug doc outside the repo for the operator to promote), and
[`v1.45.0-test-metrics-log-retention.md`](plans/v1.45.0-test-metrics-log-retention.md) (moved from v1.43.0). v1.45.0 is at its five-plan cap.

### Candidate milestone — v1.45.1 (patch)

**Bug-count questions in plain English.** Slack count questions that miss the regex router are
translated by the model into a small query object (releases, priority, state, Filed date range),
validated against a closed schema, and answered by `bug-tally`. The model never sees a bug doc or
produces a number, and every reply states what was counted. Amended 2026-10-12 (operator): a follow-up in the same
Slack thread (`ask-docs how about v1.43.2`) reuses the thread's query with the named field changed,
and count replies list the docs they counted instead of `Sources: none`. Split into a patch release because
v1.45.0 is at its five-plan cap (Claude, 2026-10-10); it also needs the v1.44.0 Filed date. Scope:
[`v1.45.1-bug-count-query-translation.md`](plans/v1.45.1-bug-count-query-translation.md).

**Engineering Decision Digest** (operator, 2026-10-11). One digest answers: what did I request,
which requests became specs, what did Claude and Codex complete, what changed without my explicit
approval, and which decisions wait on me. Approval is recorded **in the spec** (`**Approval:**
explicit|standing|pending` header) and on agent commits (`Approval:` trailer, or `spec <path>` to
inherit an approved spec), enforced by a new `commit-msg` hook and derived from git by
`scripts/decision-digest.py`. Surfaces: `make decision-digest`, a "k3dm Decision Digest" Grafana
dashboard (incl. spec approval by release) and an `/ask-docs` fast path. Scope:
[`v1.45.1-engineering-decision-digest.md`](plans/v1.45.1-engineering-decision-digest.md).

Also queued: [`v1.45.1-codex-model-routing-and-efficiency.md`](plans/v1.45.1-codex-model-routing-and-efficiency.md) — optional operator-approved Luna/Astra Codex model routing and per-task Grafana efficiency metrics; depends on v1.43.2 dispatch telemetry, no automatic escalation.

Also queued: [`v1.45.1-cve-post-remediation-rescan-verification.md`](plans/v1.45.1-cve-post-remediation-rescan-verification.md) — correlate each deployed immutable digest and targeted CVE list with a fresh post-deployment scan; distinguish “applied and healthy” from “CVE eliminated” in Grafana. Coordinate with v1.45.0 terminal notifications.

Also queued: [`v1.45.1-per-suite-test-metrics.md`](plans/v1.45.1-per-suite-test-metrics.md) — publish independent BATS/Python suite results with parent-child run correlation, prevent double-counting in Grafana, and preserve existing test exit-code semantics.

Bug carried here (triage 2026-10-15): [`repeated-cve-remediation-needs-research`](bugs/2026-10-13-repeated-cve-remediation-needs-research.md) (P2 research), alongside the rescan spec.

v1.45.1 is now **full at 5 of 5 plans**; branch `k3d-manager-v1.45.1` is cut from `main` after v1.45.0 merges.

### Candidate milestone — v1.45.2 (patch)
**VectorDB indexing provenance and freshness dashboard** (operator, 2026-10-15): distinguish last attempt, last successful indexing, runtime duration, tracked/fetched Git SHA and last fully indexed SHA; do not infer successful indexing from `noop` or zero backlog. Scope: [`v1.45.2-vectordb-index-provenance-dashboard.md`](plans/v1.45.2-vectordb-index-provenance-dashboard.md). Complements v1.44.0 bounded read-only index diagnostics. v1.45.2 had **2 of 5 plans** before the Gemini usage proposal.


**Engineering Work Tracking / spec lifecycle** (operator, 2026-10-14). v1.45.1 already has a full five-spec load and ships the Decision Digest approval metrics. Extend that existing collector and dashboard with an **independent implementation status**, verified completion, and per-release five-spec capacity, without mixing bug counts with feature specs. Link from Bug Tracking to the spec view. Specification authored on the current v1.43.2 branch; implementation after v1.45.1 lands. Scope: [`v1.45.2-engineering-work-tracking.md`](plans/v1.45.2-engineering-work-tracking.md). v1.45.2 currently has **1 of 5 plans**.


**Gemini embedding API usage and quota visibility** (operator, 2026-10-15): instrument actual embedding HTTP attempts including retries and 429s, cache reuse, durable Pacific-day totals, and optional operator-configured daily cap; show trends and unknown quota explicitly in existing VectorDB dashboard. Scope: [`v1.45.2-gemini-embedding-usage-quota-visibility.md`](plans/v1.45.2-gemini-embedding-usage-quota-visibility.md). v1.45.2 is now **3 of 5 plans**.

**Selective memory-bank RAG indexing** (operator, 2026-10-15): index allowlisted current `memory-bank/` context as stable, content-hashed chunks with source provenance, safety exclusions, advisory retrieval semantics, and correct file-vs-chunk metrics. Complements the same-release index provenance and Gemini quota specs. Scope: [`v1.45.2-memory-bank-selective-vector-indexing.md`](plans/v1.45.2-memory-bank-selective-vector-indexing.md). v1.45.2 is now **4 of 5 plans**; scheduling remains subject to operator triage.

Bug carried here (triage 2026-10-15): [`vectordb-corpus-axis-fractional-ticks`](bugs/2026-10-15-vectordb-corpus-axis-fractional-ticks.md) (P3), the same dashboard as the provenance spec.

### Candidate milestone — v1.45.3 (patch)

**Mac workstation protection for the two operator MacBooks** (operator, 2026-10-23). Everything
security-related so far watches the cluster: Trivy, cosign and Kyverno at admission, and Falco
(v1.51.0) on Linux nodes only. The laptops get nothing beyond Apple's built-ins. Yet they hold the
login Keychain, the SSH keys and the GitHub tokens, and they run agents that execute code. Malware
that rewrites itself defeats signature checks such as XProtect, so this release relies on allowlists
and watching behaviour instead. It needs no cluster changes and nothing from v1.44.x or v1.45.x.

| Piece | What it does | Rollout |
|---|---|---|
| Santa allowlist | Blocks any program that is not allowed. A changed binary gets a new fingerprint, so code that rewrites itself is blocked, not missed. | Monitor-only for two weeks on both Macs, then review what it logged. Switch to blocking only after the operator approves. |
| BlockBlock | Alerts when anything installs itself to run at startup, the step almost every info-stealer needs. | Alert only. |
| LuLu | Outbound firewall that asks before a new program connects out, to catch data being sent away. | Allow the agents, Homebrew, git and kubectl first; alert on anything else. |
| osquery | Reports startup items, Keychain access and newly allowed binaries to the hub, so the v2.6.4 triage loop also covers the laptops. | Read-only queries on a schedule, small volume. |
| Keychain hygiene | The login Keychain locks when the laptop is idle; no "Always Allow" on token items. | Checklist in the guide. |

Constraints:
- Installing and configuring the tools is the operator's job. Claude writes the spec, the
  configuration and the guide, and runs no privileged or system-extension change on either Mac.
- Santa stays monitor-only until the operator approves blocking.
- The osquery output must never carry secret values, Keychain item contents or full command lines.
  It sends only names, paths and counts, under the same label rules as the Falco plan.
- Agent sandboxes (the Codex seatbelt and the ssh-config guard) are kept, not replaced.

Deliverables: a `docs/guides/` page for Mac workstation protection, and one plan doc. v1.45.3
holds **1 of 5 plans** (spec not yet written). Branch `k3d-manager-v1.45.3` is cut from `main`
after v1.45.2 merges.

### Candidate milestone — v1.46.0

**Hermes self-recovery via the webhook.** When `HermesNotRunning` fires, Alertmanager routes it to a
new webhook route that diagnoses the Hermes LaunchAgent with a fixed routine (no model): not loaded,
interpreter missing (reports the `brew install`), mid-cycle, or on cooldown are reported only;
otherwise it runs `launchctl kickstart` at most once an hour. Every outcome posts to Slack. Prompted
by the 2026-10-09 exit-78 outage.

Scope: [`v1.46.0-hermes-not-running-recovery.md`](plans/v1.46.0-hermes-not-running-recovery.md).

**Offsite hub watch from Hostinger.** Hostinger runs two independent checks of the hub: a blackbox
probe of a public endpoint (`argocd.3ai-talk.org/healthz`) and a one-series `/federate` read of the
hub Prometheus. When both fail, `HubExternallyUnreachable` sends email at 10 minutes and SMS at 30.
When only the Prometheus read fails, `HubPrometheusUnreachable` sends email. A stale Hermes
heartbeat alerts only while the hub is reachable. Planned downtime takes a `make hub-watch-silence`
maintenance silence. Scope:
[`v1.46.0-hostinger-offsite-hub-watch.md`](plans/v1.46.0-hostinger-offsite-hub-watch.md).

**Weekly DR drill, unattended** (operator, 2026-10-11). A GUI LaunchAgent on the M2 runs the drill
on Sunday 05:00 in an explicit unattended mode. That mode requires the `enforce` Keychain guard,
refuses on a locked keychain, never widens an ACL, and writes a failed result on refusal so
`DRDrillFailed` fires the same day. The M4 pulls and publishes daily, so the M2 never holds the data
repo key. Scope: [`v1.46.0-scheduled-dr-drill.md`](plans/v1.46.0-scheduled-dr-drill.md). v1.46.0 is
**full at 5 of 5 plans** (also `v1.46.0-dr-drill-dashboard.md`,
`v1.46.0-hub-data-backup-integrity.md`); the next v1.46.0 item goes to v1.46.1.

### Candidate milestone — v1.46.1 (patch)

Both items are from the operator, 2026-10-17. No specs have been written yet. Branch
`k3d-manager-v1.46.1`, cut from `main` after v1.46.0 merges.

**Monthly in-place hub rebuild.** The weekly drill restores into a separate drill cluster, so it
never exercises the in-place path. That path is the restarts of hub dependents after the restore
(Keycloak, Grafana, argocd-server, OpenLDAP) and the `make up` steps that read restored data. It is
where the 2026-10-16 LDAP admin-bind bug lived
(`docs/bugs/2026-10-16-cluster-up-ldap-seed-admin-bind-invalid-credentials.md`).

The first rebuild is the 2026-10-29 drill. After that, the hub is rebuilt in place once a month,
attended, from the operator's tmux shell (the Keychain must be readable). The scope:

- A runbook, with a fresh export taken immediately before the rebuild.
- An ArgoCD API token reissue step, because a rebuild invalidates every token.
- The result is published to the Pushgateway: a success flag, the step that failed, and the RTO
  from `_hub_data_record_rto`.
- A "Last in-place rebuild" row on the v1.46.0 DR drill dashboard.
- A `HubRebuildStale` alert after 35 days with no successful rebuild (email, `platform-warning`).

Tests stub the publisher; they never push to the live hub's Pushgateway.

**Maintenance page instead of the Cloudflare error page.** While the hub is down, the public hub
hostnames show Cloudflare's tunnel error (530 / 1033). This applies to a planned rebuild and to an
outage. Instead, a Worker on those routes passes requests to the origin. When the origin is
unreachable, the Worker returns a small static maintenance page.

- The page must carry HTTP **503 with `Retry-After`**, never 200. The v1.46.0 offsite hub watch
  probes `argocd.3ai-talk.org/healthz`; a 200 from the Worker would hide a real outage from it.
- A planned window is switched on explicitly, and pairs with `make hub-watch-silence`.
- The page shows the window's expected end time.
- The Worker is deployed with `make`, like the slack-relay Worker.

Check whether Cloudflare's own custom error pages are available on this plan before choosing the
Worker.

**One E2E command with runner selection** (operator, 2026-10-23). Plan 1 of 5 is
[`e2e-unified-runner-command`](plans/v1.46.1-e2e-unified-runner-command.md): `k3dm e2e-remote
RUNNER=m2|m4|aws` with a validated runner per execution environment, replacing the three separate
E2E commands, with a deprecation path for `e2e-sandbox`. Split out of a v1.43.5 P3 bug, which keeps
only the error-message fix. Design spec; Files and Acceptance are written when v1.46.1 starts.

### Candidate milestone — v1.47.0

**Infra e2e and promotion gate — the only item in this release** (operator, 2026-10-10). `make
hub-e2e REF=<release branch>` builds a full candidate hub on the M2 from that commit (the M2's
other clusters are stopped for the run), proves it cannot act on the outside world, checks every
required Application, Vault/ESO, Keycloak/LDAP logins, Prometheus rules, Alertmanager, dashboards
and `make smoke`, and records the platform RTO (absorbs the former v1.46.0 full-recovery spec,
option A). `make appsets-reapply` and `make hub-up` then refuse without a passing run for the exact
commit, unless a recorded override is given. Scope:
[`v1.47.0-hub-e2e-promotion-gate.md`](plans/v1.47.0-hub-e2e-promotion-gate.md).

### Candidate milestone — v1.48.0

**Scheduled baseline load test** (operator, 2026-10-11, after the Checkout Load Test dashboard was
found empty). A light 5–10 VU baseline every 12h keeps the k6 panels filled, plus a full stress run
as a gate for major releases. Moved from the never-cut v1.41.1. Credentials and preflight come
first. Its life is bounded: v2.0.0 retires shopping-cart and v1.50.0 re-points the load test.
Scope: [`v1.48.0-loadtest-credentials-and-preflight.md`](plans/v1.48.0-loadtest-credentials-and-preflight.md),
then [`v1.48.0-scheduled-baseline-loadtest.md`](plans/v1.48.0-scheduled-baseline-loadtest.md).

**Operational quality and incident severity** (operator, 2026-10-12; specs written 2026-10-12). A
"k3dm Operational Quality" dashboard, rolling 30 days, with six headline numbers and targets:
availability ≥99.5%, deployment success ≥95%, DR drill pass rate 100%, automation success ≥90%,
security SLA ≥95%, detection coverage ≥95%; a weekly history of the rates; and a row per severity.
Severity levels: SEV1 hub unavailable or unrecoverable data loss (frequency, recovery time); SEV2
Argo CD unavailable or a production-like app outage (frequency, duration); SEV3 agent task fails or a
monitoring panel misleads (frequency, recurrence); SEV4 minor defect with no operational impact
(backlog, resolution time).
- [`v1.48.0-incident-severity-records.md`](plans/v1.48.0-incident-severity-records.md): bug docs gain a new
  `**Incident:** SEV1–SEV4` line (the existing `**Severity:**` line is left as is) and
  `**Detected by:** alert | sensor | test | human`; the bug-docs exporter counts both over 30 days.
- [`v1.48.0-operational-quality-dashboard.md`](plans/v1.48.0-operational-quality-dashboard.md): hub Prometheus keeps
  3 days and Pushgateway gauges are time-weighted, so a new `bin/k3dm-quality-metrics` computes per-run
  30-day and weekly ratios from durable records (a new webhook deployment ledger, drill results, the
  dispatch ledger, classified bug docs) and pushes the finished ratios. Closed weeks are frozen in a
  `weekly-summary.jsonl` (all weeks shown; `--rebuild` recomputes), and the local ledgers ride in each
  hub-data export, age-encrypted, so the v2 → v3 history survives a lost laptop. Key availability and deployment measures to the
  platform, not shopping-cart, which v2.0.0 retires.

Placed here because its inputs land earlier: bug Filed/Recurred/Verified dates (v1.44.0), CVE
remediation data (v1.45.0), the offsite availability probe and the weekly DR drill (v1.46.0), and
platform RTO (v1.47.0).

**Human effort per verified release** (operator, 2026-10-12; spec written 2026-10-12). One number per
release that passed the v1.47.0 `hub-e2e` gate: how many times the operator had to act. It starts
here so v1.48–v2.x give the baseline that v3.0.0 (multi-agent product team) must push down; it is
the same measure as that section's "coordinator interventions".
- [`v1.48.0-human-effort-per-release.md`](plans/v1.48.0-human-effort-per-release.md): counts explicit approvals (Decision Digest, v1.45.1),
  operator-authored commits, and operator-only steps and agent corrections recorded through a new
  `make log-intervention KIND=… NOTE=…` ledger (git cannot see these); branch-cut-to-merge hours as
  context. Minutes are optional and self-reported. A trend panel on the Operational Quality
  dashboard, one point per verified release.

v1.48.0 is **full at 5 of 5 plans**; the next v1.48.0 item goes to v1.48.1.

**Deferred to v1.48.1:** [`v1.48.1-semantic-change-approval-gate.md`](plans/v1.48.1-semantic-change-approval-gate.md) introduces trusted PR risk classification and SHA-bound approval (P2, approval pending, advisory-first). Authored on the current v1.43.2 branch; do not start implementation before its release is cut and operator approves.


### Candidate milestone — v1.48.1 (patch)

**Structured E2E failure evidence**, moved from v1.43.0 (via v1.47.0 and v1.48.0) on 2026-10-12,
when v1.48.0 took the operational-quality bundle. It depends on nothing in that bundle. Scope:
[`v1.48.1-e2e-failure-artifacts.md`](plans/v1.48.1-e2e-failure-artifacts.md). Branch
`k3d-manager-v1.48.1` is cut from `main` after v1.48.0 merges.

Also here (triage 2026-10-15): [`v1.48.1-e2e-current-release-head-sync.md`](plans/v1.48.1-e2e-current-release-head-sync.md),
which makes the E2E preflight test the current release-branch HEAD (renamed from the unversioned
proposal). With the semantic approval gate, v1.48.1 holds 3 of 5 plans.

**Unscheduled P3 backlog** (triage 2026-10-15):
[`argocd-image-updater-dashboard-kpi-alignment`](bugs/2026-10-13-argocd-image-updater-dashboard-kpi-alignment.md),
[`slack-k3dm-alertmanager-behaviour-test-target.md`](plans/slack-k3dm-alertmanager-behaviour-test-target.md).

### Candidate major — v2.0.0: a real reference workload replaces shopping-cart

**Proposed 2026-10-10 (operator; not yet scoped).** The shopping-cart apps are a demo. Their
replacement is the TwinkleAI real-estate research platform: a Next.js app in its own repo that
answers questions in Chinese or English. It reaches Taiwan open data (`realestate_land`) through MCP,
and keeps a research log. The plan source is the operator's
`房地產生成式 AI × MCP × TwinkleAI 網站 Codex 實作計畫.md`.

**English counts in the research.** The 15 questions each get an equivalent English version, so the
study is 15 × 2 languages × 3 runs = **90 records**, and human scoring doubles. English questions are
mapped to Chinese place names with a fixed district table, not by model guesswork.

Shopping-cart is the platform's acceptance contract today:
- the Tier 1 and Tier 2 e2e tests, and the v1.47.0 promotion gate;
- image signing and Kyverno, loadtest;
- the Keycloak realm, ESO and Vault paths, Dependabot coverage;
- about 100 files in `scripts/`, `bin/` and `scripts/etc/`.

So it is retired only after the new app covers the same platform surfaces. The removal is the
breaking change that makes this a major version.

**Revised 2026-10-10 (operator).** Shopping-cart has served its purpose: it has no real users, and
the nine repos stay public, archived, as the record. So there is no long side-by-side period. It
leaves Hostinger first, which frees the room the new app needs there (about 900m CPU and 3 GiB of
requests on a 2-CPU node). It stays on the hub and ACG only as the e2e target until the new app
takes over.

**Timing, revised 2026-10-10 (operator).** The two tracks are independent until they meet at
v1.49.0. App specs and the M1 `tools/list` spike live in the app repo and touch no cluster, so they
may start any time, in the gaps while agents work k3d-manager batches. M2 and later are not run in
parallel with the platform releases. The v1.47.0 gate stays mandatory for every infra promotion and
is never weakened for the app. Deploying the app onto the platform (v1.49.0) waits for v1.47.0 to
ship and for app M1. v1.47.0 and v1.48.0 are written workload-agnostic, so v1.50.0 re-points them
by editing lists, not code.

| Step | Where | Scope |
|---|---|---|
| App M1–M4 | app repo, its own versions; may start any time | 20 plan tasks in 4 milestones of at most 5 specs. Start with a live `tools/list` spike that records TwinkleAI's real tool schema as a fixture. Bilingual from M1: `next-intl`, zh-TW default, a message-file parity test, and a `locale` field on QueryLog. Postgres, not SQLite, so it fits the hub's DR export. |
| v1.49.0 | k3d-manager | Starts when app M1 is near done. Confirm, read-only, that nothing on Hostinger still depends on shopping-cart (loadtest targets, alert rules, dashboards). The operator removes shopping-cart from Hostinger. Onboard the app there: ApplicationSet, own namespace, Keycloak client, Vault/ESO secrets (the TwinkleAI and LLM keys), signed image under Kyverno, Grafana research dashboard, small requests with memory limits. |
| v1.50.0 | k3d-manager | Re-point the platform proofs from shopping-cart to the app: e2e Tier 1/2, the promotion gate, loadtest, hub-data DR inventory, Hermes e2e triage. |
| v1.50.1 | k3d-manager | Bug-fix-only patch (operator, 2026-10-12): bug-doc status cleanup. Also the docs/issues vs docs/bugs taxonomy research ([`2026-10-13`](bugs/2026-10-13-docs-issues-versus-bugs-taxonomy-research.md), triage 2026-10-15). Walk every open `docs/bugs/` doc and set a status the Bug Tracking dashboard can read — close what shipped and was proven, mark what was withdrawn, keep real open work open. Done when the dashboard's open counts match the real backlog. |
| v2.0.0 | k3d-manager | Retire shopping-cart from the hub and ACG, with no soak period. Remove the AppSets, Keycloak realm, Vault paths, `shopping_cart.sh`, tests and alerts; archive the nine `shopping-cart-*` repos. |

Release splits, new patches, and dropped milestones must update `docs/release-milestones.json` in the same commit as the roadmap change.

**Unfamiliar-app onboarding (proposed 2026-10-11).** Before TwinkleAI is onboarded by hand, test the
platform against an app it has never seen: a Bolt.new-generated app, exported to its own repo and
onboarded cold. The headline metric is manual interventions (target 0 long-term), with 100%
deployment success for supported templates and functional + operational e2e, including
observability onboarding. Generating the app may start any time; deploying it waits for v1.47.0.
Scope: [`v1.49.0-unfamiliar-app-onboarding.md`](plans/v1.49.0-unfamiliar-app-onboarding.md).

What the platform loses: the multi-service mesh traffic, RabbitMQ and Stripe payment flows. Keep one
of those only if a platform feature still needs it to prove itself.

### Candidate theme — v2.x: AI diagnostics and healing gateway

**Proposed 2026-10-10 (operator; not yet scoped).** After v2.0.0 the platform has a real application
to protect. This theme closes the loop between what the platform already observes and validates
and what it can safely do about it:
**diagnose → propose fix → policy approval → execute → retest → audit.**
Starts only after v2.0.0 is stable, never in parallel with the v1.4x releases.

| Layer | Exists today | Gap |
|---|---|---|
| Application | TwinkleAI app from v2.0.0 (API, Postgres, Kubernetes) | none at v2.0.0 |
| Observability | Prometheus, Grafana, Alertmanager, Loki, Pushgateway | app-level metrics (v1.49.0) |
| Validation | e2e Tier 1/2, v1.47.0 promotion gate, nightly offline suite, smoke, DR drill | re-pointed at v1.50.0 |
| Gateway | Hermes triage and bug drafts, webhook action allowlist, cloud-bridge roles, v1.45.0 alert intake, v1.46.0 Hermes self-recovery | one MCP tool server, an LLM provider adapter, an explicit policy engine |
| Providers | Claude, Codex, Gemini, each wired separately | one interface; per-provider scoring on recorded incidents |
| Remediation | Slack approval (pull model), Codex dispatch | the full loop, with retest and audit |

**Guardrails (non-negotiable):**
1. Read-only first: the first release diagnoses and proposes only. The model's MCP tools read
   metrics, logs and ArgoCD state, nothing else.
2. Technically reversible is not operationally safe. Each executable action is a **contract**:
   an allowlist entry, runtime preconditions, a post-action verification, and a documented rollback,
   or escalation where rollback is not reliable. Anything touching secrets, Vault, data, or cluster
   lifecycle always needs human approval.
3. Policy is code with tests. The model never decides whether its own action is allowed.
4. Every action is followed by a retest with the existing e2e and smoke checks. A failed retest
   rolls back or escalates to a human.
5. An append-only audit record of diagnosis, proposal, approver, action and retest result.
6. Providers are swappable, Claude is the default, and models are compared on recorded incidents,
   never live ones.

Initial action contracts (each precondition is drawn from an incident on this platform):

| Action | Preconditions | Verification |
|---|---|---|
| Restart an unhealthy pod | Replica redundancy (Hostinger is one node; a single replica means downtime); failure evidence; retry budget not spent (a k3s restart over dead kine compaction crash-looped) | Readiness and the app smoke check |
| Retry an ingestion or export job | Idempotent; no active duplicate | Freshness watermark advances (the hub-data export freshness alerts) |
| Sync an ArgoCD Application | Desired revision approved and on the release branch (ApplicationSets once pinned a stale branch); no destructive drift | Synced, Healthy, smoke passes |
| Scale a deployment | Bounded limits; node capacity checked first (a `maxSurge` rollout deadlocked on full requests) | Service available; node requests and memory healthy |

| Step | Scope |
|---|---|
| v2.1 | Gateway with read-only MCP tools; diagnosis and proposals only |
| v2.2 | Policy engine as code, approval flow |
| v2.3 | Execution of allowlisted reversible actions, with retest and audit |
| v2.4 | Provider adapter (Claude, OpenAI, Gemini, local LLM) and the comparison |

### Candidate theme — v2.x: intent interpretation and planning engine

**Proposed 2026-10-15 (operator; roadmap candidate only, not yet scoped or approved for implementation).**
Build a reusable, channel-neutral **intent-to-contract** layer for k3d-manager. It is **not** merely
an enhancement to `find-similar-docs`, nor is it a new unrestricted natural-language command runner.
Its purpose is to translate user requests into **typed, inspectable, verifiable plans** that can
be validated by deterministic code and existing policy gates before any execution.

- **Inputs:** Slack, CLI, authenticated API, and later a customer-facing text/voice interface.
  Voice is an input adapter, not a separate execution authority.
- **Read-only query intent:** identify topic, document kind, dates, release/status and requested
  answer; combine semantic retrieval with authoritative metadata filtering and cited sources.
  Return uncertainty when constraints cannot be grounded. `find-similar-docs` remains a
  similarity-only prior-art tool.
- **Engineering intent:** clarify missing requirements; produce a bounded application or
  infrastructure change contract with scope, acceptance tests, resource limits, security
  constraints, rollout/rollback and estimated work. Present the proposed contract for review.
- **Deterministic validation:** closed schemas, explicit capabilities, input limits, policy/RBAC,
  approval, test evidence and auditable decisions live in code. An LLM may *propose* an intent
  interpretation but cannot grant itself authority or treat a proposed plan as executed.
- **Provider-independent:** reuse the v2.x MCP gateway and provider adapter; start read-only,
  measure correctness on fixed ambiguous/negative query fixtures, and fail closed for unsupported,
  expensive or destructive requests.
- **Reuse existing work:** `v1.45.1-bug-count-query-translation.md` is a narrow predecessor
  (natural language to a validated bug-count query object); do not duplicate it. Build on
  /ask-docs retrieval improvements and the established Git-backed spec/memory-bank conventions.

**Placement / dependencies (2026-10-22 update):** The initial **read-only conversational
operations** slice is now scoped as **proposed v2.5.0**, after the stable v2.0.0 reference workload
and the existing v2.1–v2.4 gateway/policy/execution-contract/provider-adapter sequence.
Scope: [`v2.5.0-conversational-operations-assistant.md`](plans/v2.5.0-conversational-operations-assistant.md).
This consumes no v1.x spec slot and authorizes no implementation. The broader **engineering
intent-to-contract** planner remains a separate later v2.x candidate (minor version TBD);
v2.5.0 may propose read-only operational plans, not launch application builds.

**v3.0.0 dependency:** The multi-agent product team must consume **validated engineering intent
contracts**, not raw prompts that directly launch builds. Its future customer-facing application
factory can add text/voice requirements intake, AI-assisted scope/price proposals, ACG/k3s
verification, acceptance, and portable Git repository handoff (source, tests, memory-bank,
agent instructions). Customer-selected hosting and ongoing operations are separate from the
delivery acceptance contract. These are directional product goals, **not** committed v3.0.0
deliverables or a promise that arbitrary apps can be built for a fixed price.

**Proof before claiming readiness:** Demonstrate a read-only recent-bugs query with explicit
date/release/status constraints, an ambiguous request requiring clarification, a rejected
unauthorized operation, and an engineering request that results in a reviewable spec without
executing it. Later end-to-end application delivery requires deployment, functional/security
tests, handoff, and independent customer-agent continuation evidence.

### Candidate milestone — v2.5.0: Conversational Operations Assistant

**Proposed 2026-10-22 (operator requested formal roadmap/spec; implementation not yet
authorized).** Build the first stateful, evidence-grounded Slack conversational
operations assistant on top of the gateway, model adapter and policy boundaries
already proposed for v2.1–v2.4. Unlike `/k3dm` typed commands or standalone
Gemini failure analysis, it understands multi-turn context, resolves an exact
job/thread/cluster, issues bounded read-only tool plans validated by code,
and replies with current source evidence, uncertainty and safe next steps.

- **Scope:** [`v2.5.0-conversational-operations-assistant.md`](plans/v2.5.0-conversational-operations-assistant.md) — proposed plan **1 of up to 5** for v2.5.0.
- **Authority:** Slack is the initial interface; model output never grants
  action approval. Existing Make/webhook/cloud-bridge/Hermes remain authoritative.
  No unrestricted shell, autonomous recovery or cluster mutation in this release.
- **Core evidence:** provider-independent context/intent schema, thread-safe
  persistence, deterministic RBAC/tool validation, cited diagnostics and RAG,
  negative/ambiguous-input fixtures, privacy-safe audit and measurable
  correctness/outcome-per-token. A live Slack thread and a real read-only job
  investigation must pass operator verification before closing.
- **Dependencies:** v2.0.0 stable reference app; v2.1 read-only gateway;
  v2.2 policy; v2.3 action contracts (not executable by this feature);
  v2.4 provider adapter. No v1.x slot displacement.
- **Later:** validated engineering intent-to-contract authoring remains a
  future v2.x capability; v3.0.0 multi-agent product team consumes that
  interface. Do not advertise v2.5.0 as a general-purpose app-building agent.

### Candidate milestone — v2.6.0: Autonomous Ticket & Incident Investigation

**Proposed 2026-10-22 (operator requested roadmap placement; not yet an implementation spec).**
Extend the v2.5.0 conversational assistant with a **bounded, evidence-driven investigation
loop** for engineering tickets, runtime alerts and repeatable operational incidents. The
purpose is to reduce operator-led diagnostic prompting, **not** to grant an LLM unrestricted
execution privileges or conflate a plausible explanation with a verified root cause.

**Dependencies / ordering:** v2.0.0 stable reference workload; v2.1 read-only gateway;
v2.2 deterministic policy/RBAC; v2.4 swappable provider adapter; v2.5.0 authenticated,
thread-safe conversational context and cited read-only diagnostics. Reuse v2.3's action
contracts as policy references, but do **not** execute remediation in v2.6.0. Hermes
alert-driven triage, cloud-bridge allowlisted tools, RAG + Git history, and the existing
issue/bug/spec lifecycle are predecessors, not features to rebuild.

**Phased delivery within the v2.6.x series** (each patch/minor slice gets an independent
task spec and follows the maximum-five-plan-docs-per-release rule):

| Slice | Deliverable | Acceptance boundary |
|---|---|---|
| v2.6.0 | Ticket/alert intake and **structured investigation case** with source identity, severity, evidence links, deduplication, missing-context detection and ownership | Ingest a known incident and preserve provenance; no automatic bug-file mutation or alert acknowledgement |
| v2.6.1 | **Bounded hypothesize → read-only diagnostic → evaluate** loop, with competing hypotheses, deterministic allowlisted tool selection, iteration/time/token limits and escalation on inconclusive evidence | Replay incidents from frozen fixtures; unsupported claims and out-of-allowlist actions fail tests |
| v2.6.2 | Evidence-backed findings report with confidence calibration, alternatives considered, safe next actions and draft bug/spec handoff for human review | Independent evaluator checks findings against held-out ground truth; no self-certified root cause |
| v2.6.3 | Operational evaluation and Grafana dashboard: root-cause correctness, abstention quality, investigation completeness, latency, tool budget, human corrections and cost per accepted diagnosis | Operator-approved live *read-only* investigations plus correlated evidence; synthetic replay cannot be labeled live-verified |

**Investigation contract (design requirements):**
1. Input: authenticated Slack ticket/thread, GitHub issue or Hermes alert; normalize a
   stable case ID, incident window, affected cluster/repo and source provenance. Preserve
   existing permissions and refrain from assuming all channels are enabled.
2. Gather: read-only Prometheus/Alertmanager/ArgoCD state, approved log summaries,
   Git commits, past `docs/{bugs,issues,plans}` and RAG excerpts with source references
   and freshness. Retrieval text and tool outputs are untrusted evidence, never instructions.
3. Reason: explicit hypotheses, evidence-for/evidence-against, and unknowns; a model may
   select from **deterministically validated** read-only tools, but cannot expand its tool
   allowlist, issue arbitrary shell/SSH, bypass cloud-request authentication or grant roles.
4. Control: finite iteration/tool/time/token budgets, circuit breakers, loop detection,
   no-evidence/contradictory-evidence exits, resumable audit state and dedupe across Slack
   retries. Protect secrets, redact logs and avoid high-cardinality metric labels.
5. Report: separate `observed`, `inferred`, `hypothesis`, `unknown` and
   `independently verified`. Record timestamps, evidence links, requests, tool outcomes,
   hypothesis revisions and why investigation stopped. Never report resolved from silence,
   missing telemetry, or a healthy Argo CD status alone.
6. Human boundary: diagnosis/report only. Draft a bug or suggested repair for review,
   but **no autonomous code changes, merges, syncs, pod restarts, secret reads, permission
   grants or write-side cloud-bridge calls**. Existing v2.3 approval-and-retest workflow
   remains separately authorized.
7. Evaluation: frozen historical incident replay with held-out root causes, injected
   missing/stale/contradictory evidence, duplicate alerts, prompt injection, denial of
   permissions, unreachable tools and runaway-loop attempts. Independent tests are authored
   from acceptance contracts rather than agent implementation; track confidence calibration,
   correct abstentions, human escalation and outcome/token, not just ticket throughput.

**Exit criteria before calling v2.6.x autonomous investigation mature:** measurable
improvement over an operator-directed baseline on the *same* blinded incident corpus;
stable security/authorization boundaries; reproducible independent offline evaluation;
operator-reviewed real incident evidence; and calibrated abstention when evidence is
insufficient. Define numeric quality thresholds after a baseline and sample-size review,
rather than inventing accuracy or cost targets now.

**Not in this milestone:** autonomous remediation, broad network IDS, unattended release
management, arbitrary repository writes, generalized product development or unbounded
multi-agent orchestration. Integrate the separate proposed Falco IDS work from v1.51.0
only if it has actually shipped and exposes approved read-only signals; it is not a hard
dependency. This milestone feeds v3.0.0's multi-agent product team with more trustworthy
incident investigation, but does not itself implement the product team.

**Candidate slice — v2.6.4: security triage of runtime detections** (operator, 2026-10-23, after a
public design exercise on agent-based detection over streaming telemetry; design here is our own).
Deterministic rules see every event; the agent sees only what they flag. Falco (v1.51.0) and the
existing Alertmanager rules are the detection stage. The v2.6.0–v2.6.3 investigation loop becomes
the triage stage for their findings, with these additions:

- **Event fields are attacker-controlled.** A command line, file path or container name in a Falco
  event can carry text aimed at the agent. Fields reach the model as quoted data with length limits,
  never as instructions, and the replay corpus includes injected events (contract item 7).
- **Volume budget, not throughput engineering.** The hub emits megabytes a day, not a terabyte: no
  streaming bus. A per-hour cap on cases sent to the model, dedupe by rule and workload, and a counter
  of findings that went untriaged because the cap was hit.
- **Our own agents are in scope.** Codex and Gemini runs (devbox and Slack-thread candidates) are a
  telemetry source: an agent task that spawns a shell outside its worktree, or reaches a host outside
  its egress list, is a finding like any other.
- **Reproducible verdicts.** Each triage records the rule version, the event, the evidence it read and
  the model and prompt version, so a verdict can be replayed later.
- **Report only.** A verdict drafts a `docs/bugs/` entry or a Slack notice; no quarantine, pod
  deletion or network change (the v1.51.0 non-goals hold).

Depends on v1.51.0 actually shipping Falco with read-only signals, and on v2.6.0–v2.6.3.

**Scheduling:** roadmap candidate only; no `docs/plans/v2.6.x-*.md` files, new
branch, live action, or dispatch is authorized by this entry. Scope each slice only
when predecessor releases are ready and the operator approves implementation.

---

### Candidate milestone — v2.7.x: Account Abuse & Fraud Risk Detection (application-level)

**Proposed 2026-10-22 (operator suggested placement in v2.0.x; roadmap candidate only).**
Explore reusable **account-abuse detection** for an account-based e-commerce or marketplace
reference application. This is application-security and data-science work, **not** Falco
runtime IDS, Istio network security or automatic blocking by k3d-manager. The platform
provides GitOps, policy gates, observability, isolated E2E and rollback; the application
owns identities, event semantics, labels, risk decisions and consent/privacy rules.

**Placement and preconditions:** Tentatively **v2.7.x**, after the planned v2.0.0
TwinkleAI reference-app replacement and v2.5–v2.6 conversational/investigation work.
**Do not resurrect the shopping-cart application** solely to justify this feature:
it is slated for retirement at v2.0.0. TwinkleAI's currently proposed real-estate
research workload may not have registration, payments, reviews or transactions. The
first gate is to select a real account-based service/use case; otherwise defer this
milestone or build a small, explicitly isolated synthetic fixture in a separate
application repository. It should not expand k3d-manager's core infrastructure scope.

| Candidate slice | Capability | Acceptance gate |
|---|---|---|
| v2.7.0 | Threat model and events contract: signup/login/session/review/promotion patterns where supported; account/device/IP velocity with privacy constraints | Explicit app ownership, schema, consent/retention policy and reproducible synthetic fixtures; no real-person data |
| v2.7.1 | Deterministic configurable risk rules, audit trail and human review; no hard denial by default | Offline positive/negative tests, documented false-positive cases (shared IPs, families, VPNs), safe feature flags and rollback |
| v2.7.2 | Optional statistically calibrated classifier using held-out, time-split labeled data, with uncertainty and base-rate-aware evaluation | Compare precision/recall, PR-AUC, calibration, base rates and review workload against rules-only baseline; do not ship ML without sufficient defensible labels |
| v2.7.3 | End-to-end application integration and observability: risk decision API, review/challenge workflow, Grafana, alerting and E2E | Operator-reviewed disposable-environment tests and drift/latency/false-positive dashboards; no production account suspension until separately approved |

**Non-negotiable safeguards:** Risk score is not proof of fraud; enforce minimization,
hash/pseudonymization where applicable, scoped access, bounded storage/retention, audit
of reviewer overrides, and meaningful recourse for legitimate users. Never send raw
credentials, authentication secrets, full payment details or personal identifiers to
an LLM. Do not train on synthetic labels and present the result as real fraud-detection
accuracy; avoid leakage via random train/test splits of correlated events. Start with
shadow scoring and review/challenge rather than irreversible automated bans. Challenge
accessibility, operational cost, class imbalance and adversarial adaptation must be
tested. No claim that high overall accuracy proves good fraud detection.

**Success metrics:** precision at constrained review capacity, recall, false-positive
rate for legitimate accounts, precision-recall curve, probability calibration, challenge
completion, review burden, p95 decision latency, feature drift and rollback reliability.
Compare performance with a rules-only baseline, stratified by relevant non-sensitive
operational cohorts; choose numerical thresholds after collecting credible labeled
data and assessing harms.

**Release discipline:** This is a roadmap entry, not an implementation spec, branch
creation, model deployment or authorization to process personal data. Each future
release follows the maximum-five-plan-documents rule. Application code/specs belong
to the chosen app repository; k3d-manager should accept only narrowly scoped GitOps,
policy, monitoring and integration work after separate approval.

---

### Candidate theme — v2.x: model economics

**Proposed 2026-10-16 (operator; not yet scoped).** Compare Claude-only, Codex-only and
multi-model collaboration on token consumption, quota utilisation and **cost per verified
outcome**: a spec landed with its tests green and its recorded mutations red, and for releases the
e2e gate passed.

- **Placement:** with or right after v2.4. The v2.4 provider adapter is what lets one spec run
  under each arm without hand-driving it.
- **Method:** a controlled replay, not logs of real work. Real dispatches route work by kind, so
  they confound the model with the task. Freeze about 10 landed specs of mixed kinds and run each
  from the same base commit under each arm, with the spec's tests and mutations as the oracle.
- **Units:** share of weekly quota per plan, plus tokens where the CLI reports them, not dollars;
  record the model ID and plan for every run. Results are directional (small n).
- **Inputs it reuses:** per-spec dispatch metrics (v1.43.3), Codex model routing and efficiency
  (v1.45.1), human effort per verified release (v1.48.0).
- **Cheap early step (separate item, not scheduled):** record Codex tokens per dispatch so real
  data exists by v2.4.

**v3.0.0 dependency:** this is the cost baseline the multi-agent product team must beat, alongside
v1.48.0's human-effort baseline. It also answers RQ2–RQ4 of the research paper plan,
[`docs/research/2026-10-16-research-paper-plan.md`](research/2026-10-16-research-paper-plan.md).

### Engineering-contract gaps (assessed 2026-10-10)

The platform's working model rests on three principles. Each was assessed against the repo as it
stands; the scores are judgement, not measurement.

| Principle | Today | Main gap |
|---|---|---|
| Intent as an engineering contract | ~80%: every change is a spec with files, exact commit message, Definition of Done, "What NOT to do", stubbed and mutation tests, live acceptance | Operational requirements (resource budget, capacity, rollback) are rarely stated; required sections are checked by review, not by tooling |
| Verification as the release authority | ~65%, ~80% after v1.47.0: agents' claims are re-verified; CI, CodeQL, ggshield, Copilot, nightly suite, e2e, DR drill | Infra changes reach the hub untested (v1.47.0); the PR gate is a followed checklist, not enforced; the evidence behind a release decision is not kept |
| Common operational interfaces | ~40%: Slack, cloud bridge and Hermes enter through the webhook's action allowlist and roles | The CLI and local agents bypass it; the cloud bridge does not yet authenticate submitters |

Next steps, smallest first:

| Step | Lands in | Scope |
|---|---|---|
| Operational requirements in every spec | DONE 2026-10-10, with `v1.44.0-bug-lifecycle-metrics.md` | Add an `## Operational Requirements` section to `docs/plans/task-spec-template.md`: resource requests and limits, a capacity check on the target node, rollback, and the alert or dashboard that shows it working. |
| Release evidence record | v1.48.0, second item | Each release keeps a machine-written record of the evidence present when it shipped: CI run, offline suite counts, `appsets-check`, the v1.47.0 gate result, open P0/P1 bugs. |
| One authorization path, inventoried | v1.44.0 | Ship `v1.44.0-cloud-request-submitter-authentication.md`, and add a how-to that lists every channel (Slack, cloud bridge, Hermes, CLI, local agents) with how it is authorized today. The v2.x gateway closes the gaps it records. |

### Candidate theme — v2.x: agents working together in Slack threads

**Proposed 2026-10-23 (operator; roadmap candidate only, not scoped, no spec slot).** Mention an agent
in Slack (`@codex`, `@gemini`, `@claude`) and it works in that thread, and the other agents reply to it
there: Codex implements, Gemini reviews, Codex fixes, Claude verifies and asks the operator to approve.

- **Our bot identities, not vendor Slack apps.** A mention goes Slack relay → webhook allowlist →
  `make codex-dispatch`, so every run lands in the dispatch ledger and metrics. A vendor integration
  would run outside the dispatcher and lose the research data.
- **Mentions name a spec or bug doc.** Channel text is untrusted input. A free-form request goes to
  Claude, who turns it into a spec first (the intent engine above). Only allowlisted actions run:
  dispatch, review, fix findings, status.
- **The ledger drives turns.** Each agent posts when its step finishes, and that post hands the next
  step to the next agent. Git, specs, memory-bank and the ledger stay authoritative; a thread links
  to commits, test output and dashboards.
- **Bounded exchanges.** Each thread has a turn cap and a token budget, and Claude's verdict closes the
  loop, so two agents cannot ping-pong a disagreement.
- **Current roles hold.** Gemini never runs live-cluster verification; one agent per worktree; no
  agent approves another's work. Land and merge need the operator's MFA approval
  (`project_hermes_slack_approval`).

**Placement:** the first slice (`@codex dispatch <spec>`, `@gemini review <task>`, threaded replies)
is v1.44.1 plan 2 (operator, 2026-10-23), after v1.44.0's submitter authentication, because a chat
message must not start a dispatch until its sender is authenticated. The full multi-agent
conversation stays v2.x and is the interface of v3.0.0 below.

### Candidate theme — v2.x: feature flags, progressive rollout and feedback

**Proposed 2026-10-23 (operator; roadmap candidate only, not scoped, no spec slot).** Turn the
platform's staged deploys into a rollout platform: ship a change dark, expose it in steps, measure
each step, and promote or roll back on evidence. Prompted by a public system-design exercise
("design a feedback and feature rollout platform"); the design here is our own.

| Concern | Today | Gap |
|---|---|---|
| Staged rollout | `make appsets-reapply` rolls out hub first, then app clusters (`APPSETS_STAGE=hub` to soak) | Stages are per cluster, never per user, request or percentage |
| Policy rollout | Kyverno Audit → Enforce for image signing | Done by hand; no record of who promoted it or why |
| Gates | CI, e2e Tier 1 (vCluster) and Tier 2 (ACG sandbox), Grafana alerts | Gates run before deploy only; nothing watches a rollout after it starts |
| Feature switches | none | No way to turn a feature on or off without a deploy |
| Feedback | Metrics and logs per service | No signal tied to a flag variant or release step; no user feedback channel |

- **Flags in git.** OpenFeature SDKs in the shopping-cart services, flagd in-cluster, flag
  definitions synced by Argo. A flag change is a reviewed commit; nothing flips a flag outside git.
- **Canary with analysis.** Argo Rollouts on one service first (payment or order), with Prometheus
  analysis on error rate and latency; a failed step aborts and rolls back by itself.
- **Feedback tied to the change.** Per-variant and per-step metrics, a Grafana rollout-health row, and
  a small feedback endpoint whose records carry the flag variant and release.
- **Promotion record.** Each flag flip and canary promotion is a command with an id, target, actor and
  reason, on the command ledger of `v1.44.2-command-ledger-and-cluster-reconciliation`.
- **Read-only first.** As with the healing gateway: report and recommend before any automatic
  promotion; automatic rollback on a failed analysis is the one exception.

**Placement:** first slice (flagd on the ACG sandbox first, then Hostinger, one `shopping-cart-basket` flag, per-variant
metrics, flag-change record) is v1.44.3 plan 2 (operator, 2026-10-23: "go for it"):
[`feature-flags-first-slice`](plans/v1.44.3-feature-flags-first-slice.md). Basket is already Go, so
it does not wait for the order/payment rewrite. Canaries, feedback endpoint and targeting are later
slices.

### Candidate theme — v2.x: agent devbox service

**Proposed 2026-10-23 (operator; roadmap candidate only, not scoped, no spec slot).** Give each
dispatched agent task its own on-demand, isolated development environment instead of a worktree on
the operator's laptop. The intent engine above decides *what* to build; the devbox is *where* an agent
builds it. Prompted by two public system-design exercises (remote devboxes, a browser IDE platform); the
design here is our own.

| Concern | Today | Gap |
|---|---|---|
| Lifecycle state machine | Dispatch ledger: start, running, exited, land or refuse | No stop/resume; no idle reaping beyond the ACG sandbox expiry |
| Disposable compute, durable work | Worktree and `.run/` dir per task; the branch is the durable state | One shared laptop, hence the one-agent-per-sandbox and no-edit-mid-run rules |
| Egress and secrets | Codex sandbox, Vault/ESO, the webhook allowlist | Credentials are not scoped per task; the sandbox is the agent tool's, not ours |
| Access gateway | Webhook, Cloudflare tunnel, cloud-bridge requests | No short-lived, per-session access |
| Fast start | vCluster per PR, prebuilt images | No warm pool, no snapshots |
| Cost and productivity | Agent dispatch dashboard, v1.43.5 cost plans | Not attributed per environment |

A second exercise, on a browser-IDE style platform, adds three requirements that matter more for
agents than for people:

- **Agent code is untrusted.** Isolation is the core of the design, not an add-on: one task cannot
  reach another task's workspace, the hub, or internal networks beyond an explicit egress list.
- **Per-repo prepared environments.** Build each repo's toolchain image ahead of time (TwinkleAI,
  shopping-cart, k3d-manager), so a dispatch starts in seconds rather than after a fresh install.
- **Forwarded ports for review.** A server the agent starts is reachable through the authenticated
  gateway, so the operator or the QA agent can test a running preview before anything lands.

Durability follows from our model: the branch is the work product, so a lost machine costs at most
the uncommitted diff, and snapshots can stay infrequent.

**Placement:** after v2.5.0, before v3.0.0, and a v3.0.0 dependency alongside the intent engine.
Likely gated on the Mac Mini M5 as the first compute pool. Nothing moves into v1.4x.

### Candidate major — v3.0.0: multi-agent product team

**Proposed 2026-10-12 (operator; scheduled for v3.0.0, not yet scoped).** A product team made of
agents, building TwinkleAI features end to end:

- **Operator: engineering owner.** Product objectives, priorities, release approval.
- **Claude: engineering lead and release coordinator.** Specs, task allocation, dependencies,
  integration decisions.
- **Agent A: backend.** APIs and business logic.
- **Agent B: frontend.** UI and workflows.
- **Agent C: QA.** Tests and regression.

Their work lands through merge gates → CI → e2e → deployment, on k3d-manager (GitOps, vCluster,
Grafana, security, recovery).

**Ordering:** the v1.4x releases through v1.50.0 first, then v2.0.0 (the TwinkleAI workload). This
explicitly depends on the proposed **v2.x intent interpretation and planning engine** above,
in addition to the existing "Intent as an engineering contract" work, so the agents receive
validated intent contracts rather than unreviewed prompts or hand-written specs.

**Design notes to carry into the scope doc:**

1. **Contract first.** Claude publishes the API contract (OpenAPI) before A or B starts, so a
   mismatch fails a contract test.
2. **QA tests from the spec, never from A's or B's code.**
3. **Gates decide, not the coordinator.** Claude steps in on a gate failure or a conflict.
4. **Measure the experiment.** Time per agent from task handed out to work landed,
   coordinator interventions per feature, bugs caught by QA versus e2e, and tokens per role. The baseline is v1.48.0's "human effort per verified release", collected from v1.48 through v2.x.

On 2026-10-12, eight finished Codex worktrees were waiting on Claude's verify-and-land step. That
step is the known bottleneck the experiment must test.

### Post-v3.0.0 candidate — Intent-to-Verified-Software benchmark

**Roadmap placement corrected 2026-10-22 (operator): after v3.0.0, not in v2.x.**
Use external, unfamiliar engineering/system-design interview-style prompts (including
automated ticket investigation and fake-account risk classification) as a **benchmark
corpus**, not as automatic product-feature requests. This is an evaluation of the
v3.0.0 multi-agent product team's ability to translate natural-language intent into
validated requirements, architecture, implementation, deployment and independently
verified outcomes. It must follow, not block or enlarge, the v2.x gateway/conversation/
investigation milestones.

- **Input integrity:** Freeze original prompts, version their source/rights metadata,
  classify domain and difficulty, and keep held-out tasks unseen by development
  agents. Do not assume an interview solution's intended scope equals production requirements.
- **Independent oracle:** A separate human-reviewed evaluator derives acceptance
  criteria from the original prompt, without reading the implementer's generated
  spec or code. Ambiguities, missing requirements and justified clarification or
  abstention are scored explicitly.
- **Experimental controls:** Compare Claude-only, coordinated Claude/Codex and
  multi-agent/independent-QA variants using equivalent starting repositories,
  tools, time/token budgets and infrastructure. Repeat enough trials to expose
  variance; do not conflate model selection with extra time or privileged tools.
- **Outcome measurement:** Intent fidelity, externally validated acceptance pass
  rate, functional and security correctness, deployability, architecture review,
  clarification burden, human corrections, rework, wall-clock latency and cost
  per *independently verified* delivery. Distinguish spec-only, simulated test,
  isolated live E2E and customer/operator acceptance.
- **Safety:** Run unfamiliar application builds in disposable vCluster/ACG
  environments; no production credentials, live customer data, silent cloud
  spending, automatic promotion or release authorization. ML/fraud exercises
  use synthetic or appropriately consented, governed data.
- **Sequence:** First establish a stable v3.0.0 multi-agent delivery baseline;
  next implement the benchmark harness and blind oracle; then compare workflows
  and publish results with failure cases and uncertainty. Decide the exact
  post-v3 release number only when v3.0.0 proves stable and a scope doc is approved.

**Status:** Future research/evaluation theme only. No v2.x spec slot, no new
implementation spec or dispatch, and no commitment to deliver this in v3.0.0.

**Calibration corpus (operator, 2026-10-22).** Classic interview coding problems with one known
correct answer (for example: simplify a Unix path, shortest clear path in an 8-directional grid,
sum of BST values in a range), drawn from the categories on the PracHub Meta interview list
(`https://prachub.com/companies/meta`). Their purpose is calibration: a known answer measures how
often the intent → Acceptance → implementer → blind-verifier loop delivers correct code, which a
real bug cannot. Write our own problem statements and record source and rights metadata; never
copy third-party question text or paywalled content.

## Forward themes (unversioned until scoped)

These are the vision items still unshipped. No version numbers committed — a theme becomes a
milestone only when it gets a scope doc.

- **Vendor-neutral AI engineering collaboration (future enhancement; P1-blocked).** Separate the agent
  coordinator from the worker backend in a proposed `k3dm-agent-dispatch`, with shared task identity,
  lifecycle, scoped permissions, Git/test evidence, independent acceptance, and backward-compatible
  Codex dispatch history. Any authorized Claude, Codex, Gemini, Hermes or human coordinator may
  dispatch a supported backend; optional MCP/A2A transport is deferred. **Do not start or schedule
  implementation until the dispatcher worker-lifecycle P1 is fixed and verified.** Proposal:
  [`future-vendor-neutral-agent-collaboration-contract.md`](plans/future-vendor-neutral-agent-collaboration-contract.md).

- **Re-home the hub's ESO off the app-cluster ApplicationSet** — the hub's External Secrets
  Operator install (`ubuntu-k3s-eso`: 3 Deployments, 21 CRDs, 5 ClusterRoles, 2 webhook configs) is
  generated by the `eso` ApplicationSet via the `k3d-manager/role: app-cluster` cluster selector,
  which on a single-cluster setup resolves to the hub's own self-registration. The hub's ESO is
  therefore coupled to a label whose purpose is to point at *the active app cluster*, and it carries
  `resources-finalizer.argocd.argoproj.io` — so anything that moves or drops that label takes ESO's
  CRDs with it, and with them every ExternalSecret CR cluster-wide plus the owner-referenced Secrets
  they produce. Platform components the hub needs for itself belong in a hub-scoped Application
  (`hub-loki`, `hub-platform-ops` are the pattern), not in an app-cluster AppSet. Scope doc required
  before a version is assigned; the migration has to keep the CRDs adopted rather than recreated, so
  it is not a simple retarget. Discovered 2026-09-23 while scoping
  `docs/plans/v1.37.0-deregister-hub-app-cluster-shopping-cart.md`, which deliberately leaves `eso`
  untouched for exactly this reason.
- **Vault per-context auth mounts** — finish Workstream 3 above: one auth mount per kube-context
  (`kubernetes-<sanitized-context>`), a path sanitizer, and ESO SecretStore migration off the
  single `kubernetes-app` mount. Nearest concrete next milestone.
- **k3dm-mcp** — persistent MCP server, HTTP transport default (`K3DM_MCP_TRANSPORT=http|stdio`),
  FastMCP/Python; CLIs connect at `http://localhost:8765/mcp`. Read-only tool set for verify
  agents; `.git/` excluded from writable paths.
- **Hermes Phase 2 / Phase 3 (event-driven operations automation)** — **Phase 1 shipped as v1.29.0**
  (read-only health/CI monitoring, bounded polling, Slack summaries — the current milestone above).
  Phase 2's allowlisted, approval-gated repairs have shipped incrementally (R1–R9 in
  `scripts/lib/hermes/repairs.py`, Slack approval in v1.33.0); alert-driven triage is scoped into v1.42.0 above, R10 into v1.43.0.
  Phase 3 adds cooldowns, daily token/iteration budgets, audit records, and post-repair
  verification. Hermes does not replace the k3d-manager webhook or receive unrestricted cluster,
  cloud, Git, or branch-protection credentials. Each phase needs its own scope doc before a release
  is assigned (health-degraded ≠ safe-to-repair). Phase 1 scope:
  `docs/architecture/hermes-phase1-monitoring-scope.md`.
- **HIPAA readiness and compliance gap assessment** — future infrastructure work, not a compliance
  certification or a promise that the current stack may process ePHI. Start with a formal inventory
  of PHI data flows, providers, BAAs, logs, backups, CI artifacts, webhooks, Slack/AI integrations,
  and access paths. Establish a no-PHI-by-default boundary for development, k3d/k3s sandbox,
  automation, and external-agent workflows; any PHI-capable workload requires a dedicated,
  BAA-covered environment with least-privilege access, MFA, encryption and key management,
  immutable audit logging, network/egress controls, backup/restore testing, incident response,
  periodic risk analysis, and independent legal/security review. Scope document required before
  assigning a release; v1.42.0 remains at its five-plan cap.
- **Claude Code self-hosted runner (evaluation)** — sessions started from Slack that run on the
  M4, so they can reach the hub and the webhook. The cloud bridge can't do that, but the same reach
  exposes the operator's credentials, so this starts as a read-only go/no-go evaluation in a separate
  OS user. Not before v1.43.5. Plan: `docs/plans/claude-self-hosted-runner-evaluation.md`
  (operator, 2026-10-15).
- **Hardening ideas from interview design questions (operator, 2026-10-22)** — three of the
  PracHub Meta questions (`https://prachub.com/companies/meta`) describe problems this repo hit the
  same week. Each needs a scope doc or bug spec before it gets a version.
  - *Notification delivery (Q7: notification system at scale).* `_notify_job` in
    `bin/k3dm-webhook` logs `route=none` and drops a reply it cannot route (recurrence in
    `docs/bugs/2026-10-01-ask-docs-thread-follow-up-silently-dropped.md`). An undeliverable reply
    should go to a dead-letter record and raise an alert instead of disappearing.
  - *Evidence before diagnosis (Q8: diagnose a server crash with concrete Linux evidence).* The
    `~/.ssh/config` wipe (`docs/bugs/2026-10-22-ssh-config-lost-operator-host-aliases.md`) has no
    root cause because nothing recorded the write. Back up or audit-log writes to operator-owned
    files, so the next incident starts with evidence.
  - *Validate a reporting repair (Q16).* The bug-tally fix
    (`docs/bugs/2026-10-22-bug-tally-counts-implemented-and-deferred-as-open.md`) was proven by
    hand. Add a reconciliation check that the Slack bug count and the dashboard's per-bug rows
    agree for every release.
  - *Path canonicalization (Q17)* doubles as a calibration problem (see the benchmark entry above)
    and as input validation for directory traversal (`../`) in webhook and cloud-request arguments.
- **Distribution packages** — deb/rpm/brew. Long-standing vision item, never scoped.
- **Home lab** — `CLUSTER_PROVIDER=k3s-local-arm64` on a Mac Mini M5 (hardware target ~Oct 2026),
  bare-metal ingress via **MetalLB + Envoy Gateway (Gateway API)** replacing the Istio
  IngressGateway for the home tier; flow `Internet → Cloudflare Tunnel → MetalLB → Envoy Gateway
  → pods`; GitOps via ArgoCD. `homehub-mcp`.

---

## Maintenance note

Keep this file honest: when a milestone closes, move its scope block into `docs/releases.md` detail
and promote the next forward theme into a "Current milestone" section with a real scope. Do **not**
let version labels drift from what actually shipped again.
