# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-16)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| payment-service missing Secrets | **MERGED** | PR #14 merged (9d9de98); `payment-db-credentials` + `payment-encryption-secret` in k8s/base; `enforce_admins` re-enable pending |
| Force ArgoCD sync — order + product-catalog | **PENDING** | Resources exist in git; sync Unknown due to tunnel; Gemini to run `argocd app sync` |
| Verify all 5 pods Running on Ubuntu k3s | **PENDING** | basket CrashLoopBackOff (app-level, data layer missing); order/product-catalog pending ArgoCD sync |
| Re-enable shopping-cart-e2e-tests schedule | **PENDING** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.9.3 | released | See README Releases table |
| v0.9.4 | **active** | Full stack health — all app pods Running + Playwright E2E green |
| v0.9.5 | planned | Service mesh — Istio full activation |

---

## Cluster State (as of 2026-03-18)

**Architecture:** Infra cluster on M2 Air — ArgoCD manages Ubuntu k3s hub-and-spoke.

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
| k3s node | **UNINSTALLED** — VM hard-reset 2026-03-19; pending redeploy |
| Istio / ESO / Vault / OpenLDAP | **PENDING REDEPLOY** |
| ghcr-pull-secret | **PENDING REDEPLOY** |
| basket-service | **PENDING REDEPLOY** |
| order-service | **PENDING REDEPLOY** |
| product-catalog | **PENDING REDEPLOY** |
| payment-service | **PENDING REDEPLOY** |

**FIXED (2026-03-20):** `_run_command --prefer-sudo` now detects TTY availability and falls back to interactive sudo when `sudo -n` fails, covering `--prefer-sudo`, `--require-sudo`, and probe paths. Regression tests live in `scripts/tests/lib/run_command.bats`. Issue: `docs/issues/2026-03-19-run-command-non-interactive-sudo-failure.md`

**SSH Tunnel (mandatory, pending automation):** `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu &` — Codex implementing autossh + launchd plugin per `docs/plans/v0.9.4-codex-autossh-tunnel-plugin.md`

---

## shopping-cart-payment

- **main:** `9d9de98` — PR #14 merged
- **active branch:** `feat/v0.1.1` — releases table updated (4e51a5d)
- **enforce_admins:** disabled for merge — re-enable after next PR merges
- **stale branches:** all cleaned up; `docs/next-improvements` retained

---

## Operational Notes

- **ArgoCD Cluster Secret**: `cluster-ubuntu-k3s` in `cicd` ns requires `insecure: true` for `host.k3d.internal` mismatch.
- **payment encryption-key**: valid Base64 dev placeholder (`ZGV2LXBsYWNlaG9sZGVyLWtleS1kby1ub3QtdXNlLSE=`) — replace via ESO/Vault in production.
