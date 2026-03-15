# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.0` (as of 2026-03-14)

**v0.9.0 SHIPPED** — PR #30 squash-merged (616d868), 2026-03-15. Tagged + released.
**v0.9.1 active** — branch `k3d-manager-v0.9.1` cut from main 2026-03-15.

---

## Current Focus

**v0.9.1: vCluster Plugin + test() refactor + Gemini smoke test**

| Item | Status | Notes |
|---|---|---|
| vCluster plugin + Copilot review | **done** | Commits `68b263c`, `f444c4b` — all 8 Copilot threads resolved |
| CI on PR #31 | **green** | Vault unsealed on M2 Air; latest push `124a2f1` |
| Two-tier help + `--help` flag | **done** | Commit `0fc68d5` |
| `function test()` refactor | **done** | Commit `79074e58` — audit PASS, 190 tests pass, verified by Claude |
| Gemini smoke test | **RETRY READY** | Fixes in commit `45717e8`: selector corrected + plugin fns in --help; Gemini to re-run vcluster steps on M2 Air |
| Playwright E2E in CI | pending | `shopping-cart-infra` — starts after vCluster plugin ships |

### Gemini retry task — READY TO ASSIGN
Spec: `docs/plans/v0.9.1-gemini-smoke-test-task.md` (updated)

Two bugs fixed in commit `45717e8`:
1. Pod selector corrected: `app=vcluster,release=<name>`
2. vCluster functions now visible in `./scripts/k3d-manager --help`

Steps already passed: `test all` (190), bare help, `test --help`
Steps to re-run on M2 Air: `--help` vCluster category check, then
`vcluster_create` → `vcluster_list` → `vcluster_use` → `vcluster_destroy`

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.0 | released | See CHANGE.md |
| v0.9.1 | **active** | vCluster plugin + Playwright E2E in CI |
| v1.0.0 | planned | k3dm-mcp — MCP server wrapping k3d-manager CLI |
| v1.1.0 | planned | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (as of 2026-03-14 — post v0.8.0)

**Architecture:** Infra cluster on M2 Air — ArgoCD manages Ubuntu k3s hub-and-spoke.
Ubuntu at `10.211.55.14` (Parallels VM, only reachable from M2 Air).

### Infra Cluster — k3d on OrbStack on M2 Air (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |
| cert-manager | Deployed — `cert-manager` ns (v0.8.0) |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu` from M2 Air)

| Component | Status |
|---|---|
| k3s node | Ready — v1.34.4+k3s1 |
| Istio | Running |
| ESO | Running — 2/2 SecretStores Ready |
| Vault | Initialized + Unsealed |
| OpenLDAP | Running — `identity` ns |
| shopping-cart-data | Running ✅ |
| shopping-cart-apps | Synced via ArgoCD ✅ — `ImagePullBackOff` until CI/CD pushes images |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.
**Ubuntu interface:** `enp0s5` (not eth0) — MTU 1500. k3s uses flannel (MTU 1450).

---

## Core Library Rule

**Never modify `scripts/lib/foundation/` directly.** Fix in lib-foundation → PR → tag → subtree pull.
Subtree sync bypass: `K3DM_SUBTREE_SYNC=1 git subtree pull --prefix=scripts/lib/foundation ...`

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
  -- tags Copilot for code review before every code PR (not doc-only PRs)

Gemini  (SDET + Red Team)
  -- single-step verification: BATS, pod status checks, pre-commit hook smoke tests
  -- red-team / security audit
  -- ArgoCD/kubectl ops when each step is isolated and machine context is confirmed
  -- commits own work; updates memory-bank to report completion
  -- must push to remote before updating memory-bank
  -- MUST run hostname && uname -n first — has repeatedly started on wrong machine

Codex  (Production Code + Cluster Ops)
  -- pure logic fixes and feature implementation
  -- cluster rebuild / deploy scripts — follows spec precisely, no improvisation
  -- ArgoCD registration + app sync
  -- shopping-cart repo work (preferred: Ubuntu native)
  -- commits own work; updates memory-bank to report completion
  -- fallback: clone from GitHub to M4 Air, work locally, push to GitHub

Owner
  -- approves and merges PRs
```

**Agent logging convention:**
- All k3d-manager command output → `scratch/logs/<agent>-<task>-<timestamp>.log`
- `scratch/` is gitignored — logs never committed

**Agent rules:**
- Commit your own work — self-commit is your sign-off.
- Update memory-bank to report completion — this is how you communicate back to Claude.
- No credentials in task specs or reports — reference env var names only.
- Run `shellcheck` on every touched `.sh` file and report output.
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- Stay within task spec scope — do not add changes beyond what was specified.
- **First command in every session: `hostname && uname -n`** — verify machine before anything else.

**Lessons learned:**
- Gemini skips memory-bank read — paste full task spec inline in every Gemini session prompt.
- Codex fabricates commit SHAs when reporting completion — always verify with `gh api repos/.../git/commits/<sha>` before trusting any SHA Codex reports.
- Codex reports "done" after writing documentation without implementing code — require a PR URL as proof of completion, not just a memory-bank update.
- Codex silently reverts intentional decisions across session restarts — three-layer defense: Agent Instructions in `CLAUDE.md` + inline `DO NOT REMOVE` comments + memory-bank sections.
- Gemini expands scope — spec must explicitly state what is forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i`.
- `git subtree add --squash` creates a merge commit that blocks GitHub rebase-merge — use squash-merge with admin override.
- Gemini confirms plan correctly but executes differently — confirmation is not reliable, verify actual output.
- Gemini does not verify machine context — must open terminal on M2 Air before starting Gemini session.
- One command at a time for Gemini on complex tasks — no branching specs.
- BATS count: 158 total, ~108 pass with `env -i` (50 skip due to env-dependent tests) — expected, not a bug.
- ArgoCD deploy keys: per-repo, passphrase-free, added via `gh api` — GitHub forbids reusing same key across repos.
- k3s context name is always `default` — never `k3s-automation`.

---

## Release Checklist (do after every PR merge to main)

1. Tag the merge commit: `git tag v<X.Y.Z> <commit-sha> && git push origin v<X.Y.Z>`
2. Create GitHub release: `gh release create v<X.Y.Z> --title "v<X.Y.Z> — <title>" --notes "..."`
3. Update README.md Releases table on the next feature branch
4. Verify `gh release list` shows new version as Latest

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
