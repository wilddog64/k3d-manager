# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.9.4` (as of 2026-03-21)

**v0.9.3 SHIPPED** — PR #36 squash-merged (8046c73), tagged + released 2026-03-16.
**v0.9.4 ACTIVE** — full stack health milestone.

---

## Current Focus

| Item | Status | Notes |
|---|---|---|
| Reduce replicas + remove HPAs | **MERGED** | 5 repos squash-merged to main 2026-03-20 |
| Frontend nginx fix | **MERGED** | `65b354f` on main, tagged v0.1.1, released 2026-03-21 |
| **Gemini: verify frontend Running** | **COMPLETE** | Pod `frontend-85969b4bf-4wkdz` is `Running` on ubuntu-k3s |
| shopping-cart-infra PR #18 | **MERGED** | `a97ee04` — fix trivy-action 0.30.0→v0.35.0 |
| shopping-cart-infra PR #19 | **MERGED** | `4ecc6b5` — address Copilot PR #5 comments |
| **Gemini: Fix PostgreSQL Auth** | **COMPLETE** | Fixed `order-service` and `product-catalog` auth via secret patching |
| **Gemini: Fix Schema mismatch** | **COMPLETE** | Added missing columns to `orders` table in `postgresql-orders` |
| **Gemini: Fix Health Checks** | **COMPLETE** | Patched `product-catalog` readiness probe path `/health/ready` -> `/health` |
| **Gemini: Fix NetworkPolicies** | **COMPLETE** | Patched `allow-dns` and added `allow-to-istio` in `shopping-cart-payment` |
| **Codex: fix app manifests** | **ASSIGNED** | spec: `docs/plans/v0.9.4-codex-fix-app-manifests.md`; 6 files across 3 repos |
| Re-enable e2e-tests schedule | **PENDING** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |

---

## Cluster Architecture

**Infra cluster:** k3d on OrbStack on M2 Air — ArgoCD hub for Ubuntu k3s.
**App cluster:** Ubuntu k3s on AWS EC2 ACG sandbox — `i-0650af63c77af770c`, `34.219.1.106`, `t3.medium`, `us-west-2`.

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

| Component | Status |
|---|---|
| k3s node | **Ready** — v1.34.5+k3s1 |
| Istio | **Running** — `istio-system` |
| ghcr-pull-secret | **Verified** in `apps`, `data`, `payment` namespaces |
| basket-service | **Running** ✅ |
| product-catalog | **Running** ✅ (Fixed PostgreSQL auth + probe path) |
| order-service | **Running** ⚠️ (Fixed PostgreSQL auth + schema; RabbitMQ connection refused) |
| payment-service | **Pending** ⚠️ (Resource constraints; NetworkPolicies fixed) |
| frontend | **Running** ✅ (Manual emptyDir patch remains active) |


---

## Key Capabilities Added (v0.9.4)

- **PostgreSQL Auth Fix** — manual secret patching on app cluster to sync passwords with data layer.
- **Schema Validation Fix** — manual DDL update (`ADD COLUMN`) to align DB with Hibernate expectations.
- **NetworkPolicy Hardening** — fixed `allow-dns` and added `allow-to-istio` to unblock `payment-service` initialization.
- **`_run_command` TTY fallback** — interactive sudo fallback when `sudo -n` unavailable.
- **autossh tunnel plugin** — `tunnel_start|stop|status`.

---

## Operational Notes

- **Memory Constraints** — `t3.medium` (4GB) is at 95% capacity; some pods scaled to 0 during troubleshooting.
- **ArgoCD Sync Paused** — Auto-sync disabled for `order-service` and `product-catalog` to preserve manual patches.
- **PTY watchdog** — guards against Gemini CLI PTY leak.
