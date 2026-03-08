# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.7.0` (as of 2026-03-07)

**v0.6.5 SHIPPED** — tag `v0.6.5` pushed, PR #23 merged. See CHANGE.md.
**v0.7.0 active** — branch cut from `main`.

---

## Current Focus

**v0.7.0: lib-foundation subtree integration + cluster validation**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Set up git subtree — pull lib-foundation into `scripts/lib/foundation/` | Claude | **DONE** — commit b8426d4 |
| 2 | Update dispatcher source paths to use subtree | Claude | **DONE** — commit 1dc29db |
| 3 | Teardown + rebuild infra cluster (OrbStack, macOS ARM64) | Claude | **DONE** — all services healthy; 2 issues filed |
| 4 | Teardown + rebuild k3s cluster (Ubuntu VM) | Gemini | **needs completion report** — see spec below |
| 5 | Refactor `deploy_cluster` + fix `CLUSTER_NAME` env var | Codex | pending — spec: `docs/plans/v0.7.0-codex-deploy-cluster-refactor.md` |

---

## Task 4 — Gemini Spec: Ubuntu k3s Teardown + Rebuild

**Status:** Completion report required. If you have already done the work,
report what actually happened. If not, do the work now and report.

### Steps

1. `git pull origin k3d-manager-v0.7.0` — get the subtree commits (b8426d4, 1dc29db)
2. Confirm dispatcher sources from `scripts/lib/foundation/scripts/lib/`:
   ```bash
   grep "foundation" scripts/k3d-manager
   ```
3. Teardown k3s cluster:
   ```bash
   ./scripts/k3d-manager destroy_cluster
   ```
4. Rebuild k3s cluster:
   ```bash
   CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f
   ```
5. Deploy services and verify each is healthy:
   - `./scripts/k3d-manager deploy_eso` → check `kubectl get pods -n secrets`
   - `./scripts/k3d-manager deploy_vault` → check initialized + unsealed
   - `./scripts/k3d-manager deploy_ldap` → check pod running
   - `kubectl get secretstore -A` → all must be Ready=True
6. Run BATS suite in clean environment:
   ```bash
   env -i HOME="$HOME" PATH="$PATH" ./scripts/k3d-manager test all 2>&1 | tail -5
   ```
7. Check no regressions — count must be ≥ 158 passing, 0 failing.

### Required Completion Report

Copy this template exactly and fill it in. Commit it to `memory-bank/activeContext.md`
then push before marking done:

```
## Task 4 Completion Report (Gemini)

Date: YYYY-MM-DD
Branch pulled: k3d-manager-v0.7.0 (commit: <sha>)

Subtree sourced: YES / NO — [paste output of: grep foundation scripts/k3d-manager]
Teardown: PASS / FAIL — [brief description]
Rebuild: PASS / FAIL — [brief description]

Services verified:
| Component | Status | Notes |
|---|---|---|
| k3s node | Ready / NotReady | version |
| Istio | Running / Pending / Error | |
| ESO | Running / Pending / Error | |
| Vault | Initialized+Unsealed / Error | |
| OpenLDAP | Running / Error | namespace |
| SecretStores | N/N Ready | |

BATS (clean env): N/N passing — [paste last 5 lines of output]
Regressions: NONE / [describe]
Unexpected findings: NONE / [describe — do not fix without a spec]

Status: COMPLETE / BLOCKED — [reason if blocked]
```

### Rules

- Do NOT fix anything outside this scope. If you find an issue, describe it under "Unexpected findings" and stop.
- Do NOT run `git rebase`, `git reset --hard`, or `git push --force`.
- Run BATS with `env -i` clean environment — do NOT report ambient-env results.
- Commit your report and push BEFORE updating the task status to done.

---

## lib-foundation Subtree Plan

**Goal:** Pull lib-foundation `main` into `scripts/lib/foundation/` via git subtree.
Source paths updated to use subtree copy. Old `scripts/lib/core.sh` + `system.sh` kept
initially — removed in follow-up commit after full cluster rebuild passes.

**Two-step approach (reduces blast radius):**

Step 1 — Subtree setup + source path update (Claude):
- Add lib-foundation remote: `git remote add lib-foundation <url>`
- `git subtree add --prefix=scripts/lib/foundation lib-foundation main --squash`
- Update `scripts/k3d-manager` dispatcher to source from `scripts/lib/foundation/`
- Keep old `scripts/lib/core.sh` + `system.sh` as fallback
- shellcheck all touched files — must pass

Step 2 — Full cluster validation:
- Claude: OrbStack teardown → rebuild → verify Vault, ESO, Istio, OpenLDAP, Jenkins, ArgoCD, Keycloak
- Gemini: Ubuntu k3s teardown → rebuild → verify same stack on Linux
- Both must pass before PR

Step 3 — Cleanup (after PR approved):
- Remove old `scripts/lib/core.sh` + `scripts/lib/system.sh`
- Commit as follow-up on same branch

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

Rebuilt 2026-03-07 — all services verified healthy post lib-foundation subtree integration.

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns, initialized + unsealed |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` ns + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |

**Issues found during rebuild:**
- Port conflict: BATS test left `k3d-test-orbstack-exists` cluster holding ports 8000/8443. Doc: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- inotify limit in colima VM (too many open files). Applied manually — not persistent across colima restarts.
- `identity/vault-kv-store` SecretStore: Vault role `eso-ldap-directory` only bound to `directory` ns. Fixed manually (added `identity`). Root fix needed in `deploy_ldap`. Doc: `docs/issues/2026-03-07-eso-secretstore-identity-namespace-unauthorized.md`

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

- [x] lib-foundation git subtree setup + source path update (Claude — Task 1+2) — DONE
- [x] OrbStack cluster teardown + rebuild validation (Claude — Task 3) — DONE
- [ ] Ubuntu k3s teardown + rebuild validation (Gemini — Task 4) — **needs completion report** (see spec in activeContext.md)
- [ ] Refactor `deploy_cluster` — 12 if-blocks exceeds threshold of 8. Extract `_deploy_cluster_resolve_provider` helper. Also fix duplicate mac+k3s guard. Issue: `docs/issues/2026-03-07-deploy-cluster-if-count-violation.md` (Codex — Task 5, after cluster validation)
- [ ] Fix `deploy_ldap`: Vault role `eso-ldap-directory` must bind both `directory` + `identity` namespaces. Issue: `docs/issues/2026-03-07-eso-secretstore-identity-namespace-unauthorized.md` (Codex)
- [ ] Fix BATS test teardown: `k3d-test-orbstack-exists` cluster not cleaned up post-test. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md` (Gemini)
- [ ] inotify limit in colima VM not persistent — apply via colima lima.yaml or note in ops runbook
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
