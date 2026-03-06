# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.3` (as of 2026-03-06)

**v0.6.2 SHIPPED** — tag `v0.6.2` pushed, PR #19 merged to `main`.
**v0.6.3 active** — branch cut from `main`; plan at `docs/plans/v0.6.3-refactor-and-audit.md`.

---

## Current Focus

**v0.6.3: Refactoring & External Audit Integration**

Plans:
- `docs/plans/v0.6.3-refactor-and-audit.md` — main refactor plan
- `docs/plans/v0.6.3-codex-run-command-fix.md` — active Codex task (see below)

Key objectives:
1. **Fix `_run_command` TTY flakiness** — remove `auto_interactive` block (Codex)
2. De-bloat `system.sh` and `core.sh` — remove permission cascade anti-patterns (Codex)
3. Implement `_agent_lint` in `agent_rigor.sh` — digital auditor via copilot-cli (Codex)
4. BATS suite: `scripts/tests/lib/agent_rigor.bats` (Gemini)
5. Claude: review all diffs, run full BATS suite locally, commit, open PR

---

## Engineering Protocol (Activated)

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.

## Codex Standing Instructions

- **Report each fix individually.** State: fix letter, file, line numbers, what changed.
- **STOP means STOP.** Partial delivery with a complete claim is a protocol violation.
- **Do not update memory-bank.** Claude owns all memory-bank writes.
- **Do not commit.** Claude reviews and commits after verifying diffs match spec.
- **Verification is mandatory.** Run `shellcheck` on every touched file and report output.

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
| ESO | Pending | Deploy after infra work stabilizes |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.6.1 | released | See CHANGE.md |
| v0.6.2 | **released** | AI Tooling + Agent Rigor + Security hardening |
| v0.6.3 | **active** | Refactoring (De-bloat) + `rigor-cli` Integration |
| v0.6.4 | planned | lib-foundation extraction via git subtree |
| v0.7.0 | planned | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.7.0; see `docs/plans/roadmap-v1.md` |

---

## Open Items

- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [ ] `CLUSTER_NAME` env var not respected during `deploy_cluster` — see `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`
- [ ] v0.6.3: De-bloat `system.sh` / `core.sh`
- [ ] v0.6.3: `_agent_audit` implementation
- [ ] v0.6.3: `rigor-cli` integration
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## Operational Notes

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always print log path before starting
- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64

### Keycloak Known Failure Patterns

1. **Istio sidecar blocks `keycloak-config-cli` job** — already mitigated via `sidecar.istio.io/inject: "false"` in `values.yaml.tmpl`.
2. **ARM64 image pull failures** — `docker.io/bitnami/*` is amd64-only; use `docker.io/bitnamilegacy/*`.
3. **Stale PVCs block retry** — delete `data-keycloak-postgresql-0` PVC in `identity` ns before retrying.

---

## Agent Workflow (canonical)

```
Claude
  -- monitors CI / reviews agent reports for accuracy
  -- opens PR on owner go-ahead
  -- owns all memory-bank writes

Gemini
  -- SDET/Red-Team audits, BATS verification, Ubuntu SSH deployment
  -- may write stale memory-bank — always verify after

Codex
  -- pure logic fixes, no cluster dependency
  -- STOP at each verification gate

Owner
  -- approves and merges PRs
```

**Lessons learned:**
- Gemini ignores hold instructions — use review as the gate
- Gemini may write stale memory-bank content — verify after every update
- Codex commit-on-failure is a known failure mode — write explicit STOP guardrails
- PR sub-branches from Copilot agent (e.g. `copilot/sub-pr-*`) may conflict with branch work — evaluate and close if our implementation is superior
