# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.7.2` (as of 2026-03-08)

**v0.7.1 SHIPPED** — squash-merged to main (e847064), PR #25. Colima support dropped.
**v0.7.2 active** — branch cut from main, `.envrc` dotfiles symlink + tracked pre-commit hook carried forward.

---

## Current Focus

**v0.7.2: BATS teardown fix + dotfiles/hooks integration + Ubuntu app cluster**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | `.envrc` → dotfiles symlink + `scripts/hooks/pre-commit` (carried from v0.7.0) | Claude | **done** — commits 108b959, 3dcf7b1 |
| 2 | Fix BATS teardown — `k3d-test-orbstack-exists` cluster not cleaned up post-test | Gemini | pending |
| 3 | ESO deploy on Ubuntu app cluster | Gemini | pending |
| 4 | shopping-cart-data / apps deployment on Ubuntu | TBD | pending |
| 5 | lib-foundation v0.2.0 — `agent_rigor.sh` + `ENABLE_AGENT_LINT` | Claude/Codex | **done** — merged + tagged, subtree synced |
| 6 | Update `k3d-manager.envrc` — `AGENT_LINT_GATE_VAR`, `AGENT_LINT_AI_FUNC`, `AGENT_AUDIT_MAX_IF=15` | Claude | **done** |

---

## Open Items

- [x] Drop colima support (v0.7.1)
- [x] `.envrc` → `~/.zsh/envrc/k3d-manager.envrc` symlink + `.gitignore`
- [x] `scripts/hooks/pre-commit` — tracked hook with `_agent_audit` + `_agent_lint` (gated by `K3DM_ENABLE_AI=1`)
- [ ] Fix BATS teardown: `k3d-test-orbstack-exists` cluster not cleaned up. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [x] lib-foundation v0.2.0 — merged, tagged, subtree synced into `scripts/lib/foundation/`
- [x] `~/.zsh/envrc/k3d-manager.envrc` — `AGENT_LINT_GATE_VAR=K3DM_ENABLE_AI`, `AGENT_LINT_AI_FUNC=_k3d_manager_copilot`, `AGENT_AUDIT_MAX_IF=15`
- [x] `_agent_audit` smoke-tested: catches bare sudo + if-count, passes clean changes
- [ ] `_run_command` if-count refactor — 12 if-blocks exceeds threshold; workaround `AGENT_AUDIT_MAX_IF=15`. See `docs/issues/2026-03-08-run-command-if-count-refactor.md`. Fix in lib-foundation first.
- [ ] lib-foundation: sync deploy_cluster fixes back upstream (CLUSTER_NAME, provider helpers)
- [ ] lib-foundation: route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## dotfiles / Hooks Setup (completed this session)

- `~/.zsh/envrc/personal.envrc` — sync-claude (macOS) / sync-gemini (Ubuntu) on `cd`
- `~/.zsh/envrc/k3d-manager.envrc` — `source_up` + `PATH` + `git config core.hooksPath scripts/hooks`
- Symlinks: `~/src/gitrepo/personal/.envrc` → personal.envrc; `k3d-manager/.envrc` → k3d-manager.envrc
- `scripts/hooks/pre-commit` — tracked; `_agent_audit` always runs; `_agent_lint` runs when `K3DM_ENABLE_AI=1`
- Ubuntu replication: `ln -s ~/.zsh/envrc/personal.envrc ~/src/gitrepo/personal/.envrc` + same for k3d-manager

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.1 | released | See CHANGE.md |
| v0.7.2 | **active** | BATS teardown, Ubuntu app cluster, hooks/envrc integration |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.8.0 |

---

## Cluster State (as of 2026-03-07)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns, initialized + unsealed |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` ns + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |

**Known issue:** BATS test leaves `k3d-test-orbstack-exists` cluster holding ports 8000/8443.

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status |
|---|---|
| k3s node | Ready — v1.34.4+k3s1 |
| Istio | Running |
| ESO | Running |
| Vault | Initialized + Unsealed |
| OpenLDAP | Running — `identity` ns |
| SecretStores | 3/3 Ready |
| shopping-cart-data / apps | Pending |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Core Library Rule

**Never modify `scripts/lib/foundation/` directly.** All changes to core library code
(new functions, refactors, bug fixes) must originate in lib-foundation and flow in via
`git subtree pull`:

```
lib-foundation (fix) → PR → merge → tag → k3d-manager subtree pull
```

Emergency hotfixes directly in the subtree are allowed only to unblock a release — must
be filed as an issue in lib-foundation and ported upstream before the next subtree pull.

---

## Engineering Protocol

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.
5. **Memory-bank compression**: Compress at the *start* of each new branch.

---

## Agent Workflow

```
Claude
  -- reviews all agent memory-bank writes before writing next task
  -- opens PR on owner go-ahead; routes PR issues back to agents by scope
  -- writes corrective/instructional content to memory-bank
  -- tags Copilot for code review before every PR

Gemini  (SDET + Red Team)
  -- authors BATS unit tests and test_* integration tests
  -- cluster verification: full teardown/rebuild, smoke tests
  -- commits own work; updates memory-bank to report completion
  -- must push to remote before updating memory-bank

Codex  (Production Code)
  -- pure logic fixes and feature implementation, no cluster dependency
  -- commits own work; updates memory-bank to report completion

Owner
  -- approves and merges PRs
```

**Agent rules:**
- Commit your own work — self-commit is your sign-off.
- Update memory-bank to report completion — this is how you communicate back to Claude.
- No credentials in task specs or reports — reference env var names only.
- Run `shellcheck` on every touched `.sh` file and report output.
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- Stay within task spec scope — do not add changes beyond what was specified.

**Lessons learned:**
- Gemini skips memory-bank read — paste full task spec inline in every Gemini session prompt.
- Gemini expands scope — spec must explicitly state what is forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i`.
- `git subtree add --squash` creates a merge commit that blocks GitHub rebase-merge — use squash-merge with admin override.

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64

### Keycloak Known Failure Patterns

1. **Istio sidecar blocks `keycloak-config-cli` job** — mitigated via `sidecar.istio.io/inject: "false"`.
2. **ARM64 image pull failures** — use `docker.io/bitnamilegacy/*`.
3. **Stale PVCs block retry** — delete `data-keycloak-postgresql-0` PVC in `identity` ns before retrying.
