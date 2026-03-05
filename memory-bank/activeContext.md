# Active Context – k3d-manager

## Current Branch: `feature/app-cluster-deploy` (as of 2026-03-01)

**v0.5.0 merged** — Keycloak plugin complete + ARM64 image fix. Infra cluster fully deployed.
**v0.6.1 merged** — infra rebuild bug fixes integrated.
**v0.6.2 in progress** — adoption of High-Rigor Engineering Protocol for App Cluster deployment.

---

## Current Focus

**v0.6.2: Agent Rigor Protocol & Copilot CLI Management**

- [ ] **Checkpoint**: Commit current healthy state of `k3d-manager-v0.6.2`.
- [ ] **Spec-First**: Refine discovery logic for Node.js (Universal Brew + Distro footprints).
- [ ] **Protocol Implementation**: Add `_agent_checkpoint` and `_agent_audit` to `scripts/lib/agent_rigor.sh`.
- [ ] **AI-Powered Linting**: Implement `_agent_lint` using `copilot-cli` for architectural verification (the "Digital Auditor").
- [ ] **Cleanup**: Remove deprecated Colima provider support (standardizing on OrbStack for macOS).
- [ ] **Tool Implementation**: Add `_ensure_node`, `_ensure_copilot_cli`, and the `_k3d_manager_copilot` wrapper to `system.sh`.
- [ ] **Verification**: Audit against correctness, maintainability, and scope.
- [ ] **Final Loop**: Shellcheck + Bats verification.

---

## Engineering Protocol (Activated)

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **AI-Powered Linting**: Use `copilot-cli` to verify architectural intent (e.g., "Prove the test ran," "Check for price injection") before allowing a commit.
4. **Audit Phase**: Explicitly verify that no tests were weakened.
5. **Simplification**: Refactor for minimal logic before final verification.

---

## Cluster State (as of 2026-03-02)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status | Notes |
|---|---|---|
| Vault | Running | `secrets` ns, initialized + unsealed |
| ESO | Running | `secrets` ns |
| OpenLDAP | Running | `identity` ns |
| Istio | Running | `istio-system` |
| Jenkins | Running | `cicd` ns |
| ArgoCD | Running | `cicd` ns |
| Keycloak | Running | `identity` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status | Notes |
|---|---|---|
| k3s node | Ready | v1.34.4+k3s1 |
| Istio | Running | IngressGateway + istiod |
| ESO | Pending | Deploy after PR merges |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.5.0 | released | See CHANGE.md |
| v0.6.0 | released | configure_vault_app_auth + vault_app_auth.bats |
| v0.6.1 | released | PR #17 merged; infra rebuild verified |
| v0.6.2 | active | Copilot CLI tools + Agent Rigor Protocol |
| v0.6.3 | planned | lib-foundation extraction via git subtree |
| v0.7.0 | planned | Keycloak provider interface |
| v0.8.0 | planned | Multi-Agent Orchestration Foundation (MCP) |
| v0.9.0 | planned | Autonomous SRE (Active Monitoring & Self-Healing) |
| v0.10.0 | planned | Autonomous Fleet Provisioning (Deploy 100 K3s Nodes) |
| v1.0.0 | vision | Final release; see `docs/plans/roadmap-v1.md` |

---

## Open Items

- [x] `configure_vault_app_auth` — implemented + Copilot review resolved (PR #16, CI green, awaiting merge)
- [ ] ESO deploy on Ubuntu app cluster (Gemini — SSH, after PR merges)
- [ ] shopping-cart-data / apps deployment on Ubuntu (Gemini — SSH)
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [ ] v0.6.2: `_ensure_node` + `_ensure_copilot_cli` — plan: `docs/plans/v0.6.2-ensure-copilot-cli.md`
- [ ] v0.7.0: Keycloak provider interface — plan: `docs/plans/v0.7.0-keycloak-provider-interface.md` (pending)
- [ ] v0.7.0: rename cluster to `infra` + fix `CLUSTER_NAME` env var

---

## Operational Notes

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always print log path before starting
- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Vault reboot unseal**: dual-path — macOS Keychain + Linux libsecret; k8s `vault-unseal` secret is fallback
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64 — `docker.io/bitnami/*` and `public.ecr.aws/bitnami/*` are broken/amd64-only

### Keycloak Known Failure Patterns (deploy_keycloak)

1. **Istio sidecar blocks `keycloak-config-cli` job** — job hangs indefinitely; look for `keycloak-keycloak-config-cli` pod stuck in Running. Already mitigated in `values.yaml.tmpl` via `sidecar.istio.io/inject: "false"` — verify the annotation is present if job hangs again.
2. **ARM64 image pull failures** — `docker.io/bitnami/*` and `public.ecr.aws/bitnami/*` are amd64-only; `values.yaml.tmpl` must use `docker.io/bitnamilegacy/*` for Keycloak, PostgreSQL, and Keycloak Config CLI.
3. **Stale PVCs block retry** — a failed deploy leaves `data-keycloak-postgresql-0` PVC in the `identity` namespace; Helm reinstall will hang waiting for PostgreSQL. Delete the PVC before retrying: `kubectl -n identity delete pvc data-keycloak-postgresql-0`.

---

## Agent Workflow (canonical)

```
Claude
  -- monitors CI / reviews agent reports for accuracy
  -- opens PR on owner go-ahead
  -- when CI fails: identifies root cause → writes bug report → hands to Gemini

Gemini
  -- investigates, fixes code, verifies live (shellcheck + bats + cluster)
  -- handles Ubuntu SSH deployment (interactive)
  -- may write back stale memory bank — always verify after

Codex
  -- pure logic fixes with no cluster dependency
  -- STOP at each verification gate; do not rationalize partial fixes

Owner
  -- approves and merges PRs
```

**Lessons learned:**
- Gemini ignores hold instructions — accept it, use review as the gate
- Gemini may write back stale memory bank content — verify file state after every update
- Codex commit-on-failure is a known failure mode — write explicit STOP guardrails
