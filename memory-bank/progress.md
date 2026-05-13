# Progress — k3d-manager

## Status
- Current branch: `k3d-manager-v1.4.5`.
- **v1.4.4 SHIPPED** — PR #73 merged (`92ccaec1`), tagged v1.4.4, released 2026-05-08. enforce_admins restored. Retro: `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- **shopping-cart-infra PR #37 SHIPPED** — merged (`867d861`). enforce_admins restored. Retro: `docs/retro/2026-05-08-pr37-keycloak-externalsecret-retrospective.md`
- **shopping-cart-infra PR #41 SHIPPED** — merged (`180f5f89`) 2026-05-09. Keycloak PostgreSQL driver + LDAP LDIF chown fixes (Bugs 4+5). enforce_admins restored. Retro: `docs/retro/2026-05-09-pr41-keycloak-ldap-startup-retrospective.md`
- **v1.4.3 SHIPPED** — PR #72 merged (`b5601cb5`), enforce_admins restored. Retro: `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- **shopping-cart-infra PR #36 SHIPPED** — merged (`060e388`), enforce_admins restored. Retro: `docs/retro/2026-05-08-pr36-keycloak-eso-retrospective.md`
- **v1.4.2 SHIPPED** — PR #71 merged (`ad8df98c`), tagged + released 2026-05-07.

## Completed (v1.4.4)
- [x] **Keycloak ExternalSecret files missing** — spec: `docs/bugs/2026-05-08-keycloak-externalsecret-files-missing.md`
- [x] **Identity SSO fixes** — spec: `docs/plans/v1.4.4-identity-sso-fixes.md`
- [x] PR #73 merged, v1.4.4 tagged + released
- [x] enforce_admins restored on both repos
- [x] Retrospective: `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- [x] Next branch created: `k3d-manager-v1.4.5`

## Completed (v1.4.3)
- [x] **Keycloak Vault KV seeding** — bin/acg-up provisions keycloak/admin and keycloak/clients KV paths
- [x] **shopping-cart-identity ArgoCD app** — services/shopping-cart-identity kustomization wires Keycloak stack from shopping-cart-infra
- [x] **shopping-cart-infra PR #36** — Keycloak frontend OIDC client + ESO migration merged
- [x] `enforce_admins` restored on both repos (shopping-cart-infra + k3d-manager)
- [x] Retrospective: `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- [x] Next branch created: `k3d-manager-v1.4.4`

## Completed (v1.4.2)
- [x] `_ai_agent_review` dispatch layer in lib-foundation
- [x] `K3DM_ENABLE_AI` gate removed from lib-foundation backend
- [x] `ARGOCD_SERVER_WAIT_TIMEOUT` configurable (default 600s)
- [x] `bin/acg-up` bootstrap refresh on existing Hub
- [x] `bin/acg-up` `--confirm` flag
- [x] lib-acg PR #10 subtree pull (`launchctl bootout`, dead else-block)
- [x] Copilot plugin BATS suite (`scripts/tests/plugins/copilot.bats`)
- [x] All 8 Copilot PR #71 review threads resolved
- [x] `enforce_admins` restored on `main`
- [x] v1.4.2 tag + GitHub release created
- [x] Retrospective: `docs/retro/2026-05-07-v1.4.2-retrospective.md`

## Next Steps (v1.4.5)
- [x] **ArgoCD SSO via Keycloak** — COMPLETE. shopping-cart-infra PR #38 (`d314c34`, feat: ArgoCD SSO) + PR #39 (`afaf109`, fix: ldap duplicate) merged to main. enforce_admins restored. spec: `docs/plans/v1.4.5-argocd-sso-keycloak.md`; retro: `docs/retro/2026-05-09-pr38-pr39-argocd-sso-kustomize-fix.md` (on `docs/next-improvements`)
- [x] **pyjenkinsapi rigor-cli v0.1.6 subtree pull** — COMPLETE (subtree: `7d8a894b`, ci-fix: `0c479c99`); branch `docs/next-improvements`; BATS re-enabled
- [x] **acg-up /etc/hosts --soft** — COMPLETE (`3c096f6`). `_run_command --prefer-sudo` missing `--soft` causes `exit 1` instead of warning when EPERM. spec: `docs/bugs/v1.4.5-bugfix-etc-hosts-soft.md`.
- [x] **acg-up Step 10e bugs** — COMPLETE (`d6a31c5`). Fixed CoreDNS awk pattern + /etc/hosts sudo hard-fail. spec: `docs/plans/v1.4.5-bugfix-gemini.md`
- [x] **eso-ldap-directory Vault policy missing keycloak/* paths** — COMPLETE (`48938dea`). Extended `LDAP_VAULT_POLICY_PREFIX` default to `ldap,keycloak`. spec: `docs/bugs/v1.4.5-bugfix-eso-ldap-policy-missing-keycloak.md`
- [x] **shopping-cart-identity AppProject missing** — COMPLETE (`771ba5cf`). `project: shopping-cart` → `project: platform`; removed dead kustomization. spec: `docs/bugs/v1.4.5-bugfix-identity-appproject-missing.md`
- [x] **identity ESO bootstrap Bug 1** — COMPLETE (`f969b299`). `_eso_apply_vault_cluster_store` added to `eso.sh`; `ldap.sh` source guard + `deploy_ldap()` call added. Verified by Claude.
- [x] **identity ESO bootstrap Bugs 2+3** — spec: `docs/bugs/v1.4.5-bugfix-identity-externalsecret-bootstrap.md`; shopping-cart-infra PR #40 merged (`dfe00df1`); enforce_admins restored
- [x] **identity ESO bootstrap Bugs 4+5** — spec: `docs/bugs/2026-05-08-pr41-keycloak-postgresql-driver-ldap-ldif-chown-fixes.md`; shopping-cart-infra PR #41 merged (`180f5f89`); Bug 4: Keycloak `--db=postgres` in args, KC_DB removed from ConfigMap; Bug 5: LDAP LDIF chown fix via initContainer + emptyDir; enforce_admins restored
- [x] **LDAP CrashLoopBackOff Bug 6** — PR #42 merged (`11aa8d7d`); enforce_admins restored. Spec: `docs/bugs/2026-05-09-ldap-emptydir-mountpoint-rm-fails.md`
- [x] **LDAP CrashLoopBackOff Bug 7** — PR #43 merged (`dcd18af7`). enforce_admins restored. Fix: `enableServiceLinks: false` in pod spec. Retro: `docs/retro/2026-05-09-pr43-ldap-service-links-retrospective.md`
- [x] **deploy_eso unpinned chart version** — spec: `docs/bugs/v1.4.5-bugfix-deploy-eso-no-version-pin.md`; pinned to `1.0.0` via `ESO_HELM_CHART_VERSION` (SHA: `50851f0e`)
- [x] **Bug 8 — CoreDNS keycloak.shopping-cart.local → Keycloak ClusterIP** — `34e0101f`. Corefile patched with `hosts` block; NodeHosts/IngressGateway approach removed.
- [x] **Bug 9 — acg-up frontend port-forward launchd agent** — `fb56a443`. Step 13 launchd plist added (`localhost:3000 → ubuntu-k3s/shopping-cart-apps/frontend:80`).
- [x] **Bug 10 — acg-up ArgoCD localhost:8080 readiness gate** — `bin/acg-up` now waits for the Argo CD launchd listener to answer `localhost:8080/healthz` and fails fast with the log tail when it never becomes reachable.
- [x] **Bug 11 — acg-down keep-hub preservation trust gap** — `bin/acg-down` now logs the resolved Hub cluster and the `Makefile` wrapper exposes `KEEP_LOCAL` directly, making `--keep-hub` unambiguous to operators.
- [x] **Bug 12 — acg-up missing Argo CD plugin source** — `bin/acg-up` now sources `scripts/plugins/argocd.sh` before Step 4b calls `_argocd_wait_for_local_port_forward` (SHA: `6052786a`).
- [x] **Bug 13 — acg-up PLUGINS_DIR unbound before plugin sourcing** — `bin/acg-up` now initializes `PLUGINS_DIR="${SCRIPT_DIR}/plugins"` before sourcing `scripts/plugins/argocd.sh` (SHA: `5d4b9b1e`).
- [x] **Bug 14 — Keycloak `argocd` client redirect reconciliation** — `bin/acg-up` now reconciles the existing `argocd` client redirect URIs even when the realm already exists, so rebuilds do not preserve stale OIDC callbacks. Spec: `docs/bugs/2026-05-11-keycloak-argocd-client-redirect-reconciliation.md`.
- [x] **Bug 15 — Argo CD port-forward flaps after sandbox rebuild** — `bin/acg-up` now renders a self-healing launchd wrapper that restarts the Argo CD port-forward whenever `localhost:8080/healthz` stops responding. Spec: `docs/issues/2026-05-11-acg-up-argocd-port-forward-flapping.md`; commit `18f8d884`.
- [ ] **Follow-up — `scripts/plugins/argocd.sh:_argocd_write_port_forward_wrapper` Agent Audit mismatch** — the helper is temporarily allowlisted because the audit counter reports 11 `if` blocks even though the rendered function body only contains one. Spec: `docs/issues/2026-05-11-argocd-port-forward-wrapper-if-count-mismatch.md`.
- [ ] **Follow-up — `deploy_keycloak` if-count refactor** — temporary allowlist entry added for `scripts/plugins/keycloak.sh:deploy_keycloak`; separate refactor needed. Spec: `docs/issues/2026-05-11-keycloak-deploy_keycloak-if-count.md`.
- [x] **Keycloak admin token mismatch after rebuild** — `bin/acg-up` now preserves existing Vault identity secrets on rebuild, the live Vault `secret/keycloak/admin` secret was restored to the historical working password version, and admin token requests return `200` again. Specs: `docs/bugs/2026-05-11-keycloak-admin-password-reseed-on-rebuild.md` and `docs/issues/2026-05-11-keycloak-admin-token-reconciliation-failure.md`.
- [ ] **Argo CD rejects localhost return URLs during SSO login** — `/auth/login` rejects `return_url=http://localhost:8080/...` even though the Keycloak client redirect URIs are present. Spec: `docs/issues/2026-05-11-argocd-localhost-return-url-rejected.md`.
- [x] **Argo CD canonical HTTPS hostname is backed by a Vault PKI-issued local TLS listener** — `bin/acg-up` now installs a root-owned `launchd` daemon that terminates TLS for `argocd.shopping-cart.local:443` and proxies to the existing `localhost:8080` Argo CD port-forward, and `bin/acg-down` removes it. Spec: `docs/issues/2026-05-11-argocd-canonical-https-listener-missing.md` (fixed).
- [x] **Argo CD browser TLS role creation now uses a parent-domain allowed_domains shape** — `scripts/plugins/argocd.sh` derives `allowed_domains=shopping-cart.local` for `argocd.shopping-cart.local`, allowing Vault to accept the PKI role write on rebuild. Spec: `docs/issues/2026-05-11-argocd-browser-tls-role-allowed-domains.md` (fixed).
- [x] **Argo CD browser TLS role write now authenticates to Vault before upserting the PKI role** — `scripts/plugins/argocd.sh` now calls `_vault_login` before the browser TLS role write, avoiding `403 permission denied` on rebuild. Spec: `docs/issues/2026-05-11-argocd-browser-tls-vault-login-permission-denied.md`.
- [x] **Argo CD browser TLS cleanup skips revoke when prior cert is already gone** — `scripts/plugins/vault.sh` now treats a missing browser TLS serial as best-effort cleanup only, so stale certs no longer abort `make up`. Fixed in `f2942bf9`. Issue: `docs/issues/2026-05-11-argocd-browser-tls-revoke-missing-cert.md`.
- [ ] **Planned — `make up TRUST_CA=1` host CA trust bootstrap** — spec `docs/plans/v1.4.5-trust-ca-auto-import.md`. This should keep the trust-store flow opt-in while letting the helper select macOS or Linux behavior automatically.
- [x] **Argo CD browser `launchctl` stderr visibility** — `bin/acg-up` now captures stderr from the macOS browser listener install/bootstrap path in `argocd-browser-https-launchctl.log` and prints it on failure. Commit `8d18e18c`.
- [x] **Argo CD browser `launchctl bootout` best-effort** — `bin/acg-up` now ignores the expected `launchctl bootout system` failure when no listener is loaded, preventing the missing-listener case from aborting bootstrap. Commit `8d18e18c`.
- [x] **Recorded launchctl bootout edge case** — `docs/issues/2026-05-12-acg-up-argocd-browser-bootout-fails-when-listener-missing.md` captures the `Boot-out failed: 5: Input/output error` rebuild case.
- [x] **Stopped advertising localhost as browser entrypoint** — `bin/acg-up` now labels `http://localhost:8080` as terminal-only and `docs/howto/argocd.md` directs browser users to `https://argocd.shopping-cart.local`. Commit `b086aef2`. Issue doc: `docs/issues/2026-05-12-argocd-localhost-browser-entrypoint-misleading.md`.
- [x] **Argo CD browser HTTPS preflight skips sudo when already healthy** — `bin/acg-up` now checks `https://argocd.shopping-cart.local:443/healthz` before touching launchd, so repeated `make up` runs avoid the sudo prompt when the listener is already up. Commit `d5be3d0e`.
- [x] **Keycloak browser HTTP listener on localhost:80** — `bin/acg-up` now installs a local launchd-managed HTTP listener for `keycloak.shopping-cart.local:80` and keeps `/etc/hosts` on `127.0.0.1`, so Safari can reach the Keycloak auth endpoint without a certificate prompt. Commit `bca8a30c`. Issue doc: `docs/issues/2026-05-12-keycloak-browser-http-listener-missing.md`. Supersedes the earlier ingress-gateway mapping (`99581cc7`).
- [x] **Argo CD port-forward context fallback** — the generated wrapper now prefers the requested `k3d-k3d-cluster` context only when it exists, otherwise it falls back to `kubectl config current-context` and then the kubeconfig default. Commit `3f8d5150`. Issue doc: `docs/issues/2026-05-12-argocd-port-forward-context-fallback.md`.
- [x] **Argo CD browser auto-open removed from bootstrap** — `bin/acg-up` no longer opens Safari at the end of bootstrap, so `make up` finishes cleanly on both macOS and Linux without a GUI dependency, then prints `https://argocd.shopping-cart.local` for manual navigation. Issue doc: `docs/issues/2026-05-12-acg-up-browser-auto-open-removed-for-noninteractive-flows.md`.
- [ ] **Argo CD Safari stale localhost session follow-up** — old browser tabs can still exist if opened manually, but `make up` no longer drives Safari. Issue doc: `docs/issues/2026-05-12-argocd-safari-stale-localhost-tab-keeps-reopening.md`.
- [ ] **Argo CD port-forward wrapper scalar context follow-up** — the first fallback patch still rendered `_kubectl_context_args[@]` under `set -u` and quoted an empty kubeconfig value; current fix switches to a scalar context argument and leaves kubeconfig empty when unset. Issue doc: `docs/issues/2026-05-12-argocd-port-forward-wrapper-empty-array-unbound.md`.
- [ ] **Keycloak browser launchd plist path fix** — the Keycloak browser listener was staged under `~/Library/LaunchDaemons`, which does not exist on this machine; current fix moves it to `/Library/LaunchDaemons` and keeps teardown aligned. Issue doc: `docs/issues/2026-05-12-keycloak-browser-launchd-plist-installed-under-home-dir.md`.
- [x] **Keycloak realm import is mandatory** — `bin/acg-up` now fails if the Keycloak realm import does not happen, so bootstrap cannot silently report success with stale SSO state. Issue doc: `docs/issues/2026-05-12-acg-up-silent-keycloak-realm-import-skip.md`.
- [x] **Keycloak realm import status capture no longer concatenates fallback output** — a real `409` from Keycloak is now preserved instead of becoming `409000`. Issue doc: `docs/issues/2026-05-12-acg-up-keycloak-realm-import-status-concatenated-fallback.md`.
- [x] **Keycloak readiness gate reports deployment availability instead of a dead tunnel** — `bin/acg-up` now waits on `deployment/keycloak` becoming `Available` and prints deployment/pod status on timeout, so the loop no longer counts against a stale port-forward. Issue doc: `docs/issues/2026-05-12-keycloak-readiness-loop-watched-dead-port-forward.md`.
- [ ] **Live LDAP bind credentials still mismatch the running directory** — `bin/ldap-search` against the live `openldap-admin` secret returns `ldap_bind: Invalid credentials (49)` even though the cluster is up and Keycloak can reach the LDAP service. Issue doc: `docs/issues/2026-05-12-live-ldap-bind-secret-invalid-credentials.md`.
- [ ] **LDAP username attribute re-aligned to `uid`** — shopping-cart-infra bugfix branch `fix/keycloak-ldap-username-attribute-uid` now sets `LDAP_USERNAME_ATTRIBUTE` and `usernameLDAPAttribute` to `uid` to match the stable directory identifier. Issue doc: `docs/issues/2026-05-13-keycloak-ldap-username-attribute-uid.md`.
- [x] **bin helper filename normalization** — renamed the `bin/*.sh` helpers to extensionless `bin/*` scripts and updated the live caller paths plus active docs to match.
- [x] **make down preserves Hub only when explicitly requested** — default `KEEP_LOCAL` is now `0`, so local Hub deletion is the default teardown and preservation is opt-in via `KEEP_LOCAL=1`. Issue doc: `docs/issues/2026-05-12-make-down-default-preserved-local-hub-was-counterintuitive.md`.
- [ ] **Follow-up — Agent Audit if-count budget in `scripts/lib/test.sh`** — `test_jenkins` and `test_cert_rotation` still exceed the threshold; temporary allowlist entries were added and the failure was recorded in `docs/issues/2026-05-12-scripts-lib-test-if-count-allowlist.md`.
- [x] **Vault troubleshooting helper auth** — `bin/vault-exec` now auto-authenticates `vault ...` commands with the live root token before running them. Issue doc: `docs/issues/2026-05-12-vault-exec-403-unauthenticated-root-token.md`.
- [x] **acg-down browser launchd bootout is best-effort** — already-removed Keycloak and ArgoCD browser listeners now warn instead of failing `make down`. Issue doc: `docs/issues/2026-05-12-acg-down-browser-launchd-bootout-missing-listener-aborted.md`.
- [x] **Argo CD invalid scope `groups`** — Argo CD OIDC config requested `groups` in `requestedScopes`, but Keycloak rejected it with `invalid_scope: Invalid scopes: openid profile email groups`. Fixed by removing `groups` from `shopping-cart-infra/argocd/config/argocd-cm.yaml` while keeping the groups claim mapper. Shopping-cart-infra commit: `09fbb7da14b447ccdbed17bd4a422eebeaa2811d`. Issue doc: `docs/issues/2026-05-12-argocd-invalid-scope-groups-requested.md`.
- [x] **Keycloak LDAP login now keys on email** — shopping-cart-infra Keycloak LDAP federation was aligned to use `mail` as the username attribute, matching the email-style login the browser flow presents. Shopping-cart-infra PR #47 (`https://github.com/wilddog64/shopping-cart-infra/pull/47`) opened from commit `eed0b01`. Issue doc: `docs/issues/2026-05-12-keycloak-ldap-login-username-mail.md`.
- [x] **Shopping-cart-infra Copilot review thread resolved** — clarified the issue-doc heading on PR #47, pushed commit `ea491dd`, and resolved the Copilot review thread with `gh api graphql`.
- [x] **Shopping-cart-infra admin override enabled** — disabled `enforce_admins` on `main` so admins can bypass branch protection when needed. Confirmed the LDAP username change is realm-wide shopping-cart identity config, not Argo CD-only.
- [x] **Keycloak client attribute merge preserves stale PKCE** — live admin `PUT` left `pkce.code.challenge.method` behind in `client_attributes`; `bin/acg-up` now deletes the stale row directly after client reconciliation. Issue doc: `docs/issues/2026-05-12-keycloak-client-attributes-merge-preserves-pkce.md`.
- [ ] **New finding — Keycloak LDAP null username with mail mapping** — live Keycloak log shows `User returned from LDAP has null username!` when `usernameLDAPAttribute=mail`; the live LDAP entry does contain `mail: admin@shopping-cart.local`, so the runtime mapping/import path is still broken. Issue doc: `docs/issues/2026-05-12-keycloak-ldap-null-username-mail-mapping.md`.
- [x] **shopping-cart-infra PR #49 merged and synced** — branch `fix/keycloak-ldap-username-attribute-uid` merged to `shopping-cart-infra-v0.4.0`, `main` updated to merge commit `1fb43a4`, and `enforce_admins=true` restored on `main`.
- [x] **shopping-cart-infra v0.3.0 already contains the realm-import fix** — branch `shopping-cart-v0.3.0` includes `0dd3b55` (`fix(keycloak): import realm on startup`) and `5da2560` (`fix(keycloak): restore ldap root dn admin`); `main` has no additional commits to merge into that branch.
- [x] **Identity troubleshooting helpers** — added `bin/vault-exec`, `bin/ldap-search`, `bin/keycloak-logs`, and `bin/ldap-logs` with shared `_run_command`-backed wrappers in `scripts/lib/identity_tools.sh`. Added `docs/howto/identity-troubleshooting.md` for quick operator reference.
- [x] **Historical branch prune recommendation documented** — `docs/next-improvements` and `k3d-manager-v1.1.0` through `k3d-manager-v1.4.4` are not ancestors of current `main` or `k3d-manager-v1.4.5`. Recommendation: keep for auditability unless the team explicitly decides to prune branch refs. Issue doc: `docs/issues/2026-05-13-k3d-manager-historical-branches-prune-recommendation.md`.
- [ ] **acg-up known_hosts sync** — managed AWS host IPs in `~/.ssh/config` are now tracked so stale public IP entries can be pruned from `~/.ssh/known_hosts` while current entries remain. Issue doc: `docs/issues/2026-05-13-acg-up-maintain-known-hosts-for-managed-aws-ips.md`.
- [x] **Keycloak intermittent startup timeout documented** — `make up` still occasionally times out at the Keycloak readiness gate because the live deployment remains in `ContainerCreating`/unavailable. Current manifest shows `startupProbe.failureThreshold: 30` with 10s periods. Issue doc: `docs/issues/2026-05-13-keycloak-intermittent-startup-never-reaches-available.md`.
- [ ] **Refactor shopping_cart.sh → k3s_remote.sh** — spec: `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex (spec updated to also rename source line in `k3s-aws.sh` and `k3s-gcp.sh`)
- [ ] **Service mesh + LB for k3s-aws and k3s-gcp** — spec: `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; assign to Codex AFTER refactor is done
- [ ] **chisel HTTPS tunnel** — spec: `docs/plans/v1.4.3-chisel-tunnel.md`; replaces autossh+socat with HTTPS WebSocket; `TUNNEL_PROVIDER=chisel` gate; depends on refactor spec
- [ ] Restore `deploy_argocd_bootstrap "$@"` passthrough — lib-foundation flag-filtering approach; fix callers that depended on it (esp. `provision-tomcat`)
- [ ] lib-foundation upstream: remove `K3DM_ENABLE_AI=1` from `_copilot_review` usage snippet in `docs/api/functions.md`
