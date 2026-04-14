# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.0.7` (as of 2026-04-11)

**v1.0.6 SHIPPED** — PR #64 merged (`279db18c`) 2026-04-11. Tagged v1.0.6, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.6-retrospective.md`.

**v1.0.6 summary:** AWS SSM support — `ssm_wait`/`ssm_exec`/`ssm_tunnel` in new `scripts/plugins/ssm.sh`; `K3S_AWS_SSM_ENABLED` opt-in; IAM role + instance profile in CloudFormation; `--capabilities CAPABILITY_NAMED_IAM` fix; `make ssm`/`provision` targets; 6 Copilot findings fixed. `make up` smoke-tested end-to-end.

**v1.0.7 — GCP provider (`k3s-gcp`) + CLUSTER_PROVIDER-aware Makefile** — next milestone. Three specs written 2026-04-11:
- `docs/plans/v1.0.7-makefile-provider-dispatch.md` — Option B Makefile dispatch via `CLUSTER_PROVIDER`
- `docs/plans/v1.0.7-gcp-provider.md` — `k3s-gcp.sh` skeleton + `gcp.sh` stub via `gcloud` imperative CLI
- `docs/plans/v1.0.7-playwright-provider-flag.md` — `--provider aws|gcp` flag; `_extractGcpCredentials` stub (TBD pending sandbox UI inspection)

- **CLUSTER_PROVIDER-aware Makefile (Option B)** — COMPLETE (`9d013bee`). Added default `CLUSTER_PROVIDER=k3s-aws`, wrapped `up`/`down`/`refresh`/`status`/`creds` in provider dispatch cases, and documented overrides in `make help`. Verified with `make --dry-run up`, `make --dry-run up CLUSTER_PROVIDER=k3s-gcp`, and `make --dry-run down CLUSTER_PROVIDER=k3d` — the outputs show `bin/acg-up`, `deploy_cluster`, and `destroy_cluster` paths respectively.
- **Playwright `--provider` flag** — COMPLETE (`89664941`). `scripts/playwright/acg_credentials.js` now accepts `--provider aws|gcp`, defaults to AWS when omitted, splits credential extraction into `_extractAwsCredentials` and `_extractGcpCredentials`, and writes the GCP service-account JSON to `~/.local/share/k3d-manager/gcp-service-account.json`. Verified CLI usage with `node scripts/playwright/acg_credentials.js` (no args) and `node scripts/playwright/acg_credentials.js https://example.com` (defaults to AWS before Chrome launch).
- **GCP provider skeleton** — COMPLETE (`1c620795`). Added `scripts/plugins/gcp.sh`, provider entry `scripts/lib/providers/k3s-gcp.sh`, and `scripts/tests/providers/k3s_gcp.bats`. Deploy flow wraps `gcp_get_credentials` → `gcloud` instance create + firewall → `k3sup install` → kubeconfig merge/label; destroy requires `--confirm`. shellcheck clean (`-S warning` both new files); BATS suite passes.
- **GCP provider bugfixes** — COMPLETE (`d4e73a66`). `gcloud compute instances create` now pins Ubuntu 22.04 LTS image family/project; k3sup installs with `--local-path` and disables Traefik; external IP guard handles "None"/"null"; destroy cleanup removes kubeconfig context and file; `scripts/plugins/gcp.sh` validates Playwright output before exporting. shellcheck + BATS re-run.
- **GCP provider ensure gcloud** — COMPLETE (`13ec1f67`). Added `_ensure_gcloud` auto-installer in `scripts/plugins/gcp.sh`, wired `_provider_k3s_gcp_deploy_cluster` to call it, and expanded `scripts/tests/providers/k3s_gcp.bats` with `_ensure_gcloud` stubs + new tests covering installed/missing scenarios. `shellcheck` (gcp.sh + k3s-gcp.sh) and `bats scripts/tests/providers/k3s_gcp.bats` pass.
- **GCP provider ADC auth** — COMPLETE (`effa1982`). `scripts/lib/providers/k3s-gcp.sh` now sets `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` + `CLOUDSDK_CORE_PROJECT` and passes `--project` to all gcloud compute/firewall calls instead of `gcloud auth activate-service-account`. shellcheck + BATS re-run.
- **GCP provider ADC token** — COMPLETE (`153fc922`). Replaced the `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` block with an ADC access token flow (`gcloud auth application-default print-access-token`) and exports `CLOUDSDK_AUTH_ACCESS_TOKEN`; all gcloud commands remain project-scoped. shellcheck + BATS re-run.
- **GCP provider post-review bugfix** — COMPLETE (`d4e73a66`). Five issues fixed: Ubuntu 22.04 image pins, `--local-path`, `--disable=traefik`, destroy kubeconfig cleanup, `gcp.sh` validate-before-export.
- **GCP provider pre-flight compute check** — COMPLETE (`7360d96e`). `_gcp_preflight_check_compute` in `k3s-gcp.sh` probes `gcloud compute instances list --limit=1` before any instance work and fails fast with actionable guidance (SA email + IAM role to grant) instead of letting `gcloud compute create` fail deep in the flow.
- **`_ensure_gcloud`** — COMPLETE (`13ec1f67`). Auto-install `gcloud` CLI when missing; wired into `_provider_k3s_gcp_deploy_cluster`; BATS-tested.
- **GCP IAM + auth pivot** — COMPLETE (`8cd1156e`). Sandbox constraint: `setIamPolicy` blocked for console user at API level; IAM grant UI greyed out. Resolution: pivot to console user credentials for all `gcloud compute` ops. Console user has `StudentLabAdmin1/2/3` custom roles with full compute permissions (verified via `testIamPermissions`). Replaced ADC SA token block in `k3s-gcp.sh` with `gcp_login` call; simplified `_gcp_preflight_check_compute`; added `gcp_login` + `gcp_grant_compute_admin` to `gcp.sh`; 5 BATS tests pass.
- **GCP full stack spec** — COMPLETE (`1430b47e`). `docs/plans/v1.1.0-gcp-provision-full-stack.md`; `gcp_provision_stack` + `_gcp_seed_vault_kv` added to `scripts/plugins/gcp.sh`; Makefile `provision` target dispatches `k3s-gcp` to the new flow. `make --dry-run provision`/`CLUSTER_PROVIDER=k3s-gcp`, `shellcheck scripts/plugins/gcp.sh`, and `bats scripts/tests/providers/k3s_gcp.bats` pass.
- **GCP full stack bugfix** — COMPLETE (`3fd62f33`). `docs/bugs/v1.1.0-bugfix-gcp-provision-stack-ssm-vault.md`; Makefile `provision` now runs `ssm` only for AWS, and `scripts/plugins/vault.sh` handles optional `$1` so `deploy_vault` no longer fails under `set -u`.

**GCP sandbox UI confirmed 2026-04-11:** Same `input[aria-label="Copyable input"]` selector as AWS; three fields: Username, Password, Service Account Credentials (JSON). `project_id` parsed from JSON; `gcloud auth activate-service-account --key-file` is the auth path. All 3 specs are Codex-ready. Remaining unknowns (machine type, zone, SSH user) resolved on first live sandbox run.

**v1.0.5 SHIPPED** — PR #62 merged (`2a38bf84`) + fix-up PR #63 merged (`71c88b05`) 2026-04-11. Tagged v1.0.5 at `71c88b05`, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.5-retrospective.md`.

**shopping-cart-order PR #24 MERGED** (`7f0ea87e`) 2026-04-11. Bumped `rabbitmq-client` `1.0.0-SNAPSHOT` → `1.0.1`; deleted `RabbitHealthConfig.java` workaround; 3 Copilot findings addressed (`412dd4a`). `enforce_admins` restored.
**shopping-cart-order PR #25 MERGED** (`49ff6b87`) 2026-04-11. Fixed `trivy-action@0.30.0` → `@v0.35.0`; branch protection updated (stale `"CI"` context → `Build & Test` + `Checkstyle`). 2 Copilot findings fixed. `enforce_admins` restored. Next branch: `docs/next-improvements-2`. **`Build, Scan & Push` now unblocked on next main push — will build Docker image with rabbitmq-client 1.0.1 and ArgoCD auto-deploys to resolve order-service CrashLoopBackOff.**

**v1.0.5 summary:** antigravity decoupling (`_acg_extend_playwright` → `acg.sh`); LDAP Vault KV seeding in `bin/acg-up`; 13 Copilot findings fixed across 2 PRs; new process rule: wait for Copilot review entry before merging (`feedback_copilot_review_wait.md`).

---

## Previous Branch: `k3d-manager-v1.0.5` (as of 2026-04-10)

**v1.0.4 SHIPPED** — PR #61 merged to main (`bc9028fb`) 2026-04-10. Tagged v1.0.4, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-10-v1.0.4-retrospective.md`.

**Pending work for v1.0.5:**
- **rabbitmq-client-java NPE fix** — MERGED (`723eb7fc`) 2026-04-10. PR #3 merged to main. `enforce_admins` restored. Retro: `docs/retro/2026-04-10-npe-fix-retrospective.md`. Next branch: `docs/next-improvements`.

**Latest progress for v1.0.5:**
- **antigravity.sh refactor** — COMPLETE (`291a60dc`). `_acg_extend_playwright` now lives in `acg.sh`, `acg_watch` + `_acg_watch_write_wrapper` call it directly, `antigravity.sh` no longer exports `antigravity_acg_extend`, and dependent provider/tests were updated per `docs/plans/v1.0.5-antigravity-decouple.md` / `docs/issues/2026-04-06-acg-antigravity-false-dependency.md`.
- **hardcoded password cleanup** — MERGED. k3d-manager `e5b77474`; shopping-cart-infra PR #31 merged (`39c30727`); shopping-cart-order PR #22 merged (`d5c7a097`); shopping-cart-product-catalog PR #18 merged (`30bb7723`). `bin/acg-up` seeds LDAP credentials into Vault KV, postgres admin + LDAP Secrets moved to ExternalSecret manifests in shopping-cart-infra, app repos carry `CHANGE_ME` placeholders. Spec: `docs/plans/v1.0.5-fix-hardcoded-passwords.md` (Option A). `enforce_admins` restored on all 3 repos.

**v1.0.4 completed items:**
- acg-up random passwords — COMPLETE (`f709cb3c`)
- acg_extend hardening (button-first, midnight fix, ghost state, URL standardization) — COMPLETE (PR #61, `bc9028fb`)
- Copilot findings addressed — COMPLETE (`4f7f273d`): URL hostname check, credential leak removed, CDP browser close scoped, ghost state guard tightened
- ACG sandbox expired guidance — COMPLETE (`bf569a80`)

**shopping-cart-infra v0.2.2 — ArgoCD sync waves + ddl-auto** — COMPLETE (`3b8b13b`). Branch `fix/argocd-sync-waves-ddl-auto` added the ExternalSecret Lua health check, sync-wave annotations, and ddl-auto=create ConfigMap patches so ArgoCD waits for ESO before StatefulSets and Hibernate recreates schemas on sandbox rebuilds. Spec: `shopping-cart-infra/docs/plans/v0.2.2-fix-argocd-sync-waves-ddl-auto.md`.
**shopping-cart-infra v0.3.0 — manifest cross-check CI** — COMPLETE (`a37d8e1`). Branch `docs/next-improvements` adds `scripts/check-manifest-refs.sh`, wires it into pre-commit + `validate.yml` (manifest-cross-check job + smoke-test workflow_dispatch gate) so secret/configmap key mismatches halt locally and in CI. Spec: `shopping-cart-infra/docs/plans/v0.3.0-ci-manifest-validation.md`.
**shopping-cart-order v0.3.1 — Spring Rabbit health** — MERGED (PR #21, `4872691`, 2026-04-06). `SPRING_RABBITMQ_HOST/PORT/VIRTUAL_HOST` added to configmap. `enforce_admins` restored. Next branch: `docs/next-improvements`.
**shopping-cart-infra v0.3.1 — Spring Rabbit secrets** — MERGED (PR #30, `eeb34d9`, 2026-04-06). `SPRING_RABBITMQ_USERNAME/PASSWORD` added to ExternalSecret. `enforce_admins` restored. Next branch: `docs/next-improvements`.
**rabbitmq-client-java v1.0.1** — SHIPPED (`295459c9`). PR #4 merged 2026-04-11. Tag `v1.0.1` pushed. GitHub Release created. JAR published to GitHub Packages. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-v1.0.1-release-retrospective.md`. Next branch: `docs/next-improvements`.
**rabbitmq-client-java CI fix (PR #5)** — MERGED (`6268b08a`). Flaky vault apt install removed; curl API calls + vault image pinned to 1.15.6. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-ci-stabilization-retrospective.md`.
**rabbitmq-client-java CI fix (PR #6)** — MERGED (`22c92d96`). Wait for RabbitMQ management API (HTTP readiness check); use Docker service hostname `rabbitmq:15672` in Vault connection URI. `enforce_admins` restored. Retro: `docs/retro/2026-04-11-ci-mgmt-api-wait-retrospective.md`. Integration Tests now passing on main.

## Current Branch: `k3d-manager-v1.0.3` (as of 2026-04-03)

**v1.0.0 SHIPPED** — PR #57 merged to main (`807c0432`) 2026-03-29. Tagged v1.0.0, released. `enforce_admins` restored.
**v1.0.1 SHIPPED** — PR #58 merged to main (`a8b6c583`) 2026-03-31. Tagged v1.0.1, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-31-v1.0.1-retrospective.md`.
**v1.0.2 SHIPPED** — PR #59 merged to main (`1e6d35d`) 2026-04-03. Tagged v1.0.2, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-03-v1.0.2-retrospective.md`.
**v1.0.3 ACTIVE** — branch `k3d-manager-v1.0.3` cut from `1e6d35d` 2026-04-03.
**enforce_admins:** restored on main 2026-04-03.
**Branch cleanup:** v0.9.7–v0.9.17 deleted 2026-03-28; v1.0.0–v1.0.2 deleted 2026-04-03.
**docs archive:** pre-v1.0.3 plans + issues moved to `docs/plans/archive/` and `docs/issues/archive/` on v1.0.3 branch cut.

**Cold-run gate: PASSED (2026-04-03)** — `make up` from zero: 3 nodes Ready + ClusterSecretStore Ready. Commits: `96629e0` (ESO webhook wait), `e8b296b` (CSS poll 180s), `dc2c82d` (AWS creds check).
**ClusterSecretStore apiVersion bugfix** — SPECCED (2026-04-04). `bin/acg-up` step 9 uses `v1beta1` for ClusterSecretStore — ESO 1.0.0 dropped v1beta1. Bump to `v1`. Spec: `docs/plans/v1.0.3-bugfix-css-apiversion.md`. ASSIGNED to Codex.
**GHCR_PAT console leak bugfix** — SPECCED (2026-04-04). Makefile `up` target echoes `GHCR_PAT="ghp_xxx..."` to console. Fix: add `@` prefix. Spec: `docs/plans/v1.0.3-bugfix-ghcr-pat-mask.md`. ASSIGNED to Codex.
**ESO version 1.0.0 bugfix** — COMPLETE (`4dd1854`). `bin/acg-up` default `ESO_VERSION` now 1.0.0 so remote installs serve the GA `external-secrets.io/v1` API required by shopping-cart-infra manifests. Spec: `docs/plans/v1.0.3-bugfix-eso-version-1.0.0.md`.
**Makefile sync-apps target** — COMPLETE (`a47a4f5`). Added `bin/acg-sync-apps` (port-forward, argocd login, sync data-layer, pod status) and `make sync-apps` wrapper. Spec: `docs/plans/v1.0.3-makefile-sync-apps.md`.
**GHCR PAT masking** — COMPLETE (`613bb1e`). `make up` now echoes a neutral message and suppresses the GHCR_PAT command line so credentials stay off the console. Spec: `docs/plans/v1.0.3-bugfix-ghcr-pat-mask.md`.
**ClusterSecretStore apiVersion bump** — COMPLETE (`b8bcb89`). `bin/acg-up` now applies the ClusterSecretStore manifest with `external-secrets.io/v1` so ESO 1.0.0 accepts it. Spec: `docs/plans/v1.0.3-bugfix-css-apiversion.md`.
**Vault KV seeding** — COMPLETE (`d11260d`). `bin/acg-up` now seeds redis/postgres/payment static secrets in Vault KV so shopping-cart ExternalSecrets have values to sync. Spec: `docs/plans/v1.0.3-bugfix-vault-kv-seeding.md`.
**RabbitMQ Vault creds seeding** — COMPLETE (`77e69e2`). `bin/acg-up` now seeds `secret/data/rabbitmq/default` so RabbitMQ StatefulSet and app ExternalSecrets can pull credentials from Vault. Spec: `docs/plans/v0.2.1-bugfix-rabbitmq-vault-creds.md`.
**shopping-cart-infra ESO storeRef/path fix** — COMPLETE (`abb6aba`). Branch `fix/eso-externalsecret-storeref` switches ExternalSecrets to `ClusterSecretStore` and static KV paths to match the new Vault seeding. Spec: `shopping-cart-infra/docs/plans/bugfix-eso-externalsecret-storeref.md`.
**App namespace ExternalSecrets** — COMPLETE (`5cc6c86`). shopping-cart-infra branch `fix/app-namespace-secrets` adds four ExternalSecrets in `shopping-cart-apps` mirroring redis/postgres Vault KV secrets for basket, order, and product-catalog. Spec: `shopping-cart-infra/docs/plans/v0.2.1-bugfix-app-namespace-secrets.md`.
**ArgoCD register wrong context bugfix** — COMPLETE (`5cbc3cf`). `bin/acg-up` now reads the ubuntu-k3s server via name filter and switches kubectl to `k3d-k3d-cluster` before `register_app_cluster`, ensuring the cluster secret updates the local ArgoCD instance. Spec: `docs/plans/v1.0.3-bugfix-argocd-register-context.md`.
**Makefile argocd-registration target** — COMPLETE (`7dfa093`). Added `make argocd-registration` to rerun the Step 10 registration flow: grab ubuntu-k3s token, read server URL, switch to `k3d-k3d-cluster`, call `register_app_cluster`, and restart the ArgoCD controller. Spec: `docs/plans/v1.0.3-makefile-register-apps.md`.
**ArgoCD cluster server URL bugfix** — COMPLETE (`dec667f`). `bin/acg-up` now reads the EC2 kubeconfig server URL and passes it via `ARGOCD_APP_CLUSTER_SERVER` so ubuntu-k3s registers with its public API endpoint instead of `host.k3d.internal`. Spec: `docs/plans/v1.0.3-bugfix-argocd-cluster-server-url.md`.
**acg_extend selector fix** — COMPLETE (`e39efa4`). Extend button selectors updated to match the new Pluralsight UI which now uses a Modal with "Extend Session" and only appears at 1 hour remaining. Spec: `docs/plans/v1.0.3-fix-acg-extend-selectors.md`.
**ArgoCD re-registration** — COMPLETE (Gemini, 2026-04-04). Stale token replaced; apps syncing. Root cause of pod failures: ESO v1beta1 not served on remote cluster.
**ESO apiVersion fix** — MERGED (shopping-cart-infra PR #23, `0a38037`, 2026-04-04). ESO v1 manifests + validate CI + Copilot fixes merged to main. Retro: `docs/retro/2026-04-04-pr23-eso-apiversion-fix-retrospective.md`. `enforce_admins` restored.
**Remove CDP from `acg_credentials.js`** — ASSIGNED to Codex. Spec: `docs/plans/v1.0.3-remove-cdp-from-acg-credentials.md`. Drop `connectOverCDP` probe; always use `launchPersistentContext`; remove CDP pre-check in `acg.sh`.
**enforce_admins:** restored on main 2026-04-03.
**Branch cleanup:** v0.9.7–v0.9.17 deleted 2026-03-28; v1.0.0 deleted 2026-03-29.
**v0.9.15 scope:** Antigravity × GitHub Copilot coding agent validation — 3 runs, determinism verdict; spec `docs/plans/v0.9.15-antigravity-copilot-agent.md`. Antigravity plugin rewritten in `b2ba187` per `docs/plans/v0.9.15-antigravity-plugin-impl.md`. Also: ldap-password-rotator `vault kv put` stdin hardening — spec `docs/plans/v0.9.15-ensure-copilot-cli.md` (closes v0.6.2 security debt; `_ensure_copilot_cli`/`_k3d_manager_copilot`/`_ensure_node` already shipped in v0.9.12).

**vault-bridge bugfix specced:** `docs/plans/v1.0.2-bugfix-vault-bridge.md` — Codex to add `_setup_vault_bridge` in `shopping_cart.sh`, Endpoints step in `bin/acg-up`, fix ClusterSecretStore server address, add `vault-bridge-svc.yaml` in shopping-cart-infra.
- COMPLETE (`1cccf01` / `450d008`): socat systemd automation + Endpoints in k3d-manager; Service + ClusterSecretStore update in shopping-cart-infra.

**Chrome CDP launchd agent (v1.0.3):** COMPLETE (`513009f`). All platform detection bugs fixed (`_is_mac` → `uname Darwin` in `acg.sh` + `antigravity.sh`). Launchd agent active on port 9222. Spec: `docs/plans/v1.0.3-chrome-cdp-launchd.md`.
**acg-refresh skip creds fix (v1.0.3):** COMPLETE (`6dcb913`). `bin/acg-refresh` now checks `_acg_check_credentials` before extracting AWS creds, so Chrome CDP launchd agent continues running without Playwright lock conflicts. Spec: `docs/plans/v1.0.3-fix-acg-refresh-skip-creds.md`.
**ESO version bump (v1.0.3):** COMPLETE (`216f6d5`). `bin/acg-up` default `ESO_VERSION` now 0.14.0 (was 0.9.20) so remote installs serve `external-secrets.io/v1` to match shopping-cart-infra manifests. Spec: `docs/plans/v1.0.3-fix-eso-version.md`.

**Chrome Playwright refactor (early v1.0.4):** `docs/plans/v1.0.4-chrome-playwright-refactor.md` — COMPLETE (`f7f15c5`). `acg_credentials.js`/`acg_extend.js` now launch Chrome via Playwright `launchPersistentContext` with a persisted auth dir, `_antigravity_launch` renamed to `_browser_launch`, and `antigravity_acg_extend` no longer pre-launches Chrome.

**Playwright auth bootstrap (v1.0.4):** `docs/plans/v1.0.4-playwright-auth-bootstrap.md` — COMPLETE (`ce4cff7`). `acg_credentials.js` detects empty auth dir, prints bootstrap banner, and extends timeout to 300s; `acg_extend.js` fails fast with clear instructions to run `acg_get_credentials` first.

**Playwright CDP session reuse (v1.0.4):** `docs/plans/v1.0.4-playwright-cdp-session-reuse.md` — COMPLETE (`dd024ed`). First-run flow probes CDP for an existing Pluralsight session and reuses it before launching a new Chrome instance.
**Playwright Start Sandbox detection fix (v1.0.4):** `docs/plans/v1.0.4-fix-start-sandbox-detection.md` — COMPLETE (`517f697`). Credentials skip guard now checks populated values and waits up to 60s after Start/Open/Resume before extracting credentials.
**Playwright sandbox button race (v1.0.4):** `docs/plans/v1.0.4-fix-sandbox-button-race-condition.md` — COMPLETE (`f5a9399`). Waits for SPA cards to render before checking Start/Open/Resume buttons and restores conditional timeout.
**bin/ SCRIPT_DIR fix:** `docs/plans/v1.0.2-fix-bin-script-dir.md` — COMPLETE (`29a8535`). All `bin/acg-*` entry points now set `SCRIPT_DIR="${REPO_ROOT}/scripts"` so plugin sourcing works.
**bin/acg-up full stack automation:** `docs/plans/v1.0.2-fix-acg-up-full-stack.md` — COMPLETE (`e4b7527`). acg-up now performs Vault port-forward, vault-bridge Service, argocd-manager bootstrap, helm + ESO install, vault-token + ClusterSecretStore, ArgoCD registration, CSS verification, and Makefile shortcuts added; acg-down stops the port-forward.
**acg credentials CDP removal:** `docs/plans/v1.0.3-remove-cdp-from-acg-credentials.md` — COMPLETE (`ac260d0`). `acg_credentials.js` always uses `launchPersistentContext`, and `acg_get_credentials` no longer probes CDP or launches Chrome manually.
**ESO ExternalSecret storeRef + Vault KV seeding bugfix** — SPECCED (2026-04-05). Two split specs: (1) shopping-cart-infra `docs/plans/bugfix-eso-externalsecret-storeref.md` on branch `fix/eso-externalsecret-storeref` — fix `kind: SecretStore` → `ClusterSecretStore` + postgres paths to static KV; (2) k3d-manager `docs/plans/v1.0.3-bugfix-vault-kv-seeding.md` on `k3d-manager-v1.0.3` — seed Vault KV in `bin/acg-up`. ASSIGNED to Codex.

**bin/ SCRIPT_DIR fix:** ASSIGNED to Codex 2026-04-03. Spec: `docs/plans/v1.0.2-fix-bin-script-dir.md`. All `bin/` entry points (`acg-up`, `acg-refresh`, `acg-down`) set `SCRIPT_DIR` to `bin/` instead of `scripts/`; `acg.sh` guard fires false and tries `bin/plugins/aws.sh` — not found. Fix: compute REPO_ROOT first, then `SCRIPT_DIR="${REPO_ROOT}/scripts"`.

**`antigravity_acg_extend` fatal exit fix:** COMPLETE (`ed3a548`). `_err` replaced with `_info` + `return 1` so pre-flight extend failure is non-fatal. Issue: `docs/issues/2026-04-03-antigravity-acg-extend-err-exits-process.md`. Spec: `docs/plans/v1.0.2-fix-acg-extend-err.md`.

**bin/acg-up full stack automation:** ASSIGNED to Codex 2026-04-03. Spec: `docs/plans/v1.0.2-fix-acg-up-full-stack.md`. 3 files: `bin/acg-up` (8 new steps), `bin/acg-down` (Vault PF cleanup), `Makefile` (new). Sandbox deleted — e2e blocked until this lands.

**e2e verification:** blocked on Codex full stack spec. User runs `make up` to verify end-to-end.

---

## Roadmap Versioning Decision (2026-03-29)

| Version | Scope |
|---------|-------|
| v0.9.21 | `_ensure_k3sup` + `deploy_app_cluster` auto-install — SHIPPED `f98f2a8` |
| v1.0.0 | `k3s-aws` provider foundation — rename `k3s-remote` → `k3s-aws`; single-node deploy/destroy; SSH config auto-update |
| v1.0.1 | Multi-node: `acg_provision` × 3, k3sup join × 2, taints/labels |
| v1.0.2 | Full stack on 3 nodes: all 5 pods Running + E2E green |
| v1.0.3 | Service mesh: Istio fully activated + MetalLB + VirtualServices for all apps; GUI access via hostnames (`argocd.k3s.local`, `vault.k3s.local`, `keycloak.k3s.local`, `jenkins.k3s.local`) over SSH/Cloudflare tunnel |
| v1.0.4 | Samba AD DC plugin (`DIRECTORY_SERVICE_PROVIDER=activedirectory`) |
| v1.0.5 | GCP cloud provider (`k3s-gcp`) |
| v1.0.6 | Azure cloud provider (`k3s-azure`) |

`CLUSTER_PROVIDER` values: `k3s-aws` (AWS/ACG), `k3s-gcp` (GCP), `k3s-azure` (Azure) — symmetric naming across all three clouds.

**v1.0.3 GUI access gate:** service mesh must be fully functional (all 5 pods Running, Istio sidecar injection verified, mTLS active) before adding MetalLB + VirtualService layer.

## v1.0.0 — Spec Written (2026-03-29)

**Spec:** `docs/plans/v1.0.0-k3s-aws-provider.md` — assigned to Codex.

4 file changes:
1. `scripts/lib/provider.sh` — `provider_slug="${provider//-/_}"` so hyphenated `k3s-aws` maps to `_provider_k3s_aws_*` functions
2. `scripts/lib/core.sh` — add `k3s-aws` to `deploy_cluster` case statement; fix no-args guard to skip when `CLUSTER_PROVIDER` env is set
3. NEW `scripts/lib/providers/k3s-aws.sh` — `_provider_k3s_aws_deploy_cluster` + `_provider_k3s_aws_destroy_cluster`
4. NEW `scripts/tests/lib/k3s_aws_provider.bats` — 3 tests (--help, destroy without --confirm)

| Item | Status | Notes |
|---|---|---|
| **`_cluster_provider_call` slug guard** | **COMPLETE** | Hyphen providers map to `_provider_k3s_aws_*`; commit `4aba999`. |
| **`deploy_cluster` guard + case** | **COMPLETE** | Accepts `k3s-aws` and respects env-configured providers; commit `4aba999`. |
| **`scripts/lib/providers/k3s-aws.sh`** | **COMPLETE** | Wires `acg_provision` → `deploy_app_cluster` → `tunnel_start` + teardown helper; commit `4aba999`. |
| **`k3s_aws_provider.bats`** | **COMPLETE** | New suite validates help + `--confirm` gate; runs via `./scripts/k3d-manager test lib`; commit `4aba999`. |
| **BATS PATH fix** | **COMPLETE** | Jenkins auth cleanup suite prepends Homebrew bash so plugin sourcing works on macOS; commit `4aba999`. |
| **`aws_import_credentials` refactor** | **COMPLETE** | New `aws.sh` helper (CSV + quoted export) + acg alias/back-compat; commit `be7e997`. |
| **`acg_get_credentials` Antigravity source** | **COMPLETE** | `acg.sh` now sources `antigravity.sh` so helpers are always defined; commit `4357f90`. |
| **`deploy_app_cluster` IP resolve** | **COMPLETE** | Reads `HostName` from `~/.ssh/config` before falling back to alias; commit `51983d3`. |
| **`acg_watch` + pre-flight extend`** | **COMPLETE** | `acg_provision --recreate`, new `acg_watch`, and provider pre-flight extend/watch wiring; commit `51bdf3a`. |
| **`k3s-aws` multi-node deploy** | **COMPLETE** | `_acg_provision_agents`, `_k3sup_join_agent`, node labeling + tests; commit `0c89f4e`. |
| **Keypair + extend hotfix** | **COMPLETE** | Keypair import uses `--soft` + extend prompt forces `page.goto`; commit `4a57f44`. |
| **Gemini e2e smoke test (run 1)** | **COMPLETE** | Full lifecycle verified: `acg_get_credentials` → `deploy_cluster` → `get nodes` (Ready) → `destroy_cluster`. commit `4aba999`. |
| **Gemini e2e smoke test (run 2)** | **FAILED** | Blocked by `KeyPair` import conflict in `acg_provision`. Documented in `docs/issues/2026-03-29-acg-provision-keypair-import-fail.md`. |
| **Gemini e2e smoke test (run 3)** | **COMPLETE** | Verified hotfixes: Keypair import is idempotent (no error on duplicate); `antigravity_acg_extend` uses unconditional navigation. Full lifecycle confirmed functional. commit `df8f77f`. |
| **Gemini e2e smoke test (3-node)** | **COMPLETE** | Full 3-node lifecycle verified: `acg_get_credentials` → `deploy_cluster` (CloudFormation + 3 nodes Ready) → `destroy_cluster`. |
| **Gemini blocker fixes verification** | **COMPLETE** | Verified cluster rebuilding, ESO CRD patching, and registry auth restore. 3 nodes Ready. Pods 5/5 transition from ImagePullBackOff to Running/CrashLoopBackOff (Vault dependency). |
| **Vault Token transition** | **FAILED** | `ClusterSecretStore` applied with static Vault Token; still `False` due to unstable `socat` bridge on remote server. Documented in `docs/issues/2026-04-01-remote-vault-bridge-instability.md`. |

## v1.0.0 Design Decisions

- **`acg_get_credentials <sandbox-url>`** — new function; extracts AWS credentials from Pluralsight sandbox "Cloud Access" panel via Antigravity Playwright; writes to `~/.aws/credentials`; stdin paste (`pbpaste | acg_import_credentials`) as fallback. Must run before any `acg_provision` call. Single extract covers all 3 nodes (same sandbox session).

---

## Operational Notes

- **3-node Cluster Up:** Rebuilt via `acg_provision` (CloudFormation) + `k3sup install/join` after sandbox recreation.
**ArgoCD Registered:** App cluster `ubuntu-k3s` re-registered with fresh token (UID `9a98e65a...`). Sync restored.
**Remote Pod Investigation:** **FAILED** (2026-04-04). Pods are `CrashLoopBackOff` because the `data-layer` is missing.
**ESO apiVersion mismatch:** **FAILED** (2026-04-04). Even with `bin/acg-up` updated to `ESO_VERSION=0.14.0`, the live cluster remains on `v0.9.20`. Sync failed for `data-layer` because `v1` CRDs are missing.
**Vault connectivity:** `ClusterSecretStore` confirmed `Ready`. `ExternalSecrets` for apps are missing/stale due to sync failure.

- **vault-bridge bugfix specced:** `docs/plans/v1.0.2-bugfix-vault-bridge.md` — Codex to add `_setup_vault_bridge` in `shopping_cart.sh`, Endpoints step in `bin/acg-up`, fix ClusterSecretStore server address, add `vault-bridge-svc.yaml` in shopping-cart-infra.
- **ArgoCD app status:** basket `CrashLoopBackOff`, frontend `CrashLoopBackOff`, order `Running`, payment `Running`, product-catalog `Error`. All app pods reached remote execution phase.

---

## v1.1.0 — GCP Full Stack Provision (branch: `k3d-manager-v1.1.0`)

**Active branch:** `k3d-manager-v1.1.0`

### Completed

| Item | SHA | Notes |
|---|---|---|
| `_ensure_k3sup` auto-install helper | `c322e483` | Follows `_ensure_gcloud` pattern; brew → curl fallback |
| `_gcp_load_credentials` helper | `a7195034` | Caches SA key; skips Playwright if key valid on disk |
| SA key cache simplification | `5e7566b8` | Single condition: file exists + project_id valid |
| `gcp_login` + `gcp_grant_compute_admin` | `153fc922` | Three-tier gcloud auth; IAM grant helper |
| `gcp_provision_stack` spec | `2745e57b` | `docs/plans/v1.1.0-gcp-provision-full-stack.md` |
| `gcp_provision_stack` implementation | `1430b47e` | Codex; Makefile case dispatch + full 7-step stack |
| Bug spec: ssm prereq + vault unbound $1 | `04943cdd` | `docs/bugs/v1.1.0-bugfix-gcp-provision-stack-ssm-vault.md` |

### In Progress

| Item | Assignee | Spec |
|---|---|---|
| Fix `provision: ssm` unconditional prereq + `deploy_vault` bare `$1` | Codex | `docs/bugs/v1.1.0-bugfix-gcp-provision-stack-ssm-vault.md` |

### Pending
- **GCP IAM auto-grant** — HYBRID+ STRATEGY (`docs/plans/v1.1.0-gcp-iam-hybrid-plus.md`). Final strategy after exploring CLI and full-automation dead ends. Utilizes Chrome (now system default) with automated consent handling and surgical IAM binding via Playwright CDP latch-on. Secure stdin injection for credentials.
- Live smoke test: `make provision CLUSTER_PROVIDER=k3s-gcp GHCR_PAT=<pat>` against running GCP node
- **ESO deploy_eso bugfix** — COMPLETE (`320ae211`). `docs/bugs/v1.1.0-bugfix-eso-deploy-unbound-arg.md` — `deploy_eso` now guards `$1` with `${1:-}` so gcp_provision_stack can call it without args under `set -u`; shellcheck + BATS re-run.
- **Stale SA key bugfix** — ASSIGNED → Codex (`docs/bugs/v1.1.0-bugfix-gcp-stale-sa-key-project-probe.md`). New sandbox = new project ID; cached key causes pre-flight failure. Fix: probe project in `_gcp_load_credentials` before trusting cache.
- **SSH readiness probe bugfix** — COMPLETE (`de83535d`). `docs/bugs/v1.1.0-bugfix-gcp-ssh-readiness-probe.md`; `_provider_k3s_gcp_deploy_cluster` now polls `nc -z ${ip} 22` (10s backoff, 30 retries) after `_gcp_ssh_config_upsert` so `k3sup install` waits for SSH to come up.
- **Stale kubeconfig merge bugfix** — COMPLETE (`fb694ac6`). `docs/bugs/v1.1.0-bugfix-gcp-kubeconfig-stale-merge.md`; `_provider_k3s_gcp_deploy_cluster` now deletes the k3s-gcp context/cluster/user from `~/.kube/config` before merging so new k3sup credentials win after an IP change. Reran shellcheck + BATS.
- **k3s API server readiness probe** — COMPLETE (`afbcc44b`). Spec `docs/bugs/v1.1.0-bugfix-gcp-k3s-api-readiness-probe.md`; `_provider_k3s_gcp_deploy_cluster` now polls `nc -z ${external_ip} 6443` (10s backoff, 30 retries) between kubeconfig merge and `kubectl label` so labeling waits for the API server.
- **make provision depends on make up** — COMPLETE (`050160d9`). `docs/bugs/v1.1.0-bugfix-gcp-provision-depends-on-up.md`; Makefile now runs `$(MAKE) up CLUSTER_PROVIDER=...` before `gcp_provision_stack` so the cluster is guaranteed up before provisioning; BATS re-run.
- **deploy_argocd not loaded + invalid flag** — COMPLETE (`17d16e8c`). Spec `docs/bugs/v1.1.0-bugfix-gcp-deploy-argocd-not-loaded.md`. `gcp_provision_stack` now sources `argocd.sh` before calling `deploy_argocd`, removes the invalid `--skip-ldap` flag, and clears the EXIT trap so `rendered` is deleted immediately; `shellcheck scripts/plugins/gcp.sh` + `bats scripts/tests/providers/k3s_gcp.bats` pass.
- **ArgoCD rendered unbound EXIT trap bugfix** — COMPLETE (`17d16e8c`). Spec `docs/bugs/v1.1.0-bugfix-argocd-rendered-unbound-exit-trap.md`. Replaced RETURN trap with explicit `rm -f "$rendered"` + `trap - EXIT`; dangling EXIT trap no longer fires with unbound local after function returns.
- **ACG AWS functions wrong plugin** — COMPLETE (`b5f9754b`). 9 AWS-specific functions + constants moved from `acg.sh` to `aws.sh`; no circular dep since `acg.sh` already sources `aws.sh`.
- **GCP pre-flight stale project bug** — COMPLETE (`acfb0470`). `_gcp_load_credentials` probes cached project via `gcloud projects describe`; deletes key + re-extracts when sandbox changes.
- **GCP provider missing status command** — COMPLETE (`00b1b8c7`, `bf156657`). Added `_provider_k3s_gcp_status` plus top-level `status()` dispatcher so `make status CLUSTER_PROVIDER=k3s-gcp` runs gcloud describe + kubectl nodes/pods.
- **PLAN — `_kubectl` consistency sweep** — OPEN. Replace bare `kubectl` calls in runtime modules (scripts/lib/providers, scripts/plugins, scripts/lib system helpers) with `_kubectl`. Steps: 1) inventory hits via `rg -n '(?<!_)kubectl'` excluding bin/Makefile/docs; 2) refactor providers (k3s-aws/gcp) + high-traffic plugins (acg, vault, argocd, jenkins, shopping_cart) in batches with shellcheck+tests; 3) sweep shared libs; 4) add `_agent_audit` lint to block future raw usage. docs/plans entry TBD (check plan-count limit first).
