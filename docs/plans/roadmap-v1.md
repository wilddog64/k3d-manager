# k3d-manager Strategic Roadmap: Towards v1.0.0

## Vision
Transform `k3d-manager` from a collection of Bash utility scripts into a self-orchestrating, multi-agent platform capable of autonomous infrastructure management and self-healing.

---

## v0.6.x — The Tooling Baseline (Current)
*Focus: Stabilization & AI Plumbing*

- **v0.6.1 (Merged):** Standardize infra cluster structure (`secrets`, `identity`, `cicd` namespaces) and fix Istio sidecar Job hangs.
- **v0.6.2 (Active):** `copilot-cli` integration.
  - Implement `_ensure_node` and `_ensure_copilot_cli` system helpers.
  - Establish the "Universal Brew" discovery pattern.
  - Activate the High-Rigor Engineering Protocol (Spec-First + Checkpointing).
- **v0.6.3 (Planned):** Shared Library Foundation.
  - Extract `core.sh` and `system.sh` (including Copilot logic) into a discrete `lib-foundation` repository.
  - Implement **git subtree** integration to share these primitives across `k3d-manager` and `rigor-cli`.
  - Maintain "Zero-Dependency" for end-users while enabling bi-directional updates for developers.

## v0.7.0 — The Agent-Assisted Phase
*Focus: AI as a Code Generator*

- **Minor Version Change:** Introduction of AI-driven feature architecture.
- **Key Features:**
  - Implement Keycloak Provider Interface (Bitnami + Operator support).
  - Use `copilot-cli` to autonomously scaffold new plugins and BATS test suites.
  - Standardize "Template Specs" that can be fed directly to AI for consistent code generation.

## v0.8.0 — The Multi-Agent Orchestration Foundation
*Focus: AI as a Teammate (MCP & Orchestration)*

- **Minor Version Change:** Significant expansion of CLI capability via Model Context Protocol (MCP) and agent routing.
- **Key Features:**
  - **The MCP Server:** Transform `k3d-manager` into an MCP-compatible server. This allows external agents (Claude, GPT, specialized swarms) to invoke `k3d-manager` functions as "Verified Tools."
  - **The Orchestrator:** Introduce a top-level `intent` command that parses high-level goals into multi-agent task graphs.
  - **Role-Based Delegation (The "Crew"):**
    - **Architect Agent:** Uses MCP to map dependencies and audit cluster state (K8s-native discovery).
    - **Security Agent:** Specialized in Vault PKI, ESO role lifecycle, and credential auditing.
    - **SRE Agent:** Monitors "Golden Signals" and health checks via MCP tool calls.
    - **Test Agent:** Orchestrates BATS suites and validates logic integrity.
  - **Context Sharing:** Establish a shared "Agentic Memory" (leveraging the Memory Bank) to persist reasoning across agent handoffs.

## v0.9.0 — The Autonomous SRE (Operator Phase)
*Focus: AI as an Operator (Active Monitoring & Self-Healing)*

- **Minor Version Change:** Introduction of resident background agents and active feedback loops.
- **Key Features:**
  - **Auto-Diagnosis:** Failed commands automatically pipe logs to a "Diagnostics Agent" for root-cause analysis.
  - **Self-Healing:** System-initiated fixes for known failure patterns (e.g., auto-reunsealing Vault, cleaning stale PVCs, resolving Istio sidecar conflicts).
  - **Cross-Cluster Watcher:** A background process that synchronizes state and secrets between the macOS Infra cluster and Ubuntu App cluster without human triggers.

## v1.0.0 — Production-Ready Agentic Platform
*Focus: API Stability & Total Autonomy*

- **Major Version Change:** The underlying Bash API, plugin architecture, and Multi-Agent interactions are considered stable.
- **Key Features:**
  - **Zero-Touch Provisioning:** The swarm can take a high-level architecture requirement and build the entire environment from scratch.
  - **Human-in-the-Loop (HITL) Protocol:** Formalized "Guardrail" prompts for destructive actions, ensuring the human remains the ultimate authority.
  - **Complete Documentation:** Full auto-generated documentation for the entire agentic ecosystem.

---

## Engineering Standards
1. **Spec-First:** No new roadmap milestones are implemented without a confirmed investigation and plan.
2. **Checkpointing:** The repository must remain rollback-safe at every stage of the agentic evolution.
3. **Bash-Native:** AI orchestration must respect the "Zero-Dependency" (or auto-installing dependency) philosophy of the project.
