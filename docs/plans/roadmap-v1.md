# k3d-manager Strategic Roadmap

## Vision

k3d-manager is a **kops-for-k3s** — a cluster lifecycle manager for lightweight k3s/k3d
environments. Like kops, it owns its own clusters end-to-end: provision, configure, upgrade,
and destroy. Unlike cloud-managed Kubernetes (EKS, GKE, AKS), k3d-manager targets
environments where you want full control at zero managed-service cost:

- **Local** — k3d on OrbStack (M2/M4 Air, Mac Mini M5)
- **Remote sandbox** — k3s via k3sup on ACG EC2
- **Home lab** — k3s on Mac Mini M5 (planned October 2026)

The plugin layer (Vault, ESO, Istio, ArgoCD, Jenkins, OpenLDAP, Keycloak) deploys
identically against any k3s/k3d cluster. The provider abstraction controls only three
things: create, destroy, and get kubeconfig. Once those are done, plugins take over.

**k3d-manager does not wrap EKS, GKE, or AKS.** Those platforms have excellent dedicated
tooling (eksctl, gcloud, az aks). k3d-manager's value is depth on k3s, not breadth
across clouds.

---

## Currently Shipped

| Version | Highlights |
|---------|-----------|
| v0.9.20 | `_antigravity_launch` Chrome fix + `acg_credentials.js` SPA nav guard — cold-start automation working |
| v0.9.19 | `acg_get_credentials` + `acg_import_credentials` — static Playwright script extracts AWS credentials from Pluralsight sandbox |
| v0.9.18 | Pluralsight URL migration — `_ACG_SANDBOX_URL` + `_antigravity_ensure_acg_session` updated to `app.pluralsight.com` |
| v0.9.17 | Antigravity model fallback (`gemini-2.5-flash` first), ACG session check, nested agent fix (`--approval-mode yolo`) |
| v0.9.16 | Antigravity IDE + CDP browser automation — gemini CLI + Playwright engine; `antigravity_install`, `antigravity_trigger_copilot_review`, `antigravity_acg_extend` |
| v0.9.15 | Antigravity × Copilot coding agent validation; ldap-password-rotator `vault kv put` stdin hardening |
| v0.9.14 | if-count allowlist fully cleared — `_run_command` + `_ensure_node` helpers via lib-foundation PR #13 |
| v0.9.13 | v0.9.12 retro, `/create-pr` `mergeable_state` check, CHANGE.md backfill |
| v0.9.12 | Copilot CLI CI integration, lib-foundation v0.3.6 subtree pull |
| v0.9.11 | Dynamic plugin CI — `detect` job skips cluster tests for docs-only PRs |
| v0.9.10 | if-count allowlist elimination (jenkins) — allowlist now `system.sh` only |
| v0.9.9 | if-count allowlist elimination — 11 ldap helpers + 6 vault helpers extracted |
| v0.9.8 | if-count easy wins + dry-run README doc + BATS coverage |
| v0.9.7 | lib-foundation sync (`_run_command_resolve_sudo`), `deploy_cluster` no-args guard, `bin/` `_kubectl` wrapper |
| v0.9.6 | ACG sandbox plugin (`acg_provision/status/extend/teardown`), VPC/SG idempotency, `ACG_ALLOWED_CIDR` security |
| v0.9.5 | `deploy_app_cluster` — EC2 k3sup install + kubeconfig merge; replaces manual rebuild |
| v0.9.4 | autossh tunnel plugin, ArgoCD cluster registration, smoke-test gate, `_run_command` TTY fallback |
| v0.9.3 | TTY fix (`_DCRS_PROVIDER` global), lib-foundation v0.3.2 subtree, cluster rebuild smoke test |

---

## v0.9.21 — `_ensure_k3sup` (upcoming)
*Focus: k3sup auto-install — prerequisite for v1.0.0 multi-node work*

- `_ensure_k3sup` helper in `scripts/plugins/shopping_cart.sh` — follows `_ensure_node`/`_ensure_copilot_cli` pattern
- `deploy_app_cluster` replaces raw `command -v k3sup` check with `_ensure_k3sup`
- Install paths: `brew install k3sup` (macOS/Linuxbrew), `curl | sh` (Debian/Ubuntu + sudo), `_err` guidance if both unavailable
- BATS coverage: k3sup present → returns 0; absent + brew → installs; absent + no brew → error

---

## v1.0.0 — AWS/ACG: Multi-Node k3s Cluster + Samba AD
*Focus: 3-node k3sup cluster on ACG — resolves single t3.medium resource exhaustion*

**Motivation:** Single t3.medium (4GB) at 95% capacity is a structural blocker for
all 5 shopping-cart pods. ACG allows up to 5 concurrent t3.medium instances. Three nodes
gives control-plane isolation, workload distribution, and a dedicated identity/data tier —
matching real k8s topology at zero cost.

### Node Layout (3 × t3.medium — ACG)

| Node | Role | Workloads |
|------|------|-----------|
| Node 1 | Control plane | k3s server, ArgoCD, Vault, ESO |
| Node 2 | App worker | basket, frontend, order, payment, product-catalog |
| Node 3 | Data + Identity | PostgreSQL, RabbitMQ, Redis, Samba AD DC |

### New CLUSTER_PROVIDER value: `k3s-remote`

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager deploy_cluster
```

- `deploy_cluster` calls `acg_provision` three times → 3 EC2 instances
- `k3sup install` on Node 1 (control plane)
- `k3sup join` on Node 2 + Node 3 (workers)
- Node taints + labels applied
- Tunnel started automatically (`tunnel_start` — Node 1)
- Kubeconfig merged as `ubuntu-k3s`

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager destroy_cluster
# terminates all 3 EC2 instances, stops tunnel, removes kubeconfig context
```

### Samba AD DC Plugin

```bash
DIRECTORY_SERVICE_PROVIDER=activedirectory ./scripts/k3d-manager deploy_directory
```

- Deploys `samba-ad-dc` container on Node 3
- Replaces OpenLDAP simulation with real AD protocol behavior
- Resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev-only debt
- `DIRECTORY_SERVICE_PROVIDER=openldap` remains the default for local k3d

### Milestone Gate

All 5 shopping-cart pods Running + Playwright E2E green = v1.0.0 done.

---

## v1.0.1 — GCP Cloud Provider
*Focus: k3s on GCP Compute Engine — second cloud backend*

**New `CLUSTER_PROVIDER` value:** `k3s-gcp`

- `acg_provision` equivalent for GCP: provision Compute Engine VM(s) via `gcloud`
- k3sup install + kubeconfig merge (same pattern as ACG/k3s-remote)
- Plugin layer identical — no changes needed above the provider abstraction
- Credential extraction: GCP service account key → `~/.config/gcloud/`
- Milestone gate: basket-service Running on GCP-provisioned k3s + `kubectl get nodes` shows Ready

---

## v1.0.2 — Azure Cloud Provider
*Focus: k3s on Azure VM — third cloud backend*

**New `CLUSTER_PROVIDER` value:** `k3s-azure`

- `acg_provision` equivalent for Azure: provision Azure VM(s) via `az`
- k3sup install + kubeconfig merge (same pattern as ACG/GCP)
- Credential extraction: Azure service principal → `~/.azure/`
- Milestone gate: basket-service Running on Azure-provisioned k3s + `kubectl get nodes` shows Ready

---

## v1.1.0 — Full Stack Provisioning (Single Command)
*Focus: One command brings up k3s cluster + complete plugin stack*

```bash
CLUSTER_PROVIDER=k3s-remote ./scripts/k3d-manager provision_full_stack
# acg_provision × N → deploy_cluster → deploy_vault → deploy_eso → deploy_istio
# → deploy_argocd → register_app_cluster → shopping-cart apps synced
```

- `provision_full_stack` orchestrates the complete lifecycle in sequence
- Idempotent — safe to re-run after partial failure
- `teardown_full_stack` — inverse: destroy apps → deregister → destroy cluster → acg_teardown × N

---

## v1.2.0 — k3dm-mcp
*Focus: MCP server wrapping k3d-manager CLI — AI-driven cluster operations*

**Gate:** v1.0.0 multi-node proven. k3d (local) + k3s-remote (ACG) = two backends,
enough surface for a useful provider-agnostic MCP API.

**Sudo pre-flight requirement:** k3dm-mcp agents run non-interactively — any sudo
password prompt will hang the agent with no TTY to respond. Before v1.2.0 ships:
- `deploy_cluster` / `deploy_app_cluster` must include a pre-flight check:
  `ssh <host> sudo -n true 2>/dev/null` — fail fast with `_err` if passwordless sudo
  is not configured rather than hanging on a prompt
- Target node prerequisite documented: "provisioning user must have passwordless sudo
  (`NOPASSWD:ALL` in `/etc/sudoers.d/`)"
- ACG EC2 ubuntu user is passwordless by default — no change needed for that path
- Home lab (Mac Mini M5, v1.3.0) and any self-managed VMs must be pre-configured

**Discrete repo:** `wilddog64/k3dm-mcp`

**MCP tools (initial set):**
- `deploy_cluster` / `destroy_cluster` — k3d + k3s-remote
- `deploy_vault`, `deploy_eso`, `deploy_argocd`
- `acg_provision`, `acg_extend`, `acg_teardown`
- `sync_state` — cluster health snapshot

**Transport:** HTTP (default), stdio (optional). `K3DM_MCP_TRANSPORT=http|stdio`.

**Key design invariants:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` in all subprocess envs
- No raw kubectl output to LLM — SQLite state cache only
- Blast radius classification on every mutating tool
- Dry-run gate before any destructive operation

---

## v1.3.0 — Distribution Packages
*Focus: Install k3d-manager as a system package — no manual clone required*

**Debian/RedHat package** — `apt install k3d-manager` / `dnf install k3d-manager`
- Installs dispatcher + libs to `/usr/local/lib/k3d-manager/`
- Symlinks `k3d-manager` into `/usr/local/bin/`
- Packaged with `fpm` or native `dpkg`/`rpmbuild`

**Homebrew formula** — `brew install k3d-manager` (Mac-first, fits current user base)

**Gate:** v1.2.0 k3dm-mcp shipped — tool must be feature-stable before packaging.

---

## v1.4.0 — Home Lab (Mac Mini M5)
*Focus: k3s on Mac Mini M5 as always-on home cluster*

**Target hardware:** Mac Mini M5 (October 2026)

**New `CLUSTER_PROVIDER` value:** `k3s-local-arm64`

- k3s installed natively on Mac Mini via k3sup (loopback — `k3sup install --host localhost`)
- Always-on: launchd service, starts on boot
- WireGuard peer — M4 Air connects remotely from anywhere
- Home automation plugins: Home Assistant, Mosquitto MQTT, Node-RED, InfluxDB, Grafana, Zigbee2MQTT
- Managed by k3d-manager the same way as ACG EC2 — same plugin interface

**`homehub-mcp`** (separate repo) — home automation operations via MCP.
Not merged into `k3dm-mcp` — separate concern, separate lifecycle.

---

## Architectural Boundary

**k3d-manager owns k3s/k3d clusters end-to-end.** It does not wrap EKS, GKE, or AKS.
For cloud-managed Kubernetes, use eksctl, gcloud, or az aks — they are better tools
for that job. k3d-manager's lane is lightweight k3s at zero managed-service cost,
with an opinionated plugin stack that runs identically in every environment it supports.

`CLUSTER_PROVIDER` controls only: create, destroy, get kubeconfig.
Once those are done — plugins take over. Plugins speak only Kubernetes primitives
(`kubectl`, `helm`) and have no opinion on what is underneath.

---

## Shopping-Cart App Rigor Gap

The 13 shopping-cart repos (basket, order, payment, product-catalog, frontend, infra, e2e-tests,
rabbitmq-client-*) have solid CI pipelines (lint, test, security scan per language) but zero
commit-time enforcement and no agent instruction files.

**Missing across all repos:**

| Gap | Impact |
|-----|--------|
| No pre-commit hooks | Broken code reaches CI before failing; agents can push without local validation |
| No `AGENTS.md` / `CLAUDE.md` | No scope rules, no off-limits file lists, no "do not create PRs" for AI agents |
| No commit message convention | Codex/Gemini use inconsistent formats; no Conventional Commits enforcement |

**What already exists (do not duplicate in pre-commit):**
- Java: Checkstyle + OWASP dep-check (Maven)
- Go: golangci-lint + govulncheck
- Python: ruff + mypy + pip-audit
- TypeScript: ESLint + Prettier + tsc + Jest + Playwright

**Planned additions (track for v1.1.0 or a dedicated shopping-cart hardening sprint):**

1. **`AGENTS.md` per repo** — language, framework, test command, off-limits files (`.github/`, infra manifests), commit message format, "do not create PRs"
2. **Pre-commit hooks per repo** — mirror what CI already runs locally:
   - Java: `mvn checkstyle:check`
   - Go: `gofmt -l .` + `golangci-lint run`
   - Python: `ruff check .` + `ruff format --check .`
   - TypeScript: `eslint src/` + `prettier --check`
3. **Shared `.pre-commit-config.yaml` template** — one template in `shopping-cart-infra`, symlinked or copied to each app repo

**Priority:** Low — CI gates already catch issues before merge. Pre-commit is developer-experience
and agent-safety hardening, not a blocker for v1.0.0.

---

## Engineering Standards

1. **Spec-first** — no milestone implemented without a plan doc in `docs/plans/`
2. **Rollback-safe** — repository must be deployable at every commit on main
3. **Bash-native** — no heavy frameworks; all orchestration in shell or lean MCP servers
4. **No ADKs** — reject LangChain, CrewAI, and similar. Sovereign, auditable tooling only
5. **Max 5 plan docs per release** — if a milestone exceeds 5 specs, split before writing a 6th
6. **BATS coverage required** — every new plugin function needs `env -i` clean BATS tests
