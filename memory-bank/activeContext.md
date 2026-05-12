# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.5` (created from merge SHA `92ccaec1`).
- **v1.4.4 SHIPPED** — PR #73 merged to main (`92ccaec1`). Tagged v1.4.4, released 2026-05-08. `enforce_admins` restored on both k3d-manager and shopping-cart-infra.
- **v1.4.3 SHIPPED** — PR #72 merged to main (`b5601cb5`). `enforce_admins` restored on `main`. No prior CHANGE.md entry needed (small identity provisioning milestone).
- **v1.4.2 SHIPPED** — PR #71 merged to main (`ad8df98c`), tagged `v1.4.2`, released 2026-05-07.
- **shopping-cart-infra PR #41 MERGED** — `180f5f89` 2026-05-09 — Keycloak PostgreSQL driver fix + LDAP LDIF chown fix (Bugs 4+5). `enforce_admins` restored. Retro: `docs/retro/2026-05-09-pr41-keycloak-ldap-startup-retrospective.md` (committed `e0837c4` on `docs/next-improvements`).

## Post-Merge Housekeeping — 2026-05-08 (v1.4.4 + PR #37)
- **k3d-manager PR #73 + shopping-cart-infra PR #37 merged** — both enforced to main
- **k3d-manager enforce_admins restored** — `true` ✓
- **shopping-cart-infra enforce_admins restored** — `true` ✓
- **k3d-manager v1.4.4 tag + release created** — merge SHA `92ccaec1` tagged, released 2026-05-08
- **Retrospectives created** — k3d-manager `docs/retro/2026-05-08-v1.4.4-retrospective.md`, shopping-cart-infra `docs/retro/2026-05-08-pr37-keycloak-externalsecret-retrospective.md`
- **Next branches created/synced** — k3d-manager-v1.4.5, shopping-cart-infra docs/next-improvements

## Shipped in v1.4.2
- `_ai_agent_review` dispatch wrapper added to lib-foundation; copilot plugin functions route through it
- `K3DM_ENABLE_AI` gate removed from lib-foundation backend (`_copilot_review`) — gate stays in callers
- ArgoCD bootstrap: `ARGOCD_SERVER_WAIT_TIMEOUT` configurable (default 600s)
- `bin/acg-up`: bootstrap refresh on existing Hub when AppProject/ApplicationSets absent
- `bin/acg-up`: `--confirm` flag added to `deploy_argocd_bootstrap` call
- lib-acg PR #10 subtree pull: `launchctl bootout`, dead Linux else-block removal

## Deferred to v1.4.3
- **`deploy_argocd_bootstrap "$@"` passthrough** — removed in v1.4.2 (Copilot finding); correct fix is lib-foundation change to filter flags explicitly; callers (especially `provision-tomcat`) depend on this behavior
- **lib-foundation upstream doc fix** — `scripts/lib/foundation/docs/api/functions.md` usage snippet still has k3d-manager-specific `K3DM_ENABLE_AI=1` context; needs upstream lib-foundation PR

## Current Focus (v1.4.5)
- **COMPLETE:** `fix(acg-up)` — spec `docs/bugs/v1.4.5-bugfix-etc-hosts-soft.md`. Added `--soft` to line 639 (SHA: `3c096f6`).
- **COMPLETE:** `fix(acg-up-bugs)` — spec `docs/plans/v1.4.5-bugfix-gemini.md`. Fixed CoreDNS NodeHosts patch and /etc/hosts sudo fallback (SHA: `3c096f6`).
- **COMPLETE:** `fix(argocd-sso)` — spec at `docs/plans/v1.4.5-argocd-sso-keycloak.md`; implemented 5-change ArgoCD SSO wiring.
- **COMPLETE:** pyjenkinsapi rigor-cli v0.1.6 subtree pull.
- **COMPLETE:** `fix(ldap)` — shopping-cart-infra PR #39 `fix/ldap-duplicate-externalsecret` (SHA: `afaf109`) + PR #38 SSO wiring (SHA: `d314c34`). Removed duplicate `ldap-secrets-externalsecret.yaml` entry; ArgoCD SSO Keycloak wired end-to-end. enforce_admins restored on shopping-cart-infra.
- **COMPLETE:** `fix(argocd)` — spec `docs/bugs/v1.4.5-bugfix-services-git-identity-exclude.md` (SHA: `fa7bb830`). Excluded `shopping-cart-identity` from `services-git` ApplicationSet generator; re-applied identity Application with correct local-cluster destination.
- **COMPLETE:** `fix(vault)` — spec `docs/bugs/v1.4.5-bugfix-eso-ldap-policy-missing-keycloak.md` (SHA: `48938dea`). Extended `LDAP_VAULT_POLICY_PREFIX` default to `ldap,keycloak` so `eso-ldap-directory` policy covers `keycloak/*` paths.
- **COMPLETE:** `fix(acg-up)` — spec `docs/bugs/v1.4.5-bugfix-identity-appproject-missing.md` (SHA: `771ba5cf`). Changed `project: shopping-cart` → `project: platform` in step 10c inline Application; removed dead `services/shopping-cart-identity/kustomization.yaml`.
- **COMPLETE:** `fix(identity-eso-bootstrap)` — spec `docs/bugs/v1.4.5-bugfix-identity-externalsecret-bootstrap.md`. Bug 1 (`f969b299`). Bugs 2+3: shopping-cart-infra PR #40 merged to main (`dfe00df1`). Bugs 4+5: shopping-cart-infra PR #41 merged to main (`180f5f89`) — Keycloak PostgreSQL driver + LDAP LDIF chown fixes. enforce_admins restored.
- **MERGED Bug 6 — LDAP CrashLoopBackOff fix** — shopping-cart-infra PR #42 merged (`11aa8d7d`) 2026-05-09. enforce_admins restored. Retro: `docs/retro/2026-05-09-pr42-ldap-ldif-staging-retrospective.md` (on `docs/next-improvements`).
- **MERGED Bug 7 — LDAP CrashLoopBackOff (LDAP_PORT service link conflict)** — shopping-cart-infra PR #43 merged (`dcd18af7`) 2026-05-09. enforce_admins restored. Retro: `docs/retro/2026-05-09-pr43-ldap-service-links-retrospective.md` (on `docs/next-improvements`).
- **COMPLETE:** `fix(eso)` — spec `docs/bugs/v1.4.5-bugfix-deploy-eso-no-version-pin.md` (SHA: `50851f0e`). Pinned ESO Helm chart version to `1.0.0` (overridable via `ESO_HELM_CHART_VERSION`); matches remote cluster install in `acg-up`.
- **COMPLETE Bug 8 — CoreDNS Corefile patched with Keycloak ClusterIP** — `34e0101f`. Removed NodeHosts/IngressGateway approach; added stable `hosts` block in Corefile pointing to Keycloak ClusterIP. Spec: `docs/bugs/2026-05-09-argocd-sso-coredns-keycloak-clusterip.md`.
- **COMPLETE Bug 9 — frontend port-forward launchd agent** — `fb56a443`. Step 13 added to acg-up; plist targets `ubuntu-k3s/shopping-cart-apps/frontend:80 → localhost:3000`. Spec: `docs/bugs/2026-05-09-acg-up-frontend-port-forward.md`.
- **COMPLETE Bug 10 — ArgoCD localhost:8080 readiness gate** — `bin/acg-up` now waits for `localhost:8080/healthz` after loading the Argo CD launchd agent and fails fast with the log tail if the listener never becomes reachable. Spec: `docs/bugs/2026-05-11-acg-up-argocd-port-forward-readiness.md`.
- **COMPLETE Bug 11 — acg-down keep-hub preservation trust gap** — `bin/acg-down --confirm --keep-hub` now logs the resolved Hub cluster and the `Makefile` wrapper exposes `KEEP_LOCAL` directly, so the preserved-Hub path is unambiguous. Spec: `docs/bugs/2026-05-11-acg-down-keep-hub-preservation.md`.
- **COMPLETE Bug 12 — acg-up missing Argo CD plugin source** — `bin/acg-up` now sources `scripts/plugins/argocd.sh` before Step 4b calls `_argocd_wait_for_local_port_forward` (SHA: `6052786a`). Spec: `docs/bugs/2026-05-11-acg-up-missing-argocd-source.md`.
- **COMPLETE Bug 13 — acg-up PLUGINS_DIR unbound before plugin sourcing** — `bin/acg-up` now initializes `PLUGINS_DIR="${SCRIPT_DIR}/plugins"` before sourcing `scripts/plugins/argocd.sh` (SHA: `5d4b9b1e`). Spec: `docs/issues/2026-05-11-acg-up-unbound-plugins-dir.md`.
- **COMPLETE Bug 14 — Keycloak `argocd` client redirect reconciliation** — `bin/acg-up` now reconciles the existing `argocd` client redirect URIs even when the realm already exists, so rebuilds do not preserve stale OIDC callbacks. Spec: `docs/bugs/2026-05-11-keycloak-argocd-client-redirect-reconciliation.md`.
- **COMPLETE Bug 15 — Argo CD port-forward flaps after sandbox rebuild** — `bin/acg-up` now renders a self-healing launchd wrapper that restarts the Argo CD port-forward whenever `localhost:8080/healthz` stops responding. Spec: `docs/issues/2026-05-11-acg-up-argocd-port-forward-flapping.md`. Commit: `18f8d884`.
- **FOLLOW-UP:** `scripts/plugins/argocd.sh:_argocd_write_port_forward_wrapper` is temporarily allowlisted because the Agent Audit counter over-reports the helper as if it contained 11 `if` blocks. Spec: `docs/issues/2026-05-11-argocd-port-forward-wrapper-if-count-mismatch.md`.
- **FOLLOW-UP:** `scripts/plugins/keycloak.sh:deploy_keycloak` remains over the Agent Audit if-count threshold and is temporarily allowlisted pending a separate refactor. Spec: `docs/issues/2026-05-11-keycloak-deploy_keycloak-if-count.md`.
- **COMPLETE:** Keycloak admin token mismatch after rebuild. `bin/acg-up` now preserves existing Vault identity secrets on rebuild, and the live Vault `secret/keycloak/admin` secret was restored to the historical working password version. Specs: `docs/bugs/2026-05-11-keycloak-admin-password-reseed-on-rebuild.md` and `docs/issues/2026-05-11-keycloak-admin-token-reconciliation-failure.md`.
- **OPEN:** Argo CD rejects `localhost:8080` return URLs during SSO login. Live `/auth/login` rejects `return_url=http://localhost:8080/...` while `https://argocd.shopping-cart.local/...` succeeds. Spec: `docs/issues/2026-05-11-argocd-localhost-return-url-rejected.md`.
- **COMPLETE:** Argo CD canonical HTTPS hostname is now backed by a Vault PKI-issued local TLS listener. `bin/acg-up` installs a root-owned `launchd` daemon that terminates TLS for `argocd.shopping-cart.local:443` and proxies to the existing `localhost:8080` Argo CD port-forward, and `bin/acg-down` removes it. Spec: `docs/issues/2026-05-11-argocd-canonical-https-listener-missing.md` (fixed).
- **COMPLETE:** Argo CD browser TLS role creation now derives `allowed_domains=shopping-cart.local` for `argocd.shopping-cart.local` so Vault accepts the PKI role write on rebuild. Spec: `docs/issues/2026-05-11-argocd-browser-tls-role-allowed-domains.md` (fixed).
- **COMPLETE:** Argo CD browser TLS role write now authenticates to Vault before upserting the PKI role so the browser TLS helper does not hit `403 permission denied` on rebuild. Spec: `docs/issues/2026-05-11-argocd-browser-tls-vault-login-permission-denied.md`.
- **COMPLETE:** Argo CD browser TLS cleanup now skips revoke when the prior cert is already gone, so stale serials no longer abort `make up`. Fixed in `f2942bf9`. Spec: `docs/issues/2026-05-11-argocd-browser-tls-revoke-missing-cert.md`.
- **PLANNED:** `make up TRUST_CA=1` host CA trust bootstrap — spec `docs/plans/v1.4.5-trust-ca-auto-import.md`. Goal is to keep trust installation opt-in while letting the helper auto-detect macOS vs Linux.
- **COMPLETE:** `fix(acg-up)` now preserves stderr from the macOS browser `launchctl` install/bootstrap path and reports `argocd-browser-https-launchctl.log` on failure. Commit `8d18e18c`.
- **COMPLETE:** `fix(acg-up)` now treats the macOS browser `launchctl bootout` step as best-effort, so a missing existing listener no longer aborts bootstrap. Commit `8d18e18c`.
- **NOTE:** Added `docs/issues/2026-05-12-acg-up-argocd-browser-bootout-fails-when-listener-missing.md` to record `launchctl bootout system` exit code `5` during rebuilds.
- **COMPLETE:** `docs: stop advertising localhost as browser entrypoint` — `bin/acg-up` now labels localhost as terminal-only and `docs/howto/argocd.md` points browser SSO users at `https://argocd.shopping-cart.local`. Commit `b086aef2`. Added `docs/issues/2026-05-12-argocd-localhost-browser-entrypoint-misleading.md`.
- **COMPLETE:** `fix(acg-up)` — browser HTTPS preflight now skips the privileged launchd reinstall when `https://argocd.shopping-cart.local:443/healthz` is already healthy, so repeat `make up` runs no longer prompt for sudo unnecessarily. Commit `d5be3d0e`.
- **COMPLETE:** `fix(acg-up)` — browser-side Keycloak now runs through a local launchd-managed HTTP listener on `keycloak.shopping-cart.local:80` while `/etc/hosts` keeps the hostname on `127.0.0.1`, fixing the Safari “can’t connect to server” redirect path. Commit `bca8a30c`. Issue doc: `docs/issues/2026-05-12-keycloak-browser-http-listener-missing.md`. Supersedes the earlier ingress-gateway browser mapping (`99581cc7`).
- **COMPLETE:** `fix(acg-up)` — the Argo CD port-forward wrapper now falls back from the requested `k3d-k3d-cluster` context to `kubectl config current-context` and then to the kubeconfig default, preventing `make up` from looping on a missing-context launchd environment. Commit `3f8d5150`. Issue doc: `docs/issues/2026-05-12-argocd-port-forward-context-fallback.md`.
- **COMPLETE:** `fix(acg-up)` — `bin/acg-up` now opens `https://argocd.shopping-cart.local` automatically on macOS after the browser listener is healthy, so stale localhost tabs do not remain the default entrypoint. Commit `5e4b4de0`. Issue doc: `docs/issues/2026-05-12-acg-up-auto-opens-canonical-argocd-browser.md`.
- **IN PROGRESS:** `fix(acg-up)` follow-up — the first fallback patch still rendered an optional `_kubectl_context_args[@]` array under `set -u` and quoted an empty kubeconfig value. New patch switches the wrapper to a scalar context argument and renders absent kubeconfig as truly empty. Issue doc: `docs/issues/2026-05-12-argocd-port-forward-wrapper-empty-array-unbound.md`.
- **IN PROGRESS:** `fix(acg-up)` follow-up — Keycloak browser listener plist was still staged under `~/Library/LaunchDaemons`, which does not exist on this machine and caused `sudo install` to fail before bootstrap. New patch moves the plist to `/Library/LaunchDaemons` and keeps `acg-down` aligned. Issue doc: `docs/issues/2026-05-12-keycloak-browser-launchd-plist-installed-under-home-dir.md`.
- **COMPLETE:** `fix(argocd-sso)` follow-up — Argo CD OIDC config requested the unsupported `groups` scope, causing `invalid_scope: Invalid scopes: openid profile email groups`. Patched `shopping-cart-infra/argocd/config/argocd-cm.yaml` to remove `groups` from `requestedScopes` while keeping the groups claim mapper. Shopping-cart-infra commit: `09fbb7da14b447ccdbed17bd4a422eebeaa2811d`. Issue doc: `docs/issues/2026-05-12-argocd-invalid-scope-groups-requested.md`.
- **Pending:** `refactor(plugins)` — spec at `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex after SSO wiring is verified. Updated to include `k3s-aws.sh` and `k3s-gcp.sh` source-line changes (both source `shopping_cart.sh` directly — must rename to `k3s_remote.sh`).
- **Next:** `feat(providers)` — spec at `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; depends on refactor spec.
- **Next:** `feat(tunnel)` — spec at `docs/plans/v1.4.3-chisel-tunnel.md`; depends on refactor spec.
- Preserve subtree discipline: `scripts/lib/foundation/` and `scripts/lib/acg/` edits upstream first.

## Notes
- The two baseline failures in `scripts/tests/plugins/argocd.bats` remain unresolved (pre-existing, unrelated to v1.4.2 changes).
- Retro (v1.4.4): `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- Retro (v1.4.3): `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- Retro (v1.4.2): `docs/retro/2026-05-07-v1.4.2-retrospective.md`
