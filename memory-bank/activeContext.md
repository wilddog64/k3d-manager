# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.3.0` (as of 2026-04-30)

**v1.2.0 SHIPPED** — PR #67 merged to main (`f628c3cb`), tagged `v1.2.0`, released 2026-04-30.
`enforce_admins` restored. Retro: `docs/retro/2026-04-30-v1.2.0-retrospective.md`.

## v1.2.0 Summary (SHIPPED)

Key deliverables:
- `scripts/lib/acg/` subtree from `wilddog64/lib-acg` — ACG/GCP Playwright automation extracted
- `gemini.sh` (renamed from `antigravity.sh`) — browser automation plugin
- `deploy_shopping_cart_data()` — full data layer auto-bootstrap in `acg-up` Step 10b
- GHCR Vault-first fail-closed — no `gh auth token` OAuth fallback
- ArgoCD launchd KeepAlive port-forward (localhost:8080)
- ApplicationSet `${K3D_MANAGER_BRANCH}` envsubst variable
- Vault sealed-state auto-recovery; tunnel reverse-port fix (18200)
- `services/shopping-cart-namespace/` — namespace ownership (partial SharedResourceWarning fix)

All v1.2.0 bug/issue detail in `docs/bugs/`, `docs/issues/`, and `git log`.

---

## v1.3.0 First Commits (DONE)

- `23475ac0` — `chore: revert K3D_MANAGER_BRANCH to hardcoded main` — `services-git.yaml` + `bin/acg-up` cleanup
- `dec36c9f` — `chore(subtree): pull lib-acg main` — extend timing fix (PR #3, `9b39df02`); `_sanitizePhaseLabel`, dynamic `remainingMs`, screenshot on failure

---

## v1.2.1 Open Items (shopping-cart upstream fixes — Codex)

These are the remaining shopping-cart sync issues from v1.2.0. Spec: `docs/plans/v1.2.0-fix-orders-init-sql-and-security-config.md`.

**Fix 1** — `shopping-cart-infra` (`fix/orders-init-sql-uuid`): Replace SERIAL with UUID in orders init SQL configmap.
- After merge: remove `SPRING_JPA_HIBERNATE_DDL_AUTO=update` from `services/shopping-cart-order/kustomization.yaml`

**Fix 2** — `shopping-cart-order` (`fix/actuator-health-security`): Add `/actuator/health/**` to SecurityConfig permit list.
- After merge + RabbitMQHealthIndicator JAR fix: remove TCP socket probe patches from `services/shopping-cart-order/kustomization.yaml`
- NOTE: Fix 2 alone is NOT enough — JAR NPE still causes 503. Both must land.

**Fix 3** — Remove `namespace.yaml` from `shopping-cart-order` and `shopping-cart-product-catalog` kustomize bases.
- k3d-manager side already done (`services/shopping-cart-namespace/`)
- After merge: SharedResourceWarning clears; `shopping-cart-product-catalog` goes Synced+Healthy

**Final gate**: after all three cleanup steps done → `make down` → `make up` → `make sync-apps` → all 5 pods Running + all apps Synced+Healthy

---

## v1.3.0 Planned Work

- **`${K3D_MANAGER_BRANCH}` cleanup** — see FIRST COMMIT section above (immediate)
- **shopping-cart / k3d-manager decoupling** — `services/`, `shopping_cart.sh`, Step 10b make k3d-manager app-specific. Fix: move overlays + data-layer bootstrap to `shopping-cart-infra/k8s-overlays/`; ApplicationSet repoURL/branch configurable. Spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.
- **Keycloak deployment** — spec at `docs/plans/v1.2.0-deploy-keycloak.md`. Move ArgoCD to 9090; Keycloak on 8080; `testuser`/`testpassword`. Assign to Codex.
- **LDAP hardcoded password** — remove `userPassword` from LDIF; `_ldap_rotate_user_passwords` → Vault. Spec: `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`.
- **vault-bridge pod-origin traffic** — `ClusterSecretStore/vault-backend` stays `Ready=False`. Spec: `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
- **ACG Watcher extend button** — button not found during 1h TTL window. Spec: `docs/issues/2026-04-29-acg-watcher-extend-button-not-found.md`.
- **stage2 CI always fails in PR context** — cluster health check requires live OrbStack/k3d on self-hosted runner; should be gated behind a label or made optional.
- **GCP E2E smoke test** — BLOCKED. Full `make up` end-to-end on live GCP sandbox not verified.
- **ACG Watcher / Extend button** — OPEN. See spec above.
- **Orchestration Fragility** — OPEN. `docs/bugs/2026-04-23-infra-orchestration-fragility.md`.
- **Dual-cluster Status UX** — OPEN. `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`.
- **Repo Retention Cleanup** — OPEN. `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`.
- **Whitespace Enforcement** — OPEN. Add trailing-whitespace detection to `_agent_lint` for `.js`/`.sh`.
