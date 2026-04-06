# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.0.4` (as of 2026-04-05)

**v1.0.3 SHIPPED** — PR #60 merged to main (`91552139`) 2026-04-05. Tagged v1.0.3, released. `enforce_admins` restored. Retro: `docs/retro/2026-04-05-v1.0.3-retrospective.md`.
**Next:** k3d-manager-v1.0.4 branch created. No specs yet.
**shopping-cart-infra v0.2.2 — ArgoCD sync waves + ddl-auto** — COMPLETE (`3b8b13b`). Branch `fix/argocd-sync-waves-ddl-auto` added the ExternalSecret Lua health check, sync-wave annotations, and ddl-auto=create ConfigMap patches so ArgoCD waits for ESO before StatefulSets and Hibernate recreates schemas on sandbox rebuilds. Spec: `shopping-cart-infra/docs/plans/v0.2.2-fix-argocd-sync-waves-ddl-auto.md`.
**shopping-cart-infra v0.3.0 — manifest cross-check CI** — COMPLETE (`a37d8e1`). Branch `docs/next-improvements` adds `scripts/check-manifest-refs.sh`, wires it into pre-commit + `validate.yml` (manifest-cross-check job + smoke-test workflow_dispatch gate) so secret/configmap key mismatches halt locally and in CI. Spec: `shopping-cart-infra/docs/plans/v0.3.0-ci-manifest-validation.md`.

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
