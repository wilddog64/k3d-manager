# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-16)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| payment-service missing Secrets | **MERGED** | PR #14 merged (9d9de98); `payment-db-credentials` + `payment-encryption-secret` in k8s/base; `enforce_admins` re-enable pending |
| Rebuild Ubuntu k3s + E2E verify | **ASSIGNED TO GEMINI** | spec: `docs/plans/v0.9.4-gemini-rebuild-ubuntu-k3s-e2e.md`; gate: Codex tunnel plugin verified first |
| Verify all 5 pods Running on Ubuntu k3s | **PENDING** | basket CrashLoopBackOff expected (data layer missing); covered in Gemini rebuild spec |
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

### App Cluster — Ubuntu k3s (now on EC2)

**Migrated 2026-03-20 from Parallels VM to AWS EC2 (ACG sandbox)**
- Instance: `i-0f3de7d43ccae4a52` — `t3.medium` — `54.186.107.155` — `us-west-2`
- SSH: `Host ubuntu` in `~/.ssh/config` — key `~/.ssh/k3d-manager-key.pem` — user `ubuntu`
- Old Parallels config preserved as `Host ubuntu-parallels`
- No ProxyJump — direct SSH from M4

| Component | Status |
|---|---|
| k3s node | **PENDING DEPLOY** — fresh EC2 instance |
| Istio / ESO / Vault / OpenLDAP | **PENDING DEPLOY** |
| ghcr-pull-secret | **PENDING DEPLOY** |
| basket-service | **PENDING DEPLOY** |
| order-service | **PENDING DEPLOY** |
| product-catalog | **PENDING DEPLOY** |
| payment-service | **PENDING DEPLOY** |

**FIXED (2026-03-20):** `_run_command --prefer-sudo` now detects TTY availability and falls back to interactive sudo when `sudo -n` fails, covering `--prefer-sudo`, `--require-sudo`, and probe paths. Regression tests live in `scripts/tests/lib/run_command.bats`. Issue: `docs/issues/2026-03-19-run-command-non-interactive-sudo-failure.md`

**SSH Tunnel (autossh plugin live):** Use `tunnel_start`/`tunnel_status`/`tunnel_stop` from `scripts/k3d-manager` to manage the launchd-backed autossh bridge; defaults in `scripts/etc/tunnel/vars.sh`. Spec: `docs/plans/v0.9.4-codex-autossh-tunnel-plugin.md`
**ArgoCD cluster registration:** `register_app_cluster` applies `scripts/etc/argocd/cluster-secret.yaml.tmpl` with `envsubst` (token via `ARGOCD_APP_CLUSTER_TOKEN`); replaces failing `argocd cluster add`. Spec: `docs/plans/v0.9.4-codex-argocd-cluster-registration.md`
**Cluster smoke test:** `bin/smoke-test-cluster-health.sh` checks ghcr secret, ArgoCD sync, and pod counts before declaring success. Spec: `docs/plans/v0.9.4-codex-smoke-test-cluster-health.md`

**SSH Tunnel launchd fix (2026-03-20):** `~/.ssh/config` now has `Host ubuntu-tunnel` (no ControlMaster, IdentitiesOnly yes) for use by launchd. `com.k3d-manager.ssh-tunnel.plist` updated to use `ubuntu-tunnel`. Key added to macOS keychain via `ssh-add --apple-use-keychain`.

**ArgoCD cluster secret:** `cluster-ubuntu-k3s` created in `cicd` ns pointing to `https://host.k3d.internal:6443`. Apps still `Unknown` — cluster secret missing bearer token. `register_app_cluster` spec updated to include `ARGOCD_APP_CLUSTER_TOKEN` (required). Pre-req: create `argocd-manager` service account on ubuntu k3s before running `register_app_cluster`.

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
