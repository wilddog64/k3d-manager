# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.7.3` (as of 2026-03-08)

**v0.7.2 SHIPPED** — squash-merged to main (4738fd8), PR #26, 2026-03-08.
**v0.7.3 active** — branch cut from main 2026-03-08.

---

## Current Focus

**v0.7.3: Shopping Cart CI/CD + Cluster Rebuild Validation**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Cluster rebuild + pre-commit hook smoke test | Gemini | ✅ done — commit 88c144f |
| 2 | Reusable GitHub Actions workflow (build + Trivy + push + kustomize update) | Codex | pending |
| 3 | Caller workflow in each service repo (5 services) | Codex | pending |
| 4 | Fix ArgoCD Application CR repoURLs + destination.server | Codex | pending |
| 5 | `shopping_cart.sh` plugin — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps` | Codex | pending |
| 6 | End-to-end verification: push → ghcr.io → ArgoCD → pod on Ubuntu | Gemini | pending |

## v0.7.3 Task 1 Completion Report (Gemini — 2026-03-08)

- Infra cluster rebuild (k3d/OrbStack): PASS
- BATS result: 158/158 passing
- Pre-commit hook tests: A=PASS, B=PASS, C=PASS, D=PASS
- Ubuntu k3s cluster rebuild: PASS
- Ubuntu SecretStores: 2/2 Ready (App Cluster scope — note: was 3/3 previously, needs clarification)
- Ubuntu shopping-cart-data: Running
- Ubuntu shopping-cart-apps: ImagePullBackOff (expected — pending v0.7.3 CI/CD)
- Commit SHA: 88c144f

---

## Open Items

- [x] Cluster rebuild + v0.7.2 hook validation (Gemini) — spec: `docs/plans/v0.7.3-gemini-rebuild.md`
- [ ] Shopping cart CI/CD pipeline — full spec: `docs/plans/v0.7.3-shopping-cart-cicd.md`
- [ ] lib-foundation: `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] lib-foundation: sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] lib-foundation: route bare sudo in `_install_debian_helm` / `_install_debian_docker`

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.2 | released | See CHANGE.md |
| v0.7.3 | **active** | Shopping cart CI/CD + cluster rebuild |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.8.0 |

---

## Cluster State (rebuilt 2026-03-08 — Gemini validated)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status |
|---|---|
| k3s node | Ready — v1.34.4+k3s1 |
| Istio | Running |
| ESO | Running — 2/2 SecretStores Ready (⚠️ was 3/3 — needs clarification) |
| Vault | Initialized + Unsealed |
| OpenLDAP | Running — `identity` ns |
| shopping-cart-data | Running ✅ |
| shopping-cart-apps | BLOCKED — ImagePullBackOff (images not yet pushed) |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

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
