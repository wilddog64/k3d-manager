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
| **Codex: fix app manifests** | **MERGED** | PRs merged to main 2026-03-21; order `d109004`, product-catalog `aa5de3c`, infra `1a5c34d`; tagged v0.1.1; `docs/next-improvements` branches created |
| **Gemini: re-enable ArgoCD sync** | **COMPLETE** | Auto-sync re-enabled for all apps; verified tracking `HEAD` |
| **Gemini: force sync post-manifest-fix** | **BLOCKED** | Gemini exhausted context; documented discrepancies instead of running sync; `argocd app sync` still needed |
| **Frontend regression** | **OPEN** | Was Running ✅; now CrashLoopBackOff after ArgoCD sync — emptyDir patch possibly overwritten; probe failing on port 8080 `/health` |
| **product-catalog OutOfSync** | **OPEN** | ArgoCD shows OutOfSync+Degraded at `1214373f`; manifest fix `aa5de3c` on main but not picked up yet |
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
| basket-service | **Running** ✅ — ArgoCD Healthy |
| product-catalog | **OutOfSync / Degraded** ⚠️ — manifest fix `aa5de3c` not yet picked up by ArgoCD |
| order-service | **Degraded** ⚠️ — PostgreSQL OK; RabbitMQ `Connection refused` persists |
| payment-service | **Progressing** ⚠️ — resource constraints; NetworkPolicies fixed |
| frontend | **CrashLoopBackOff** ⚠️ — REGRESSION; was Running; emptyDir patch may have been overwritten by ArgoCD sync |


---

## Key Capabilities Added (v0.9.4)

- **GitOps Reconciliation** — ArgoCD auto-sync re-enabled and tracking `HEAD` for all shopping-cart applications.
- **PostgreSQL Auth Fix** — manual secret patching on app cluster to sync passwords with data layer.
- **Schema Validation Fix** — manual DDL update (`ADD COLUMN`) to align DB with Hibernate expectations.
- **NetworkPolicy Hardening** — fixed `allow-dns` and added `allow-to-istio` to unblock `payment-service` initialization.
- **`_run_command` TTY fallback** — interactive sudo fallback when `sudo -n` unavailable.
- **autossh tunnel plugin** — `tunnel_start|stop|status`.

---

## Operational Notes

- **Manifest fix PRs (2026-03-21):** order PR #15 (`d109004`), product-catalog PR #14 (`aa5de3c`), infra PR #20 (`1a5c34d`) — all squash-merged; v0.1.1 tagged; `docs/next-improvements` branches created on all three.
- **Copilot P1 bugs fixed:** product-catalog env var keys corrected (`DATABASE_*` → `DB_*`, `RABBITMQ_USER` → `RABBITMQ_USERNAME`, readiness probe `/health` → `/ready`); order-service `VAULT_ENABLED: false` set alongside `SPRING_CLOUD_VAULT_ENABLED: false`.
- **ArgoCD Sync Issues (resolved):** Original Codex SHAs (`007d80a`, `f9a7381`, `aaa08c1`) were committed to local `main` only — never pushed. Fixed by feature branch workflow. Manifests now on remote main.
- **Root findings (2026-03-21):**
    - `order-service` was missing `shipping_postal_code` and `total_amount` columns in PostgreSQL.
    - `product-catalog` was connecting to `localhost` fallback — env var key mismatch silently ignored.
    - `shopping-cart-payment` namespace had restrictive NetworkPolicies blocking DNS and Istiod egress.
    - `order-service` experiencing `Connection refused` to RabbitMQ service despite successful DB connection.
- **Memory Constraints** — `t3.medium` (4GB) is at 95% capacity; some pods scaled to 0 during troubleshooting.
- **PTY watchdog** — guards against Gemini CLI PTY leak.
- **Gemini context exhaustion (2026-03-21):** Gemini lost task context mid-session; documented discrepancies instead of running `argocd app sync`. Commit `ae2af95` (3 issue docs in `docs/issues/`). Force sync still pending.
- **Frontend regression:** ArgoCD at `65b354f` (correct SHA) but pod CrashLoopBackOff — possible ArgoCD sync overwrote manual emptyDir volume patch. Next session must check `kubectl describe pod -l app=frontend | grep -A5 volume`.
- **ArgoCD app status (last known 2026-03-21):** basket Healthy ✅, frontend Progressing/CrashLoop, order Degraded, payment Progressing, product-catalog OutOfSync+Degraded, shopping-cart-apps OutOfSync.
