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
| **v1.25.0** | E2E verification harness (Tier 1 vCluster + Tier 2 ACG Stripe) + Stripe/Go live acceptance |
| **v1.26.0** | Sandbox registration lifecycle hygiene (TTL watchdog, resource-preserving Application cleanup) + Fleet node lifecycle for Lambda |
| **v1.27.0** | Image signing + attestation (cosign sign/attest, Kyverno verify Audit→Enforce) + adaptive checkout load testing |
| **v1.28.0** | Platform zero-downtime rollouts (hub tier scale, probes/PDBs, rolling-update guarantees) + public-endpoint probe |

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
- [ ] Reapply hub + ACG observability ApplicationSets pinned to `k3d-manager-v1.29.0`, confirm with
      `argocd_check_values_branch` (6 Applications were on `v1.28.0`; render + `kubectl diff` verified
      the only change is the values branch — apply pending, live-write gated).
- [ ] Hub CPU overcommit Step 2 load-shed.
- [ ] `/create-pr` gate met (CI green + Copilot addressed + Gemini smoke + Claude scope), PR merged,
      tag `v1.29.0`, retro written. **Never auto-merge.**

---

## Queued milestones (scoped)

None currently queued with a committed version number. The previously queued block
(**v1.24.1** status output contract, **v1.25.0** E2E verification harness + Stripe/Go acceptance,
**v1.26.0** sandbox registration lifecycle hygiene, **v1.27.0** image signing + adaptive checkout
load, **v1.28.0** platform zero-downtime rollouts) has all shipped — see the arc table above and
`docs/releases.md` (ledger catch-up for v1.25+ is pending). The next milestone will be chosen from
Forward themes below once it gets a scope doc.

## Forward themes (unversioned until scoped)

These are the vision items still unshipped. No version numbers committed — a theme becomes a
milestone only when it gets a scope doc.

- **Vault per-context auth mounts** — finish Workstream 3 above: one auth mount per kube-context
  (`kubernetes-<sanitized-context>`), a path sanitizer, and ESO SecretStore migration off the
  single `kubernetes-app` mount. Nearest concrete next milestone.
- **k3dm-mcp** — persistent MCP server, HTTP transport default (`K3DM_MCP_TRANSPORT=http|stdio`),
  FastMCP/Python; CLIs connect at `http://localhost:8765/mcp`. Read-only tool set for verify
  agents; `.git/` excluded from writable paths.
- **Hermes Phase 2 / Phase 3 (event-driven operations automation)** — **Phase 1 shipped as v1.29.0**
  (read-only health/CI monitoring, bounded polling, Slack summaries — the current milestone above).
  Phase 2 adds allowlisted, approval-gated repairs (restart webhook, refresh edge, retry transient
  CI); Phase 3 adds cooldowns, daily token/iteration budgets, audit records, and post-repair
  verification. Hermes does not replace the k3d-manager webhook or receive unrestricted cluster,
  cloud, Git, or branch-protection credentials. Each phase needs its own scope doc before a release
  is assigned (health-degraded ≠ safe-to-repair). Phase 1 scope:
  `docs/architecture/hermes-phase1-monitoring-scope.md`.
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
