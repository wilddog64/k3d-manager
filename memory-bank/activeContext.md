# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.3` (as of 2026-03-16)

**v0.9.2 SHIPPED** — PR #35 squash-merged (f0cec06), 2026-03-15. Tagged + released.
**v0.9.3 ACTIVE** — branch cut from main 2026-03-15.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| lib-foundation v0.3.2 subtree pull | **done** | commit `e4d2eed` |
| TTY fix — `_DCRS_PROVIDER` global in core.sh | **done** | commit `04522b5` |
| Cluster rebuild smoke test | **DONE — PASS on M2 Air** | spec: `docs/plans/v0.9.3-cluster-rebuild-smoke-test.md` | Destroy/rebuild verified; all 8 components running; TTY fix verified |
| v0.9.4 spec | **done** | `docs/plans/v0.9.4-full-stack-health.md` |
| NVD API key | **done** | set in order + payment repos 2026-03-16 |
| Milestone brainstorm | **done** | v0.9.4 = full stack health; demo after v0.9.x series |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.2 | released | See README Releases table |
| v0.9.3 | **active** | TTY fix + lib-foundation v0.3.2 + cluster rebuild smoke test |
| v0.9.4 | planned | Full stack health — ImagePullBackOff fix + Playwright E2E in CI |
| v1.0.0 | planned | k3dm-mcp — MCP server wrapping k3d-manager CLI |
| v1.1.0 | planned | Multi-cloud providers (EKS/GKE/AKS) + ACG sandbox lifecycle |

---

## Cluster State (as of 2026-03-15)

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
| k3s node | Ready |
| Istio / ESO / Vault / OpenLDAP | Running |
| shopping-cart-apps | ArgoCD Synced — `ImagePullBackOff` until images pushed to ghcr.io |

**SSH:** `ForwardAgent yes`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Core Library Rule

**Never modify `scripts/lib/foundation/` directly.** Fix in lib-foundation → PR → tag → subtree pull.
Subtree sync bypass: `K3DM_SUBTREE_SYNC=1 git subtree pull --prefix=scripts/lib/foundation ...`
**lib-foundation is now on v0.3.3** — subtree pull pending after v0.9.3 smoke test.

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
