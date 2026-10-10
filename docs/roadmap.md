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
v1.43.0 is now at its five-plan cap, so anything new goes to v1.44.0.

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
  - [`secret-store-data-puts-value-in-security-argv`](bugs/2026-10-09-secret-store-data-puts-value-in-security-argv.md)
    and [`…-reports-success-on-failed-keychain-write`](bugs/2026-10-10-secret-store-data-reports-success-on-failed-keychain-write.md):
    one agent in lib-foundation, then a subtree-pull here.
  - [`frontend-index-html-no-cache-control`](bugs/2026-10-10-frontend-index-html-no-cache-control.md):
    `shopping-cart-frontend`.
- **Batch 2:** one agent, after v1.43.1 lands, because both edit `bin/dr-drill`.
  - [`dr-drill-keep-deletes-kubeconfig`](bugs/2026-10-10-dr-drill-keep-deletes-kubeconfig.md)
  - [`dr-drill-set-u-wrappers`](bugs/2026-10-10-dr-drill-set-u-wrappers.md)
- **Not dispatched:**
  - the hub-recovery node map is deferred (superseded by `hub_data_recover`);
  - the e2e payments assertion needs only the operator's live Tier 1 rerun;
  - hub CPU overcommit (August) and data-layer `RespectIgnoreDifferences` (June) need re-triage
    against today's hub first.

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
[`v1.46.0-hostinger-offsite-hub-watch.md`](plans/v1.46.0-hostinger-offsite-hub-watch.md). v1.46.0
is now at 2 of 5 plans.

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

**Structured E2E failure evidence**, moved from v1.43.0 (via v1.47.0) on 2026-10-10. Scope:
[`v1.48.0-e2e-failure-artifacts.md`](plans/v1.48.0-e2e-failure-artifacts.md).

## Forward themes (unversioned until scoped)

These are the vision items still unshipped. No version numbers committed — a theme becomes a
milestone only when it gets a scope doc.

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
