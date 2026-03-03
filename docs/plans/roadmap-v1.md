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

## v0.7.0 — The Agent-Assisted Phase
*Focus: AI as a Code Generator*

- **Minor Version Change:** Introduction of AI-driven feature architecture.
- **Key Features:**
  - Implement Keycloak Provider Interface (Bitnami + Operator support).
  - Use `copilot-cli` to autonomously scaffold new plugins and BATS test suites.
  - Standardize "Template Specs" that can be fed directly to AI for consistent code generation.

## v0.8.0 — The Multi-Agent Orchestration Foundation
*Focus: AI as a Teammate (ADK Integration)*

- **Minor Version Change:** Significant expansion of CLI capability via internal agent routing.
- **Key Features:**
  - **The Orchestrator:** Introduce a top-level `intent` command (e.g., `./k3d-manager intent "Deploy Shopping Cart"`).
  - **ADK Integration:** Integrate a lightweight Agent Development Kit (ADK) to manage state and handoffs between sub-agents.
  - **Role-Based Delegation:**
    - **Architect Agent:** Maps dependencies and verifies cluster resources.
    - **Security Agent:** Manages Vault policies and secret lifecycle.
    - **Test Agent:** Orchestrates parallel BATS execution and reports regressions.

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
