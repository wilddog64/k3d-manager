# Progress Archive — k3d-manager (v1.4.2 through v1.4.8)

Archived from memory-bank/progress.md on 2026-05-25.
Active content moved to memory-bank/progress.md.

---

## Status (v1.4.8 — PR #77 merged 2026-05-19 + post-merge complete)
- **RELEASED:** k3d-manager v1.4.8 — PR #77 merged to main (SHA `8f08bd35`); enforce_admins restored; next branch: `k3d-manager-v1.4.9`; v1.4.8 retrospective committed `9946fa66` on k3d-manager-v1.4.9
- **MERGED:** k3d-manager PR #77 — vault temp file leaks, CDP hang, Keycloak frontendUrl, Cloudflare tunnel; merge SHA `8f08bd35`; v1.4.8 retrospective committed on k3d-manager-v1.4.9
- **POST-MERGE:** k3d-manager PR #77 housekeeping — enforce_admins restored ✓; next branch created ✓; retrospective committed ✓; memory-bank updated (in progress)
- **COMPLETE:** Keycloak public URL follow-up landed across all four repos: `k3d-manager` commit `ea9977b4` sets Keycloak `frontendUrl` to `https://keycloak.3ai-talk.org` after realm import; `shopping-cart-basket` commit `cb5a294` sets `OAUTH2_ISSUER_URI` to the Cloudflare public issuer; `shopping-cart-order` commit `fb578ca` sets both `OAUTH2_ISSUER_URI` and `OAUTH2_JWK_SET_URI` to the Cloudflare public issuer; `shopping-cart-frontend` commit `cb348c4` sets both `VITE_KEYCLOAK_URL` occurrences to `https://keycloak.3ai-talk.org`; explicit feature refs were pushed to `origin/fix/keycloak-public-url` in each shopping-cart repo, and the upstream-push quirk was documented in `docs/issues/2026-05-19-git-push-upstream-default-targeted-main.md`.
- **RELEASED:** k3d-manager v1.4.7 — tag `v1.4.7` pushed, GitHub release created, enforce_admins restored, next branch: `k3d-manager-v1.4.8`
- **MERGED:** k3d-manager PR #76 — Keycloak cross-cluster tunnel + CoreDNS on k3s-aws; merge SHA `0278e8d7`; v1.4.7 retrospective committed on k3d-manager-v1.4.8
- **POST-MERGE:** lib-foundation PR #28 — fix: Copilot CLI auth + rigor scanner improvements; merge SHA `fee313ed`; branch `feat/v0.3.20` cut, retrospective committed `a64e2ad`; enforce_admins restored (pending)
- **POST-MERGE:** lib-acg PR #13 — docs: PR #12 retrospective and Phase 3 completion; merge SHA `1bdc663`; branch `docs/next-improvements` created, retrospective committed `4d93147`; enforce_admins restored (pending)
- **RELEASED:** shopping-cart-infra v0.5.0 — tag `v0.5.0` pushed, GitHub release created, enforce_admins restored, next branch: `shopping-cart-infra-v0.5.5`
- **MERGED:** k3d-manager PR #75 — Keycloak cross-cluster reachability fix (SSH tunnel + iptables DNAT + CoreDNS patch); merge SHA `8cb5709b`; v1.4.6 retrospective committed on v1.4.7
- **MERGED:** shopping-cart-order PR #30 — Keycloak JWT issuer URI fix; merge SHA `16640fd5`; `docs/next-improvements` branch created
- **MERGED:** shopping-cart-basket PR #11 — Keycloak JWT issuer URI fix; merge SHA `c718c1cd`; `docs/next-improvements` branch created
- **MERGED:** shopping-cart-infra PR #59 — products table DDL removed (SQLAlchemy now owns schema); merge SHA `475794c0`; `docs/next-improvements` branch created
- **MERGED:** shopping-cart-frontend PR #16 — API response field mapping + customerId from Keycloak; merge SHA `674116b2`; `docs/next-improvements` branch created
- **COMPLETE:** products ConfigMap schema mismatch fix — `shopping-cart-infra/data-layer/postgresql/products/configmap.yaml` now matches `init-db.sql` by keeping only categories schema + seed data; commit `eb05a3f`; branch `fix/products-db-schema` pushed to `origin`.
- **NO-OP:** ArgoCD SSO `invalid_scope: groups` already absent from `shopping-cart-infra/argocd/config/argocd-cm.yaml` on `origin/main`; issue doc recorded the stale spec state at `docs/issues/2026-05-18-argocd-groups-scope-already-fixed.md`.
- **acg-up Keycloak LDAP user passwords seeding completed** — `bin/acg-up` now seeds `keycloak/users/admin`, `keycloak/users/developer`, and `keycloak/users/operator` in Vault and applies the passwords to LDAP on every `make up`; committed as `34c6f8a9` (`fix(acg-up): seed Keycloak LDAP user passwords in Vault on every make up`) and pushed to `origin/k3d-manager-v1.4.6`; validated with `shellcheck -S warning bin/acg-up` and `bats scripts/tests/bin/acg_up.bats`; PR URL: not created (per repository instruction).
- **shopping-cart PRs #20 + #29 post-merge completed** — `shopping-cart-product-catalog` PR #20 (SHA `12dfe79`) + `shopping-cart-order` PR #29 (SHA `8a2739d`) merged to main; enforce_admins restored on both; `docs/next-improvements` branch created on both repos; k3d-manager memory-bank updated
- **acg-up credential extraction skip completed** — `bin/acg-up` now checks `_acg_check_credentials` before calling `acg_get_credentials` for `k3s-aws`, skipping Playwright extraction when the existing AWS credentials are valid and falling back to extraction otherwise; committed as `7d2be2e6` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **frontend 504 fix for shared namespace services completed** — `shopping-cart-product-catalog/k8s/base/service.yaml` now sets the ClusterIP port to `8082`, and `shopping-cart-order/k8s/base/service.yaml` now sets the ClusterIP port to `8081`, matching the frontend nginx upstream config; committed as `345d89a` and `0edba5b` on `fix/argocd-shared-namespace` and pushed to origin in both repos; PR URL: not created (per repository instruction).
- **k3s-aws CloudFormation stack status-aware provisioning completed** — `scripts/lib/providers/k3s-aws.sh` now checks the existing CloudFormation stack status before provisioning, reuses healthy stacks without `--recreate`, recreates only broken stacks, and creates missing/unknown stacks without forcing recreation; committed as `25f867f0` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **127.0.0.2 loopback alias launchd agent completed** — `bin/acg-up` now ensures `127.0.0.2` exists on `lo0` with a best-effort `ifconfig lo0 alias 127.0.0.2` call, then installs a persistent `com.k3d-manager.loopback-alias` launchd daemon at `/Library/LaunchDaemons` so the alias survives reboots before the frontend-browser-http wrapper starts; committed as `8066f35e` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **frontend-browser-http wrapper kubectl path fix completed** — `bin/acg-up` now captures `kubectl` with `command -v` before writing the Step 10g frontend-browser-http wrapper heredoc, then expands that absolute path inside the launchd script so the root daemon does not depend on `PATH`; committed as `4b0509ff` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **Cloudflare Tunnel launchd agents completed** — `bin/acg-up` now installs macOS launchd agents for `cloudflared tunnel --url http://localhost:8080` and `cloudflared tunnel --url http://127.0.0.2:80`, logs the random `trycloudflare.com` URLs to `~/.local/share/k3d-manager/tunnel-urls.txt`, and prints the public ArgoCD/frontend URLs at the end of `acg-up`; committed as `e45a6b22` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **frontend.shopping-cart.local direct port-forward fix completed** — `bin/acg-up` now binds `frontend.shopping-cart.local` to `127.0.0.2` and starts a launchd-managed `kubectl port-forward --address=127.0.0.2 svc/frontend 80:80` listener instead of the blocked ServiceEntry path; committed as `84cb5a21` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **Cloudflare Tunnel task completed** — the pending tunnel spec is now implemented in `bin/acg-up` with launchd agents and `trycloudflare.com` URL logging; commit `e45a6b22` supersedes the pending note.
- **frontend.shopping-cart.local NodePort/ServiceEntry/VirtualService wiring completed** — `bin/acg-up` now creates the `frontend-nodeport` NodePort 30080 service on ubuntu-k3s, derives the ubuntu-k3s IP from kubeconfig, applies the `frontend-ubuntu-k3s` ServiceEntry and `frontend` VirtualService in k3d, and updates the Step 13 URL text; committed as `14e7b8b0` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **Keycloak empty-admin-secret hard-fail fix completed** — `scripts/plugins/keycloak.sh` now hard-fails if the admin ExternalSecret never becomes Ready or the decoded secret is empty, and `bin/acg-up` now fails fast when Vault returns an empty `keycloak/admin` password field; committed as `1ab96ed1` and pushed to `origin/k3d-manager-v1.4.6`; PR URL: not created (per repository instruction).
- **lib-acg extend dialog AppleScript native click fix completed** — `playwright/acg_credentials.js` now computes screen coordinates in `page.evaluate()` and uses `osascript` via `child_process.execSync` to native-click the close button; committed as `7874e9d` and pushed to `origin/fix/acg-credentials-extend-dialog`; PR URL: not created (per repository instruction).
- **lib-acg extend dialog bringToFront/Enter attempt superseded** — `1e7f2ff` used `page.bringToFront()` plus `Enter`, but that dismissed iTerm2 hotkey focus and reset the page before the key event arrived; superseded by the AppleScript native-click fix.
- **lib-acg extend dialog selector fix completed** — `playwright/acg_credentials.js` now uses `getByRole('button', { name: 'Cancel' })` and logs click errors instead of swallowing them; committed as `787cab8` and pushed to `origin/fix/acg-credentials-extend-dialog`; PR URL: not created (per repository instruction).
- **lib-acg extend dialog locator-click attempt superseded** — the earlier `locator('button', { hasText: 'Cancel' })` fix was superseded by the new `getByRole('button', { name: 'Cancel' })` selector and error logging; prior commit `98bbf59` is no longer the branch tip.
- **k3d-manager validation follow-up docs committed** — recorded the `.git/index.lock` permission note and the unrelated-suite `./scripts/k3d-manager test all` failures in `docs/issues/2026-05-16-git-commit-index-lock-permission-error.md` and `docs/issues/2026-05-17-repo-test-all-existing-failures.md`; committed as `65582d0c` (`docs: record validation follow-up notes`); PR URL: not created (per repository instruction).
- **lib-acg extend dialog and credential write fixes completed** — the prior escape-key fallback spec is superseded by the committed locator-click and credential-write fixes on `fix/acg-credentials-extend-dialog`; remote SHAs are `98bbf59` and `217609a`; PR URL: not created (per repository instruction).
- **k3d-manager v1.4.6 addLocatorHandler post-handler wait loop (acg_extend.js + acg_credentials.js) — completed** — spec: `docs/bugs/2026-05-16-acg-extend-locator-handler-no-wait-after.md`; implemented `{ noWaitAfter: true }` in `acg_extend.js` + `{ times: 1, noWaitAfter: true }` in `acg_credentials.js`; committed as `5a638912` and pushed to `origin/k3d-manager-v1.4.6`.
- **k3d-manager v1.4.6 acg "Session extended" toast × — mouse.click bounding-rect + addLocatorHandler — STILL FAILING** — spec: `docs/bugs/2026-05-16-session-extended-mouse-click-and-locator-handler.md`; committed as `718562b9`; × click works but addLocatorHandler fires in infinite loop; superseded by noWaitAfter spec
- **k3d-manager v1.4.6 acg "Session extended" toast × — page.evaluate DOM traversal — STILL FAILING** — spec: `docs/bugs/2026-05-16-session-extended-evaluate-close-button.md`; element.click() in evaluate does not trigger React synthetic event handler; committed as `ebd3a985`; superseded by mouse-click-bounding-rect spec
- **k3d-manager v1.4.6 acg "Session extended" toast never dismissed — STILL FAILING** — spec: `docs/bugs/2026-05-16-session-extended-text-locator-page-level-close.md`; `[role="alert"]` fallback hangs 30s (no role on toast container); committed as `70ce5ca9`; superseded by evaluate spec
- **k3d-manager v1.4.6 acg-credentials Start Sandbox outside viewport — completed** — spec: `docs/bugs/2026-05-16-acg-credentials-start-sandbox-outside-viewport.md`; added 3× retry loop to `_clickStartSandbox` scroll+click; committed as `7b828419` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg "Session extended" × close fallback — completed** — spec: `docs/bugs/2026-05-16-session-extended-close-fallback-button-last.md`; added count-check + `button.last()` fallback at all 7 dismiss sites in `acg_credentials.js` + `acg_extend.js`; committed as `e464bafa` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg "Session extended" × button[aria-label="Close"] — STILL FAILING** — spec: `docs/bugs/2026-05-16-session-extended-button-aria-label.md`; `button[aria-label="Close"]` silently finds 0 elements inside container (.catch swallows), card stays visible; committed as `fd9b2fe7` but still fails
- **k3d-manager v1.4.6 acg-up return outside function — completed** — spec: `docs/bugs/2026-05-16-acg-up-return-outside-function.md`; changed `bin/acg-up` `|| return 1` to `|| exit 1`; committed as `fd9b2fe7`
- **k3d-manager v1.4.6 acg-credentials _clickStartSandbox blocked by Session extended — completed** — spec: `docs/bugs/2026-05-16-acg-credentials-click-start-sandbox-blocked-by-session-extended.md`; `_clickStartSandbox` now dismisses the "Your sandbox has been extended." card before scrolling/clicking Start Sandbox; committed as `644ec725` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials isEnabled() gate skips Start Sandbox — completed** — spec: `docs/bugs/2026-05-16-acg-credentials-start-sandbox-isenabled-gate.md`; `scripts/lib/acg/playwright/acg_credentials.js` Pattern 1 now always clicks Start Sandbox when visible; committed as `ee8be3ca` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-up credential shortcut skips extraction — completed** — spec: `docs/bugs/2026-05-16-acg-up-credential-shortcut-skips-extraction.md`; `bin/acg-up` now always calls `acg_get_credentials ${sandbox_url:+"$sandbox_url"} || return 1` for `k3s-aws`; committed as `b1da7ef4` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials Escape does not dismiss Extend Your Session dialog — completed** — spec: `docs/bugs/2026-05-16-acg-credentials-escape-does-not-dismiss-extend-session-dialog.md`; `scripts/lib/acg/playwright/acg_credentials.js` line 392 now clicks `_extendSessionPrompt.locator('button[aria-label="Close"]').first().click({ force: true })`; committed as `c66e8bc5` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg Session extended modal wrong-button completed** — spec: `docs/bugs/2026-05-16-acg-session-extended-modal-wrong-button.md`; 6 single-line locator changes in acg_extend.js (3) + acg_credentials.js (3); committed as `8eb6fd02` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 k3s-aws CloudFormation rollback-state completed** — spec: `docs/bugs/2026-05-16-k3s-aws-cloudformation-rollback-state.md`; `scripts/lib/providers/k3s-aws.sh` now calls `acg_provision --confirm --recreate`; committed as `bc4485d8` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg Session extended modal escape-unreliable completed** — spec: `docs/bugs/2026-05-16-acg-session-extended-modal-escape-unreliable.md`; `scripts/lib/acg/playwright/acg_extend.js` and `scripts/lib/acg/playwright/acg_credentials.js` now click the dialog's scoped button instead of Escape; implementation committed as `f39adc25`; validation note committed as `43dc422a`; both pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 agent rigor helper validation note** — direct `_agent_checkpoint` / `_agent_lint` / `_agent_audit` invocation in this shell emitted `.git/index.lock` permission errors and missing `_err` helper output; recorded in `docs/issues/2026-05-16-git-commit-index-lock-permission-error.md`
- **k3d-manager v1.4.6 acg-up step-number grep drift — completed** — updated `scripts/tests/bin/acg_up.bats` to expect `Step 10e/14 — Installing Istio ingress HTTP listener`, matching current `bin/acg-up`
- **k3d-manager v1.4.6 acg-credentials credential-wait-escape-closes-panel completed** — spec: `docs/bugs/2026-05-16-acg-credentials-credential-wait-escape-closes-panel.md`; committed as `b7f0d0a5` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials handler-times-1-click-helper completed** — committed as `982d551e` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials handler-times-1-click-helper ASSIGNED** — spec: `docs/bugs/2026-05-16-acg-credentials-handler-times-1-click-helper.md`
- **k3d-manager v1.4.6 acg-credentials addlocatorhandler-extend-session-button STILL FAILING** — spec: `docs/bugs/2026-05-16-acg-credentials-addlocatorhandler-extend-session-button.md`; committed as `6154b0df`; superseded by handler-times-1-click-helper spec
- **k3d-manager v1.4.6 acg-credentials remove-addlocatorhandler SUPERSEDED** — `02d792a4`; superseded
- **k3d-manager v1.4.6 acg-credentials extend-session-via-filled-button SUPERSEDED** — `452fee93`; superseded
- **k3d-manager v1.4.6 acg-credentials start-sandbox-detached SUPERSEDED** — `7d2faaba`; superseded
- **k3d-manager v1.4.6 acg-credentials handler-nonblocking-250ms completed** — `e2d4bb1b`; handler ~350ms/cycle; still failing post-dismiss due to React re-render detaching button — new bug filed
- **k3d-manager v1.4.6 acg-credentials handler-dismiss-waitfor SUPERSEDED** — `73660e6a`; superseded by nonblocking-250ms spec
- **k3d-manager v1.4.6 acg-credentials extend-not-cancel completed** — committed as `a07c3c10` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials handler animation settle completed** — committed as `0fbdba3079b8c1e183e8cb1b72fdbf1429a3f3ff` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials addLocatorHandler animation wait loop completed** — committed as `1026389cdbb4353ec4a4dba6b402f0ec5e9bcb88` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials Extend Modal addLocatorHandler completed** — committed as `4cbe3b7e26e41eee1a2e05897a75c1d030557ef8` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 frontend.shopping-cart.local automation completed** — committed as `e701139a17eb4acb19bb84976db5e4a14e795a8f` and pushed to `origin/k3d-manager-v1.4.6`
- Current branch: `k3d-manager-v1.4.6` (created from k3d-manager PR #74 merge SHA `8f93df25`)
- **k3d-manager v1.4.6 acg-credentials Extend Your Session modal fix completed** — committed as `69204c91e5e060df6e2ca230c1180d6055f1d91d` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials GCP reads AWS inputs fix completed** — committed as `1ba5c5ac66d5493cdfa8ca661c0372ca518c6882` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager PR #74 merged** — k3d-manager-v1.4.5 → main (SHA: `8f93df25`); ACG extend navigation fix + frontend SSO wiring; v1.4.6 branch created with retrospective
- **k3d-manager v1.4.6 acg-credentials "Extend Your Session" modal fix ASSIGNED** — spec: `docs/plans/v1.4.6-bugfix-acg-credentials-extend-session-modal.md`; apply first
- **k3d-manager v1.4.6 acg-credentials GCP reads AWS inputs fix ASSIGNED** — spec: `docs/plans/v1.4.6-bugfix-acg-credentials-gcp-reads-aws-inputs.md`; apply after extend-session-modal fix
- **k3d-manager v1.4.6 acg-credentials Session extended modal fix completed** — committed as `3444c171d4797e4cc305b4fc9c1bc707b6a9fb5c` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-credentials wrong sandbox provider fix completed** — committed as `5dfbdf44c2f3dce49e53f1e3f245b5c8e3a470fd` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 acg-extend Start Sandbox race fix completed** — committed as `bae89aafae42aeea7b7d71cd65eed4c24ca84962` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 auto-trust Vault CA fix completed** — committed as `42d9941306658c259f367916bc68ea69573a3085` and pushed to `origin/k3d-manager-v1.4.6`
- **k3d-manager v1.4.6 follow-up completed** — `scripts/lib/acg/playwright/acg_extend.js` commit `34c41ced492f37525f170feed6664156b5647634`; `bin/acg-up` final fix commit `0ea4cc9f89649a3a5ca7d8a2da4df4f6b39fb4b9` (interactive sudo + 120s listener timeout); both pushed to `origin/k3d-manager-v1.4.6`
- **shopping-cart-infra PR #58 merged** — shopping-cart-infra-v0.5.3 → main (SHA: `67f8d228`); ArgoCD SSO OIDC callback fix; v0.5.4 next branch created; retrospective added and pushed
- **shopping-cart-frontend PR #15 merged** — shopping-cart-frontend-v0.5.1 → main (SHA: `19e47118`); Keycloak SSO wiring (CI build-args + nginx CSP); v0.5.1 branch created with retrospective
- **shopping-cart-infra PR #57 merged** — shopping-cart-infra-v0.5.2 → main (SHA: `adbaec8`); networking + mTLS fixes; v0.5.3 branch created with retrospective
- **shopping-cart-infra PR #56 merged** — shopping-cart-infra-v0.5.1 → main (SHA: `79c42b7`); python3 → kcadm.sh bugfix + retrospective on v0.5.2
- **shopping-cart-infra PR #55 merged** — bug/keycloak-ldap-mappers-missing → main; v0.5.1 next branch created with retrospective
- **rigor-cli PR #10 merged** — rigor-cli-v0.1.6 → main; v0.1.6 tagged and released; v0.1.7 next branch created with retrospective
- Branch protection (`enforce_admins=true`) restored on all repos after merge
- v1.4.4, v1.4.3, and v1.4.2 remain shipped; branch protection was restored after each merge.

## Completed (v1.4.6 partial — lib-acg PR #12)
- [x] **lib-acg PR #12 merged** — feat/acg-multi-provider → main; exit 0 on stale "Session extended" toast at startup; SHA `8fe35fa1`
- [x] enforce_admins + required_approving_review_count=1 restored on lib-acg
- [x] feat/acg-gcp-credentials branch created from merge SHA
- [x] Retrospective: `docs/retro/2026-05-17-pr12-retrospective.md` (on lib-acg feat/acg-gcp-credentials, commit `0b9c224`)
- [x] k3d-manager memory-bank updated (activeContext.md + progress.md)

## Completed (v1.4.6 partial — lib-acg PR #11)
- [x] **lib-acg PR #11 merged** — fix/acg-credentials-extend-dialog → main; AWS credential extraction + dialog handling; SHA `feeb8e80`
- [x] enforce_admins restored on lib-acg (required_approving_review_count=1)
- [x] feat/acg-multi-provider branch created from merge SHA
- [x] Retrospective: `docs/retro/2026-05-17-pr11-retrospective.md` (on lib-acg feat/acg-multi-provider, commit `d2e3e48`)

## Completed (v1.4.5 partial — shopping-cart-frontend #15)
- [x] **shopping-cart-frontend PR #15 merged** — Keycloak SSO wiring (CI build-args + nginx CSP); SHA `19e47118`
- [x] enforce_admins restored on shopping-cart-frontend
- [x] v0.5.1 branch created from merge SHA
- [x] Retrospective: `docs/retro/2026-05-15-v0.5.1-retrospective.md` (on shopping-cart-frontend-v0.5.1, commit `60e660f`)

## Completed (v1.4.5 — k3d-manager PR #74)
- [x] **k3d-manager PR #74 merged** — merge SHA `8f93df25`; branch `k3d-manager-v1.4.5`; next branch `k3d-manager-v1.4.6` cut
- [x] enforce_admins restored on k3d-manager main
- [x] Retrospective: `docs/retro/2026-05-15-v1.4.5-retrospective.md` (on k3d-manager-v1.4.6, commit `b6b9f15e`)

## Completed (v1.4.5 partial — shopping-cart-infra #57)
- [x] **shopping-cart-infra PR #57 merged** — networking + mTLS fixes (appproject + keycloak-destinationrule); SHA `adbaec8`
- [x] enforce_admins restored on shopping-cart-infra
- [x] v0.5.3 branch created from merge SHA
- [x] Retrospective: `docs/retro/2026-05-15-v0.5.2-retrospective.md` (on shopping-cart-infra-v0.5.3)
- [x] Branch cleanup — deleted v0.4.0, v0.5.0, v0.5.2; retained v0.5.3

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
- [x] **multi-repo SSO wiring follow-up** — COMPLETE. `k3d-manager` ACG sandbox navigation fix: `3bb7aa817983948cd426bc6a96525a811b2bd7ff`; `shopping-cart-infra` SSO ingress/workflow update: `8c581840b904f21459fa225c80ddfe54f93ed9aa`; `shopping-cart-frontend` CI/CSP update: `6120783b8af124abebca7f242f5b905a29734836`; frontend issue-doc commit: `64c943e5b39ec1468c1de8f0a7e6768a1d4cb6b1`; frontend `main` reverted to `2872a4cd9b120b55673b0c2633ab8e6270cb6b8c` after an accidental remote update. Issue doc: `docs/issues/2026-05-15-frontend-main-push-reverted.md`.
- [x] **networking ArgoCD project + Keycloak mTLS fix** — COMPLETE (`6c70fee99baa2c2f29330113e4f1c96b2b94cf75`).
- [x] **ArgoCD SSO via Keycloak** — COMPLETE. shopping-cart-infra PR #38 + PR #39 merged to main. spec: `docs/plans/v1.4.5-argocd-sso-keycloak.md`
- [x] **pyjenkinsapi rigor-cli v0.1.6 subtree pull** — COMPLETE
- [x] **acg-up /etc/hosts --soft** — COMPLETE (`3c096f6`)
- [x] **acg-up Step 10e bugs** — COMPLETE (`d6a31c5`)
- [x] **eso-ldap-directory Vault policy missing keycloak/* paths** — COMPLETE (`48938dea`)
- [x] **shopping-cart-identity AppProject missing** — COMPLETE (`771ba5cf`)
- [x] **identity ESO bootstrap Bug 1** — COMPLETE (`f969b299`)
- [x] **identity ESO bootstrap Bugs 2+3** — shopping-cart-infra PR #40 merged (`dfe00df1`)
- [x] **identity ESO bootstrap Bugs 4+5** — shopping-cart-infra PR #41 merged (`180f5f89`)
- [x] **LDAP CrashLoopBackOff Bug 6** — PR #42 merged (`11aa8d7d`)
- [x] **LDAP CrashLoopBackOff Bug 7** — PR #43 merged (`dcd18af7`)
- [x] **deploy_eso unpinned chart version** — COMPLETE (`50851f0e`)
- [x] **Bug 8 — CoreDNS keycloak.shopping-cart.local → Keycloak ClusterIP** — `34e0101f`
- [x] **Bug 9 — acg-up frontend port-forward launchd agent** — `fb56a443`
- [x] **Bug 10 — acg-up ArgoCD localhost:8080 readiness gate**
- [x] **Bug 11 — acg-down keep-hub preservation trust gap**
- [x] **Bug 12 — acg-up missing Argo CD plugin source** — SHA: `6052786a`
- [x] **Bug 13 — acg-up PLUGINS_DIR unbound before plugin sourcing** — SHA: `5d4b9b1e`
- [x] **Bug 14 — Keycloak `argocd` client redirect reconciliation**
- [x] **Bug 15 — Argo CD port-forward flaps after sandbox rebuild** — commit `18f8d884`
- [x] **Keycloak admin token mismatch after rebuild**
- [x] **Argo CD canonical HTTPS hostname backed by Vault PKI listener**
- [x] **Argo CD browser TLS role creation uses parent-domain allowed_domains**
- [x] **Argo CD browser TLS role write authenticates to Vault before upserting**
- [x] **Argo CD browser TLS cleanup skips revoke when cert already gone** — `f2942bf9`
- [x] **Argo CD browser `launchctl` stderr visibility** — commit `8d18e18c`
- [x] **Argo CD browser `launchctl bootout` best-effort** — commit `8d18e18c`
- [x] **Stopped advertising localhost as browser entrypoint** — commit `b086aef2`
- [x] **Argo CD browser HTTPS preflight skips sudo when already healthy** — commit `d5be3d0e`
- [x] **Keycloak browser HTTP listener on localhost:80** — commit `bca8a30c`
- [x] **Argo CD port-forward context fallback** — commit `3f8d5150`
- [x] **Argo CD browser auto-open removed from bootstrap**
- [x] **Keycloak realm import is mandatory**
- [x] **Keycloak realm import status capture no longer concatenates fallback output**
- [x] **Keycloak readiness gate reports deployment availability instead of dead tunnel**
- [x] **Keycloak deployment NotFound readiness gate fix**
- [x] **Argo CD VirtualService host default moved to canonical browser URL**
- [x] **acg-up stale shopping-cart-infra realm JSON path fixed** — commit `c0566cb4`
- [x] **Identity troubleshooting helpers** — `bin/vault-exec`, `bin/ldap-search`, `bin/keycloak-logs`, `bin/ldap-logs`
- [x] **shopping-cart-infra v0.5.0 release** — tag `v0.5.0`, GitHub release created
- [x] **shopping-cart-infra various PRs** — #47, #48, #49, #51, #52, #53, #54 merged
