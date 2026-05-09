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
- **Pending:** `refactor(plugins)` — spec at `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex after SSO wiring is verified. Updated to include `k3s-aws.sh` and `k3s-gcp.sh` source-line changes (both source `shopping_cart.sh` directly — must rename to `k3s_remote.sh`).
- **Next:** `feat(providers)` — spec at `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; depends on refactor spec.
- **Next:** `feat(tunnel)` — spec at `docs/plans/v1.4.3-chisel-tunnel.md`; depends on refactor spec.
- Preserve subtree discipline: `scripts/lib/foundation/` and `scripts/lib/acg/` edits upstream first.

## Notes
- The two baseline failures in `scripts/tests/plugins/argocd.bats` remain unresolved (pre-existing, unrelated to v1.4.2 changes).
- Retro (v1.4.4): `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- Retro (v1.4.3): `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- Retro (v1.4.2): `docs/retro/2026-05-07-v1.4.2-retrospective.md`
