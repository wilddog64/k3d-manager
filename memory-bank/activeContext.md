# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.7.3` (as of 2026-03-10)

**v0.7.2 SHIPPED** — squash-merged to main (4738fd8), PR #26, 2026-03-08.
**v0.7.3 active** — branch cut from main 2026-03-08.

---

## Current Focus

**v0.7.3: Shopping Cart CI/CD + Cluster Rebuild Validation**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Cluster rebuild + pre-commit hook smoke test | Gemini | ✅ done — commit 88c144f |
| 2 | Reusable GitHub Actions workflow (build + Trivy + push + kustomize update) | Codex | ✅ done — commit 0a28d10 |
| 3 | Caller workflow in each service repo (5 services) | Codex | ✅ done — commits eaa592f/c086e09/96c9c05/e220ac4 |
| 4 | Fix ArgoCD Application CR repoURLs + destination.server | Codex | ✅ done — commit 9066bd3 |
| 5 | `shopping_cart.sh` plugin — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps` | Codex | ✅ done |
| 6 | Trivy restore + repin all 5 service repos | Codex | ✅ done — commit 981008c |
| 7–12 | ArgoCD→Ubuntu connectivity investigation | Gemini | ✅ done — root cause found |
| 13 | Rebuild infra cluster on M2 Air + ArgoCD→Ubuntu registration + app sync | Codex | 🔄 active — spec: `docs/plans/v0.7.3-gemini-task13-m2air-infra-rebuild.md` |

**Root cause (Tasks 7–12):** ArgoCD was on M4 Air which has no network route to Ubuntu
(`10.211.55.14` is a Parallels VM only reachable from M2 Air). Fix: rebuild infra cluster
on M2 Air (Task 13). Ruled out: TLS SAN, iptables/ufw, MTU fragmentation.

---

## Open Items

- [ ] Task 13: Codex rebuilds infra on M2 Air + registers Ubuntu + syncs apps — Ubuntu k3s intact, do NOT rebuild Ubuntu
- [ ] v0.7.3 PR — open after Task 13, tag Copilot for review
- [ ] lib-foundation: `_run_command` if-count refactor (v0.3.0)
- [ ] lib-foundation: sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] lib-foundation: route bare sudo in `_install_debian_helm` / `_install_debian_docker`

### Task 13 status (Codex — 2026-03-10)

- Infra cluster tear-down/redeploy on M2 Air: PASS (k3d cluster rebuilt; Vault/ESO/Istio/ArgoCD/Jenkins/OpenLDAP running; logs under `scratch/logs/codex-task13-*`)
- Vault automatically re-seeded during `deploy_vault`; namespace health verified (`kubectl get pods -A` clean)
- Blocked at Task 5 — root cause: `add_ubuntu_k3s_cluster` never implemented kubeconfig export via SSH. Fix assigned as Task 14.

### Task 14 (Codex — assigned 2026-03-10)

Fix `add_ubuntu_k3s_cluster` to auto-export kubeconfig via SSH.
Spec: `docs/plans/v0.7.3-codex-task14-ubuntu-kubeconfig-export.md`

**Prerequisite (owner runs on Ubuntu before Codex starts Task 14):**
```bash
ssh ubuntu "mkdir -p /home/parallels/.kube && \
  sudo cp /etc/rancher/k3s/k3s.yaml /home/parallels/.kube/k3s.yaml && \
  sudo chown parallels:parallels /home/parallels/.kube/k3s.yaml && \
  chmod 600 /home/parallels/.kube/k3s.yaml"
```

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.2 | released | See CHANGE.md |
| v0.7.3 | **active** | Shopping cart CI/CD + cluster rebuild |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) — local clusters |
| v0.9.0 | planned | Messaging gateway (Slack) — natural language cluster ops |
| v1.0.0 | vision | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (Task 13 in progress — 2026-03-10)

**Architecture:** Infra cluster on M2 Air (not M4 Air) — ArgoCD needs direct access to
Ubuntu at `10.211.55.14` (Parallels VM, only reachable from M2 Air's network).
M4 Air has its own local k3d cluster for dev only — not the infra cluster.

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
| shopping-cart-apps | BLOCKED — ArgoCD sync pending (Task 13) |

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
  -- commits own work; updates memory-bank to report completion
  -- must push to remote before updating memory-bank
  -- NOT suited for multi-step cluster rebuild or orchestration tasks

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
- Gemini made unauthorized code fixes in Task 6 — Claude must verify against Codex's commits before merge.
- Gemini confirms plan correctly but executes differently — confirmation is not reliable, verify actual output.
- Gemini does not verify machine context — Task 13 failures caused by session running on Ubuntu, not M2 Air.
- One command at a time for Gemini on complex tasks — no branching specs.
- BATS count: 158 total, ~108 pass with `env -i` (50 skip due to env-dependent tests) — expected, not a bug.

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
