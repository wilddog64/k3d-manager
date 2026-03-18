# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-16)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16. First commit: README releases table.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| ArgoCD cluster registration fix | **COMPLETE** | Manual cluster secret `cluster-ubuntu-k3s` patched with `insecure: true`; registered with `https://host.k3d.internal:6443` |
| Verify ArgoCD all 5 apps Synced + Healthy | **BLOCKED** | Missing Secrets + ConfigMaps on Ubuntu k3s — see `docs/issues/2026-03-18-shopping-cart-missing-secrets-configmaps.md` |
| Shopping cart missing Secrets/ConfigMaps | **CODEX ASSIGNED** | payment-service: `payment-db-credentials` + `payment-encryption-secret` missing from k8s/base; Codex spec: `shopping-cart-infra/docs/plans/codex-payment-missing-secrets.md`; order/product-catalog: resources exist but ArgoCD sync Unknown — Gemini to force sync |
| Jenkins optional | **COMPLETE** | all 3 files gated — commits 08dc1bd + 4b02e16; BATS 2/2; shellcheck PASS |
| Multi-arch CI builds | **merged** | infra PR #7 (a937211) — all 5 app repos benefit |
| Multi-arch workflow pin fix | **COMPLETE** | All 5 app repos merged to main 2026-03-18; arm64 images pushed to ghcr.io |
| Gemini: re-verify ArgoCD after arm64 images | **COMPLETE** | Spec: `docs/plans/v0.9.4-gemini-argocd-verify.md` — Verified `ghcr-pull-secret`, registered cluster, added frontend |
| Codex: kubeconfig merge automation | **COMPLETE** | Spec: `docs/plans/v0.9.4-codex-kubeconfig-merge.md` — merged kubeconfig automation (6699ce8) |
| Re-enable shopping-cart-e2e-tests schedule | **pending** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.3 | released | See README Releases table |
| v0.9.4 | **active** | Full stack health — ImagePullBackOff fix + Playwright E2E in CI |
| v0.9.5 | planned | Service mesh — Istio full activation (mTLS, AuthzPolicy, Gateway, DestinationRule, ServiceEntry) |

---

## Cluster State (as of 2026-03-18 — Gemini verified)

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
| ghcr-pull-secret | Verified in `apps`, `data`, `payment` namespaces |
| shopping-cart-apps | Pulling ARM64 images; some in CrashLoopBackOff (normal init); `payment-service` pending sync refresh |

**SSH Tunnel (mandatory):** `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu &`

---

## Release Checklist

1. `git tag v<X.Y.Z> <sha> && git push origin v<X.Y.Z>`
2. `gh release create v<X.Y.Z> --title "..." --notes "..."`
3. Update README Releases table on next feature branch
4. `gh release list` — verify Latest

---

## Operational Notes

- **ArgoCD Cluster Secret**: `cluster-ubuntu-k3s` in `cicd` ns requires `insecure: true` for `host.k3d.internal` mismatch.
- **Frontend Manifest**: `argocd/applications/frontend.yaml` added to `shopping-cart-infra` (PR #17).
- **Tag Refresh**: Run `update_tags.sh` to ensure `newTag: latest` across all app repos for ARM64 builds.
