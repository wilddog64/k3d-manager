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

## v0.8.0 — MCP Server for Desktop AI Clients
*Focus: One server, many clients*

- **Key Feature:** Build a lean MCP server (`k3dm-mcp`) that wraps the `k3d-manager` CLI,
  exposing core operations as MCP tools callable from any compatible desktop client.
- **Supported Clients:**
  - Claude Desktop (Anthropic) — native MCP support
  - OpenAI Codex — desktop app, CLI, and VS Code; shares MCP config
  - ChatGPT Atlas (OpenAI) — AI browser with MCP developer mode
  - Perplexity Comet — local MCP on macOS
- **Exposed Tools (initial set):**
  - `deploy_cluster`, `destroy_cluster`
  - `deploy_vault`, `unseal_vault`
  - `deploy_jenkins`, `deploy_ldap`, `deploy_eso`
  - `test smoke [namespace]`
  - `test all` (BATS)
- **Sovereignty Gating:** Destructive actions (destroy, force-redeploy) require
  human confirmation via the MCP client's approval model.
- **Implementation:** Thin MCP server (Node.js or Python) that shells out to
  `./scripts/k3d-manager`. Expected scope: a few hundred lines, single repo or
  subdirectory within `k3d-manager`.
- **Observability:** Structured OpenTelemetry span output, opt-in via `ENABLE_OTEL=1`.
  Each MCP tool call = root span. Each `k3d-manager` subprocess = child span. Output to
  stdout or `/tmp/k3dm.spans`. No external dependencies. Consistent with existing
  `ENABLE_TRACE=1` pattern — off by default, zero overhead when disabled.
- **One AI Layer Rule:** When k3dm-mcp is the tool being called by an AI agent (Claude Desktop,
  Codex, etc.), the subprocess env must always set `K3DM_ENABLE_AI=0`. The MCP caller is
  already the AI reasoning layer — a second AI layer (Copilot CLI) inside the subprocess is
  redundant, opaque, and a dilution risk.
  - MCP tool calls must invoke specific deterministic k3d-manager functions, never AI-assisted ones
  - Structured JSON responses only — no free-form prose that an outer agent must interpret
  - Audit log per tool call via OTel spans — what was called, what env was set, exit code, output
  - Violation of this rule means two AI agents are reasoning about the same action with no
    visibility into each other's logic: error laundering, double confidence, prompt injection risk

- **Environment Isolation:** MCP server must never inherit the parent process environment blindly.
  Each subprocess call to `./scripts/k3d-manager` receives an explicitly constructed env:
  - `SCRIPT_DIR` resolved to an absolute path at server startup
  - `PATH`, `HOME` set explicitly — no ambient shell state
  - `CLUSTER_PROVIDER` and other k3d-manager vars set from MCP server config, not inherited
  - Per-call env is a fresh copy — no state bleeds between tool calls
  - Startup validation: required paths (`scripts/k3d-manager`, `scripts/lib/system.sh`) must
    exist before the server accepts any tool calls — fail fast, not silently mid-call
  - Integration tests run with `env -i` clean environment — same rule as BATS suites
  - Rationale: k3d-manager depends on `SCRIPT_DIR` at source time. A polluted or empty
    inherited env causes silent failures that are hard to debug across MCP clients.
- **Agent Safety Guards:** Structural controls built into the MCP server, not bolted on externally.
  - **Loop detection:** Same tool called 3+ times with identical args in a session → block and
    return structured error. Prevents runaway agent loops and cost spirals.
  - **Session call limit:** Configurable max tool calls per session (`K3DM_MCP_MAX_CALLS`,
    default: 20). Destructive tools (`destroy_cluster`, force-redeploy) count double.
  - **Credential scan:** MCP tool arguments scanned for API key, token, and password patterns
    before forwarding to `k3d-manager`. Block on match — credentials must come from Vault, not args.
  - **Fast-fail, no retry:** MCP server never retries a failed tool call automatically. Failure
    returned to calling agent immediately. The agent decides whether to retry with different args.
  - These guards complement existing shell-layer protections (`_args_have_sensitive_flag`,
    `_run_command` privilege model, Vault + ESO secret injection). Defense in depth — not a replacement.

- **Destructive Operation Controls** *(motivated by real AI+Terraform incident — production DB deleted, snapshots gone, no recovery path)*:

  - **Blast radius classification:** Every exposed MCP tool is tagged `read`, `mutate`, or `destroy`.
    - `read`: `cluster_status`, `argocd app list` — no confirmation required
    - `mutate`: `deploy_vault`, `deploy_jenkins`, `deploy_eso` — single confirmation
    - `destroy`: `destroy_cluster`, force-redeploy — explicit `--confirm` flag required + counts double toward session limit
    - Classification is enforced in the MCP server, not left to the calling agent

  - **Dry-run gate:** `destroy_cluster` and any `mutate`/`destroy` tool must support a `dry_run: true`
    input that returns what would happen without executing. Calling agent should always invoke
    dry-run first and present the plan before requesting actual execution.

  - **Pre-destroy snapshot:** Before any `destroy`-class operation executes, automatically dump
    current cluster state to `scratch/logs/pre-destroy-snapshot-<timestamp>.log`:
    - Running namespaces + pod counts
    - Vault seal status
    - ArgoCD app sync states
    - Provides a recovery reference even after the cluster is gone

  - **Independent confirmation per destructive call:** If an agent chains `destroy_cluster` →
    `deploy_cluster`, each requires its own confirmation. A single approval does not cover a sequence.
    This prevents an agent from collapsing a multi-step destructive chain into one approved action.

- **Context Architecture — SQLite State Cache:**
  MCP tool responses must never dump raw `kubectl` output into the LLM context. Cluster state
  is pre-aggregated into a local SQLite cache; MCP tools query that cache and return structured
  summaries. This keeps token usage efficient and responses deterministic.

  **Two-phase model:**
  - **Sync phase:** `k3dm-mcp` runs `kubectl get pods -A`, `argocd app list`, Vault status on
    demand (triggered by `deploy`, `destroy`, `unseal` tool calls, or explicit `sync_state` tool).
    Results stored in SQLite: one row per pod/service/component with status + timestamp.
  - **Query phase:** `cluster_status` and other read tools query SQLite — no live `kubectl` call.
    Returns aggregated summary: "infra: 7/7 healthy | app: 4/5 healthy (basket: ImagePullBackOff)".

  **SQLite tuning (same as article pattern):** WAL mode, covering indexes on `(namespace, status)`.

  **Staleness signaling:** Every MCP tool response includes `last_synced_at`. If stale beyond a
  configurable threshold (`K3DM_MCP_CACHE_TTL`, default: 5 minutes), the response includes a
  `stale: true` flag so the calling agent can decide whether to trigger a sync first.

  **What this prevents:** LLM reasoning over 300 lines of raw pod output, token waste, and
  confabulation from partial context windows.

- **Testing Strategy:** Two-layer approach — own the regression layer, use MCPSpec as an external audit layer.

  **Layer 1 — Roll our own (BATS-based MCP harness):**
  We control the server, so we control the test surface. Three files:
  - `scripts/tests/mcp/harness.sh` — sends JSON-RPC tool calls via stdio, captures responses
  - `scripts/tests/mcp/audit.sh` — scans tool descriptions for prompt injection patterns,
    excessive permissions, undocumented side effects
  - `scripts/tests/mcp/*.bats` — one test suite per exposed tool

  Each BATS test: send a tool call → assert response shape + exit code → assert no credential
  leak in args. Record-replay via BATS fixtures: capture a tool call + response as a fixture file,
  replay against new server versions to detect regressions. Run with `env -i` clean environment —
  same rule as all other BATS suites.

  **Layer 2 — MCPSpec as external audit (not regression):**
  Run `mcpspec audit` against `k3dm-mcp` as a CI gate for security rule coverage.
  Use pre-built MCPSpec collections for any third-party MCP servers we consume.
  Do NOT depend on MCPSpec for core regression coverage — record-replay fragility
  (timestamps, UUIDs, non-deterministic output) makes it unsuitable as a primary test layer.

  **What we do NOT build:**
  - Dashboard UI — not worth it for a local dev tool
  - Quality scoring — vanity metric without reproducible criteria
  - Active security probing — `_agent_audit` + credential scan in MCP args covers our threat model

## v0.8.1 — Trace UI (Optional)
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

## v1.0.0 — Multi-Cloud + ACG Sandbox Lifecycle
*Focus: Same stack definition, any cloud*

**Motivation:** The architectural boundary already supports this — `CLUSTER_PROVIDER`
abstracts create/destroy/kubeconfig, and plugins speak only Kubernetes primitives.
Adding EKS/GKE/AKS providers means k3d-manager deploys the same Vault + ESO + Istio +
ArgoCD stack to any cloud cluster without modification.

**Key use case — A Cloud Guru (ACG) sandbox lifecycle:**
ACG provides temporary AWS/Azure/GCP sandbox environments (expire after a few hours).
Manual stack setup per session is wasteful. k3dm-mcp automates the full lifecycle:

```
"Spin up my standard stack on this AWS sandbox"
→ CLUSTER_PROVIDER=eks + sandbox credentials from ACG
→ deploy_cluster: Vault, ESO, Istio, ArgoCD, OpenLDAP
→ SQLite state: records expiry time from ACG session
→ Slack: "Stack ready on EKS. Sandbox expires in 4h. Auto-teardown reminder set."
→ 30min before expiry: "Sandbox expiring soon. Run destroy_cluster to clean up."
```

**New CLUSTER_PROVIDER values:**
- `eks` — AWS EKS (kubeconfig via `aws eks update-kubeconfig`)
- `gke` — Google GKE (kubeconfig via `gcloud container clusters get-credentials`)
- `aks` — Azure AKS (kubeconfig via `az aks get-credentials`)

Cloud credentials handled through Vault — never in config files or CLI args.

**Sandbox lifecycle extensions to SQLite state cache:**
- `sandbox_expiry` column — tracks ACG session expiry
- `stale: true` flag extended to cover expired sandboxes
- `sync_state` tool warns when sandbox has < 30min remaining

**API stability:** v1.0.0 declares the MCP tool surface stable. Breaking changes
require a major version bump. Bash CLI compatibility maintained for all existing scripts.

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
