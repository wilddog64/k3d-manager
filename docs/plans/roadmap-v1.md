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

## v0.8.1 — Trace UI
*Focus: Visual observability for local dev*

- **Key Feature:** Jaeger trace UI as an optional sidecar alongside the MCP server.
- **Implementation:**
  - `k3dm-mcp start --with-tracing` spins up a single `jaegertracing/all-in-one` Docker container
  - v0.8.0 OTLP span output exported to Jaeger — no instrumentation changes required
  - UI available at `localhost:16686` while MCP server is running
  - Container tears down with the MCP server
- **No Grafana:** Jaeger's built-in UI is sufficient for local dev. Grafana/Tempo is
  a shared-team concern, not a local dev tool concern.
- **Dependency:** Docker (already required for k3d).

## v1.0.0 — Reassess After v0.7.0
*Scope TBD — revisit once v0.7.0 ships*

Potential directions to evaluate:
- API stability declaration for the Bash CLI and MCP tool surface.
- Zero-touch provisioning for new clusters.
- Formalized Human-in-the-Loop (HITL) protocol for destructive operations.
- Auto-generated documentation for the full ecosystem.

Previous v0.9.0 (Autonomous SRE) and v0.10.0 (Fleet Provisioning) milestones
were removed — they exceeded the project's scope as a local dev tool. If fleet
management becomes a real need, it belongs in a separate tool built on
`lib-foundation`.

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
