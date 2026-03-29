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

## v1.0.0 — `k3s-aws` Provider Foundation
*Focus: establish `CLUSTER_PROVIDER=k3s-aws`; single-node deploy/destroy; SSH config auto-update*

**Rename:** `k3s-remote` → `k3s-aws` — symmetric naming with `k3s-gcp` and `k3s-azure`.

```bash
CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster
CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager destroy_cluster
```

- `deploy_cluster` with `k3s-aws`: `acg_provision` (single node) → `_ensure_k3sup` → k3sup install → kubeconfig merge → tunnel start
- `destroy_cluster` with `k3s-aws`: `acg_teardown` → stop tunnel → remove kubeconfig context
- **SSH config auto-update**: `acg_provision` writes new EC2 IP back to `~/.ssh/config` `ubuntu` + `ubuntu-tunnel` HostName entries automatically
- Milestone gate: single node Ready, `kubectl get nodes` works from M2 Air via tunnel

---

## v1.0.1 — Multi-Node Expansion (3 × t3.medium)
*Focus: 3-node k3sup cluster — resolves single t3.medium resource exhaustion*

**Motivation:** Single t3.medium (4GB) at 95% capacity structurally blocks all 5 shopping-cart
pods. ACG allows up to 5 concurrent instances. Three nodes gives control-plane isolation,
workload distribution, and a dedicated data tier.

### Node Layout

| Node | Role | Workloads |
|------|------|-----------|
| Node 1 | Control plane | k3s server, ArgoCD, Vault, ESO |
| Node 2 | App worker | basket, frontend, order, payment, product-catalog |
| Node 3 | Data + Identity | PostgreSQL, RabbitMQ, Redis, Samba AD DC |

- `deploy_cluster` calls `acg_provision` × 3 → k3sup install on Node 1 → k3sup join × 2
- Node taints + labels applied (control-plane taint, app/data worker labels)
- Tunnel started automatically from Node 1
- Milestone gate: 3 nodes Ready in `kubectl get nodes`

**`k3d-manager doctor`:** Pre-flight diagnostic command. Checks all prerequisites and
reports green/red per item before the operator runs `deploy_cluster`:

```
✓ aws CLI, k3sup, autossh, kubectl, node, Playwright
✓/✗ Antigravity (port 9222 open)
✓/✗ AWS credentials valid (sts get-caller-identity)
✓/✗ SSH config — Host ubuntu + Host ubuntu-tunnel present
✓/✗ SSH key — ~/.ssh/k3d-manager-key.pem exists
```

Non-zero exit if any check fails. Operator-facing — no cluster knowledge required.

**lib-agc preparation (step 1 of 3):** `aws_provision` namespace refactor.
Promote `acg_provision` → `_acg_provision` (private). Add `aws_provision` public entry point
with `_aws_is_acg_sandbox()` auto-detection. `acg_provision` becomes deprecated alias.
Goal: no k3d-manager-external caller should need to know about ACG internals.

---

## v1.0.2 — Full Stack on 3 Nodes
*Focus: all 5 shopping-cart pods Running on the multi-node cluster*

- Workload placement: app pods scheduled to Node 2, data tier (PostgreSQL, RabbitMQ, Redis) to Node 3
- ArgoCD sync from infra cluster → app cluster
- Milestone gate: all 5 pods Running + Playwright E2E green

**lib-agc preparation (step 2 of 3):** Dependency audit.
Verify `acg.sh`, `aws.sh`, and `antigravity.sh` have zero imports from k3d-manager core
(`core.sh`, `cluster_provider.sh`, `_kubectl`). Any found dependencies are extracted or
replaced with self-contained equivalents. Shared helpers (`_info`, `_err`, `_run_command`)
are the only permitted cross-boundary calls — these will be satisfied by `lib-foundation`
after extraction.

---

## v1.0.3 — Samba AD DC Plugin
*Focus: real Active Directory protocol — replaces OpenLDAP simulation*

```bash
DIRECTORY_SERVICE_PROVIDER=activedirectory ./scripts/k3d-manager deploy_directory
```

- Deploys `samba-ad-dc` container on Node 3
- Resolves `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` dev-only debt
- `DIRECTORY_SERVICE_PROVIDER=openldap` remains the default for local k3d
- Milestone gate: AD auth working end-to-end; `TRUST_ALL_CERTIFICATES` flag removed from production paths

**lib-agc preparation (step 3 of 3):** Standalone source test.
Add a BATS test that sources `acg.sh`, `aws.sh`, `antigravity.sh` in a clean `env -i`
environment (no k3d-manager dispatcher, no `SCRIPT_DIR` pre-set) and confirms all public
functions are defined. Passing this test is the extractability gate — if it passes,
`lib-agc` can be created as an independent repo at any point after v1.0.3.

---

## v1.0.4 — GCP Cloud Provider
*Focus: k3s on GCP Compute Engine — second cloud backend*

**New `CLUSTER_PROVIDER` value:** `k3s-gcp`

- Provision Compute Engine VM(s) via `gcloud`
- k3sup install + kubeconfig merge (same pattern as `k3s-aws`)
- Credential extraction: GCP service account key → `~/.config/gcloud/`
- Milestone gate: basket-service Running on GCP-provisioned k3s

---

## v1.0.5 — Azure Cloud Provider
*Focus: k3s on Azure VM — third cloud backend*

**New `CLUSTER_PROVIDER` value:** `k3s-azure`

- Provision Azure VM(s) via `az`
- k3sup install + kubeconfig merge (same pattern as `k3s-aws`)
- Credential extraction: Azure service principal → `~/.azure/`
- Milestone gate: basket-service Running on Azure-provisioned k3s

---

## Post-v1.0.5 — Extract `lib-agc`
*Gate: all 3 cloud providers shipped (k3s-aws, k3s-gcp, k3s-azure)*

ACG sandbox tooling is not cluster lifecycle — it is Pluralsight/AWS sandbox automation.
Once k3d-manager manages 3 cloud backends, the ACG-specific code should live in its own repo.

**New repo:** `wilddog64/lib-agc`

**Extraction scope:**

| File | Destination |
|------|-------------|
| `scripts/plugins/acg.sh` | `lib-agc` — Playwright, CDP, sandbox lifecycle |
| `scripts/plugins/aws.sh` | `lib-agc` — `aws_import_credentials`, `_aws_write_credentials` |
| `scripts/plugins/antigravity.sh` | `lib-agc` — `_antigravity_launch`, CDP browser automation |

**Integration:** k3d-manager sources `lib-agc` as a git subtree at `scripts/lib/agc/`,
same pattern as `lib-foundation` at `scripts/lib/foundation/`.

**k3dm-mcp** also depends on `lib-agc` directly — separate consumer, separate subtree pull.

---

## Pre-v1.1.0 — `aws_provision` Namespace Refactor
*Pre-requisite for k3dm-mcp: public entry point + ACG auto-detection*

Before the MCP layer is built, `acg_provision` must be promoted to a generic public API.
AI agents should call `aws_provision`, not know ACG-specific internals.

**Design:**

```
aws_provision()          ← public — calls _aws_is_acg_sandbox() to route
  _aws_is_acg_sandbox()  ← private — checks `aws sts get-caller-identity` ARN for "cloud_user"
  _acg_provision()       ← private — current acg_provision logic renamed
  _aws_ec2_provision()   ← stub — _err "not yet implemented" (future: raw EC2 CLI path)
```

**Detection logic:**

```bash
function _aws_is_acg_sandbox() {
  local arn
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
  [[ "$arn" == *"cloud_user"* ]]
}
```

**Routing:**

```bash
function aws_provision() {
  if _aws_is_acg_sandbox; then
    _acg_provision "$@"
  else
    _err "[aws] Non-ACG EC2 provisioning not yet implemented"
    return 1
  fi
}
```

**Rule:** `acg_provision` kept as deprecated alias → `aws_provision` until k3dm-mcp ships.
**Gate:** implement before v1.2.0 (k3dm-mcp); k3dm-mcp tools must call `aws_provision`, not `acg_provision`.

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
