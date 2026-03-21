# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-20)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), tagged + released 2026-03-16.
**v0.9.4 ACTIVE** — full stack health milestone.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| Reduce replicas + remove HPAs | **PRs merged** (5 repos) | basket, order, payment, product-catalog, frontend — squash-merged to main 2026-03-20 |
| Rebuild Ubuntu k3s + E2E verify | **ASSIGNED TO GEMINI** | spec: `docs/plans/v0.9.4-gemini-rebuild-ubuntu-k3s-e2e.md`; gate: Codex tunnel plugin verified |
| ArgoCD cluster registration | **ASSIGNED TO GEMINI** | spec: `docs/plans/v0.9.4-gemini-argocd-cluster-registration.md`; needs argocd-manager SA on EC2 first |
| Verify all 5 pods Running | **PENDING** | basket CrashLoopBackOff expected (data layer Redis/RabbitMQ missing on k3s) |
| Re-enable e2e-tests schedule | **PENDING** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |
| Codex: fix `instsudo` typo | **PENDING** | `scripts/lib/system.sh` line 838 |

---

## Cluster Architecture

**Infra cluster:** k3d on OrbStack on M2 Air — ArgoCD hub for Ubuntu k3s.
**App cluster:** Ubuntu k3s on AWS EC2 ACG sandbox — `i-035fd7f7c8fac77da`, `t3.medium`, `34.219.77.212`, `us-west-2`. SSH: `Host ubuntu` → `~/.ssh/k3d-manager-key.pem`.

### Infra Cluster (M2 Air — k3d/OrbStack)

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

### App Cluster (EC2 — Ubuntu k3s)

**Migrated 2026-03-20 from Parallels VM to EC2 ACG sandbox.**
ArgoCD cluster secret `cluster-ubuntu-k3s` updated with `bearerToken` from `argocd-manager` SA.

| Component | Status |
|---|---|
| k3s node | **Ready** — v1.34.5+k3s1 |
| Istio | **Running** — `istio-system` |
| ghcr-pull-secret | **Verified** in `apps`, `data`, `payment` namespaces |
| payment-service | **Running** (confirmed connectivity to infra cluster Vault) |
| basket-service | **CrashLoopBackOff** (expected — Redis/RabbitMQ missing on k3s) |
| order-service | **CrashLoopBackOff** (data layer missing) |
| product-catalog | **CrashLoopBackOff** (data layer missing) |
| frontend | **CrashLoopBackOff** (nginx permissions issue) |

---

## Key Capabilities Added (v0.9.4)

- **`_run_command` TTY fallback** — `--prefer-sudo`/`--require-sudo`/probe paths fall back to interactive sudo when `sudo -n` unavailable; BATS coverage in `scripts/tests/lib/run_command.bats`
- **autossh tunnel plugin** — `tunnel_start|stop|status` via `scripts/k3d-manager`; launchd plist `com.k3d-manager.ssh-tunnel` uses `Host ubuntu-tunnel` (no ControlMaster, keychain-loaded key)
- **`register_app_cluster`** — applies `scripts/etc/argocd/cluster-secret.yaml.tmpl` with `ARGOCD_APP_CLUSTER_TOKEN`; replaces manual `argocd cluster add`
- **`bin/smoke-test-cluster-health.sh`** — ghcr secret + ArgoCD sync + pod count gate
- **Safety gate audit + dry-run + plan mode** — `deploy_*` require `--confirm`; `--dry-run`/`-n` prints commands; `deploy_vault --plan` reads cluster state (unreviewed — Codex worked on wrong task)

---

## Operational Notes

- **Branch protection** — review requirement temporarily set to 0 for merge; restore to 1 after all 5 PRs merged
- **payment enforce_admins** — was disabled for PR #14; re-enable after feat/v0.1.1 merges
- **ArgoCD cluster secret** — `cluster-ubuntu-k3s` in `cicd` ns; `insecure: true`; needs `bearerToken`
- **payment encryption-key** — dev placeholder Base64 — replace via ESO/Vault in production
- **PAT rotation** — expires 2026-04-12; reminder fires daily 9am April 5-11 via launchd
