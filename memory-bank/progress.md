# Progress — k3d-manager

## Status
- Current branch: `k3d-manager-v1.4.5`.
- **v1.4.4 SHIPPED** — PR #73 merged (`92ccaec1`), tagged v1.4.4, released 2026-05-08. enforce_admins restored. Retro: `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- **shopping-cart-infra PR #37 SHIPPED** — merged (`867d861`). enforce_admins restored. Retro: `docs/retro/2026-05-08-pr37-keycloak-externalsecret-retrospective.md`
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
- [x] **ArgoCD SSO via Keycloak** — COMPLETE (infra: `473dd01`, manager: `aa3dc6f`).  ASSIGNED TO GEMINI; spec: `docs/plans/v1.4.5-argocd-sso-keycloak.md`; k3d-manager `k3d-manager-v1.4.5` + shopping-cart-infra `docs/next-improvements`
- [x] **pyjenkinsapi rigor-cli v0.1.6 subtree pull** — COMPLETE (subtree: `7d8a894b`, ci-fix: `0c479c99`); branch `docs/next-improvements`; BATS re-enabled
- [x] **acg-up /etc/hosts --soft** — COMPLETE (`3c096f6`). `_run_command --prefer-sudo` missing `--soft` causes `exit 1` instead of warning when EPERM. spec: `docs/bugs/v1.4.5-bugfix-etc-hosts-soft.md`.
- [x] **acg-up Step 10e bugs** — COMPLETE (`d6a31c5`). Fixed CoreDNS awk pattern + /etc/hosts sudo hard-fail. spec: `docs/plans/v1.4.5-bugfix-gemini.md`
- [ ] **Refactor shopping_cart.sh → k3s_remote.sh** — spec: `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex (spec updated to also rename source line in `k3s-aws.sh` and `k3s-gcp.sh`)
- [ ] **Service mesh + LB for k3s-aws and k3s-gcp** — spec: `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; assign to Codex AFTER refactor is done
- [ ] **chisel HTTPS tunnel** — spec: `docs/plans/v1.4.3-chisel-tunnel.md`; replaces autossh+socat with HTTPS WebSocket; `TUNNEL_PROVIDER=chisel` gate; depends on refactor spec
- [ ] Restore `deploy_argocd_bootstrap "$@"` passthrough — lib-foundation flag-filtering approach; fix callers that depended on it (esp. `provision-tomcat`)
- [ ] lib-foundation upstream: remove `K3DM_ENABLE_AI=1` from `_copilot_review` usage snippet in `docs/api/functions.md`
