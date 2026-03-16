# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.3` (as of 2026-03-15)

**v0.9.2 SHIPPED** — PR #35 squash-merged (f0cec06), 2026-03-15. Tagged + released.
**v0.9.3 ACTIVE** — branch `k3d-manager-v0.9.3` cut from main 2026-03-15.

---

## Current Focus

**v0.9.3: Next milestone — TBD**

| Item | Status | Notes |
|---|---|---|
| v0.9.2 merge + tag + release | **done** | PR #35 merged, v0.9.2 tagged, GitHub release created |
| README v0.9.2 entry | **done** | Added to releases table on k3d-manager-v0.9.3 |
| Branch protection k3d-manager-v0.9.3 | **done** | enforce_admins: true |
| lib-foundation v0.3.1 subtree pull | **done** | commit `1f8bcc5` on k3d-manager-v0.9.3 |
| Playwright E2E in CI | pending | `shopping-cart-infra` — blocked on ImagePullBackOff (images not in ghcr.io) |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.2 | released | See README Releases table |
| v0.9.3 | **active** | TBD — cut 2026-03-15 |
| v1.0.0 | planned | k3dm-mcp — MCP server wrapping k3d-manager CLI |
| v1.1.0 | planned | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (as of 2026-03-15 — post v0.9.2)

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
| cert-manager | Deployed — `cert-manager` ns (v0.8.0) |

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
  -- MUST run hostname && uname -n first

Codex  (Production Code + Cluster Ops)
  -- pure logic fixes and feature implementation
  -- commits own work; updates memory-bank to report completion
  -- fallback: clone from GitHub to M4 Air, work locally, push to GitHub

Owner
  -- approves and merges PRs
```

**Agent rules:**
- Commit your own work. Update memory-bank to report completion.
- No credentials in task specs — reference env var names only.
- Run `shellcheck` on every touched `.sh` file.
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- **First command in every session: `hostname && uname -n`**

**Lessons learned:**
- Gemini skips memory-bank read — paste full task spec inline.
- Codex fabricates commit SHAs — verify with `gh api repos/.../git/commits/<sha>`.
- Codex reports "done" after writing docs without code — require PR URL as proof.
- Codex silently reverts decisions — three-layer defense: CLAUDE.md + DO NOT REMOVE comments + memory-bank.
- Gemini expands scope — spec must state what is forbidden.
- Gemini over-reports test success — verify with `env -i`.
- `git subtree add --squash` blocks GitHub rebase-merge — use squash-merge with admin override.
- BATS count: 190 total, ~108 pass with `env -i` — expected.
- vCluster v0.32.1 pod labels: `app=vcluster,release=<name>`.
- Vault unseal: `kubectl exec -n secrets vault-0 -- vault operator unseal "$KEY"`. Key field: `shard-1`.
- Copilot thread resolution: GraphQL `resolveReviewThread` mutation — REST API does not support it.
- Always resolve Copilot threads after replying — do not wait for user to ask.
- `enforce_admins` policy: always ON; disable only to merge, re-enable immediately after.

---

## Release Checklist (do after every PR merge to main)

1. Tag the merge commit: `git tag v<X.Y.Z> <sha> && git push origin v<X.Y.Z>`
2. Create GitHub release: `gh release create v<X.Y.Z> --title "..." --notes "..."`
3. Update README.md Releases table on the next feature branch
4. Verify `gh release list` shows new version as Latest

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Branch protection**: `enforce_admins` always ON — disable only to merge, re-enable immediately
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64
