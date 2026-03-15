# k3d-manager Strategic Roadmap: Towards v1.0.0

## Vision
Transform `k3d-manager` from a collection of Bash utility scripts into an
AI-assistable local Kubernetes platform — operable from any MCP-compatible
desktop client (Claude Desktop, OpenAI Codex, ChatGPT Atlas, Perplexity Comet).

---

## v0.6.x — The Tooling Baseline (Current)
*Focus: Stabilization & AI Plumbing*

- **v0.6.1 (Merged):** Standardize infra cluster structure (`secrets`, `identity`, `cicd` namespaces) and fix Istio sidecar Job hangs.
- **v0.6.2 (Active):** Copilot CLI Integration & Security Hardening.
  - Implement `_ensure_node` and `_ensure_copilot_cli` system helpers (auto-install pattern).
  - Implement `_k3d_manager_copilot` scoped passthrough wrapper with deny-tool guardrails.
  - Implicit `K3DM_ENABLE_AI` gating — all AI features opt-in, graceful auth failure.
  - Security: stdin-based secret injection for Vault KV, `_safe_path` helper, instruction integrity checks.
  - Plan: `docs/plans/v0.6.2-ensure-copilot-cli.md`
- **v0.6.3 (Planned):** The Great Refactor & Digital Auditor.
  - Refactor `core.sh` and `system.sh` to eliminate "Defensive Bloat" (redundant logic).
  - Reduce cyclomatic complexity and standardize OS-specific "footprints."
  - Implement `_agent_lint` (copilot-cli-powered architectural auditor) and `_agent_audit` (test-weakening detection).
  - Plan: `docs/plans/v0.6.3-refactor-and-audit.md`
- **v0.6.4 (Planned):** Shared Library Foundation.
  - Extract `core.sh` and `system.sh` into a discrete `lib-foundation` repository.
  - Implement **git subtree** integration across `k3d-manager`, `rigor-cli`, and `shopping-carts`.

## v0.7.0 — The Agent-Assisted Phase
*Focus: AI as a Code Generator + App Cluster Deployment*

- **Key Features:**
  - Implement Keycloak Provider Interface (Bitnami + Operator support).
  - Use `copilot-cli` to autonomously scaffold new plugins and BATS test suites.
  - Standardize "Template Specs" that can be fed directly to AI for consistent code generation.
  - Deploy ESO on Ubuntu app cluster and shopping-cart stack (PostgreSQL, Redis, RabbitMQ, apps).

## v0.8.0 — Security Hardening + lib-foundation Backlog
*Focus: Close open security gaps in k3d-manager before MCP integration*

### Vault-Managed ArgoCD Deploy Keys
Empty-passphrase SSH deploy keys stored on disk are insecure and hard to rotate.
Move all ArgoCD GitHub repo credentials into Vault — ESO syncs them to Kubernetes secrets,
ArgoCD reads from those secrets. No key files on disk.

- One Vault KV entry per repo: `secret/argocd/deploy-keys/<repo-name>`
- ESO `ExternalSecret` per repo → syncs to `argocd-repo-<name>` secret in `cicd` ns
- New Vault policy: `argocd-deploy-key-reader` (read-only on `secret/argocd/deploy-keys/*`)
- New function: `configure_vault_argocd_repos` in a plugin
- **Rotation:** `vault kv put secret/argocd/deploy-keys/<repo> private_key=@<new-key>` →
  ESO syncs → ArgoCD picks up automatically → update GitHub deploy key. One operation.
- Motivated by: shopping cart deploy keys with empty passphrases discovered during v0.7.3

### Certificate Management (SC-081 Readiness)
CA/Browser Forum Ballot SC-081 compresses public TLS cert lifetimes to 47 days by 2029.
Manual renewal at that cadence is not viable. k3d-manager already handles cluster-internal
certs via Vault PKI — this adds ACME-based auto-renewal for external-facing services.

**Two-issuer architecture:**
- **Vault PKI** — unchanged, handles internal service mesh certs. CA owned by us.
- **cert-manager + ACME** — new, handles external-facing ingress certs (Let's Encrypt).

**New plugin: `deploy_cert_manager`**
```bash
./scripts/k3d-manager deploy_cert_manager                          # Let's Encrypt staging
./scripts/k3d-manager deploy_cert_manager --production             # Let's Encrypt production
ACME_EMAIL=user@example.com ./scripts/k3d-manager deploy_cert_manager
```

- Installs cert-manager via Helm (pinned chart version)
- Configures `ClusterIssuer` for Let's Encrypt ACME (HTTP-01 via Istio ingress)
- Annotates existing ingress resources to use cert-manager issuer
- Provider-aware extension in v1.0.0: ACM (EKS), GCP Certificate Manager (GKE), Key Vault (AKS)

### lib-foundation Backlog
- `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- Sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- Add `.github/copilot-instructions.md` to lib-foundation

### Shopping Cart CI Stabilization + Code Quality Gates

Execution order is fixed — each step unblocks the next:

1. **Fix CI failures (P1 first, P2 second):**
   - basket + product-catalog: replace custom Trivy install with `aquasecurity/trivy-action@0.30.0` in infra workflow
   - frontend: remove unused imports + add `"types": ["vite/client"]` to tsconfig
   - payment: fix `mvnw` init failure
   - order: publish `rabbitmq-client-java` to GitHub Packages or add CI pre-install step

2. **Add missing linters (after CI is green):**
   - basket: `golangci-lint` + `go vet`
   - order: Checkstyle + OWASP dependency check
   - product-catalog: `ruff check` + `mypy` + `black --check`
   - payment: Checkstyle/SpotBugs (OWASP already present)
   - frontend: already enforces ESLint + Prettier + `tsc --noEmit`

3. **Branch protection (after linters pass):**
   - All 5 repos: require PR, required status checks, no force push, dismiss stale reviews
   - Automated via `configure_shopping_cart_branch_protection` in `scripts/plugins/shopping_cart.sh`

### Shopping Cart E2E — Playwright MCP (deferred to v0.8.1)

`@playwright/mcp` runs **outside the cluster** on the dev machine. The AI client (Claude,
Copilot, or Gemini CLI) drives browser automation via MCP tool calls. No Chrome-in-cluster
needed — simpler, no resource pressure on Ubuntu k3s node.

**Prerequisite chain:** CI green → images in ghcr.io → ArgoCD syncs → services running →
branch protection enforced → then Playwright MCP can test against live services.

**Design:**
- `@playwright/mcp` runs as a local process on dev machine
- Browser connects to shopping-cart-frontend via `port-forward.sh` or Istio ingress
- Tests live in `shopping-cart-e2e-tests/` repo (already has Playwright structure + flow specs)
- Copilot already has Playwright MCP built in — zero extra setup for test generation
- Trigger: manual via Claude/Copilot MCP session, or CI job that installs + runs Playwright

**Hardware note:** M5 Mac mini (Oct 2026) — revisit parallel test execution when hardware upgrades.

**Tool boundary:**
- Playwright MCP → tests apps you own and control
- Google Antigravity → interacts with third-party UIs you cannot control (ACG sandbox — v1.0.0)

---

## k3dm-mcp — Separate Repository (after v0.8.0)
*Discrete repo: [github.com/wilddog64/k3dm-mcp](https://github.com/wilddog64/k3dm-mcp)*

Lean MCP server wrapping the k3d-manager CLI. Exposes cluster operations as structured MCP
tools callable from any MCP-compatible AI client. Owns its own memory-bank and roadmap.

**Full scope:** see `k3dm-mcp/docs/plans/roadmap.md`

**Key design decisions carried forward from k3d-manager planning:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` always set in subprocess env
- Explicit subprocess env — no ambient shell state
- SQLite state cache — never dump raw kubectl output to LLM
- Blast radius classification, dry-run gate, pre-destroy snapshot
- Loop detection + session call limit + credential scan on tool args
- BATS-based MCP test harness (env -i, record-replay fixtures)

## v0.8.1 — Trace UI (Optional, k3dm-mcp)
*Focus: Visual observability for local dev — no hard dependencies*

- **Key Feature:** Jaeger trace UI as an opt-in sidecar. Environments without Docker
  continue to use v0.8.0 span file output unchanged.
- **Gating:** `ENABLE_JAEGER=1` — consistent with `ENABLE_OTEL=1` and `ENABLE_TRACE=1`.
  Off by default. Never required. Never assumed.
- **Implementation:**
  - `ENABLE_JAEGER=1 k3dm-mcp start` spins up a single `jaegertracing/all-in-one` container
  - v0.8.0 OTLP span output exported to Jaeger — no instrumentation changes required
  - UI available at `localhost:16686` while MCP server is running
  - Container tears down with the MCP server
- **Capability matrix:**

  | Environment | `ENABLE_OTEL` | `ENABLE_JAEGER` |
  |---|---|---|
  | Bare metal k3s, no Docker | spans to file | not available |
  | Local dev with Docker | spans to file | Jaeger UI |
  | CI pipeline | spans to stdout | not available |
  | Air-gapped | spans to file | not available |
  | External OTLP backend (Tempo, Datadog) | configure OTLP endpoint | not needed |

- **No Grafana:** Jaeger's built-in UI is sufficient for local dev. Grafana/Tempo is
  a shared-team concern, not a local dev tool concern.
- **Dependency:** Docker — optional. k3s/bare metal environments use span file output only.

## v0.9.1 — vCluster Plugin + Playwright E2E in CI
*Focus: Ephemeral tenant clusters for isolated testing*

**Motivation:** Shopping-cart has no real traffic — the value is fast lifecycle, not scale.
Spin up a clean vCluster tenant, deploy the full stack, run Playwright E2E tests, tear it down.
Clean slate every PR run, no shared cluster state pollution.

**Track 1a — vCluster plugin (`scripts/plugins/vcluster.sh`):**
```bash
./scripts/k3d-manager vcluster_create  <name>   # spin up tenant cluster inside host
./scripts/k3d-manager vcluster_destroy <name>   # tear it down
./scripts/k3d-manager vcluster_use     <name>   # switch kubeconfig to tenant
./scripts/k3d-manager vcluster_list            # list active tenant clusters
```
- `VCLUSTER_NAMESPACE` env var — target namespace in host (default: `vclusters`)
- `VCLUSTER_VERSION` env var — pin chart version, no floating `latest`
- Prerequisite check: verify host cluster context is active before any operation
- dry-run gate inherited from `_run_command`
- BATS coverage: `scripts/tests/plugins/vcluster.bats` (`env -i` clean)

**Track 1b — Playwright E2E in CI (`shopping-cart-infra`):**
```
PR opened on any shopping-cart repo
→ CI: vcluster_create shopping-cart-e2e
→ deploy full stack (ESO + shopping-cart-data + apps) into tenant
→ Playwright runs E2E against tenant services
→ pass/fail reported to PR
→ vcluster_destroy shopping-cart-e2e
```
- Playwright runs outside the cluster on the CI runner (no Chrome-in-cluster)
- Tests live in `shopping-cart-e2e-tests/` repo
- Prerequisite: images in ghcr.io (CI stabilization complete ✅)

**Spec:** `docs/plans/v0.9.1-vcluster-plugin.md`

---

## v0.9.0 — Messaging Gateway
*Focus: Natural language interface for cluster operations*

**Motivation:** k3dm-mcp (v0.8.0) exposes cluster ops as MCP tools. v0.9.0 adds a
messaging layer so those tools can be triggered from chat — Slack, Telegram, or any
channel the team already uses. Builds on OpenClaw's architecture concept but with
security-first design: Vault for credentials, blast radius classification enforced,
no raw token storage in config files.

**Key features:**
- Slack-first channel adapter (webhook receiver → intent parser → k3dm-mcp tool call)
- Natural language → deterministic MCP tool mapping (no free-form LLM execution)
- Async notification back to channel: "Deploy complete. Vault unsealed. 7/7 pods healthy."
- Multi-user awareness — team sees operations in shared channel
- Security model inherited from v0.8.0: dry-run gate, blast radius, independent confirmation

**What it is NOT:**
- Not a general-purpose chatbot
- Not a replacement for the CLI — CLI stays the primary interface
- Not a multi-tenant platform — personal/team use only

**Implementation:** Thin TypeScript gateway (Node.js). Shells out to k3dm-mcp via
JSON-RPC stdio. No direct k3d-manager calls — always through the MCP security layer.

---

## v1.0.0 — k3dm-mcp
*Focus: MCP server wrapping k3d-manager CLI — AI-driven cluster operations*

**Motivation:** k3d-manager (v0.9.1) has vCluster + full stack ops. k3dm-mcp exposes those
as structured MCP tools callable from any MCP-compatible AI client (Claude Desktop, Copilot).

**Discrete repo:** [`wilddog64/k3dm-mcp`](https://github.com/wilddog64/k3dm-mcp)

**Key design decisions:**
- One AI Layer Rule: `K3DM_ENABLE_AI=0` always set in subprocess env
- Explicit subprocess env — no ambient shell state
- SQLite state cache — never dump raw kubectl output to LLM
- Blast radius classification, dry-run gate, pre-destroy snapshot
- Loop detection + session call limit + credential scan on tool args
- BATS-based MCP test harness (`env -i`, record-replay fixtures)

**MCP tools exposed (initial set):**
- `deploy_cluster` / `destroy_cluster`
- `deploy_vault`, `deploy_eso`, `deploy_argocd`
- `vcluster_create` / `vcluster_destroy` / `vcluster_use` / `vcluster_list`
- `sync_state` — cluster health snapshot into SQLite

**Full scope:** see `k3dm-mcp/docs/plans/roadmap.md`

---

## v1.1.0 — AWS EKS Provider + ACG Sandbox Lifecycle
*Focus: First cloud provider — AWS is the most common ACG sandbox*

**Motivation:** The architectural boundary already supports this — `CLUSTER_PROVIDER`
abstracts create/destroy/kubeconfig, and plugins speak only Kubernetes primitives.
Adding EKS means k3d-manager deploys the same Vault + ESO + Istio + ArgoCD stack to
AWS without modification to any plugin.

**New CLUSTER_PROVIDER value:**
- `eks` — AWS EKS via `eksctl` (lazy-loaded on first use)
  - kubeconfig via `aws eks update-kubeconfig`
  - Single t3.medium node — sufficient for full stack on ACG sandbox
  - `AWS_SESSION_TOKEN` support for ACG STS credentials

Cloud credentials handled through Vault — never in config files or CLI args.

**Key use case — ACG AWS sandbox lifecycle:**
```
"Spin up my standard stack on this AWS sandbox"
→ CLUSTER_PROVIDER=eks + STS credentials from ACG
→ deploy_cluster: Vault, ESO, Istio, ArgoCD, OpenLDAP
→ SQLite state: records expiry time from ACG session
→ Slack: "Stack ready on EKS. Sandbox expires in 4h. Auto-teardown reminder set."
→ 30min before expiry: "Sandbox expiring soon. Run destroy_cluster to clean up."
```

**ACG login automation — Google Antigravity:**
ACG has no public API — everything goes through the web UI.
Antigravity automates login and STS credential extraction.
Clean handoff: Antigravity outputs credentials → k3dm-mcp injects into Vault → k3d-manager reads.

**Sandbox lifecycle extensions to SQLite state cache:**
- `sandbox_expiry` column — populated from Antigravity output
- `stale: true` flag extended to cover expired sandboxes
- `sync_state` tool warns when sandbox has < 30min remaining

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (EKS + ACG sections)

---

## v1.2.0 — Google GKE Provider
*Focus: Second cloud provider — GCP ACG sandbox support*

**New CLUSTER_PROVIDER value:**
- `gke` — Google GKE via `gcloud container clusters` (lazy-loaded on first use)
  - kubeconfig via `gcloud container clusters get-credentials`
  - Single e2-standard-2 node — sufficient for full stack
  - `GOOGLE_CREDENTIALS_JSON` via process substitution — never written to disk

**ACG GCP sandbox:**
- Service account JSON extracted by Antigravity, injected into Vault
- `gcloud auth activate-service-account --key-file <(echo $GOOGLE_CREDENTIALS_JSON)`

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (GKE section — implementation phase 2)

---

## v1.3.0 — Azure AKS Provider
*Focus: Third cloud provider — Azure ACG sandbox support*

**New CLUSTER_PROVIDER value:**
- `aks` — Azure AKS via `az aks` (lazy-loaded on first use)
  - kubeconfig via `az aks get-credentials`
  - Single Standard_B2s node (Standard_B2ms preferred if quota allows)
  - Resource group lifecycle: create on deploy, delete on destroy
  - Service principal auth: `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET`, `AZ_TENANT_ID` from Vault

**ACG Azure sandbox:**
- Service principal credentials extracted by Antigravity, injected into Vault

**Design spec:** `docs/plans/v1.1.0-multi-cloud-design.md` (AKS section — implementation phase 3)

**API stability:** v1.3.0 declares the full multi-cloud provider surface stable. Breaking
changes require a major version bump. Bash CLI compatibility maintained for all existing scripts.

**Engineering standards inherited:** spec-first, no ADKs, bash-native plugins,
Zero-Dependency philosophy, `env -i` BATS suites for all new providers.

---

## Architectural Boundary

**k3d-manager does not compete with Terraform, Pulumi, or any cloud provisioner.**

Those tools own infrastructure provisioning — VPCs, node groups, IAM, networking.
k3d-manager owns what runs *on top of* the cluster — Vault, ESO, Istio, Jenkins, OpenLDAP, ArgoCD.

The handoff point is a kubeconfig:
```
Terraform/Pulumi provisions EKS/GKE/AKS  →  outputs kubeconfig
k3d-manager points at that kubeconfig    →  deploys and configures the service stack
```

**The plugin layer speaks only Kubernetes primitives** (`kubectl`, `helm`) and has no opinion
on what is underneath. A plugin works identically against:
- k3d on a laptop
- k3s on a Ubuntu VM
- EKS, GKE, AKS, Rancher, Talos — any cluster with a valid kubeconfig

`CLUSTER_PROVIDER` controls only three things: create, destroy, and get kubeconfig.
Once those are done — by k3d-manager or by an external provisioner — the provider
abstraction is finished and the plugins take over.

This boundary is intentional and permanent. k3d-manager's value is **dev/staging environment
parity**: the same stack definition runs locally, in staging, and can target production-grade
clusters without modification. That problem is unsolved by Terraform and Pulumi — it is
k3d-manager's lane.

---

## Engineering Standards
1. **Spec-First:** No new roadmap milestones are implemented without a confirmed investigation and plan.
2. **Checkpointing:** The repository must remain rollback-safe at every stage.
3. **Bash-Native:** AI orchestration must respect the "Zero-Dependency" (or auto-installing dependency) philosophy of the project.
4. **Native Agency (No ADKs):** Explicitly reject heavy Agent Development Kits (e.g., LangChain, CrewAI) to keep the tool lightweight, manageable, and sovereign. All orchestration logic must live in the shell or via lean MCP servers.
