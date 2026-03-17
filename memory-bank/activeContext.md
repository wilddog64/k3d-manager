# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-16)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16. First commit: README releases table.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| ArgoCD cluster registration fix | **PR open** | shopping-cart-infra PR #5; Application manifests → host.k3d.internal:6443; register-ubuntu-k3s.sh added |
| Jenkins optional | **COMPLETE** | all 3 files gated — commits 08dc1bd + 4b02e16; BATS 2/2; shellcheck PASS |
| Deploy key rotation policy | **specced** | roadmap-v1.md v0.8.0; implementation pending |
| Pre-publication security cleanup | **COMPLETE** | 3 PRs merged — RSA key (product-catalog), CHANGE_ME placeholders (order, infra); all 6 repos now **public** (2026-03-17) |
| Multi-arch CI builds | **merged** | infra PR #7 (a937211) — all 5 app repos benefit |
| ArgoCD architecture docs | **merged** | infra PR #7 — app-of-apps rationale, kustomize patches, add-service guide |
| Stale `examples/` deleted | **merged** | infra PR #7 — Jenkins CD never implemented |
| Docs standardization (product-catalog + order) | **PR open** | product-catalog PR #8 + order PR #8; Copilot tagged; monitoring background |
| Verify ArgoCD all 5 apps Synced + Healthy | **Blocked** | 401 fix: `fix/argocd-image-pull` (f1e12b1) — PR pending |
| Re-enable shopping-cart-e2e-tests schedule | **pending** | after ArgoCD green |
| Playwright E2E green | **milestone gate** | |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.3 | released | See README Releases table |
| v0.9.4 | **active** | Full stack health — ImagePullBackOff fix + Playwright E2E in CI |
| v1.0.0 | planned | k3dm-mcp — MCP server wrapping k3d-manager CLI |
| v1.1.0 | planned | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (as of 2026-03-16 — Gemini smoke test verified)

**Architecture:** Infra cluster on M2 Air — ArgoCD manages Ubuntu k3s hub-and-spoke.
Ubuntu at `10.211.55.14` (Parallels VM, only reachable from M2 Air).

### Infra Cluster — k3d on OrbStack on M2 Air

| Component | Status |
|---|---|
| Vault | Running + Unsealed — `secrets` ns |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |
| cert-manager | Running — `cert-manager` ns |

### App Cluster — Ubuntu k3s

| Component | Status |
|---|---|
| k3s node | Ready (arm64) |
| Istio / ESO / Vault / OpenLDAP | Running |
| shopping-cart-apps | Synced — `ImagePullBackOff` (arch mismatch: amd64 on arm64 node + 401 Unauthorized) |

**SSH:** `ForwardAgent yes`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Core Library Rule

**Never modify `scripts/lib/foundation/` directly.** Fix in lib-foundation → PR → tag → subtree pull.
Subtree sync bypass: `K3DM_SUBTREE_SYNC=1 git subtree pull --prefix=scripts/lib/foundation ...`
**lib-foundation is now on v0.3.3** — subtree pulled on v0.9.4 branch (7684266).

---

## Engineering Protocol

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Memory-bank compression**: Compress at the *start* of each new branch.

---

## Agent Workflow

```
Claude  — specs, PRs, memory-bank, Copilot review management
Gemini  — cluster verification, BATS, red-team (M2 Air; push before memory-bank update)
Codex   — pure code, no cluster dependency
Owner   — approves and merges PRs
```

**Agent rules:** commit own work · no credentials in specs · shellcheck every touched .sh · no rebase/reset --hard/push --force · first command: `hostname && uname -n`

**Lessons:** Gemini skips memory-bank — paste spec inline · Codex fabricates SHAs — verify via `gh api` · Gemini expands scope — state forbidden actions explicitly · Copilot quota hit 2026-03-16 — resets monthly; docs-only PRs can merge without review

---

## Release Checklist

1. `git tag v<X.Y.Z> <sha> && git push origin v<X.Y.Z>`
2. `gh release create v<X.Y.Z> --title "..." --notes "..."`
3. Update README Releases table on next feature branch
4. `gh release list` — verify Latest

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart
- **Ubuntu k3s rebuild:** run `sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet` before reinstalling k3s — `k3s-uninstall.sh` alone leaves stale state
- **OrbStack→Parallels connectivity:** requires SSH tunnel on M2 Air: `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu`. ArgoCD cluster secret uses `https://host.k3d.internal:6443`
- **Vault auth over tunnel:** use static token with `eso-reader` policy — Kubernetes auth CA validation fails over tunnel
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Branch protection**: `enforce_admins` always ON — disable only to merge, re-enable immediately
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64
- **kustomization.yaml update in infra workflow**: step has `continue-on-error: true` — a protected branch push failure won't fail the job. Image is in ghcr.io but kustomization SHA won't be updated automatically; update manually or via ArgoCD image updater after CI green.
