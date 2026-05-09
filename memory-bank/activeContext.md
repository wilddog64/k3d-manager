# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.5` (created from merge SHA `92ccaec1`).
- **v1.4.4 SHIPPED** — PR #73 merged to main (`92ccaec1`). Tagged v1.4.4, released 2026-05-08. `enforce_admins` restored on both k3d-manager and shopping-cart-infra.
- **v1.4.3 SHIPPED** — PR #72 merged to main (`b5601cb5`). `enforce_admins` restored on `main`. No prior CHANGE.md entry needed (small identity provisioning milestone).
- **v1.4.2 SHIPPED** — PR #71 merged to main (`ad8df98c`), tagged `v1.4.2`, released 2026-05-07.

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
- **PARTIAL:** `fix(identity-eso-bootstrap)` — spec `docs/bugs/v1.4.5-bugfix-identity-externalsecret-bootstrap.md`. Bug 1 COMPLETE (`f969b299`). Bugs 2+3 OPEN (shopping-cart-infra PR #40 `fix/identity-externalsecret-bootstrap`): Gemini fixup + Claude corrections committed (`ccfc2e0`); PR awaiting merge.
- **COMPLETE:** `fix(eso)` — spec `docs/bugs/v1.4.5-bugfix-deploy-eso-no-version-pin.md` (SHA: `50851f0e`). Pinned ESO Helm chart version to `1.0.0` (overridable via `ESO_HELM_CHART_VERSION`); matches remote cluster install in `acg-up`.
- **Pending:** `refactor(plugins)` — spec at `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex after SSO wiring is verified. Updated to include `k3s-aws.sh` and `k3s-gcp.sh` source-line changes (both source `shopping_cart.sh` directly — must rename to `k3s_remote.sh`).
- **Next:** `feat(providers)` — spec at `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; depends on refactor spec.
- **Next:** `feat(tunnel)` — spec at `docs/plans/v1.4.3-chisel-tunnel.md`; depends on refactor spec.
- Preserve subtree discipline: `scripts/lib/foundation/` and `scripts/lib/acg/` edits upstream first.

## Notes
- The two baseline failures in `scripts/tests/plugins/argocd.bats` remain unresolved (pre-existing, unrelated to v1.4.2 changes).
- Retro (v1.4.4): `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- Retro (v1.4.3): `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- Retro (v1.4.2): `docs/retro/2026-05-07-v1.4.2-retrospective.md`
