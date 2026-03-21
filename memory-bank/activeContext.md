# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-20)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), tagged + released 2026-03-16.
**v0.9.4 ACTIVE** — full stack health milestone.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| Reduce replicas + remove HPAs | **MERGED** | 5 repos squash-merged to main 2026-03-20 |
| Frontend nginx fix | **MERGED** | `65b354f` on main, tagged v0.1.1, released 2026-03-21 |
| **Gemini: verify frontend Running** | **COMPLETE** | Pod `frontend-85969b4bf-zq9st` is `Running` on ubuntu-k3s; manually patched with `emptyDir` volumes |
| Rebuild Ubuntu k3s + E2E verify | **ASSIGNED TO GEMINI** | spec: `docs/plans/v0.9.4-gemini-rebuild-ubuntu-k3s-e2e.md`; gate: Codex tunnel plugin verified |
| ArgoCD cluster registration | **ASSIGNED TO GEMINI** | spec: `docs/plans/v0.9.4-gemini-argocd-cluster-registration.md`; needs argocd-manager SA on EC2 first |
| Verify all 5 pods Running | **PENDING** | basket/order/product-catalog CrashLoopBackOff (data layer missing) |
| Re-enable e2e-tests schedule | **PENDING** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |

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

Migrated 2026-03-20 from Parallels VM to EC2 ACG sandbox. ArgoCD cluster secret `cluster-ubuntu-k3s` updated with `bearerToken` from `argocd-manager` SA.

| Component | Status |
|---|---|
| k3s node | **Ready** — v1.34.5+k3s1 |
| Istio | **Running** — `istio-system` |
| ghcr-pull-secret | **Verified** in `apps`, `data`, `payment` namespaces |
| payment-service | **Running** (confirmed connectivity to infra cluster Vault) |
| frontend | **Running** (manually patched with emptyDir volumes for nginx cache) |
| basket-service | **CrashLoopBackOff** (expected — Redis/RabbitMQ missing on k3s) |


---

## Key Capabilities Added (v0.9.4)

- **`_run_command` TTY fallback** — interactive sudo fallback when `sudo -n` unavailable; BATS coverage in `scripts/tests/lib/run_command.bats`
- **autossh tunnel plugin** — `tunnel_start|stop|status`; launchd plist `com.k3d-manager.ssh-tunnel` uses `Host ubuntu-tunnel`
- **`register_app_cluster`** — applies `scripts/etc/argocd/cluster-secret.yaml.tmpl` with `ARGOCD_APP_CLUSTER_TOKEN`; replaces manual `argocd cluster add`
- **`bin/smoke-test-cluster-health.sh`** — ghcr secret + ArgoCD sync + pod count gate
- **Safety gate audit + dry-run + plan mode** — `deploy_*` require `--confirm`; `--dry-run`/`-n` prints commands; `deploy_vault --plan` reads cluster state

---

## Operational Notes

- **payment encryption-key** — dev placeholder Base64 — replace via ESO/Vault in production
- **ArgoCD cluster secret** — `cluster-ubuntu-k3s` in `cicd` ns; `insecure: true`; needs `bearerToken`
- **PAT rotation** — expires 2026-04-12; launchd reminder fires daily 9am April 5-11
- **Re-enable `enforce_admins`** — shopping-cart-payment main branch (was disabled for PR #14)
