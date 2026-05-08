# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.4` (created from main at `b5601cb5`).
- **v1.4.3 SHIPPED** — PR #72 merged to main (`b5601cb5`). `enforce_admins` restored on `main`. No prior CHANGE.md entry needed (small identity provisioning milestone).
- **v1.4.2 SHIPPED** — PR #71 merged to main (`ad8df98c`), tagged `v1.4.2`, released 2026-05-07.

## Post-Merge Housekeeping — 2026-05-08
- **rigor-cli v0.1.4 tag restored** — v0.1.4 shipped 2026-05-03 via PR #7 (`ac7a39d5`) but tag was missing; created and pushed to origin
- **rigor-cli enforce_admins restored** — was `false`; restored to `true`
- **k3d-manager enforce_admins verified** — `true` ✓
- **shopping-cart-infra enforce_admins verified** — `true` ✓
- **All next branches verified as present** — k3d-manager-v1.4.4, shopping-cart-infra docs/next-improvements, rigor-cli-v0.1.6

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

## Current Focus (v1.4.4)
- **OPEN: Keycloak ExternalSecret files missing** — bug spec at `docs/bugs/2026-05-08-keycloak-externalsecret-files-missing.md`; assign to Gemini. shopping-cart-infra `docs/next-improvements` branch: create `keycloak-secrets-externalsecret.yaml`, `keycloak-client-secrets-externalsecret.yaml`, patch `configmap.yaml` with `KEYCLOAK_ADMIN` + `KC_DB_USERNAME`. Discovered during verify pass after v1.4.4-identity-sso-fixes.
- **DONE:** `feat(identity)` — spec at `docs/plans/v1.4.4-identity-sso-fixes.md`. k3d-manager `95d0226` + shopping-cart-infra `7bc6e96` committed and pushed. Missing ExternalSecret files created and static vars moved to configmap.
- **Next:** `refactor(plugins)` — spec at `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex after identity SSO fixes. Updated to include `k3s-aws.sh` and `k3s-gcp.sh` source-line changes (both source `shopping_cart.sh` directly — must rename to `k3s_remote.sh`).
- **Next:** `feat(providers)` — spec at `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; Istio + MetalLB (k3s-aws) + externalIPs + GCP firewall (k3s-gcp). Depends on refactor spec first. Assign to Codex after refactor is merged.
- **Next:** `feat(tunnel)` — spec at `docs/plans/v1.4.3-chisel-tunnel.md`; replace autossh+socat with chisel HTTPS WebSocket tunnel; `TUNNEL_PROVIDER=chisel` gate; autossh remains default. AWS: install via SSM. GCP: cloud-init startup-script. Depends on refactor spec.
- Preserve subtree discipline: `scripts/lib/foundation/` and `scripts/lib/acg/` edits upstream first.

## Notes
- The two baseline failures in `scripts/tests/plugins/argocd.bats` remain unresolved (pre-existing, unrelated to v1.4.2 changes).
- Retro (v1.4.3): `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- Retro (v1.4.2): `docs/retro/2026-05-07-v1.4.2-retrospective.md`
