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
1. **Fix `_run_command` TTY flakiness** — remove `auto_interactive` block (Codex) ✅ done 2026-03-06
2. **Phase 1 Verification** — BATS 125/125 PASS, E2E Cluster rebuild success (Gemini) ✅ done 2026-03-06
3. De-bloat `system.sh` and `core.sh` — remove permission cascade anti-patterns (Codex) ✅ done 2026-03-06
4. Implement `_agent_lint` in `agent_rigor.sh` — digital auditor via copilot-cli (Codex) ✅ done 2026-03-06
5. BATS suite: `scripts/tests/lib/agent_rigor.bats` (Gemini) ✅ done 2026-03-06
6. Claude: review all diffs, run full BATS suite locally, commit, open PR

---

## Codex Next Tasks (v0.6.3 Phase 2)

Phase 1 complete and independently verified by Claude: **125/125 BATS passing locally**,
`run_command.bats` tests 1 & 2 confirmed passing, smoke tests PASS.

Codex proceeds with Phase 2. Plan: `docs/plans/v0.6.3-refactor-and-audit.md`.

### Standing Rules (apply to every task)
- Report each fix individually with file and line numbers changed.
- Run `shellcheck` on every touched file and report output.
- Do not modify test files (`*.bats`) — Gemini owns those.
- Do not modify `memory-bank/` — Claude owns memory-bank writes.
- Do not commit — Claude reviews and commits.
- STOP after all listed fixes. Do not proceed to the next task without Claude go-ahead.

### Task 1 — De-bloat `scripts/lib/core.sh` (permission cascade anti-patterns)

Targets (see plan for full before/after):
- `_ensure_path_exists` — collapse 4-attempt mkdir cascade to single `_run_command --prefer-sudo`
- `_k3s_start_server` — collapse 4-attempt sh cascade to 2-path (root vs non-root)
- `_setup_kubeconfig` — collapse dual permission checks to single `_run_command --prefer-sudo` per op
- `_install_k3s` file ops — collapse dual writable-check pattern to direct `_run_command --prefer-sudo`

After all targets done: `shellcheck scripts/lib/core.sh` — report output.

### Task 2 — De-bloat `scripts/lib/system.sh` (OS dispatch consolidation)

Targets (see plan for full before/after):
- Add `_detect_platform` helper (returns `mac`/`wsl`/`debian`/`redhat`/`linux` or error)
- `_install_docker` — replace 4-branch inline switch with `_detect_platform` dispatch
- `deploy_cluster` platform detection — replace 5-branch cascade with `_detect_platform`
- `_create_nfs_share` — extract `_create_nfs_share_mac` to system.sh, guard in core.sh

After all targets done: `shellcheck scripts/lib/system.sh` — report output.

### Task 3 — Implement `_agent_lint` in `scripts/lib/agent_rigor.sh`

See plan Component 2 for full spec. Key rules enforced:
- No permission cascades (>1 sudo escalation path for same op)
- OS dispatch via `_detect_platform` (not raw inline chains)
- Secret hygiene (no tokens in kubectl exec args)
- Namespace isolation (no `kubectl apply` without `-n`)

After implementation: `shellcheck scripts/lib/agent_rigor.sh` — report output.

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
- **No credentials in task specs.** Task specs and reports must never contain actual credential values, cluster addresses, kubeconfig paths, or tokens — reference env var names only (e.g. `$VAULT_ADDR`, not the actual URL). Live values stay on the owner's machine.

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
