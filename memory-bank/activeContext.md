# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.8.0` (as of 2026-03-11)

**v0.7.3 SHIPPED** — squash-merged to main (9bca648), PR #27, 2026-03-11. Tagged + released.
**v0.8.0 active** — branch cut from main 2026-03-11.

---

## Current Focus

**v0.8.0: Security Hardening + lib-foundation Backlog**

Two k3d-manager tasks are spec-complete and ready for Codex. Shopping cart
work is independent and runs after these two are merged.

| Item | Status | Spec | Notes |
|---|---|---|---|
| Vault-managed ArgoCD deploy keys | **DONE — committed `7785033`** | `docs/plans/v0.8.0-vault-argocd-deploy-keys.md` | BATS 8/8, shellcheck clean, all fns ≤ 8 ifs |
| `deploy_cert_manager` plugin | **DONE — verified on M2 Air** | `docs/plans/v0.8.0-gemini-cert-manager-verify.md` | BATS 10/10; live cluster verify PASS with manual IngressClass apply |
| lib-foundation v0.3.0 | pending | `docs/issues/2026-03-08-run-command-if-count-refactor.md` | `_run_command` if-count refactor + bare sudo routing |
| Shopping cart branch protection | pending | — | Automate via `gh api` across 5 repos; blocked until CI green |

**k3dm-mcp is a separate repo** — starts after v0.8.0 ships.
Repo: `~/src/gitrepo/personal/k3dm-mcp` | Roadmap: `k3dm-mcp/docs/plans/roadmap.md`

---

## Open Items

- [x] **Fix if-count violations in `argocd.sh`** — spec: `docs/plans/v0.8.0-codex-if-count-fix.md`; helpers extracted, shellcheck clean, BATS 8/8, `AGENT_AUDIT_MAX_IF=8` audit ✅ (git add blocked by index.lock)
- [x] `deploy_cert_manager` plugin — committed `f4f84e3`; BATS 10/10, shellcheck clean, all fns ≤ 4 ifs
- [x] Install tracked pre-commit hook on all machines — spec: `docs/plans/v0.8.0-codex-install-hooks.md`
  - Commit `09ebb52` adds `scripts/hooks/install-hooks.sh`; symlink verified on M4 Air (`.git/hooks/pre-commit -> ../../scripts/hooks/pre-commit`)
  - M2 Air install blocked (SSH git pull fails: `git@github.com: Permission denied (publickey)`; existing repo still lacks script)
  - Ubuntu repo present; git pull rebased but `scripts/hooks/install-hooks.sh` absent on branch `k3d-manager-v0.7.3` → install skipped; owner follow-up needed
- [x] Istio ingress fix — committed `587ab88`; `scripts/etc/istio-ingressclass.yaml`, `_provider_k3d_configure_istio` applies it, `shellcheck scripts/lib/providers/k3d.sh`, `bats scripts/tests/lib/istio_ingressclass.bats`, `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh`
- [ ] lib-foundation: `_run_command` if-count refactor (v0.3.0)
- [ ] lib-foundation: sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] lib-foundation: route bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] Shopping cart repo hygiene: branch protection on all 5 repos (automate via `gh api`)
- [ ] v0.8.0 planning: write implementation spec for k3dm-mcp

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.3 | released | See CHANGE.md |
| v0.8.0 | **active** | Lean MCP server (`k3dm-mcp`) — discrete repo |
| v0.9.0 | planned | Messaging gateway (Slack) — natural language cluster ops |
| v1.0.0 | vision | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (as of 2026-03-11 — post v0.7.3)

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
  -- tags Copilot for code review before every PR

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
