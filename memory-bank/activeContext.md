# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.2` (as of 2026-03-15)

**v0.9.1 SHIPPED** — PR #31 squash-merged (942660e), 2026-03-15. Tagged + released.
**v0.9.2 ACTIVE** — branch `k3d-manager-v0.9.2` cut from main 2026-03-15.

---

## Current Focus

**v0.9.2: Copilot review process docs + Playwright E2E in CI**

| Item | Status | Notes |
|---|---|---|
| Copilot review process guide | **done** | `docs/guides/copilot-review-process.md` + `copilot-review-template.md` |
| README releases table update | **done** | Split to `docs/releases.md`, README shows last 3 |
| Reusable vCluster E2E workflow | pending | `.github/workflows/vcluster-e2e-setup.yml` in k3d-manager |
| Playwright E2E in CI | pending | `shopping-cart-e2e-tests` calls reusable workflow; blocked on ImagePullBackOff fix |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.1 | released | See CHANGE.md |
| v0.9.2 | **active** | Copilot review docs + Playwright E2E in CI |
| v1.1.0 | planned | AWS EKS provider + ACG sandbox lifecycle |
| v1.2.0 | planned | Google GKE provider |
| v1.3.0 | planned | Azure AKS provider |
| v1.4.0 | planned | k3dm-mcp — MCP server wrapping k3d-manager CLI (after all 3 providers) |

---

## Cluster State (as of 2026-03-15 — post v0.9.1)

**Architecture:** Infra cluster on M2 Air — ArgoCD manages Ubuntu k3s hub-and-spoke.
Ubuntu at `10.211.55.14` (Parallels VM, only reachable from M2 Air).

### Infra Cluster — k3d on OrbStack on M2 Air (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running + Unsealed — `secrets` ns |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |
| cert-manager | Deployed — `cert-manager` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu` from M2 Air)

| Component | Status |
|---|---|
| k3s node | Ready |
| Istio | Running |
| ESO | Running — 2/2 SecretStores Ready |
| Vault | Initialized + Unsealed |
| OpenLDAP | Running — `identity` ns |
| shopping-cart-data | Running |
| shopping-cart-apps | Synced via ArgoCD — `ImagePullBackOff` until CI/CD pushes images |

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
  -- commits own work; updates memory-bank to report completion
  -- must push to remote before updating memory-bank
  -- MUST run hostname && uname -n first — has repeatedly started on wrong machine

Codex  (Production Code + Cluster Ops)
  -- pure logic fixes and feature implementation
  -- shopping-cart repo work (preferred: Ubuntu native)
  -- commits own work; updates memory-bank to report completion

Owner
  -- approves and merges PRs
```

**Agent logging:** All k3d-manager output → `scratch/logs/<agent>-<task>-<timestamp>.log`

**Agent rules:**
- Commit your own work — self-commit is your sign-off.
- Update memory-bank to report completion.
- No credentials in task specs — reference env var names only.
- Run `shellcheck` on every touched `.sh` file.
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- **First command in every session: `hostname && uname -n`**

**Lessons learned:**
- Gemini skips memory-bank read — paste full task spec inline in every Gemini session prompt.
- Codex fabricates commit SHAs — always verify with `gh api repos/.../git/commits/<sha>`.
- Codex reports "done" after docs without code — require a PR URL as proof.
- Codex silently reverts intentional decisions — three-layer defense: CLAUDE.md + `DO NOT REMOVE` comments + memory-bank.
- Gemini expands scope — spec must explicitly state what is forbidden.
- Gemini over-reports test success with ambient env vars — verify with `env -i`.
- Gemini does not verify machine context — open terminal on M2 Air before starting.
- One command at a time for Gemini on complex tasks.
- BATS count: 190 total; ~108 pass with `env -i` (50 skip env-dependent) — expected.
- vCluster v0.32.1 pod labels: `app=vcluster,release=<name>`.
- Vault unseal non-interactive: `kubectl exec -n secrets vault-0 -- vault operator unseal "$KEY"`. Key field: `shard-1`.

---

## Release Checklist (do on the next feature branch after every PR merge to main)

1. Tag: `git tag v<X.Y.Z> <sha> && git push origin v<X.Y.Z>`
2. Release: `gh release create v<X.Y.Z> --title "v<X.Y.Z> — <title>" --notes "..."`
3. `docs/releases.md` — add new row at the top
4. `README.md` Releases table — keep last 3 rows, drop oldest
5. `README.md` Guides section — add links to any new guide docs
6. `README.md` Issue Logs section — add links to notable issues/findings from the release
7. Verify `gh release list` shows new version as Latest

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
