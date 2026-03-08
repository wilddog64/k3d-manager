# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.7.1` (as of 2026-03-08)

**v0.7.0 SHIPPED** — squash-merged to main (eb26e43), PR #24. See CHANGE.md.
**v0.7.1 active** — branch cut from main.

---

## Current Focus

**v0.7.1: BATS test teardown + inotify persistence + Ubuntu app cluster**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Fix BATS teardown — `k3d-test-orbstack-exists` cluster not cleaned up | Gemini | pending |
| 2 | inotify limit — make persistent in colima VM or document in ops runbook | Claude | pending |
| 3 | ESO deploy on Ubuntu app cluster | TBD | pending |
| 4 | shopping-cart-data / apps deployment on Ubuntu | TBD | pending |

---

## Open Items

- [ ] Fix BATS test teardown: `k3d-test-orbstack-exists` cluster not cleaned up post-test. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- [ ] inotify limit in colima VM not persistent — apply via colima lima.yaml or note in ops runbook
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] lib-foundation: sync deploy_cluster fixes back upstream (CLUSTER_NAME, provider helpers, if-count)
- [ ] lib-foundation: bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] lib-foundation: tag v0.1.1 push to remote (pending next release cycle)
- [ ] v0.7.0 (deferred): Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.0 | released | See CHANGE.md |
| v0.7.1 | **active** | BATS teardown, inotify, Ubuntu app cluster |
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

**Known issues:**
- Port conflict: BATS test leaves `k3d-test-orbstack-exists` cluster holding ports 8000/8443. Doc: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- inotify limit in colima VM not persistent across restarts.

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
- Stay within task spec scope — do not add changes beyond what was specified.

**Push rules by agent location:**
- **Codex (M4 Air, same machine as Claude):** Commit locally + update memory-bank. Claude reviews and handles push + PR.
- **Gemini (Ubuntu VM):** Must push to remote — Claude cannot see Ubuntu-local commits. Always push before updating memory-bank.

**Lessons learned:**
- Gemini skips memory-bank read and acts immediately — paste full task spec inline in the Gemini session prompt; do not rely on Gemini pulling it from memory-bank independently.
- Gemini expands scope beyond task spec — spec must explicitly state what is forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i` clean environment.
- PR sub-branches from Copilot agent may conflict — evaluate and close if our implementation is superior.
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
