# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.2.0` (as of 2026-04-25)

**v1.1.0 SHIPPED** — PR #65 merged to main (`e013d23b`), tagged `v1.1.0`, released 2026-04-25.
Branch protection (`enforce_admins`) restored. Retro: `docs/retro/2026-04-25-v1.1.0-retrospective.md`.

## v1.1.0 Summary (SHIPPED — see `docs/retro/2026-04-25-v1.1.0-retrospective.md`)

Key commits: `3de58f4d` vars.sh, `a986d5bb` robot engine, `9686e5c3` GCP identity bridge,
`3a3806aa` CLUSTER_NAME fix, `1ab14ebf` CDP headless, `e013d23b` merge SHA.
All v1.1.0 bug detail archived in `docs/bugs/` and `git log`.


## Sandbox Rebuild Readiness — Option 2 Decision (2026-04-27)

**Decision:** Permanent fixes first, then cleanup, then merge to `main`. No ApplicationSet branch-pin hack.

**Why rebuild is NOT clean today:** ApplicationSet template uses `targetRevision: main`. The kustomize workarounds for order-service (TCP probes, `ddl-auto=update`, `SPRING_RABBITMQ_*`) live on `k3d-manager-v1.2.0`, not `main`. After a fresh `make up`, order-service breaks immediately.

**Cleanup dependency chain (do IN ORDER after each fix merges):**

1. **After Fix 1 merges** (`shopping-cart-infra` init SQL UUID — Codex):
   - Remove `SPRING_JPA_HIBERNATE_DDL_AUTO=update` patch from `services/shopping-cart-order/kustomization.yaml`

2. **After Fix 2 AND RabbitMQHealthIndicator JAR are both fixed**:
   - Remove all three TCP socket probe patches (readiness, liveness, startup) from `services/shopping-cart-order/kustomization.yaml`
   - NOTE: Fix 2 (SecurityConfig) alone is NOT enough — JAR NPE still causes 503. Both must land before TCP probes come out.

3. **After Fix 3 merges** (`shopping-cart-order` + `shopping-cart-product-catalog` + k3d-manager namespace app — Codex):
   - No cleanup needed. `services/shopping-cart-namespace/` stays as the permanent namespace owner.

4. **After all three cleanups above are done:**
   - Merge `k3d-manager-v1.2.0` → `main`
   - ApplicationSet then uses `main` forever — no workarounds, no branch-pin needed
   - `make down` → `make up` → `make sync-apps` produces all 5 pods Running + all apps Synced+Healthy

**What already survives rebuilds (no action needed):**
- `ghcr-pull-secret` — Step 5 of `acg-up` creates it automatically
- Data layer (PostgreSQL, Redis, RabbitMQ) — Step 10b `deploy_shopping_cart_data()` handles it
- Password alignment — automated in `deploy_shopping_cart_data()`
- `OrphanedResourceWarning` suppressed — `platform.yaml.tmpl` has `warn: false` (`625b82c2`)
- ApplicationSet revision — `services-git.yaml` template uses `${K3D_MANAGER_BRANCH}` variable; `acg-up` exports it from `git rev-parse --abbrev-ref HEAD` before calling `deploy_argocd`. No runtime kubectl patch needed. **When `k3d-manager-v1.2.0` merges to `main`, change template back to hardcoded `main`** and remove the `K3D_MANAGER_BRANCH` export from `acg-up`.

## v1.2.0 Open Items

- **ACG credential extraction misses visible sandbox** — SUBTREE SYNCED (2026-04-28). lib-acg PR #2 merged (`7cb7f64a`); Copilot comments addressed and resolved before merge. k3d-manager pulled `wilddog64/lib-acg@main` into `scripts/lib/acg/` via subtree (`88cb8bbc` merge commit, `a0b44c87` subtree squash). Focused verification passed: `node --check scripts/lib/acg/playwright/acg_credentials.js`, `shellcheck scripts/lib/acg/scripts/plugins/acg.sh scripts/lib/acg/scripts/lib/cdp.sh scripts/lib/acg/scripts/vars.sh`, `bats scripts/tests/lib/acg.bats`, `git diff --check`, and `./scripts/k3d-manager _agent_audit`. Live `make up` rerun remains pending. Spec: `docs/issues/2026-04-28-acg-credentials-cdp-context-miss.md`.
- **lib-acg main branch protection** — COMPLETE (2026-04-28). After user re-authenticated `gh`, `wilddog64/lib-acg` `main` protection was enabled: enforce admins, require 1 approving review, dismiss stale reviews, require conversation resolution, disallow force pushes/deletions. Verification returned `{"allow_deletions":false,"allow_force_pushes":false,"dismiss_stale_reviews":true,"enforce_admins":true,"required_approving_review_count":1,"required_conversation_resolution":true}`. Issue: `docs/issues/2026-04-28-lib-acg-main-branch-protection-auth-blocked.md`.
- **LDAP hardcoded test password** — OPEN. All LDAP users share static `test1234` baked into `bootstrap-basic-schema.ldif`. Fix: remove `userPassword` from LDIF; add `_ldap_rotate_user_passwords` to `ldap.sh` (generates unique pw per user, stores in Vault `secret/ldap/users/<user>`); also persist Dex bind PW into `argocd-secret` via `deploy_argocd`. Spec: `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`.
- **LDAP SSHA double-hash** — OPEN. Bitnami OpenLDAP re-hashes `{SSHA}` values in LDIF import — all bootstrapped users have unknown passwords. Workaround: set passwords via `ldappasswd`. Permanent fix: remove `userPassword` from LDIF (covered in parent bug spec). Spec: `docs/bugs/2026-04-26-ldap-ssha-rehash-password-unusable.md`. Current live cred: `chengkai.liang` / `ChangeMe123!` (ephemeral).
- **ArgoCD missing shopping-cart apps** — COMPLETE (2026-04-27). All 5 services deployed via ArgoCD ApplicationSet on ubuntu-k3s. Spec: `docs/bugs/2026-04-26-argocd-missing-shopping-cart-apps.md`.
- **shopping-cart data layer not auto-deployed** — COMPLETE (`d5cf80ed`). `deploy_shopping_cart_data()` added to `shopping_cart.sh`; wired into `bin/acg-up` Step 10b. Deploys PostgreSQL (orders/payment/products), Redis cart, RabbitMQ; aligns passwords to `CHANGE_ME`; creates `rabbitmq-credentials`; copies `redis-cart-secret` to shopping-cart-apps. Takes effect on next sandbox creation.
- **order-service all 5 pods Running** — COMPLETE (`20b0408e`). All shopping-cart pods now 1/1 Running. Kustomize patches applied: (1) `SPRING_JPA_HIBERNATE_DDL_AUTO=update`; (2) readiness+startup probes changed to TCP socket (bypass broken RabbitMQHealthIndicator NPE); (3) liveness probe patched to `/actuator/health`; (4) `SPRING_RABBITMQ_*` env vars for Spring AMQP. Permanent fix needed: update rabbitmq-client JAR + init SQL + SecurityConfig. Spec: `docs/bugs/2026-04-27-orders-init-sql-serial-vs-uuid.md`.
- **shopping-cart ImagePullBackOff — no ghcr-pull-secret** — COMPLETE (`4b0856cb`). `bin/acg-up` Step 5 now falls back to `gh auth token` when `GHCR_PAT` unset; all 5 `services/` kustomizations patched with `imagePullSecrets: [{name: ghcr-pull-secret}]`. Takes effect on next `make up`. Spec: `docs/bugs/2026-04-26-shopping-cart-imagepullbackoff-no-ghcr-pull-secret.md`.
- **ArgoCD SharedResourceWarning — duplicate Namespace/shopping-cart-apps** — OPEN. `shopping-cart-order` and `shopping-cart-product-catalog` both define `Namespace/shopping-cart-apps` in their kustomize base, causing `shopping-cart-product-catalog` to stay OutOfSync. Fix: remove `namespace.yaml` from both repos; add `services/shopping-cart-namespace/` in k3d-manager to own the namespace with merged labels (`istio-injection: enabled`). Spec: `docs/bugs/2026-04-26-argocd-shared-namespace-shopping-cart.md`.
- **ArgoCD port-forward on acg-up** — COMPLETE (`3c671667`). Step 4b added to `bin/acg-up`; cleanup in `bin/acg-down`. PID at `~/.local/share/k3d-manager/argocd-pf.pid`.
- **ArgoCD LDAP RBAC group mismatch** — PATCHED (ephemeral). `argocd-rbac-cm` mapped `cn=admins` (non-existent) to `role:admin`; patched to map `cn=it-devops` instead. Dex bind PW patched into `argocd-secret` ephemerally — both lost on Hub rebuild. Permanent fix is part of LDAP hardcoded password bug spec.

- **shopping-cart frontend login (Keycloak)** — OPEN. Frontend uses Keycloak OIDC at `localhost:8080` (baked into JS bundle). Keycloak not yet deployed. Fix: add `services/shopping-cart-identity/` kustomization; move ArgoCD to port 9090; Keycloak port-forward on 8080. Login: `testuser`/`testpassword`. Spec: `docs/plans/v1.2.0-deploy-keycloak.md`. Assign to Codex.
- **k3d-manager / shopping-cart tight coupling** — OPEN (v1.3.0). `services/`, `shopping_cart.sh`, and Step 10b in `acg-up` make k3d-manager app-specific. Fix: move overlays + bootstrap to `shopping-cart-infra/k8s-overlays/`; make ApplicationSet repoURL configurable. Spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.

- **ACG repo extraction** — IN PROGRESS (`docs/plans/v1.2.0-lib-acg-extraction.md`). P1–P5 COMPLETE. lib-acg PR #1 merged (`5c0e8e2d`). k3d-manager subtree synced from main (`84da5d5e`). enforce_admins restored on lib-acg.
- **ACG repo extraction P5** — COMPLETE. lib-acg PR #1 merged to main (`5c0e8e2d`). CI (shellcheck + node --check + yamllint) + pre-commit hook + Copilot findings fixed (`698e65f`). k3d-manager subtree at `scripts/lib/acg/` updated (`84da5d5e`).
- **GCP Sign-in-to-Chrome dialog** — COMPLETE (`ff44516` lib-acg, merged `5c0e8e2d`). `gcp_login.js` now dismisses Chrome's account-sync prompt via `context.on('page', ...)` handler. Spec: `docs/bugs/2026-04-25-gcp-login-chrome-signin-dialog.md`.
- **acg-extend Session Extended modal** — COMPLETE (`ac6525a` lib-acg, merged `5c0e8e2d`). Modal dismissed via Escape + fallback X-button + waitFor(hidden) guard. Spec: `docs/bugs/2026-04-26-acg-extend-session-extended-modal-blocks-button.md`.
- **sync-apps APP_CONTEXT hardwired** — COMPLETE. `make sync-apps CLUSTER_PROVIDER=k3s-gcp` was using `ubuntu-k3s` (AWS) context for pod status check instead of `ubuntu-gcp`. Fixed in Makefile `sync-apps` target. Spec: `docs/bugs/2026-04-25-sync-apps-app-context-hardwired-ubuntu-k3s.md`.
- **status APP_CONTEXT hardwired** — COMPLETE. Same root cause: `make status CLUSTER_PROVIDER=k3s-gcp` showed empty nodes from unreachable `ubuntu-k3s`. Fixed with same Makefile pattern. Spec: `docs/bugs/2026-04-25-status-app-context-hardwired-ubuntu-k3s.md`.
- **status ArgoCD CLI requires port-forward** — COMPLETE. Replaced `argocd app list` (requires active port-forward) with `kubectl get applications.argoproj.io -A --context INFRA_CONTEXT` (reads CRDs directly, no port-forward needed). Spec: `docs/bugs/2026-04-25-status-argocd-requires-port-forward.md`.
- **acg-down GCP _cluster_provider_call missing** — COMPLETE (`b8b72a67`). `bin/acg-down` k3s-gcp branch called `destroy_cluster` which routes through `_cluster_provider_call` (defined in `provider.sh`, never sourced). Fixed by calling `_provider_k3s_gcp_destroy_cluster` directly. Spec: `docs/bugs/2026-04-25-acg-down-gcp-cluster-provider-call-missing.md`.
- **acg-down GCP_PROJECT not set** — COMPLETE (`ca18e581`). `GCP_PROJECT` only exported in-memory by `gcp_get_credentials`; lost in new shell. Fixed by auto-detecting from `~/.local/share/k3d-manager/gcp-service-account.json` in `bin/acg-down`.
- **sync-apps missing Hub cluster preflight** — COMPLETE (`7fc1a6f4`). `bin/acg-sync-apps` gave cryptic kubectl error when Hub context missing. Added pre-flight check with clear message. Spec: `docs/bugs/2026-04-25-sync-apps-missing-hub-cluster-context.md`.
- **GCP instance creation not idempotent** — COMPLETE (`7582e290`). `_gcp_create_instance` failed on re-run if instance already existed. Added `instances describe` existence check matching `_gcp_ensure_firewall` pattern. Spec: `docs/bugs/2026-04-25-gcp-create-instance-not-idempotent.md`.
- **acg-up GCP skips Hub cluster** — COMPLETE (`f8f9d93b`). Early exit after Step 2 for k3s-gcp skipped Hub k3d cluster creation (Steps 3.5/3.6/4 are provider-agnostic). Fixed: only SSH tunnel (Step 3) gated behind non-GCP; Hub cluster + Vault + ArgoCD now created for GCP too. Steps 5–12 still AWS-only. Spec: `docs/bugs/2026-04-25-acg-up-gcp-skips-hub-cluster.md`.
- **status AWS Credentials section shown for GCP** — COMPLETE. `bin/acg-status` always ran `aws sts get-caller-identity` regardless of provider. Gated behind `CLUSTER_PROVIDER != k3s-gcp`; Makefile now passes `CLUSTER_PROVIDER` to the script. Spec: `docs/bugs/2026-04-25-status-shows-aws-creds-for-gcp.md`.
- **GCP OAuth fix (attempt 2)** — COMPLETE (`51afead` lib-acg, `df143452` k3d-manager). `--no-launch-browser` causes `EOFError` (gcloud waits for stdin verification code when run backgrounded). Fix: inject fake `open`/`xdg-open` into PATH so gcloud's browser-open call routes to CDP Chrome; localhost-redirect flow needs no code entry. Spec: `docs/bugs/2026-04-25-gcp-oauth-eof-stdin-crash.md`.
- **ACG repo extraction P4b bug** — COMPLETE (`c54de858`). Replaced source-only `acg.sh` / `gcp.sh` stubs with grep-compatible wrapper functions so the dispatcher can discover `acg_*` and `gcp_*` entry points.
- **ACG repo extraction P4** — COMPLETE (`99b2e143`). Wired the `wilddog64/lib-acg` subtree into `scripts/lib/acg/`, replaced `scripts/plugins/acg.sh` and `scripts/plugins/gcp.sh` with stubs, and updated `scripts/plugins/gemini.sh` to source CDP helpers from the subtree.
- **ACG repo extraction P3** — COMPLETE (`f1c577c`). Migrated acg/gcp/playwright files from k3d-manager to `wilddog64/lib-acg` and pushed `feat/phase3-migration`.
- **ACG repo extraction P1** — COMPLETE (`20df717c`). Renamed `antigravity.sh` → `gemini.sh`; all `antigravity_*` → `gemini_*`.
- **ACG repo extraction P2** — COMPLETE (`b253b9b`). `wilddog64/lib-acg` created; skeleton + lib-foundation subtree committed and pushed; branch protection set.
- **GCP E2E smoke test** — BLOCKED. `k3s-gcp` provisioning logic is in place; full `make up` end-to-end on a live GCP sandbox has not been verified. Blocked by CDP startup on Linux.
- **GCP single-node vs AWS 3-node** — OPEN. GCP provider creates 1 node; AWS creates 3 (server + 2 agents). Consistency gap, no stress testing done yet. Spec: `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`.
- **Whitespace enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files.
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Hub orchestration does not explicitly sequence ArgoCD install + bootstrap + app-cluster registration.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up/status` do not clearly separate Hub health from app-cluster health.
- **Vault Resilience Gap** — OPEN. Vault can still drift after Mac sleep; `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` tracks the remaining gap.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and historical docs should be reviewed for purge.
