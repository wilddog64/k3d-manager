# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- v1.1.0 — Unified ACG automation AWS + GCP (PR #65, `e013d23b`, 2026-04-25)
- v1.0.6 — AWS SSM support for `k3s-aws` (PR #64, `a54e152f`, 2026-04-11)
- v1.0.5 — antigravity decoupling + LDAP Vault KV seeding + Copilot fix-up (PR #62/#63, `71c88b05`, 2026-04-11)
- v1.0.4 — acg-up random passwords, acg_extend hardening (PR #61, `bc9028fb`, 2026-04-10)

Pre-v1.0.4 detail removed from this file; see `git log --tags` and `docs/retro/`.

---

## v1.2.0 Track (branch: `k3d-manager-v1.2.0`)

- [ ] **ACG repo extraction** — IN PROGRESS. Plan: `docs/plans/v1.2.0-lib-acg-extraction.md`. P1+P2+P3+P4+P4b done (`20df717c`, `b253b9b`, `f1c577c`, `99b2e143`, `c54de858`); residual ArgoCD help/login verification gaps are tracked in `docs/issues/2026-04-25-phase4-verification-argocd-preexisting-failures.md`.
- [x] **ACG repo extraction P4b** — COMPLETE (`c54de858`). Replaced the source-only `acg.sh` and `gcp.sh` stubs with grep-compatible wrapper functions and preserved the existing test harness behavior.
- [x] **ACG repo extraction P4** — COMPLETE (`99b2e143`). Wired `scripts/lib/acg/` subtree into k3d-manager, replaced `acg.sh` and `gcp.sh` with stubs, and moved CDP helper sourcing into `gemini.sh`.
- [x] **ACG repo extraction P3** — COMPLETE (`f1c577c`). Migrated `acg.sh`, `gcp.sh`, `vars.sh`, `acg-cluster.yaml`, and the Playwright scripts into `wilddog64/lib-acg` and pushed `feat/phase3-migration`.
- [x] **ACG repo extraction P1** — COMPLETE (`20df717c`). Renamed `antigravity.sh` → `gemini.sh`; all `antigravity_*` → `gemini_*`.
- [x] **ACG repo extraction P2** — COMPLETE (`b253b9b`). `wilddog64/lib-acg` repo created; skeleton + lib-foundation subtree on `main`; `enforce_admins` branch protection set.
- [ ] **GCP E2E smoke test** — BLOCKED. GCP cluster provisioning is PARTIAL; full `make up` end-to-end on a live GCP sandbox not yet verified.

---

## v1.1.0 Track (branch: `k3d-manager-v1.1.0` — SHIPPED)

- **Baseline** — branched off `main` (`279db18c`); AWS path verified 2026-04-19.
- [x] **Shared playwright vars** — COMPLETE (`3de58f4d`)
- [x] **Robot engine unification** — COMPLETE (`a986d5bb`)
- [x] **GCP identity bridge** — COMPLETE (`9686e5c3`). Credential extraction, identity bridge, OAuth automation verified.
- [x] **Documentation alignment** — COMPLETE (`7f3bd0a6`)
- [x] **lib-foundation v0.3.17** — COMPLETE (PR #23 merged). `_agent_lint` glob expanded to `*.sh *.js *.md`.
- [ ] **GCP cluster provisioning** — **PARTIAL**. CLUSTER_NAME default fix committed in `3a3806aa`; live smoke test is still blocked by Chrome CDP startup (`docs/issues/2026-04-21-cluster-name-smoke-test-blocked-by-cdp.md`).
- [ ] **E2E verify** — **BLOCKED**. Needs a clean `make up` run past Chrome CDP startup.
- [x] **CDP Linux headless + profile unification** — **COMPLETE** (`1ab14ebf`). Implemented `docs/bugs/2026-04-21-cdp-linux-headless-launch-failure.md`; D1/D2/D3 passed locally and D4 live sandbox validation remains pending user execution.
- [ ] **ACG repo extraction** — **PLANNED** (`8639592c`). Plan: `docs/plans/v1.1.0-acg-extraction-repo-split.md`. Extract browser/CDP/Playwright automation into its own repo to stop polluting `k3d-manager` stability.

---

- [ ] **Safe Identity Reset** — OPEN. Plan `docs/plans/v1.1.0-recovery-phase-b-safe-identity-reset.md`; implement domain-isolated cookie wipe (.google.com only) and trap escape for fresh login.
## Agent Rigor CLI Improvements

- [ ] **Whitespace Enforcement** — OPEN. Add trailing-whitespace detection to `_agent_lint` for `.js`/`.sh` files.

---

## Known Bugs / Gaps
- [x] **ACG credential extraction misses visible sandbox** — SUBTREE SYNCED from lib-acg PR #2 (`https://github.com/wilddog64/lib-acg/pull/2`). PR merged to lib-acg `main` as `7cb7f64a`; k3d-manager pulled the subtree into `scripts/lib/acg/` (`88cb8bbc` merge commit, `a0b44c87` subtree squash). Focused verification passed: `node --check`, `shellcheck`, `bats scripts/tests/lib/acg.bats`, `git diff --check`, and `_agent_audit`. Temporary live validation with the same patch also passed: `acg_get_credentials` and `aws sts get-caller-identity`. Full live `make up` rerun remains pending. Spec: `docs/issues/2026-04-28-acg-credentials-cdp-context-miss.md`.
- [x] **lib-acg main branch protection** — COMPLETE. After user re-authenticated `gh`, `wilddog64/lib-acg` `main` protection was enabled: enforce admins, require 1 approving review, dismiss stale reviews, require conversation resolution, disallow force pushes/deletions. Issue: `docs/issues/2026-04-28-lib-acg-main-branch-protection-auth-blocked.md`.
- [x] **acg-up sealed Vault health misclassified** — FIXED. Live `make up` failed at Step 4 with "Vault not responding"; actual state was sealed `secrets/vault-0`. `bin/acg-up` now preserves Vault health JSON for sealed non-2xx responses, runs `deploy_vault --re-unseal`, and rechecks before continuing. Issue: `docs/issues/2026-04-28-acg-up-vault-sealed-health-misclassified.md`.
- [ ] **vault-bridge pod-origin traffic empty reply** — OPEN. Same-port reverse tunnel reset has a partial fix (`remote 8200 -> local 18200`), and host-origin remote Vault health returns HTTP 200. Remaining blocker: pod-origin traffic to `vault-bridge.secrets.svc.cluster.local:8201` returns empty reply, so `ClusterSecretStore/vault-backend` stays `Ready=False`. Issues: `docs/issues/2026-04-28-vault-bridge-same-port-reverse-tunnel-reset.md`, `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
- [ ] **shopping-cart ImagePullBackOff — GHCR token scope mismatch** — OPEN (2026-04-29). The `ghcr-pull-secret` exists in `shopping-cart-apps`, but live pods still fail with `403 Forbidden` from `ghcr.io` because the current GitHub CLI token does not have `read:packages`. Issue: `docs/issues/2026-04-29-gh-auth-token-insufficient-scope-for-ghcr.md`. Live fix path: refresh `gh` with `read:packages`, recreate the Vault-stored PAT secret, and restart the shopping-cart deployments.
- [x] **shopping-cart data layer not auto-deployed on sandbox creation** — COMPLETE (`d5cf80ed`). `deploy_shopping_cart_data()` in `shopping_cart.sh`; wired into `acg-up` Step 10b. Aligns all passwords to `CHANGE_ME`, creates RabbitMQ + Redis secrets.
- [x] **order-service kustomize workarounds** — COMPLETE (`20b0408e`). TCP socket probes (readiness+startup), DDL-auto, Spring AMQP credentials all patched. All 5 shopping-cart pods now 1/1 Running.
- [ ] **Sandbox rebuild clean (Option 2)** — BLOCKED. `make down` → `make up` → `make sync-apps` does NOT produce all-healthy ArgoCD yet. Three cleanup gates required (in order): (1) Fix 1 merges → remove `ddl-auto=update` patch; (2) Fix 2 + JAR fix both land → remove TCP probe patches; (3) Fix 3 merges → (no cleanup); (4) all three done → merge `k3d-manager-v1.2.0` to `main`. Decision: no ApplicationSet branch-pin hack — permanent fixes first. See `activeContext.md` "Sandbox Rebuild Readiness" section.
- [ ] **orders init SQL SERIAL vs UUID + SecurityConfig probe gap** — OPEN. Spec: `docs/bugs/2026-04-27-orders-init-sql-serial-vs-uuid.md`. Needs PRs in `shopping-cart-infra` (init SQL) and `shopping-cart-order` (SecurityConfig). Codex spec: `docs/plans/v1.2.0-fix-orders-init-sql-and-security-config.md`. Assign to Codex.
- [ ] **ArgoCD SharedResourceWarning — duplicate Namespace/shopping-cart-apps** — OPEN. `shopping-cart-order` + `shopping-cart-product-catalog` both define `Namespace/shopping-cart-apps`; `product-catalog` stays OutOfSync. Fix: remove `namespace.yaml` from both repos, add `services/shopping-cart-namespace/` in k3d-manager. Spec: `docs/bugs/2026-04-26-argocd-shared-namespace-shopping-cart.md`. Repos: `shopping-cart-order`, `shopping-cart-product-catalog`, `k3d-manager`.
- [ ] **shopping-cart frontend login (Keycloak)** — OPEN. Deploy Keycloak to `identity` ns; move ArgoCD to 9090; Keycloak port-forward on 8080 (frontend hardcoded). Realm `shopping-cart` + client `frontend` + user `testuser/testpassword` auto-imported via realm.json. Spec: `docs/plans/v1.2.0-deploy-keycloak.md`. Assign to Codex.
- [ ] **k3d-manager / shopping-cart tight coupling** — OPEN (v1.3.0). `services/`, `shopping_cart.sh`, Step 10b in `acg-up` make k3d-manager app-specific. Fix: move overlays + data-layer bootstrap to `shopping-cart-infra/k8s-overlays/`; make ApplicationSet repoURL/branch configurable via env vars. Spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.
- [ ] **Orchestration Fragility** — OPEN. Issue `docs/bugs/2026-04-23-infra-orchestration-fragility.md`; the local Hub flow does not explicitly unify ArgoCD install, bootstrap, app-cluster registration, and operator access setup.
- [ ] **Dual-cluster Status UX** — OPEN. Issue `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`; `make up` and `make status` do not clearly separate local Hub health, remote app-cluster health, tunnel endpoint state, and local ArgoCD access setup.
- [ ] **ACG Extraction Boundary** — OPEN. Issue `docs/bugs/2026-04-23-acg-extraction-boundary-gemini-coupling.md`; the `acg_*` workflow still keeps Gemini/browser automation coupled to `k3d-manager` instead of an extracted ACG subsystem.
- [x] **Teardown State Drift** — COMPLETE (`3fd6f4d6`). Implemented the spec in `docs/bugs/2026-04-23-acg-down-full-teardown-spec.md`; `acg-down` now tears down the local Hub by default and preserves it only with `--keep-hub`.
- [x] **acg-sync-apps + acg-status dual-cluster** — COMPLETE (`a5422141`). Implemented the spec in `docs/bugs/2026-04-23-acg-sync-apps-and-acg-status-dual-cluster.md`; `acg-sync-apps` now polls port-forward readiness and uses configurable `ARGOCD_APP`, and `acg-status` now reports Hub cluster nodes + pods.
- [ ] **Repo Retention Cleanup** — OPEN. Issue `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`; `scratch/` and historical docs should be reviewed for purge/archive based on active references.
- [x] **Vault Preflight After Sleep** — COMPLETE (`e577579e`). Spec `docs/bugs/2026-04-23-acg-up-vault-state-preflight-gap-after-mac-sleep.md`; `bin/acg-up` now checks Hub reachability before Vault PF startup and exits early if Vault is sealed or unreachable.
- [x] **acg-extend isPanelOpen false positive** — COMPLETE (`79b87e36`). Spec `docs/bugs/2026-04-24-acg-extend-ispanelopen-false-positive.md`; `isPanelOpen` now follows `clicked`, and Open Sandbox targets the running sandbox card instead of `.first()`.
- [x] **acg-sync-apps app not found** — COMPLETE (`eaaf9a9e`). Spec `docs/bugs/2026-04-24-acg-sync-apps-argocd-app-not-found.md`; missing-app errors now list available ArgoCD app names.
- [x] **acg-sync-apps port-forward hidden failure** — COMPLETE (`3bd96955`). Spec `docs/bugs/2026-04-24-acg-sync-apps-port-forward-hidden-failure.md`; `bin/acg-sync-apps` now captures the background `kubectl port-forward` stderr, fails fast when the process exits early, and prints the log tail on readiness timeout.
- [x] **acg-sync-apps local port 8080 collision** — COMPLETE (`3a1e2554`). Spec `docs/bugs/2026-04-24-acg-sync-apps-local-port-8080-collision.md`; `bin/acg-sync-apps` now rejects a pre-existing local listener on 8080 before starting the ArgoCD port-forward.
- [x] **acg-sync-apps port-forward reuse** — COMPLETE (`f18c8ec7`). Spec `docs/bugs/2026-04-24-acg-sync-apps-port-forward-reuse.md`; `bin/acg-sync-apps` now persists managed ArgoCD port-forward metadata, reuses its own active listener, and replaces foreign listeners on 8080 automatically.
- [x] **acg-sync-apps state dir not writable** — COMPLETE (`890ba2a6`). Spec `docs/bugs/2026-04-24-acg-sync-apps-state-dir-not-writable.md`; `bin/acg-sync-apps` now defaults to a writable temp-backed state directory and creates it before the port-forward starts.
- [x] **acg-sync-apps error log preserved in scratch** — COMPLETE (`2e766a43`). Spec `docs/bugs/2026-04-24-acg-sync-apps-error-log-preserved-in-scratch.md`; `bin/acg-sync-apps` now writes the failure log under `./scratch/logs/` and keeps it on non-zero exit while still cleaning up stale state metadata.
- [x] **acg-sync-apps ArgoCD login still interactive** — COMPLETE (`c3a2f146`). Spec `docs/bugs/2026-04-24-acg-sync-apps-argocd-login-noninteractive.md`; `bin/acg-sync-apps` now uses the same non-interactive ArgoCD login flags as `_argocd_ensure_logged_in()`, including `--plaintext --skip-test-tls --grpc-web </dev/null`.
- [x] **acg-sync-apps https vs http readiness** — COMPLETE (`0896d9ec`). Spec `docs/bugs/2026-04-24-acg-sync-apps-https-vs-http-readiness-check.md`; `bin/acg-sync-apps` now uses `http://localhost:<port>/healthz` for both the managed port-forward reuse check and the startup readiness loop, matching ArgoCD's insecure HTTP mode.
- [x] **acg-sync-apps default app wrong** — COMPLETE (`b83d5596`). Spec `docs/bugs/2026-04-24-acg-sync-apps-argocd-app-default-wrong.md`; `bin/acg-sync-apps` now defaults `ARGOCD_APP` to `rollout-demo-default`, which is the canonical app generated after bootstrap.
- [x] **acg-down provider dispatch** — COMPLETE (`706e0ba2`). Spec `docs/bugs/2026-04-24-acg-down-provider-dispatch-gcp-teardown.md`; `bin/acg-down` now dispatches remote teardown by `CLUSTER_PROVIDER` and calls `destroy_cluster --confirm` for GCP.
- [ ] **acg-credentials Open Sandbox provider-blind** — DEFERRED to lib-acg. Spec `docs/bugs/2026-04-24-acg-credentials-open-sandbox-provider-blind.md`; will be fixed in provider-isolated files during lib-acg extraction.
- [x] **acg-down expired credentials abort** — COMPLETE (`ae2fca66`, follow-up `07ca18a6`). Spec `docs/bugs/2026-04-24-acg-down-expired-credentials-abort.md`; local Hub + Vault PF cleanup remains non-fatal on expired AWS credentials, and the follow-up fix now suppresses the prior ERROR noise.
- [x] **acg-down credential check noise** — COMPLETE (`07ca18a6`). Spec `docs/bugs/2026-04-24-acg-down-credential-check-noise.md`; `bin/acg-down` now pre-checks AWS creds silently before calling `acg_teardown` and skips with a single clean INFO when invalid.
- [x] **acg-up Hub cluster auto-create** — COMPLETE (`73382eb2`). Spec `docs/bugs/2026-04-24-acg-up-hub-cluster-not-created.md`; Step 3.5 now auto-creates the local Hub cluster when missing and still uses `kubectl get nodes` as the true OrbStack-broken-state guard.
- [x] **k3d-provider EXIT trap leak** — COMPLETE (`258de0d1`). Spec `docs/bugs/2026-04-24-k3d-provider-exit-trap-leak.md`; `_provider_k3d_configure_istio` now uses `RETURN` for temp file cleanup, matching `_provider_k3d_create_cluster` and preventing EXIT trap leakage into inline callers.
- [x] **k3d-provider RETURN trap scope** — COMPLETE (`e6a9ec91`). Spec `docs/bugs/2026-04-24-k3d-provider-return-trap-scope.md`; both k3d provider RETURN trap handlers now self-clear on first fire, preventing re-fire in parent functions with out-of-scope local variables.
- [ ] **Vault Resilience Gap** — BLOCKED. `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` now tracks the remaining gap accurately: cached unseal replacement and some automatic recovery already exist, but local Vault can still land in drifted states that are not fully reconciled before seeding.
- [x] **GCP Login Linux Headless OAuth** — COMPLETE (`927cb452`). Spec `docs/bugs/2026-04-23-gcp-login-linux-headless-oauth-url-capture.md`; `gcp.sh` captures OAuth URL from gcloud on Linux; `gcp_login.js` navigates directly via `GCP_AUTH_URL`. Live test pending.
- [x] **GCP Provisioning Error 1** — COMPLETE (`346c3df2`). Bug `docs/bugs/2026-04-23-gcp-node-readiness-timeout-bash-pitfall.md`; `(( attempts++ ))` → `(( ++attempts ))` at lines 109 + 211 of `k3s-gcp.sh`. Spec complete; committed 2026-04-23.
- [x] **Start Sandbox Disabled Timeout** — COMPLETE (`13d398ab`). Bug `docs/bugs/2026-04-23-acg-start-sandbox-button-disabled-timeout.md`; add `isEnabled()` guard before `startButton.click()` in `acg_credentials.js`; committed 2026-04-23.
- [x] **acg-up Hub cluster bootstrap** — COMPLETE (`c59f2c3a`). Bug `docs/bugs/2026-04-24-acg-up-hub-cluster-bootstrap.md`; `bin/acg-up` now tracks fresh Hub creation in Step 3.5 and runs Step 3.6 to bootstrap Vault + ArgoCD before the Vault port-forward path.
- [x] **acg-up Hub bootstrap safety gate** — COMPLETE (`8b43122f`). Bug `docs/bugs/2026-04-24-acg-up-hub-bootstrap-safety-gate.md`; Step 3.6 now passes `--confirm` to both dispatcher calls so Hub bootstrap clears the deploy safety gate.
- [x] **acg-up Hub bootstrap LDAP missing** — COMPLETE (`c650f032`). Bug `docs/bugs/2026-04-24-acg-up-hub-bootstrap-ldap-missing.md`; Step 3.6 now deploys LDAP through the dispatcher before ArgoCD, preventing the direct `deploy_ldap --confirm` failure path.
- [x] **argocd LDAP namespace hardcoded** — COMPLETE (`032bfadb`). Bug `docs/bugs/2026-04-24-argocd-ldap-namespace-hardcoded.md`; `deploy_argocd` now checks `ns "${LDAP_NAMESPACE:-ldap}"`, matching LDAP's configured namespace and avoiding the direct `deploy_ldap --confirm` failure path when LDAP already exists in `identity`.
- [x] **argocd LDAP vars not sourced** — COMPLETE (`1c3ead28`). Bug `docs/bugs/2026-04-24-argocd-ldap-vars-not-sourced.md`; `argocd.sh` now sources LDAP vars before dependency checks and uses `_kubectl --no-exit` for Vault/LDAP namespace probes. Live `deploy_argocd --confirm` exited 0. Current shellcheck/BATS still show pre-existing ArgoCD verification gaps tracked in `docs/issues/2026-04-24-argocd-verification-preexisting-failures.md`; CLI login EOF follow-up is tracked in `docs/issues/2026-04-24-argocd-cli-login-eof-during-bootstrap.md`.
- [x] **ESO webhook readiness race** — COMPLETE (`e7b06b2b`). Bug `docs/bugs/2026-04-24-eso-webhook-readiness-race.md`; `deploy_eso` now waits for all ESO controller/webhook/cert-controller deployments plus the webhook endpoint before returning, including the already-installed fast path. Focused ESO checks and live `deploy_eso --confirm` pass; full suite still has the known ArgoCD help-test failure.
- [x] **ArgoCD CLI login plaintext prompt** — COMPLETE (`fdbef8c4`). Bug `docs/bugs/2026-04-24-argocd-cli-login-plaintext-prompt.md`; `_argocd_ensure_logged_in()` now uses `--plaintext --skip-test-tls` and closes stdin, which removes the TLS confirmation prompt and lets `deploy_argocd` complete bootstrap.
- [x] **Google Identity Drift** — **COMPLETE** (`6ae2a6c3`). Implemented clean-slate login pattern (logout + explicit credentials entry).

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| GCP node readiness timeout | COMPLETE | Extended to 300s (`c65f0c90`). |
| GCP latch-on selector gap | COMPLETE | `gcp_login.js` hardened with "Agree and continue" + "Confirm" (`e45d9a04`). |
| Google identity drift | COMPLETE | `6ae2a6c3` — implemented clean-slate login pattern. |
| Polite tab selection | COMPLETE | Hardened `acg_credentials.js` to avoid hijacking active page (RCA 1 fix: `131dca33`). |
| Gemini CLI Throttling | OPEN | Policy-driven traffic prioritization may cause capacity errors. |
| macOS CDP Direct Launch | OPEN | `open -a` can reuse an existing Chrome instance and fail to apply CDP flags; bug doc is now scoped as a problem statement, not an implementation script. |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer bugs** live in their repos as GitHub Issues:

- `wilddog64/shopping-cart-order#26` — RabbitMQHealthIndicator NPE on stale `:latest` image; fix in `rabbitmq-client 1.0.1`, remediation is rebuild + rollout.

---

## Roadmap

- **v1.1.0** — Unified ACG automation AWS + GCP (IN PROGRESS on `k3d-manager-v1.1.0`; extraction plan now defined for browser automation)
- **v1.2.0** — k3dm-mcp (gate: v1.1.0 AWS+GCP fully provisioning; two cloud backends)
- **v1.3.0** — Home lab on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope
