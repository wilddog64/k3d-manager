# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.4` (as of 2026-03-07)

**v0.6.2 SHIPPED** — tag `v0.6.2` pushed, PR #19 merged to `main`.
**v0.6.3 SHIPPED** — tag `v0.6.3` pushed, PR #21 merged to `main`.
**v0.6.4 active** — branch cut from `main`.

---

## Current Focus

**v0.6.4: Linux k3s Validation + lib-foundation Extraction**

Key objectives:
1. **Linux k3s validation gate** — Gemini full 5-phase teardown/rebuild on Ubuntu VM (`CLUSTER_PROVIDER=k3s`) to validate refactored functions under real Linux conditions
2. **Create `lib-foundation` repository** — owner action
3. **Extract `core.sh` + `system.sh`** via git subtree (Codex)

---

## Engineering Protocol (Activated)

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.

## Agent Workflow — Revised Protocol

### Agent responsibilities (Codex / Gemini)
- **Commit your own work** — self-commit is your sign-off; provides clear attribution in git history.
- **Update memory-bank to report completion** — this is how you communicate back to Claude. Mark tasks done, note what changed, flag anything unexpected.
- **Report each fix individually.** State: fix letter, file, line numbers, what changed.
- **Verification is mandatory.** Run `shellcheck` on every touched `.sh` file and report output.
- **No credentials in task specs or reports.** Reference env var names only (`$VAULT_ADDR`, not the actual URL). Live values stay on the owner's machine.

### Claude responsibilities
- **Review every agent memory-bank write** — detect overclaiming, stale entries, missing items, inaccuracies before the next agent reads it.
- **Write corrective/instructional content to memory-bank** — this is what agents act on next.
- **Open PR when code is ready** — route PR review issues based on scope:
  - Small/isolated fix → Claude fixes directly in the branch
  - Logic or test fix → assign back to Codex via memory-bank
  - Cluster verification needed → assign to Gemini via memory-bank

### Memory-bank communication flow
```
Agent  → memory-bank   (report: task complete, what changed, what was unexpected)
Claude reads           (review: detect gaps, inaccuracies, overclaiming)
Claude → memory-bank   (instruct: corrections + next task spec)
Agent reads + acts
```

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
| v0.6.3 | **released** | Refactoring (De-bloat) + Digital Auditor |
| v0.6.4 | **active** | Linux k3s validation gate + lib-foundation extraction via git subtree |
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
- [x] v0.6.3: De-bloat `system.sh` / `core.sh`
- [x] v0.6.3: `_agent_lint` implementation (Digital Auditor)
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
  -- reviews all agent memory-bank writes before writing next task
  -- opens PR on owner go-ahead; routes PR issues back to agents by scope
  -- writes corrective/instructional content to memory-bank

Gemini  (SDET + Red Team)
  -- authors BATS unit tests and test_* integration tests
  -- cluster verification: full teardown/rebuild, smoke tests
  -- red team: adversarially tests existing security controls (bounded scope)
  -- commits own work; updates memory-bank to report completion

Codex  (Production Code)
  -- pure logic fixes and feature implementation, no cluster dependency
  -- commits own work; updates memory-bank to report completion
  -- fixes security vulnerabilities found by Gemini red team

Owner
  -- approves and merges PRs
```

**Red Team scope (Gemini):**
- Test existing controls only: `_copilot_prompt_guard`, `_safe_path`, stdin injection, trace isolation
- Try to bypass, leak credentials, or inject via proc/cmdline
- Report findings to memory-bank as structured report — Claude routes fixes to Codex
- Do NOT propose new attack surfaces or modify production code

**Lessons learned:**
- Gemini may write stale memory-bank content — Claude reviews every update before writing next task
- PR sub-branches from Copilot agent (e.g. `copilot/sub-pr-*`) may conflict with branch work — evaluate and close if our implementation is superior
