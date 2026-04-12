# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 SHIPPED** — merged to main (662878a), PR #37, 2026-03-21.
**v0.9.5 SHIPPED** — PR #38 squash-merged to main (`573c0ac`) 2026-03-21. Tagged v0.9.5, released.
**v0.9.6 SHIPPED** — PR #39 merged to main (`8b09d577`) 2026-03-22. Tagged v0.9.6, released.
**v0.9.7 SHIPPED** — PR #41 merged to main (`97249a6f`) 2026-03-22. Tagged v0.9.7, released.
**v0.9.8 SHIPPED** — PR #42 merged to main (`64525e3f`) 2026-03-22. if-count easy wins + dry-run doc/tests. No version tag (CHANGELOG [Unreleased]).
**v0.9.9 SHIPPED** — PR #43 merged to main (`c1043175`) 2026-03-22. Tagged v0.9.9, released. if-count allowlist: ldap (7) + vault (5) entries removed.
**v0.9.10 SHIPPED** — PR #44 merged to main (`877ec970`) 2026-03-22. Tagged v0.9.10, released. if-count allowlist: jenkins (4) entries removed; allowlist now system.sh only.
**v0.9.11 SHIPPED** — PR #45 merged to main (`1a0c913`) 2026-03-22. Tagged v0.9.11, released. Dynamic plugin CI: detect job + conditional stage2.
**v0.9.12 SHIPPED** — PR #47 merged to main (`f8014bc`) 2026-03-23. No version tag (CHANGE.md [Unreleased]). Copilot CLI CI integration + lib-foundation v0.3.6 subtree.
**v0.9.13 SHIPPED** — PR #48 merged to main (`c54fbe6`) 2026-03-23. Tagged v0.9.13, released. v0.9.12 retro + CHANGE.md backfill + mergeable_state process check.
**v0.9.14 SHIPPED** — PR #50 merged to main (`d317429b`) 2026-03-24. No version tag (CHANGE.md [Unreleased]). if-count allowlist fully cleared: _run_command + _ensure_node helpers extracted via lib-foundation PR #13.
**v0.9.15 SHIPPED** — PR #51 squash-merged to main (`484354da`) 2026-03-27. Tagged v0.9.15, released.
**v0.9.16 SHIPPED** — PR #51 squash-merged to main (`484354da`) 2026-03-27. Tagged v0.9.16, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-27-v0.9.16-retrospective.md`.
**v0.9.17 SHIPPED** — PR #52 merged (`c88ca7a`) 2026-03-28. Tagged v0.9.17, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.17-retrospective.md`. Branches v0.9.7–v0.9.17 deleted.
**v0.9.18 SHIPPED** — PR #53 merged (`7567a5c`) 2026-03-28. Tagged v0.9.18. Released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.18-retrospective.md`.
**v0.9.19 SHIPPED** — PR #54 merged (`0f13be1`) 2026-03-28. Tagged v0.9.19. Released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.19-retrospective.md`.
**v0.9.20 SHIPPED** — PR #55 merged to main (`bfd66fe`) 2026-03-29. Tagged v0.9.20, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v0.9.20-retrospective.md`.
**v0.9.21 SHIPPED** — PR #56 merged to main (`f98f2a8`) 2026-03-29. Tagged v0.9.21, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v0.9.21-retrospective.md`.
**v1.0.0 SHIPPED** — PR #57 merged to main (`807c0432`) 2026-03-29. Tagged v1.0.0, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v1.0.0-retrospective.md`.
**v1.0.1 SHIPPED** — PR #58 merged to main (`a8b6c583`) 2026-03-31. Tagged v1.0.1, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-31-v1.0.1-retrospective.md`.

---

## v1.0.3 — SHIPPED

**PR #60 merged to main (`91552139`) 2026-04-05. Tagged v1.0.3, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-05-v1.0.3-retrospective.md`.**

**v1.0.4 SHIPPED** — PR #61 merged to main (`bc9028fb`) 2026-04-10. Tagged v1.0.4, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-10-v1.0.4-retrospective.md`.

## v1.0.7 — Active (branch `k3d-manager-v1.0.7`)

Specs written 2026-04-11:

- [x] **CLUSTER_PROVIDER-aware Makefile (Option B)** — **COMPLETE** (`9d013bee`). `docs/plans/v1.0.7-makefile-provider-dispatch.md`; Makefile now defaults `CLUSTER_PROVIDER=k3s-aws`, wraps `make up`/`down`/`refresh`/`status`/`creds` in `case "$(CLUSTER_PROVIDER)"` dispatch, adds `k3s-gcp` credential extraction, and documents overrides in `make help`. Verified with `make --dry-run up`, `make --dry-run up CLUSTER_PROVIDER=k3s-gcp`, and `make --dry-run down CLUSTER_PROVIDER=k3d`.
- [x] **GCP provider skeleton** — **COMPLETE** (`1c620795`). `docs/plans/v1.0.7-gcp-provider.md`; added `scripts/plugins/gcp.sh`, `scripts/lib/providers/k3s-gcp.sh`, and `scripts/tests/providers/k3s_gcp.bats`. Deploy flow wraps `gcp_get_credentials` → `gcloud` compute → `k3sup` install → kubeconfig merge/label; destroy requires `--confirm`. `shellcheck -S warning` clean on both new shell files; `bats scripts/tests/providers/k3s_gcp.bats` passes.
- [ ] **GCP provider post-review bugfix** — `docs/plans/v1.0.7-bugfix-gcp-provider-fixes.md`; fixes: ubuntu image flags on instance create, k3sup `--local-path` + `--disable=traefik`, destroy kubeconfig cleanup, `gcp.sh` validate-before-export.
- [x] **Playwright `--provider` flag** — **COMPLETE** (`89664941`). Added `--provider` (default `aws`) to `scripts/playwright/acg_credentials.js`, split extraction into `_extractAwsCredentials` / `_extractGcpCredentials`, and implemented the confirmed GCP selectors + service account key writer. Verified CLI usage with `node scripts/playwright/acg_credentials.js` (error with no URL) and `node scripts/playwright/acg_credentials.js https://example.com` (defaults to AWS path before Chrome launch).

---

## v1.0.6 — SHIPPED

**PR #64 merged to main (`279db18c`) 2026-04-11. Tagged v1.0.6, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.6-retrospective.md`.**

- [x] **AWS SSM Support for k3s-aws** — **COMPLETE** (`8d35e2cb`). Added IAM role/profile and opt-in `K3S_AWS_SSM_ENABLED` flow so deploy/destroy can use `ssm_exec`/`ssm_tunnel`; introduced `scripts/plugins/ssm.sh` + tests. Spec: `docs/plans/v1.0.6-aws-ssm-support.md`.
- [x] **shopping-cart-order: bump rabbitmq-client to 1.0.1** — **MERGED** (PR #24, `7f0ea87e`) 2026-04-11. Bumped `rabbitmq-client` from `1.0.0-SNAPSHOT` to `1.0.1`; deleted `RabbitHealthConfig.java` + test (wrong bean name, NPE fix at source in `1.0.1`); 3 Copilot findings addressed (`412dd4a`): kustomization tag reverted to `latest`, stale CHANGELOG bullet removed, dangling word fixed. `enforce_admins` restored. Next branch: `docs/next-improvements`.
- [x] **shopping-cart-order: CI fix + docs catch-up** — **MERGED** (PR #25, `49ff6b87`) 2026-04-11. Fixed `trivy-action@0.30.0` → `@v0.35.0`; resolved docs/next-improvements divergence. 2 Copilot findings fixed. Branch protection updated: stale `"CI"` context → `Build & Test` + `Checkstyle`. `enforce_admins` restored. Next branch: `docs/next-improvements-2`. Retro: `docs/retro/2026-04-11-pr25-ci-fix-retrospective.md`. **`Build, Scan & Push` now unblocked — next main push builds Docker image with rabbitmq-client 1.0.1 to resolve order-service CrashLoopBackOff.**
- [x] **PR #64 MERGED** (`279db18c`) 2026-04-11. 6 Copilot findings fixed (`6fb423e5`). Retro: `docs/retro/2026-04-11-v1.0.6-retrospective.md`.

---

## v1.0.5 — SHIPPED

**PR #62 merged (`2a38bf84`) + fix-up PR #63 merged (`71c88b05`) 2026-04-11. Tagged v1.0.5 at `71c88b05`, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.5-retrospective.md`.**

- [x] **antigravity.sh refactor** — **COMPLETE** (`291a60dc`). `_acg_extend_playwright` moved into `acg.sh`, `acg_watch` + `_acg_watch_write_wrapper` now invoke it directly, `antigravity.sh` dropped the old helper, and dependent provider/tests were updated per `docs/plans/v1.0.5-antigravity-decouple.md`.
- [x] **rabbitmq-client-java NPE fix PR** — **COMPLETE**. PR #3 merged to main (`723eb7fc`) 2026-04-10. `enforce_admins` restored. Retro: `docs/retro/2026-04-10-npe-fix-retrospective.md`. Next branch: `docs/next-improvements`.
- [x] **rabbitmq-client-java v1.0.1 release** — **SHIPPED** (`295459c9`). PR #4 merged 2026-04-11. Tag `v1.0.1` pushed. GitHub Release created. JAR published to GitHub Packages (Publish job SUCCESS). `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.1-release-retrospective.md`.
- [x] **rabbitmq-client-java CI fix (PR #5)** — **MERGED** (`6268b08a`). Removes flaky vault apt install; curl API calls + vault image pinned to 1.15.6. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-ci-stabilization-retrospective.md`.
- [x] **rabbitmq-client-java CI fix (PR #6)** — **MERGED** (`22c92d96`). Wait for RabbitMQ management API; Docker service hostname `rabbitmq:15672` in Vault connection URI. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-ci-mgmt-api-wait-retrospective.md`. Integration Tests fully green on main.
- [x] **hardcoded password cleanup** — **MERGED**. k3d-manager `e5b77474`; shopping-cart-infra PR #31 (`39c30727`); shopping-cart-order PR #22 (`d5c7a097`); shopping-cart-product-catalog PR #18 (`30bb7723`). All 3 repos merged to main, `enforce_admins` restored. Spec: `docs/plans/v1.0.5-fix-hardcoded-passwords.md`.

## v1.0.4 — SHIPPED

## v1.0.3 — Complete

- [x] **acg_extend logic refinement** — **COMPLETE** (PR #61, `bc9028fb`). Button-first search, midnight date-wrap fix, ghost state guard tightened (`remainingMins !== null && remainingMins < 15`), CDP browser close scoped to launched contexts. Issues: `docs/issues/2026-04-08-acg-extend-midnight-and-modal-trapping.md`, `docs/issues/2026-04-08-acg-extend-stale-session-ghost-state.md`. Copilot PR #61 findings documented: `docs/issues/2026-04-10-copilot-pr61-review-findings.md`.
- [x] **acg_credentials URL mismatch fix** — **COMPLETE**. Standardized all Pluralsight URLs to `/hands-on/playground/` across `acg.sh` and `acg_credentials.js`. Commit `86883...`.
- [x] **acg_extend selector fix** — **COMPLETE**. Fixed `h4` false positive by sanitizing `extendSelectors`. Implemented robust "trapped UI" handling: script now forces a "Start/Resume" click if the extend button is missing. Commit `ae765f2d`.

- [x] **Chrome CDP launchd agent** — **COMPLETE**. `fe0f313` adds constants/helpers + `acg_chrome_cdp_install`/`acg_chrome_cdp_uninstall` + `make chrome-cdp`/`chrome-cdp-stop`. Platform detection fixed: `513009f` (`acg.sh`), `4ce2b51` (`antigravity.sh`). Spec: `docs/plans/v1.0.3-chrome-cdp-launchd.md`.

- [x] **acg-refresh skip creds fix** — **COMPLETE**. Commit `6dcb913` gates `bin/acg-refresh` credential extraction behind `_acg_check_credentials` so existing AWS creds skip Playwright, preventing Chrome CDP lock conflicts. Spec: `docs/plans/v1.0.3-fix-acg-refresh-skip-creds.md`.

- [x] **ESO version bump** — **COMPLETE**. Commit `216f6d5` sets the default ESO Helm chart version to 0.14.0 so remote installs expose `external-secrets.io/v1` required by shopping-cart-infra. Spec: `docs/plans/v1.0.3-fix-eso-version.md`.

- [x] **ArgoCD cluster server URL bugfix** — **COMPLETE**. Commit `dec667f` injects the ubuntu-k3s API server URL into `register_app_cluster` so ArgoCD registers the EC2 cluster endpoint instead of `host.k3d.internal`. Spec: `docs/plans/v1.0.3-bugfix-argocd-cluster-server-url.md`.

- [x] **ArgoCD register wrong context bugfix** — **COMPLETE**. Commit `5cbc3cf` switches kubectl to `k3d-k3d-cluster` before calling `register_app_cluster`, so the cluster secret is applied to the local ArgoCD cluster where the controller runs. Spec: `docs/plans/v1.0.3-bugfix-argocd-register-context.md`.

- [x] **Makefile argocd-registration target** — **COMPLETE**. Commit `7dfa093` adds `make argocd-registration` so users can re-register ubuntu-k3s with ArgoCD (Step 10 logic) after sandbox recreation or IP change. Spec: `docs/plans/v1.0.3-makefile-register-apps.md`.

- [x] **Makefile sync-apps target** — **COMPLETE**. Commit `a47a4f5` adds `bin/acg-sync-apps` + `make sync-apps` to port-forward argocd-server, log in, sync `cicd/data-layer`, and show remote pod status. Spec: `docs/plans/v1.0.3-makefile-sync-apps.md`.

- [x] **GHCR PAT masking** — **COMPLETE**. Commit `613bb1e` suppresses `make up` command echo so `GHCR_PAT` isn’t printed to the console. Spec: `docs/plans/v1.0.3-bugfix-ghcr-pat-mask.md`.

- [x] **ClusterSecretStore apiVersion bump** — **COMPLETE**. Commit `b8bcb89` switches the `bin/acg-up` ClusterSecretStore manifest to `external-secrets.io/v1` so ESO 1.0.0 accepts it. Spec: `docs/plans/v1.0.3-bugfix-css-apiversion.md`.

- [x] **Vault KV seeding** — **COMPLETE**. Commit `d11260d` seeds redis/postgres/payment static secrets in Vault KV so shopping-cart ExternalSecrets have data to sync. Spec: `docs/plans/v1.0.3-bugfix-vault-kv-seeding.md`.
- [x] **RabbitMQ Vault creds seeding** — **COMPLETE**. Commit `77e69e2` adds `rabbitmq/default` KV seeding so shopping-cart-infra can source RabbitMQ credentials from Vault. Spec: `docs/plans/v0.2.1-bugfix-rabbitmq-vault-creds.md`.
- [x] **shopping-cart-infra ESO storeRef/path fix** — **COMPLETE**. shopping-cart-infra commit `abb6aba` (branch `fix/eso-externalsecret-storeref`) switches ExternalSecrets to `ClusterSecretStore` and static KV paths matching the new Vault seeds. Spec: `shopping-cart-infra/docs/plans/bugfix-eso-externalsecret-storeref.md`.

- [x] **shopping-cart-infra App namespace ExternalSecrets** — **COMPLETE**. shopping-cart-infra commit `5cc6c86` adds four ExternalSecrets under `shopping-cart-apps` namespace mirroring redis/postgres Vault KV secrets for basket, order-service, and product-catalog. Spec: `shopping-cart-infra/docs/plans/v0.2.1-bugfix-app-namespace-secrets.md`.

- [x] **shopping-cart-infra ArgoCD sync waves + ddl-auto sandbox fix** — **COMPLETE**. shopping-cart-infra commit `3b8b13b` (branch `fix/argocd-sync-waves-ddl-auto`) adds the ExternalSecret Lua health check, sync-wave annotations (wave 0 for ExternalSecrets, wave 1 for StatefulSets), and ddl-auto=create ConfigMap patches for order-service/product-catalog. Spec: `shopping-cart-infra/docs/plans/v0.2.2-fix-argocd-sync-waves-ddl-auto.md`.

- [x] **shopping-cart-infra manifest cross-check CI** — **COMPLETE**. shopping-cart-infra commit `a37d8e1` (branch `docs/next-improvements`) adds `scripts/check-manifest-refs.sh`, wires it into `.pre-commit-config.yaml`, and extends `validate.yml` with the manifest-cross-check job + workflow-dispatched smoke test. Spec: `shopping-cart-infra/docs/plans/v0.3.0-ci-manifest-validation.md`.

- [x] **shopping-cart order-service Spring Rabbit health fix** — **MERGED**. shopping-cart-order PR #21 merged to main (`4872691`) 2026-04-06. `SPRING_RABBITMQ_HOST/PORT/VIRTUAL_HOST` added to `k8s/base/configmap.yaml`. `enforce_admins` restored. Next branch: `docs/next-improvements`.
- [x] **shopping-cart-infra order-service ExternalSecret update** — **MERGED**. shopping-cart-infra PR #30 merged to main (`eeb34d9`) 2026-04-06. `SPRING_RABBITMQ_USERNAME/PASSWORD` added to ExternalSecret. `enforce_admins` restored. Next branch: `docs/next-improvements`.

- [x] **ACG sandbox expired guidance** — **COMPLETE**. k3d-manager commit `bf569a80` expands `_acg_check_credentials` with the sandbox-expired path (start new sandbox → `acg_get_credentials` → `make up`) per `docs/plans/v1.0.4-bugfix-acg-up-sandbox-expired.md`.

- [x] **rabbitmq-client ConnectionManager stats fix** — **COMPLETE**. Commit `36ed860` (branch `fix/connection-manager-get-stats-npe`) guards `getCacheProperties()` so `/actuator/health` no longer throws before the first AMQP channel is opened. Spec: `rabbitmq-client-java/docs/plans/bugfix-connection-manager-get-stats-npe.md`.

- [x] **acg-up random password generation** — **COMPLETE**. k3d-manager commit `f709cb3c` swaps the hardcoded redis/postgres/rabbitmq passwords in `bin/acg-up` for per-run `openssl rand` secrets while leaving AES/payment placeholders untouched. Spec: `docs/plans/v1.0.4-bugfix-acg-up-random-passwords.md`.

- [x] **ESO version 1.0.0 bugfix** — **COMPLETE**. Commit `4dd1854` bumps the default `ESO_VERSION` in `bin/acg-up` to 1.0.0 so installed ESO serves `external-secrets.io/v1`. Spec: `docs/plans/v1.0.3-bugfix-eso-version-1.0.0.md`.

- [x] **ESO apiVersion fix** — **COMPLETE**. shopping-cart-infra commit `c34b690` updates all 8 `data-layer/secrets/*.yaml` manifests (ClusterSecretStore + ExternalSecrets) from `external-secrets.io/v1beta1` to `external-secrets.io/v1` so ArgoCD can sync against the remote cluster. Spec: `docs/plans/v1.0.3-fix-eso-api-version.md`; branch `docs/next-improvements`.

## v1.0.2 — Active

- [x] **Gemini blocker fixes verification** — Verified cluster rebuilding (after sandbox expiry), ESO CRD patching, and registry auth restore. 3 nodes Ready. Pods 5/5 transition from ImagePullBackOff to Running/CrashLoopBackOff (Vault dependency). Spec: `docs/plans/v1.0.2-gemini-fix-cluster-blockers.md`.
- [ ] **Vault Token transition** — **FAILED**. Successfully stored local Vault token as remote secret and applied `ClusterSecretStore`. Blocked by unstable `socat` bridge on remote server. See `docs/issues/2026-04-01-remote-vault-bridge-instability.md`.
- [x] **Codex: vault-bridge automation** — Spec `docs/plans/v1.0.2-bugfix-vault-bridge.md`; commits `1cccf01` (k3d-manager) / `450d008` (shopping-cart-infra). Automates socat systemd unit, creates K8s Endpoints + Service, and fixes ClusterSecretStore server address.
- [x] **projectBrief.md update** — reframed as multi-cloud framework; added Provider + Plugin System section; committed `199681c` by user.
- [ ] **bin/ SCRIPT_DIR fix** — ASSIGNED to Codex. All `bin/` entry points set `SCRIPT_DIR` to `bin/` instead of `scripts/`; plugins that source siblings via `${SCRIPT_DIR}/plugins/` break. Spec: `docs/plans/v1.0.2-fix-bin-script-dir.md`.
- [x] **`antigravity_acg_extend` fatal exit fix** — `_err` → `_info` + `return 1`; pre-flight extend failure is now non-fatal. Issue: `docs/issues/2026-04-03-antigravity-acg-extend-err-exits-process.md`.
- [ ] **bin/acg-up full stack automation** — ASSIGNED to Codex. Spec: `docs/plans/v1.0.2-fix-acg-up-full-stack.md`. Adds 8 missing steps (Vault port-forward, vault-bridge Service, argocd-manager SA, helm+ESO install, ClusterSecretStore, ArgoCD registration) + Makefile.
- [x] **e2e verification** — **PARTIAL**. Cluster up and `ClusterSecretStore` Ready. However, `data-layer` sync is blocked by `v1` vs `v1alpha1` ESO mismatch.
- [x] **Chrome launchPersistentContext refactor** — Spec `docs/plans/v1.0.4-chrome-playwright-refactor.md`; commit `f7f15c5` replaces CDP connect calls with `launchPersistentContext`, persists auth dir, renames `_antigravity_launch` → `_browser_launch`, and drops the pre-launch requirement from `antigravity_acg_extend`. Gemini live test pending.
- [x] **Playwright auth bootstrap detection** — Spec `docs/plans/v1.0.4-playwright-auth-bootstrap.md`; commit `ce4cff7` adds first-run detection with bootstrap instructions (`acg_credentials.js`) and prevents `acg_extend.js` from running until `acg_get_credentials` seeds the auth dir. Gemini live test pending.
- [x] **Playwright CDP session reuse** — Spec `docs/plans/v1.0.4-playwright-cdp-session-reuse.md`; commit `dd024ed` probes CDP on first run to reuse existing Pluralsight sessions before launching Chrome. Gemini live test pending.
- [x] **Playwright Start Sandbox detection** — Spec `docs/plans/v1.0.4-fix-start-sandbox-detection.md`; commit `517f697` checks credential values before skipping Start/Open flow and waits up to 60s for inputs to populate after starting the sandbox. Gemini live test pending.
- [x] **Playwright sandbox button race** — Spec `docs/plans/v1.0.4-fix-sandbox-button-race-condition.md`; commit `f5a9399` waits for sandbox cards to render before checking buttons and restores the conditional timeout. Gemini live test pending.
- [x] **bin/ SCRIPT_DIR fix** — Spec `docs/plans/v1.0.2-fix-bin-script-dir.md`; commit `29a8535` makes all bin entry points set `SCRIPT_DIR="${REPO_ROOT}/scripts"` so plugins resolve correctly.
- [x] **acg-up full stack automation** — Spec `docs/plans/v1.0.2-fix-acg-up-full-stack.md`; commit `e4b7527` adds Vault port-forward, ESO install, ArgoCD bootstrap/register, vault-token sync, ClusterSecretStore verification, and Makefile shortcuts; acg-down stops the port-forward.
- [x] **acg credentials CDP removal** — Spec `docs/plans/v1.0.3-remove-cdp-from-acg-credentials.md`; commit `ac260d0` removes the CDP probe from `acg_credentials.js` and the Chrome pre-check in `acg_get_credentials` so Playwright always launches Chrome with the persistent auth dir.
- [x] **Antigravity Chrome launch** — `_antigravity_launch` now opens Google Chrome with `--password-store=basic` and dedicated user data dir so CDP probe works without manual browser start. Spec: `docs/plans/v0.9.20-acg-automation-fixes.md`, commit `8dd9cbb`.
- [x] **`acg_credentials.js` SPA nav fix** — Script finds the Pluralsight tab, avoids hard `page.goto` when already on `app.pluralsight.com`, SPA-navigates when needed, waits for `aria-busy` to clear, and increases credential selector timeout to 60s. Commit `8dd9cbb`.
- [x] **Automation Verification** — Verified Chrome cold-start (flags/profile) and SPA navigation guard in `acg_credentials.js`. Logic confirmed via live verification.
- [x] **BATS coverage** — `scripts/tests/plugins/shopping_cart.bats` gained `_ensure_k3sup` success/failure tests; suite run via `bats scripts/tests/plugins/shopping_cart.bats` green.

---

## v0.9.19 — Shipped

- [x] **`acg_get_credentials` + `acg_import_credentials`** — commit `3970623` adds `_acg_write_credentials`, both public functions, docs updates, and 8 BATS tests per `docs/plans/v0.9.19-acg-get-credentials.md`
- [x] **Static Playwright script** — `scripts/playwright/acg_credentials.js` implemented + live-verified by Gemini against Pluralsight sandbox. `acg_get_credentials updated to call static script. Spec: `docs/plans/v0.9.19-acg-playwright-script.md`.
- [x] **Gemini: verify Playwright selectors** — `aws sts get-caller-identity` confirmed valid account ID; credentials written to `~/.aws/credentials`. Live-verified.
- [x] **Copilot PR #54 findings** — 9 findings addressed in `392dae5`: session token optional, playwright guard, null parent, chmod trace suppression, docs fixes, spec status, issue doc resolution, BATS AKIA test.
- [x] **GitGuardian false positive** — `.gitguardian.yaml` added to exclude `scripts/tests/` from scanning.
- [ ] **scratch/ cleanup** — `rm -rf scratch/*` — wipe stale Playwright artifacts at release cut

---

## v0.9.17 — Shipped

- [x] **`_antigravity_ensure_acg_session`** — Implemented in `scripts/plugins/antigravity.sh`; BATS coverage in `scripts/tests/lib/antigravity.bats`; verified via `env -i` BATS run.
- [x] **E2E live test: `_antigravity_ensure_acg_session`** — **COMPLETE**. Verified `gemini-2.5-flash` is used as first attempt. Fallback helper and nested agent fix (YOLO + workspace temp) verified working. ACG login logic verified via manual prompt. Spec: `docs/plans/v0.9.17-acg-session-e2e-test.md`.
- [x] **Pin gemini model to gemini-2.5-flash** — Gemini implemented in `scripts/plugins/antigravity.sh`; BATS tests pending Codex implementation. Spec: `docs/plans/v0.9.17-antigravity-model-flag.md`.
- [x] **Model fallback helper** — implemented (`d004bb3`), BATS added by Codex (`74d182d`). Spec: `docs/plans/v0.9.17-antigravity-model-fallback.md`.
- [x] **Nested agent fix** — Implemented `--approval-mode yolo` + workspace temp path in `scripts/plugins/antigravity.sh`; shellcheck clean; commit pushed (`978b215`). Spec: `docs/plans/v0.9.17-antigravity-nested-agent-fix.md`. Unblocks e2e retest.

---

## v0.9.15+v0.9.16 — Shipped

- [x] **Playwright Integration Documentation** — `docs/plans/playwright-gemini.md` created; defines high-level orchestration, MCP benefits, and cross-browser support strategy.
- [x] **Antigravity plugin rewrite** — commit `b2ba187` rewrites plugin to use gemini CLI + Playwright per `docs/plans/v0.9.15-antigravity-plugin-impl.md`
- [x] **Antigravity × Copilot coding agent validation** — Determinism verdict: **FAIL**. Automation blocked by auth isolation. Findings doc: `docs/issues/2026-03-24-antigravity-copilot-agent-validation.md`
- [x] **ldap-password-rotator vault kv put stdin fix** — commit `e91a662` implements stdin (`@-`) vault writes per `docs/plans/v0.9.15-ensure-copilot-cli.md`

---

## v0.9.16 — Planned

- [x] **antigravity.sh MCP refactor** — commit `45168cf` switches plugin to Antigravity IDE + Playwright MCP over CDP (`_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready`); spec: `docs/plans/v0.9.16-antigravity-plugin-mcp-refactor.md`
- [x] **antigravity.sh launch + session** — commit `e83d89d` adds `_antigravity_launch` (auto-start IDE) + `_antigravity_ensure_github_session` (CDP login + wait) per `docs/plans/v0.9.16-antigravity-launch-session.md`
- [x] **antigravity _curl probe fix** — commit `6b98902` updates `_antigravity_launch` to `_run_command --soft -- curl` per `docs/plans/v0.9.16-antigravity-curl-probe-fix.md`
- [x] **lib-foundation v0.3.13 subtree pull** — commit `dfcb590` pulls `_antigravity_browser_ready` probe fix (`e870c6d9`) into `scripts/lib/foundation/`
*(v0.9.16 scope complete — PR ready)*

---

## v0.9.19 — Active

- [x] **Static acg_credentials.js** — **COMPLETE**. Replaced Gemini-generated Playwright with static `scripts/playwright/acg_credentials.js`. Verified with live Pluralsight sandbox. commit `67a445c`. Spec: `docs/plans/v0.9.19-acg-playwright-script.md`.
- [ ] **scratch/ cleanup** — `rm -f scratch/*`; stale Playwright artifacts from v0.9.18 and earlier
- [ ] **ArgoCD Sync — `order-service` & `product-catalog`** — **FAILED**. Attempted sync on infra cluster; ArgoCD server logged in successfully but app cluster connection failed. Root cause: ACG sandbox credentials expired; SSH tunnel down. See `docs/issues/2026-03-28-argocd-sync-acg-credentials-expired.md`.

---

## v0.9.18 — Shipped

- [x] **Pluralsight URL fix** — commit `8f857ea` updates `_ACG_SANDBOX_URL`, `_antigravity_ensure_acg_session`, and docs to `app.pluralsight.com`; Gemini e2e verified; PR #53 merged `7567a5c`

---

## v0.9.17 — Completed

- [x] **`_antigravity_ensure_acg_session`** — Implemented in `scripts/plugins/antigravity.sh`; BATS coverage in `scripts/tests/lib/antigravity.bats`; verified via `env -i` BATS run.

---

## v0.9.12 — Completed

- [x] lib-foundation v0.3.6 subtree pull — `9a030bc` — `doc_hygiene.sh` + hooks now in subtree
- [x] `_ensure_copilot_cli` / `_ensure_node` / `_k3d_manager_copilot` — already implemented (pre-compaction); BATS tests present in `scripts/tests/lib/`
- [x] Roadmap update — **STALE**: current roadmap already correct; no changes needed
- [x] **Copilot CLI auth CI integration** — PR #47 (`f8014bc`): installs Copilot CLI in lint job, wires `COPILOT_GITHUB_TOKEN`/`K3DM_ENABLE_AI`/`K3DM_COPILOT_LIVE_TESTS` into BATS, adds live binary check; 2 Copilot findings fixed (`fbb9ba4`)

## v0.9.14 — Completed

- [x] GitHub PAT rotation — rotated 2026-03-23; new expiry 2026-04-22
- [x] **if-count: `_run_command` + `_ensure_node`** — commit `b9fcbf6` (lib-foundation feat/v0.3.7) extracts helpers; subtree pull `aec6673` copies `system.sh` + clears allowlist per spec `docs/plans/v0.9.14-if-count-system-sh.md`
- [x] **PR #50 merged** — `d317429b` 2026-03-24; Copilot findings addressed; retro `docs/retro/2026-03-24-v0.9.14-retrospective.md`; branch v0.9.15 cut

---

## v0.9.13 — Completed

- [x] v0.9.12 retrospective — `docs/retro/2026-03-23-v0.9.12-retrospective.md` (`3f19383`)
- [x] `/create-pr` skill — `mergeable_state` check in Post-creation Steps + "Dirty PR silently kills CI" failure mode
- [x] CHANGE.md — backfill `[v0.9.12]` entry; add `[v0.9.13]` section
- [x] README + docs/releases.md — add v0.9.13 release row; v0.9.9 moved to collapsible
- [x] Copilot PR #48 findings fixed (`d1972ca`) — stale `memory/` ref, `CHANGELOG`→`CHANGE.md`, stale branch header
- [x] v0.9.13 retrospective — `docs/retro/2026-03-23-v0.9.13-retrospective.md`

---

## v0.9.4 — Completed

- [x] README releases table — v0.9.3 added — `1e3a930`
- [x] lib-foundation v0.3.3 subtree pull — `7684266`
- [x] Multi-arch workflow pin — all 5 app repos merged to main 2026-03-18
- [x] ArgoCD cluster registration fix — manual cluster secret `cluster-ubuntu-k3s` with `insecure: true`
- [x] Missing `frontend` manifest — `argocd/applications/frontend.yaml` in shopping-cart-infra (PR #17)
- [x] Verify `ghcr-pull-secret` — present in `apps`, `data`, `payment` namespaces
- [x] Tag refresh for ARM64 images — `newTag: latest` in all 5 repos
- [x] Codex: kubeconfig merge automation — `6699ce8`
- [x] payment-service missing Secrets — PR #14 merged (9d9de98)
- [x] Fix `_run_command` non-interactive sudo failure — `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`
- [x] autossh tunnel plugin — `feat(tunnel): add autossh tunnel plugin with launchd boot persistence`
- [x] ArgoCD cluster registration automation — `register_app_cluster` + cluster-secret template
- [x] Smoke tests — `bin/smoke-test-cluster-health.sh`
- [x] Reduce replicas to 1 + remove HPAs — merged 2026-03-20
- [x] Fix frontend nginx CrashLoopBackOff — `65b354f` merged to main 2026-03-21; tagged v0.1.1
- [x] Gemini: rebuild Ubuntu k3s + E2E verification — `7d614bc`
- [x] Gemini: ArgoCD cluster registration + app sync — `7d614bc`
- [x] Force ArgoCD sync — order-service + product-catalog — verified
- [x] Gemini: deploy data layer to ubuntu-k3s — all Running in `shopping-cart-data`
- [x] Gemini: Fix PostgreSQL auth issues — patched `order-service` and `product-catalog` secrets
- [x] Gemini: Fix PostgreSQL schema mismatch — added columns to `orders` table
- [x] Gemini: Fix product-catalog health check — patched readiness probe path
- [x] Gemini: Fix NetworkPolicies — unblocked `payment-service` and local DNS
- [x] Codex: fix app manifests — PRs merged to main; order `d109004`, product-catalog `aa5de3c`, infra `1a5c34d`; tagged v0.1.1; `docs/next-improvements` branch created
- [x] Codex: fix frontend manifests — PR #11 CLOSED; Copilot P1 confirmed original port 8080 + /health was correct; root cause is resource exhaustion not manifest error; deferred to v1.0.0
- [x] Gemini: Re-enable ArgoCD auto-sync — all apps reconciled to `HEAD`
- [x] Codex: add deploy_app_cluster automation — commit `13c79b3` adds k3sup install + kubeconfig merge helper and BATS coverage

---

## v0.9.5 — Completed

- [x] **`deploy_app_cluster` via k3sup** — `k3sup install` on EC2 + kubeconfig merge + ArgoCD cluster registration; replaces manual Gemini rebuild; prerequisite for v1.0.0 multi-node extension
- [x] check_cluster_health.sh hardening — kubectl context pinning, API server retry loop, `kubectl wait` replacing `rollout status`
- [x] Retro: `docs/retro/2026-03-21-v0.9.5-retrospective.md`

---

## v0.9.6 — Shipped

**ACG plugin shipped + 9 Copilot findings resolved. PR #39 squash-merged `8b09d577` 2026-03-22. Tagged v0.9.6, released.**

- [x] **ACG plugin** — `scripts/plugins/acg.sh`: `acg_provision`, `acg_status`, `acg_extend`, `acg_teardown`; retire `bin/acg-sandbox.sh`; commit `37a6629`
- [x] **Copilot fixes** — 9 findings: exit safety (`--soft`), VPC idempotency, CIDR security, heredoc fix, test pattern; commits `7987453` + `75f3b0f` + `157d431`
- [x] **README + functions.md** — ACG plugin documented; v0.9.6 in releases table
- [x] **CHANGE.md** — v0.9.6 entry with Fixed + Documentation subsections
- [x] **Retrospective** — `docs/retro/2026-03-22-v0.9.6-retrospective.md`

---

## v0.9.7 — Shipped

**PR #41 merged to main (`97249a6f`) 2026-03-22. Tagged v0.9.7, released.**

### Tooling (done this session)
- [x] `/create-pr` skill — Copilot reply+resolve flow (Steps 4+5, 3 new failure modes)
- [x] `/post-merge` skill — branch cleanup step (Step 8, every 5 releases)
- [x] SSH config — persistent Keychain (`Host *` block); `lib-foundation` remote → SSH
- [x] Issue doc: `docs/issues/2026-03-21-frontend-readonly-filesystem-failure.md`
- [x] **README overhaul** — PR #40 merged (`de684fe7`); Plugins table (14), How-To by component, Issue Logs section, Releases 3+collapsible; `docs/releases.md` backfilled

### Code Quality / Architecture (carried from v0.9.6)
- [x] **Upstream local lib edits to lib-foundation** — commits `b60ddc6` (system.sh TTY fix) + `15f041a` (agent_rigor allowlist) on lib-foundation/feat/v0.3.4
- [x] **Sync scripts/lib/system.sh from lib-foundation** — commit `4c6e143` copies `b60ddc6`, `c216d45` adds bare-sudo allowlist so `_agent_audit` passes; tracked missing `scripts/tests/lib/system.bats` in `docs/issues/2026-03-22-missing-system-bats.md`
- [ ] **Reduce if-count allowlist** — v0.9.8 easy wins done (commit `9a4f795`); `docs/issues/2026-03-22-if-count-allowlist-deferred.md` tracks remaining 18 functions for v0.9.9+
- [x] **`bin/` script consistency** — commit `b0b76b3` makes `bin/smoke-test-cluster-health.sh` source system.sh + use `_kubectl`
- [x] **Relocate app-layer bug tracking** — filed as GitHub Issues: order #16, payment #16, product-catalog #16, frontend #12

### Secondary
- [x] **Safety gate audit** — commit `51a40b0` adds no-args guard to `deploy_cluster`; `deploy_k3d_cluster`/`deploy_k3s_cluster` inherit fix
- [x] **`--dry-run` / `-n` mode** — docs/tests added in commit `f1b4ca7` (README Safety Gates doc + `scripts/tests/lib/dry_run.bats`); implementation already shipped
- [x] **Reduce if-count allowlist (ldap)** — commit `ba6f3a9` extracts helpers so `_ldap_*` + `deploy_ldap`/`deploy_ad` drop under threshold; allowlist trimmed to vault/system entries only
- [x] **Reduce if-count allowlist (vault)** — commit `365846c` extracts deploy/HA helpers and guard clauses so 5 `vault.sh` functions drop ≤8 ifs; removed vault entries from the allowlist
- [x] **Reduce if-count allowlist (jenkins)** — commit `733123a` on k3d-manager-v0.9.10 — new helpers drop 4 `jenkins.sh` functions ≤8 ifs; allowlist entries removed
- [x] **GitHub PAT rotation** — rotated 2026-03-23; new expiry 2026-04-22

### Deferred to v1.0.0 (needs multi-node)
- [ ] All 5 pods Running — order-service (RabbitMQ), payment-service (memory), frontend (resource exhaustion)
- [ ] Re-enable `shopping-cart-e2e-tests` + Playwright E2E green
- [ ] Re-enable `enforce_admins` on shopping-cart-payment
- [ ] Service mesh — Istio full activation

---

## Roadmap

- **v0.9.6** — ACG plugin (`acg_provision`, `acg_extend`, `acg_teardown`) + LoadBalancer for ArgoCD/Keycloak/Jenkins; retire `bin/acg-sandbox.sh`
- **v1.0.0** — 3-node k3s via k3sup + Samba AD DC; `CLUSTER_PROVIDER=k3s-remote`; resolves resource exhaustion; frontend + e2e milestone gate
- **v1.1.0** — Full stack provisioning: `provision_full_stack` single command (k3s + Vault + ESO + Istio + ArgoCD)
- **v1.2.0** — k3dm-mcp (gate: v1.0.0 multi-node proven; k3d + k3s-remote = two backends)
- **v1.3.0** — Home lab: k3s on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope

---

## Known Bugs / Gaps

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer (to be filed as GitHub Issues in their repos — v0.9.5 task):**

| Item | Repo | Notes |
|---|---|---|
| frontend CrashLoopBackOff | shopping-cart-frontend | Root cause: resource exhaustion (t3.medium); deferred to v1.0.0 3-node cluster |
| order-service CrashLoopBackOff | shopping-cart-order | PostgreSQL OK; RabbitMQ `Connection refused` only remaining |
| payment-service Pending | shopping-cart-payment | Memory constraints on `t3.medium` |
| product-catalog Degraded | shopping-cart-product-catalog | Synced to `aa5de3c`; `RABBITMQ_USERNAME` ESO key mismatch |
