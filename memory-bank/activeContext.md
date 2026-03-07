# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.7.0` (as of 2026-03-07)

**v0.6.5 SHIPPED** — tag `v0.6.5` pushed, PR #23 merged. See CHANGE.md.
**v0.7.0 active** — branch cut from `main`.

---

## Current Focus

**v0.7.0: Keycloak provider + App Cluster deployment**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Refactor `deploy_cluster` + fix `CLUSTER_NAME` env var | Codex | **active** — spec: `docs/plans/v0.7.0-codex-deploy-cluster-refactor.md` |
| 2 | Implement `_resolve_script_dir` in lib-foundation | Codex | **active** — spec in lib-foundation memory-bank, branch `feature/v0.1.1-script-dir-resolver` |

---

## Engineering Protocol

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.
5. **Memory-bank compression**: Compress memory-bank at the *start* of the new branch, before the first agent task.

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
  -- red team: adversarially tests existing security controls (bounded scope)
  -- commits own work; updates memory-bank to report completion

Codex  (Production Code)
  -- pure logic fixes and feature implementation, no cluster dependency
  -- commits own work; updates memory-bank to report completion
  -- fixes security vulnerabilities found by Gemini red team

Owner
  -- approves and merges PRs
```

**Agent rules:**
- Commit your own work — self-commit is your sign-off.
- Update memory-bank to report completion — this is how you communicate back to Claude.
- No credentials in task specs or reports — reference env var names only (`$VAULT_ADDR`).
- Run `shellcheck` on every touched `.sh` file and report output.
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- Stay within task spec scope — do not add changes beyond what was specified, even if they seem like improvements. Unsanctioned scope expansion gets reverted.

**Push rules by agent location:**
- **Codex (M4 Air, same machine as Claude):** Commit locally + update memory-bank. Claude reviews local commit and handles push + PR.
- **Gemini (Ubuntu VM):** Must push to remote — Claude cannot see Ubuntu-local commits. Always push before updating memory-bank.

**Claude awareness — Gemini works on Ubuntu VM:**
- Gemini commits directly to the active branch from the Ubuntu VM repo clone.
- Always `git pull origin <branch>` before reading or editing any file Gemini may have touched.
- Conflicts are possible if Claude and Gemini both push to the same branch concurrently.

**Red Team scope (Gemini):**
- Test existing controls only: `_copilot_prompt_guard`, `_safe_path`, stdin injection, trace isolation.
- Report findings to memory-bank — Claude routes fixes to Codex.
- Do NOT modify production code.

**Gemini BATS verification rule:**
- Always run tests in a clean environment:
  ```bash
  env -i HOME="$HOME" PATH="$PATH" ./scripts/k3d-manager test <suite> 2>&1 | tail -10
  ```
- Never report a test as passing unless it passed in a clean environment.

**Memory-bank flow:**
```
Agent  → memory-bank   (report: task complete, what changed, what was unexpected)
Claude reads           (review: detect gaps, inaccuracies, overclaiming)
Claude → memory-bank   (instruct: corrections + next task spec)
Agent reads + acts
```

**Lessons learned:**
- Gemini may write stale memory-bank content — Claude reviews every update before writing next task.
- Gemini expands scope beyond task spec — spec must explicitly state what is forbidden.
- Gemini ran `git rebase -i` on a shared branch — destructive git ops explicitly forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i` clean environment.
- PR sub-branches from Copilot agent may conflict — evaluate and close if our implementation is superior.
- Claude owns Copilot PR review fixes directly — no need to route small surgical fixes through agents.

---

## Cluster State (as of 2026-03-07)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns, initialized + unsealed |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status |
|---|---|
| k3s node | Ready — v1.34.4+k3s1 |
| Istio | Running |
| ESO | Pending |
| shopping-cart-data / apps | Pending |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.6.5 | released | See CHANGE.md |
| v0.7.0 | **active** | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.7.0 |

---

## Open Items

- [ ] Refactor `deploy_cluster` — 12 if-blocks exceeds threshold of 8. Extract `_deploy_cluster_resolve_provider` helper. Also fix duplicate mac+k3s guard. Issue: `docs/issues/2026-03-07-deploy-cluster-if-count-violation.md`
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner)
- [ ] `CLUSTER_NAME` env var not respected during `deploy_cluster`
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server
- [ ] lib-foundation PR #1 merge → tag v0.1.0 (owner)

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
