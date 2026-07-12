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

---

## Current milestone — v1.14.0 (active)

**Theme: observability & multi-cluster reliability hardening.** Not a planned-feature milestone —
this is a reactive hardening sprint that emerged from operating the v1.12 observability stack and
the multi-cluster (laptop / Hostinger / OCI / ACG) fleet under real load. Captured as **21 bug
specs** in `docs/bugs/`, of which **19 have shipped** as `fix(...)` commits on
`origin/k3d-manager-v1.14.0`.

### Workstream 1 — Observability fidelity & persistence — **shipped**
Grafana stability, Prometheus durability, and dashboard correctness for the CVE/Trivy/Image-Updater
hub dashboard.

| Spec (`docs/bugs/`) | Status | Fix |
|---|---|---|
| `2026-07-06-grafana-restarting-frequently` | ✅ | `1af49f44` raise Grafana memory limit |
| `2026-07-06-grafana-repeatedly-killed-by-liveness-probe…` | ✅ | `1af49f44` (memory) |
| `2026-07-06-prometheus-tsdb-on-emptydir` | ✅ | `6ae2f758` persist TSDB on a PVC |
| `2026-07-07-app-cluster-prometheus-keeps-only-2h` | ✅ | `23e5d67f` PVC + 15d retention |
| `2026-07-08-grafana-public-route-must-serve-hub-dashboard-instance` | ✅ | `65dcf6e8` route hub domain to hub Grafana |
| `2026-07-08-image-updater-processing-results-need-parsed-drilldown` | ✅ | `06813683` parse log counters |
| `2026-07-08-trivy-infra-panels-need-object-level-drilldown` | ✅ | `f4560d56`/`d0a2d92f`/`76752337` |
| `2026-07-08-trivy-findings-should-trigger-actionable-alerts` | ✅ | `a95fda82` drilldown summaries |
| `2026-07-09-trivy-finding-ownership-classification-and-fixed-state` | ✅ | `215a4157`/`68b71222`/`44488f88` |
| `2026-07-10-trivy-drilldown-panels-redundant-and-banner-newlines-literal` | ✅ | `ae088b34` |
| `2026-07-10-loki-logs-panels-render-empty-and-raw-json` | ✅ | `7e39ffaa` (verified + deployed by Claude) |

### Workstream 2 — ACG sandbox lifecycle robustness — **shipped**

| Spec | Status | Fix |
|---|---|---|
| `2026-07-06-acg-up-seed-vault-empty-port-exit-22` | ✅ | `ac5e3fde` resolve seed Vault addr at call time |
| `2026-07-07-acg-up-vault-kv-put-swallows-http-status` | ✅ | `44c1aec8` surface KV write HTTP status |
| `2026-07-08-acg-sandbox-expiry-is-not-just-tunnel-loss` | ✅ | `e2c79595` classify absent sandbox vs tunnel loss |
| `2026-07-10-acg-provider-context-missing-k3s-oci-case` | ✅ | `80ac1ba0` map k3s-oci to its own context |
| `v1.14.0-bugfix-acg-pluralsight-autologin` | ✅ | shipped |
| `v1.14.0-bugfix-acg-tunnel-mode-autoselect` | ✅ | `2834e1d3` probe iam:CreateRole to pick SSM vs SSH |

### Workstream 3 — Vault multi-cluster portability — **pulled into v1.14.0 (2026-07-12)**
Profile-state scoping shipped. Per user decision 2026-07-12 the per-context auth-mount work is now
**in scope for v1.14.0**. Phase 1 implementation spec written; Phases 2–3 are the milestone tail
(ship within v1.14.0 or split — see closing condition).

| Spec | Status | Note |
|---|---|---|
| `2026-07-07-global-hub-vault-profile-is-shared-across-clusters` | ✅ | `e7fc432e` scope profile state by app context |
| `2026-07-07-stale-kube-context-assumptions` | ✅ | addressed via `80ac1ba0`/`e7fc432e` |
| `2026-07-12-vault-per-context-auth-mount-phase1` | 📝 spec written | Phase 1: mount `kubernetes-<sanitized-context>`, all 3 mount sites + migration; awaiting review then handoff |
| `2026-07-07-app-cluster-vault-portability` | 🎨 design | signed-off design doc behind the Phase 1 spec above (do NOT hand off directly) |
| `2026-07-07-vault-kubernetes-auth-mount-is-single-target` | 🎨 design | consolidated into the design doc; single-target root cause |
| Phase 2 — per-context hub-Vault profile | ⏳ queued | follows Phase 1; not yet specced |
| Phase 3 — `ubuntu-k3s` demote + reachability preflight | ⏳ queued | re-scoped by decision #1; not a mass rename |

### Closing condition for v1.14.0
- [x] Workstream 1 (observability) verified live on hub **and** app cluster (2026-07-12): Grafana
      512Mi + 0 restarts since 2026-07-09 on both; hub Prometheus PVC 25Gi Bound / 7d-20GB;
      app-cluster Prometheus PVC 10Gi Bound / 15d-8GB; trivy dedupe + loki panels deployed.
- [ ] Workstream 2 (ACG lifecycle) is shell-logic — covered by BATS; live verification requires
      exercising an `acg-up`/refresh cycle, deferred (not triggered casually).
- [x] Decision recorded on Workstream 3 (2026-07-12): **pulled into v1.14.0.** Phase 1 spec written
      (`docs/bugs/2026-07-12-vault-per-context-auth-mount-phase1.md`). Remaining: implement Phase 1
      (handoff pending review) + decide whether Phases 2–3 land in v1.14.0 or split to v1.15.0.
- [ ] Untracked `docs/bugs/2026-07-08-refresh-output-is-healthy.md` triaged — commit it as a real
      spec or delete it; do not ship the milestone with it dangling in the working tree.
- [ ] `/create-pr` gate met, PR merged, tag `v1.14.0`, retro written.

---

## Forward themes (unversioned until scoped)

These are the vision items still unshipped. No version numbers committed — a theme becomes a
milestone only when it gets a scope doc.

- **Vault per-context auth mounts** — finish Workstream 3 above: one auth mount per kube-context
  (`kubernetes-<sanitized-context>`), a path sanitizer, and ESO SecretStore migration off the
  single `kubernetes-app` mount. Nearest concrete next milestone.
- **k3dm-mcp** — persistent MCP server, HTTP transport default (`K3DM_MCP_TRANSPORT=http|stdio`),
  FastMCP/Python; CLIs connect at `http://localhost:8765/mcp`. Read-only tool set for verify
  agents; `.git/` excluded from writable paths.
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
