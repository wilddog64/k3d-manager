# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.5` (as of 2026-03-07)

**v0.6.4 SHIPPED** — tag `v0.6.4` pushed, PR #22 merged. See CHANGE.md.
**v0.6.5 active** — branch cut from `main`.

---

## Current Focus

**v0.6.5: BATS audit test coverage + lib-foundation extraction**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | BATS tests for `_agent_audit` bare sudo + kubectl exec credential scan | Gemini | ✅ done — 4 tests, suite 9/9, total 158/158 |
| 2 | Create `lib-foundation` repository + branch protection + CI | Owner | ✅ done — https://github.com/wilddog64/lib-foundation |
| 3 | Extract `core.sh` + `system.sh` into lib-foundation | Codex | ✅ done — shellcheck fixed, PR #1 open on lib-foundation, CI green |
| 4 | Replace awk if-count check with pure bash in `_agent_audit` | Codex | ✅ done — spec: `docs/plans/v0.6.5-codex-awk-bash-rewrite.md` |

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

### Completion Reports (2026-03-07)

**Codex Task 4 — awk → pure bash rewrite in `_agent_audit`:**
- commit `6b14539` — `agent_rigor.sh` lines 112–132 only
- shellcheck PASS (Claude verified), no bash 4.0+ features
- BATS agent_rigor: 5/5 (Codex) → re-verified 9/9 by Gemini

**Gemini Task 1 — BATS tests for bare sudo + kubectl exec credential scan:**
- commit `5f04814` — `scripts/tests/lib/agent_rigor.bats` only
- 4 tests added (ok 6–9), real git repo per test, no git stubs
- Total suite: 9/9 agent_rigor, 158/158 full BATS (clean env, Ubuntu VM)

**Lessons learned:**
- Gemini may write stale memory-bank content — Claude reviews every update before writing next task.
- Gemini expands scope beyond task spec — spec must explicitly state what is forbidden.
- Gemini ran `git rebase -i` on a shared branch — destructive git ops explicitly forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i` clean environment.
- PR sub-branches from Copilot agent may conflict — evaluate and close if our implementation is superior.

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
| v0.1.0–v0.6.4 | released | See CHANGE.md |
| v0.6.5 | **active** | BATS audit coverage + lib-foundation extraction |
| v0.7.0 | planned | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.7.0 |

---

## Open Items

- [ ] BATS tests for `_agent_audit` new checks (v0.6.5 — Gemini)
- [x] Create `lib-foundation` repository (owner) — ✅ done
- [x] Extract `core.sh` + `system.sh` via git subtree (Codex) — ✅ done, PR #1 open on lib-foundation
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner)
- [ ] `CLUSTER_NAME` env var not respected during `deploy_cluster`
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

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
