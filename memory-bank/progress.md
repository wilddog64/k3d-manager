# Progress — k3d-manager

## Status
- Current branch: `k3d-manager-v1.4.3`.
- **v1.4.2 SHIPPED** — PR #71 merged (`ad8df98c`), tagged + released 2026-05-07.

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

## Next Steps (v1.4.3)
- [ ] **Refactor shopping_cart.sh → k3s_remote.sh** — spec: `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex
- [ ] Restore `deploy_argocd_bootstrap "$@"` passthrough — lib-foundation flag-filtering approach; fix callers that depended on it (esp. `provision-tomcat`)
- [ ] lib-foundation upstream: remove `K3DM_ENABLE_AI=1` from `_copilot_review` usage snippet in `docs/api/functions.md`
