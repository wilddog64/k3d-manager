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
- [ ] **Refactor shopping_cart.sh → k3s_remote.sh** — spec: `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex (spec updated to also rename source line in `k3s-aws.sh` and `k3s-gcp.sh`)
- [ ] **Service mesh + LB for k3s-aws and k3s-gcp** — spec: `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; assign to Codex AFTER refactor is done
- [ ] **chisel HTTPS tunnel** — spec: `docs/plans/v1.4.3-chisel-tunnel.md`; replaces autossh+socat with HTTPS WebSocket; `TUNNEL_PROVIDER=chisel` gate; depends on refactor spec
- [ ] Restore `deploy_argocd_bootstrap "$@"` passthrough — lib-foundation flag-filtering approach; fix callers that depended on it (esp. `provision-tomcat`)
- [ ] lib-foundation upstream: remove `K3DM_ENABLE_AI=1` from `_copilot_review` usage snippet in `docs/api/functions.md`
