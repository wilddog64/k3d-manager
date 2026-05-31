# Active Context Archive — k3d-manager (v1.4.2 through v1.4.8)

Archived from memory-bank/activeContext.md on 2026-05-25.
Active content moved to memory-bank/activeContext.md.

---

## In Progress (v1.4.7)
- **NO-OP:** ArgoCD SSO `invalid_scope: groups` spec was already satisfied on `origin/main` in `shopping-cart-infra`; `requestedScopes` already contains only `openid`, `profile`, and `email`, so there was nothing to commit. Issue doc: `docs/issues/2026-05-18-argocd-groups-scope-already-fixed.md`.

## Completed (v1.4.6)
- **SPEC WRITTEN:** Frontend API contract mismatch — spec: `docs/bugs/2026-05-17-frontend-api-contract-mismatch.md`; products blank (backend `items/total/page_size/pages` → frontend needs `data/totalItems/pageSize/totalPages`; `quantity` → `stock`, `image_url` → `imageUrl`); orders 400 (missing `customerId`; backend returns plain array, frontend expects paginated shape); all fixes in `shopping-cart-frontend` on branch `fix/frontend-api-contract`.
- **SPEC WRITTEN:** Keycloak JWT issuer mismatch (app cluster) — spec: `docs/bugs/2026-05-17-keycloak-jwt-issuer-mismatch-app-cluster.md`; OAUTH2_ISSUER_URI must change from `keycloak.identity.svc.cluster.local` to `keycloak.shopping-cart.local` (matches actual JWT iss); `bin/acg-up` Step 10g.5 adds SSH tunnel + iptables DNAT + CoreDNS patch on ubuntu-k3s; changes also in `shopping-cart-order/k8s/base/configmap.yaml` and `shopping-cart-basket/k8s/base/configmap.yaml`.
- **SPEC WRITTEN:** product-catalog init SQL UUID/SERIAL mismatch — spec: `docs/bugs/2026-05-17-product-catalog-init-sql-serial-vs-uuid.md`; `shopping-cart-infra/data-layer/postgresql/products/init-db.sql` must remove the SERIAL products table DDL so SQLAlchemy owns the schema; workaround (table drop + restart) applied 2026-05-17 on live cluster.
- **LIVE STATE:** order-service and product-catalog both returning 200 on live ubuntu-k3s cluster (2026-05-17); ArgoCD self-heal is ON for all shopping-cart apps; next pod restart will pick up OAUTH2_ENABLED=true from configmap → JWT auth will fail again until Keycloak JWT spec is implemented.
- **COMPLETE:** `acg-up` now skips AWS credential extraction when `_acg_check_credentials` says the current AWS credentials are valid, otherwise it falls back to Playwright extraction; committed as `7d2be2e6` (`fix(acg-up): skip credential extraction when existing AWS credentials are valid`) and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** frontend 504 fix for shared namespace services — `shopping-cart-product-catalog/k8s/base/service.yaml` now exposes the ClusterIP on `8082` and `shopping-cart-order/k8s/base/service.yaml` now exposes the ClusterIP on `8081`, matching the frontend nginx upstream config; committed as `345d89a` in product-catalog and `0edba5b` in order, both on `fix/argocd-shared-namespace` and both pushed to origin.
- **COMPLETE:** k3s-aws CloudFormation stack status-aware provisioning — `scripts/lib/providers/k3s-aws.sh` now checks the existing CloudFormation stack state before provisioning, reuses healthy stacks without `--recreate`, and only recreates broken states; committed as `25f867f0` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** 127.0.0.2 loopback alias launchd agent for frontend port-forward — added a best-effort `ifconfig lo0 alias 127.0.0.2` check plus a persistent `/Library/LaunchDaemons/com.k3d-manager.loopback-alias.plist` bootstrap in Step 10g of `bin/acg-up`; committed as `8066f35e` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** frontend-browser-http wrapper kubectl path fix — `bin/acg-up` now bakes the absolute `kubectl` path into the Step 10g launchd wrapper; committed as `4b0509ff` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Cloudflare Tunnel launchd agents for public ArgoCD + frontend access — added Step 10h in `bin/acg-up`; committed as `e45a6b22` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** frontend.shopping-cart.local direct port-forward fix — replaced the broken ServiceEntry/VirtualService path with a launchd-managed `kubectl port-forward --address=127.0.0.2 svc/frontend 80:80` flow in `bin/acg-up`; committed as `84cb5a21` and pushed to `origin/k3d-manager-v1.4.6`.
- **NEXT:** Cloudflare Tunnel for ArgoCD + frontend access — spec: `docs/bugs/2026-05-17-cloudflare-tunnel-argocd-frontend.md`; start only after the frontend port-forward fix is merged and verified.
- **COMPLETE:** frontend.shopping-cart.local NodePort/ServiceEntry/VirtualService wiring — added Step 10g in `bin/acg-up`; committed as `14e7b8b0` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Keycloak empty-admin-secret hard-fail fix — committed as `1ab96ed1` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** lib-acg Extend Your Session dialog AppleScript click fix — committed as `7874e9d` and pushed to `origin/fix/acg-credentials-extend-dialog`.
- **COMPLETE (STILL FAILING — superseded):** lib-acg Extend Your Session dialog bringToFront/Enter attempt — `1e7f2ff` dismissed iTerm2 hotkey window; superseded by the AppleScript screen-coordinate click fix.
- **COMPLETE:** lib-acg credential-test write fix — `bin/acg-credential-test` now writes AWS credentials to `~/.aws/credentials` under `[default]` and validates with `AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity`; committed as `217609a` and pushed to `origin/fix/acg-credentials-extend-dialog`.
- **COMPLETE:** Codex — addLocatorHandler post-handler wait loop in BOTH `acg_extend.js` + `acg_credentials.js` — spec: `docs/bugs/2026-05-16-acg-extend-locator-handler-no-wait-after.md`; committed as `5a638912` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE (STILL FAILING — new issue):** Codex — acg "Session extended" toast × — page.mouse.click bounding-rect + addLocatorHandler — committed as `718562b9`; superseded by noWaitAfter spec.
- **COMPLETE (STILL FAILING):** Codex — acg "Session extended" toast × — page.evaluate DOM traversal — committed as `ebd3a985`; still failing — element.click() does not trigger React synthetic event handler
- **COMPLETE (STILL FAILING):** Codex — acg "Session extended" toast never dismissed — text-locator + page-level CI close — committed as `70ce5ca9`; still failing — toast has no aria-label
- **COMPLETE:** Codex — acg-credentials Start Sandbox outside viewport — committed as `7b828419` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg "Session extended" × close fallback — committed as `e464bafa` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE (STILL FAILING):** Codex — acg "Session extended" × button not clicked — committed as `fd9b2fe7`; button[aria-label="Close"] not found in container
- **COMPLETE:** Codex — acg-up return outside function — committed as `fd9b2fe7`
- **COMPLETE:** Codex — acg-credentials _clickStartSandbox blocked by Session extended modal — committed as `644ec725` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg-credentials isEnabled() gate skips Start Sandbox click — committed as `ee8be3ca` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg-up aws sts shortcut skips credential extraction — committed as `b1da7ef4` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg-credentials Escape does not dismiss "Extend Your Session" dialog — committed as `c66e8bc5` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg Session extended modal × button not clicked — wrong locator scope — committed as `8eb6fd02` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — k3s-aws CloudFormation deploy fails when stack is in terminal failure state — committed as `bc4485d8` and pushed to `origin/k3d-manager-v1.4.6`
- **COMPLETE:** Codex — acg Session extended modal not closed (Escape unreliable) — implementation committed as `f39adc25`; validation note committed as `43dc422a`; both pushed to `origin/k3d-manager-v1.4.6`
- **NOTE:** Direct ad hoc `_agent_checkpoint` / `_agent_lint` / `_agent_audit` invocation in this shell emitted `.git/index.lock` permission errors; recorded in `docs/issues/2026-05-16-git-commit-index-lock-permission-error.md`
- **COMPLETE:** `bats scripts/tests/bin/acg_up.bats` step-number grep drift resolved — updated the expectation to `Step 10e/14 — Installing Istio ingress HTTP listener`
- **COMPLETE:** Codex — acg-credentials handler loops 3× then times out — committed as `982d551e` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials fallback Escape closes credentials panel — committed as `b7f0d0a5` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE (STILL FAILING):** Codex — acg-credentials Start Sandbox detaches after modal dismiss — committed as `7d2faaba`; superseded by extend-session-via-filled-button spec.
- **COMPLETE (STILL FAILING):** Codex — acg-credentials handler Cancel/filled-button causes dialog loop — committed as `452fee93`; superseded.
- **COMPLETE (SUPERSEDED):** Codex — acg-credentials remove addLocatorHandler — committed as `02d792a4`; superseded.
- **COMPLETE (STILL FAILING):** Codex — acg-credentials re-add addLocatorHandler with exact "Extend Session" button label — committed as `6154b0df`; superseded by handler-times-1-click-helper spec.
- **COMPLETE:** Codex — acg-credentials handler non-blocking 250ms — committed as `e2d4bb1b` and pushed to `origin/k3d-manager-v1.4.6`. Still failing: post-dismiss React re-render detaches Start Sandbox button.
- **COMPLETE (SUPERSEDED):** Codex — acg-credentials handler dismiss-only with waitFor + 500ms settle — committed as `73660e6a`; superseded.
- **COMPLETE:** Codex — acg-credentials handler clicks Cancel instead of Extend, dialog reappears 5× and times out — committed as `a07c3c10` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials startButton detaches after React re-render following modal close — committed as `0fbdba3079b8c1e183e8cb1b72fdbf1429a3f3ff` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials addLocatorHandler post-handler wait loops on CSS slide-out animation — committed as `1026389cdbb4353ec4a4dba6b402f0ec5e9bcb88` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials "Extend Your Session" modal still blocks during sandbox wait and button-click phase — committed as `4cbe3b7e26e41eee1a2e05897a75c1d030557ef8` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — add frontend.shopping-cart.local via Istio ingress gateway — committed as `e701139a17eb4acb19bb84976db5e4a14e795a8f` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials "Extend Your Session" modal not dismissed — committed as `69204c91e5e060df6e2ca230c1180d6055f1d91d` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials GCP reads AWS inputs — committed as `1ba5c5ac66d5493cdfa8ca661c0372ca518c6882` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials "Session extended" modal not dismissed — committed as `3444c171d4797e4cc305b4fc9c1bc707b6a9fb5c` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-credentials wrong sandbox provider — committed as `5dfbdf44c2f3dce49e53f1e3f245b5c8e3a470fd` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — acg-extend "Start Sandbox" race — committed as `bae89aafae42aeea7b7d71cd65eed4c24ca84962` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — auto-trust Vault CA cert in macOS System Keychain — committed as `42d9941306658c259f367916bc68ea69573a3085` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — /etc/hosts sudo + HTTPS listener timeout — committed as `0ea4cc9f89649a3a5ca7d8a2da4df4f6b39fb4b9` and pushed to `origin/k3d-manager-v1.4.6`.
- **COMPLETE:** Codex — argocd-cm HTTP URL breaks OIDC SSO callback — committed as `411ebb2e3b551cccbe44260c30bb561940357eb8` and pushed to `origin/shopping-cart-infra-v0.5.3`.

## Post-Merge Housekeeping — 2026-05-15 (shopping-cart-frontend #15)
- **shopping-cart-frontend PR #15 merged** — shopping-cart-frontend-v0.5.1 → main, SHA `19e47118a2156589fadcfc8998b37f29bda18f75`
- **Keycloak SSO wiring shipped** — CI build-args; nginx CSP; deployment stabilized with nginx-cache emptyDir
- **enforce_admins restored** — `true` ✓ (shopping-cart-frontend)
- **v0.5.1 branch created** — retrospective: `docs/retro/2026-05-15-v0.5.1-retrospective.md` (commit `60e660f`)

## Post-Merge Housekeeping — 2026-05-15 (shopping-cart-infra #57)
- **shopping-cart-infra PR #57 merged** — shopping-cart-infra-v0.5.2 → main, SHA `adbaec8de6725817ba55b8a36c1653a5fa1bb3ae`
- **Networking + mTLS fixes shipped** — `project: shopping-cart` AppProject; Keycloak DestinationRule with `tls.mode: DISABLE`
- **enforce_admins restored** — `true` ✓ (shopping-cart-infra)
- **v0.5.3 branch created** — retrospective: `docs/retro/2026-05-15-v0.5.2-retrospective.md` (commit `907bf06`)
- **Branch cleanup** — deleted v0.4.0, v0.5.0, v0.5.2; retained v0.5.3

## Post-Merge Housekeeping — 2026-05-15 (shopping-cart-infra #56)
- **shopping-cart-infra PR #56 merged** — shopping-cart-infra-v0.5.1 → main, SHA `79c42b71db07f0889f90e744d571d2a9998a4934`
- **Keycloak reconcile hook fix shipped** — replaced python3 JSON parsing with kcadm.sh -q server-side filters
- **enforce_admins restored** — `true` ✓ (shopping-cart-infra)
- **v0.5.2 branch created** — retrospective: `docs/retro/2026-05-15-v0.5.1-retrospective.md` (on shopping-cart-infra-v0.5.2)

## Post-Merge Housekeeping — 2026-05-15 (shopping-cart-infra #55 + rigor-cli #10)
- **shopping-cart-infra PR #55 merged** — bug/keycloak-ldap-mappers-missing → main, SHA `ff9e4d5a`
- **rigor-cli PR #10 merged** — rigor-cli-v0.1.6 → main, SHA `2d6d4b68`, tagged `v0.1.6`
- **enforce_admins restored on both repos** — `true` ✓ (shopping-cart-infra + rigor-cli)
- **rigor-cli v0.1.6 tag + GitHub release created** — merge SHA `2d6d4b68` tagged, released 2026-05-15
- **Retrospectives created** — shopping-cart-infra `docs/retro/2026-05-15-v0.5.0-retrospective.md`, rigor-cli `docs/retro/2026-05-15-v0.1.6-retrospective.md`
- **Next branches created** — shopping-cart-infra-v0.5.1, rigor-cli-v0.1.7
- **bug/keycloak-ldap-mappers-missing deleted** — merged branch cleaned up

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

## Current Focus (v1.4.5) — archived historical entries
- All v1.4.5 Current Focus items were marked COMPLETE before v1.4.6 shipped.
- Key commits: SSO wiring `3bb7aa81`, networking fix `6c70fee9`, acg-up bugs `3c096f6`, ArgoCD SSO `d314c34`/`afaf109`, identity ESO bootstrap PRs #40-#43, CoreDNS `34e0101f`, frontend port-forward `fb56a443`, ArgoCD localhost readiness gate, HTTPS listener, browser TLS PKI, Keycloak reconcile fixes.
- Full detail preserved in shopping-cart-infra CHANGELOG and retrospective docs.

## Notes
- The two baseline failures in `scripts/tests/plugins/argocd.bats` remain unresolved (pre-existing, unrelated to v1.4.2 changes).
- Historical branch pruning recommendation recorded in `docs/issues/2026-05-13-k3d-manager-historical-branches-prune-recommendation.md`
- Retro (v1.4.4): `docs/retro/2026-05-08-v1.4.4-retrospective.md`
- Retro (v1.4.3): `docs/retro/2026-05-08-v1.4.3-retrospective.md`
- Retro (v1.4.2): `docs/retro/2026-05-07-v1.4.2-retrospective.md`
