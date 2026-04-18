# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.1.0`

Earlier branch/milestone context through `v1.0.7` is archived in `memory-bank/archive/activeContext-pre-v1.1.0.md`.

## v1.1.0 — GCP Full Stack Provision (branch: `k3d-manager-v1.1.0`)

**Active branch:** `k3d-manager-v1.1.0`

### Completed

| Item | SHA | Notes |
|---|---|---|
| `_ensure_k3sup` auto-install helper | `c322e483` | Follows `_ensure_gcloud` pattern; brew → curl fallback |
| `_gcp_load_credentials` helper | `a7195034` | Caches SA key; skips Playwright if key valid on disk |
| SA key cache simplification | `5e7566b8` | Single condition: file exists + project_id valid |
| `gcp_login` cleanup | `840ae84c` | Removed dead `gcp_grant_compute_admin`; `cloud_user` already has sufficient permissions |
| `gcp_provision_stack` spec | `2745e57b` | `docs/plans/v1.1.0-gcp-provision-full-stack.md` |
| `gcp_provision_stack` implementation | `1430b47e` | Codex; Makefile case dispatch + full 7-step stack |
| Bug spec: ssm prereq + vault unbound $1 | `04943cdd` | COMPLETE — both fixes already in code (Makefile + vault.sh) |
| Makefile GCP up-target spec | `ae747192`, `a1f9fc25` | COMPLETE — `Makefile` now runs `deploy_cluster && gcp_provision_stack` from `make up CLUSTER_PROVIDER=k3s-gcp`; `make sync-apps CLUSTER_PROVIDER=k3s-gcp` now calls `register_shopping_cart_apps` for AWS parity |

### In Progress

| Item | Assignee | Spec |
|---|---|---|
| Remove dead `gcp_grant_compute_admin` | COMPLETE (`840ae84c`) | `docs/bugs/v1.1.0-bugfix-remove-gcp-grant-compute-admin.md` |
| Automate `gcp_login` via Playwright | COMPLETE (`70c80354`) | `docs/bugs/v1.1.0-bugfix-gcp-login-playwright.md`; `gcp_login` now runs `gcloud auth login --no-launch-browser` and delegates OAuth consent to `scripts/playwright/gcp_login.js` |
| Fix `gcp_login` FIFO deadlock | COMPLETE (`9d8fca41`) | `docs/bugs/v1.1.0-bugfix-gcp-login-fifo-deadlock.md`; opens FIFO write end before spawning gcloud and logs raw gcloud output on URL extraction failure |
| Separate GCP app registration into `make sync-apps` | COMPLETE (`a1f9fc25`) | `docs/bugs/v1.1.0-bugfix-gcp-sync-apps-separation.md`; `gcp_provision_stack` no longer registers apps and `Makefile` `sync-apps` now delegates to `register_shopping_cart_apps` |
| Fix `sync-apps` k3s-gcp KUBECONFIG | COMPLETE (`fbbcf742`) | `docs/bugs/v1.1.0-bugfix-sync-apps-kubeconfig.md`; `Makefile` now exports `KUBECONFIG=$HOME/.kube/k3s-gcp.yaml` when `sync-apps` targets GCP |
| Scope sandbox button clicks to provider card | COMPLETE (`0bab1ba4`) | `docs/bugs/v1.1.0-bugfix-acg-credentials-provider-card-scope.md`; `acg_credentials.js` now scopes Start/Open/Resume buttons to the active provider card before clicking |
| Check Open Sandbox before Start Sandbox | COMPLETE (`c463a942`) | `docs/bugs/v1.1.0-bugfix-acg-credentials-button-priority.md`; `acg_credentials.js` now prefers `Open Sandbox` before `Start Sandbox` to avoid disabled AWS button clicks when GCP is active |
| Use `data-heap-id` for sandbox button selection | COMPLETE (`132421ad`) | `docs/bugs/v1.1.0-bugfix-acg-credentials-heap-id-selector.md`; `acg_credentials.js` now selects Start/Open/Resume buttons by provider-specific `data-heap-id` instead of brittle card text matching |
| Extract GCP credentials via `getByLabel` | COMPLETE (`6bb2bbcf`) | `docs/bugs/v1.1.0-bugfix-gcp-credential-extraction.md`; `_extractGcpCredentials` now waits on `text=Username` and reads Username/Password/Service Account fields via `page.getByLabel(...)` |
| Extract GCP credentials by position | COMPLETE (`8e34610e`) | `docs/bugs/v1.1.0-bugfix-gcp-credential-extraction-v2.md`; `_extractGcpCredentials` now reads `input[aria-label="Copyable input"]` by position because GCP panel labels are not HTML-associated |
| Wait for DOM after "Use another account" | REGRESSION (`c7930b93` — post-click `waitForLoadState` still races) | `docs/bugs/v1.1.0-bugfix-gcp-login-email-input-timeout.md`; fix did not work — `waitForLoadState` resolves against already-loaded page, misses navigation |
| Guard "Use another account" navigation with `Promise.all` | REGRESSION (`1bcee5fd`) | No navigation event fires — Google account chooser is a SPA; `waitForNavigation` always times out |
| Treat "Use another account" as SPA transition | REGRESSION (`886bc24b`) | Still times out — root cause: `div:has-text` matches container div, click lands on wrong element |
| `gcp_login` wrong click target for "Use another account" | COMPLETE (`6178c6a0`) | `docs/bugs/v1.1.0-bugfix-gcp-login-use-another-locator.md`; fix accidentally bundled into docs commit; email fills confirmed in live test |
| `gcp_login` Allow button timeout — unhandled post-password screens | COMPLETE (`8ea4310b`) | `docs/bugs/v1.1.0-bugfix-gcp-login-allow-button-timeout.md`; `gcp_login.js` now logs URLs after password/before Allow, handles Skip/Not now/Confirm prompts, and waits up to 30s for Allow |
| `gcp_login` Allow button not found on ifWebSignIn | COMPLETE (`6a46fdab`) | `docs/bugs/v1.1.0-bugfix-gcp-login-allow-button-not-found.md`; `gcp_login.js` now logs visible buttons, tries broader Allow label variants, and dumps page body text on timeout |
| Make password step optional when session already authenticated | COMPLETE (`0fbb516a`) | `docs/bugs/v1.1.0-bugfix-gcp-login-password-step-optional.md`; `gcp_login.js` now checks `passwordInput.isVisible({ timeout: 5000 })` and skips password entry when Google session cookies are already active |
| Handle second account chooser before Allow | COMPLETE (`39e2a05f`) | `docs/bugs/v1.1.0-bugfix-gcp-login-second-account-chooser.md`; `gcp_login.js` now clicks the inline `div[data-identifier]` account picker on `signin/oauth/id` before waiting for Allow |
| Force-click second account chooser | COMPLETE (`84e6d556`) | `docs/bugs/v1.1.0-bugfix-gcp-login-second-chooser-force-click.md`; `gcp_login.js` now uses `click({ force: true })` and a 2s settle wait to bypass overlay interception on the inline account picker |
| Add late account chooser check before Allow | COMPLETE (`eccdf4c3`) | `docs/bugs/v1.1.0-bugfix-gcp-login-late-account-chooser.md`; `gcp_login.js` now performs a second `div[data-identifier]` chooser pass immediately before waiting for Allow, including a post-chooser Continue handler |
| Replace Allow wait with polling loop | COMPLETE (`2914082d`) | `docs/bugs/v1.1.0-bugfix-gcp-login-allow-loop-account-chooser.md`; `gcp_login.js` now polls for both AccountChooser and Allow during the 30s window, recovering when AccountChooser appears mid-wait |
| Extend Allow deadline + handle empty-session AccountChooser re-login | COMPLETE (`3f15ec90`) | `docs/bugs/v1.1.0-bugfix-gcp-login-pw-log-and-empty-session.md` (Change 2 only); `gcp_login.js` now extends the Allow loop to 60s and re-enters the email/password flow when AccountChooser appears without any account rows |
| Revoke stale gcloud auth on sandbox rotation + guard status describe | COMPLETE (`b28b8925`) | `docs/bugs/v1.1.0-bugfix-gcp-stale-auth-invalid-grant.md`; `_gcp_load_credentials` now revokes stale auth before re-extraction and `_provider_k3s_gcp_status` skips `gcloud compute instances describe` when no active account exists |
| Use print-access-token to validate gcloud auth in status describe guard | COMPLETE (`e9749112`) | `docs/bugs/v1.1.0-bugfix-gcp-status-token-validity-check.md`; `_provider_k3s_gcp_status` now probes `gcloud auth print-access-token` instead of trusting `gcloud auth list`, suppressing stale deleted-account `invalid_grant` errors |
| Return early in status on stale creds + soften kubectl exits | COMPLETE (`c39fa0a3`) | `docs/bugs/v1.1.0-bugfix-gcp-status-stale-kubectl-timeout.md`; `_provider_k3s_gcp_status` now exits immediately on stale auth and treats kubectl status queries as informational (`|| true`) while the BATS stub returns a dummy access token |
| `make up` GCP runs full stack — should be cluster only | OPEN | `docs/bugs/v1.1.0-bugfix-makefile-gcp-up-provision-split.md`; assigned to Codex |
| Fix AccountChooser URL case + post-email chooser handler | COMPLETE (`504bf9ab`) | `docs/bugs/v1.1.0-bugfix-gcp-login-accountchooser-case-and-post-email.md`; `gcp_login.js` now uses a lowercase `accountchooser` URL check and handles the redirect-to-chooser path immediately after the initial email Next click |
| Handle "I understand" inside Allow polling loop | COMPLETE (`b78a1dfe`) | `docs/bugs/v1.1.0-bugfix-gcp-login-i-understand-in-poll-loop.md`; `gcp_login.js` now re-checks the welcome-screen `I understand` prompt during the Allow loop and waits 2000ms after password Next |
| Move Playwright log to `logs/` + 7-day retention | COMPLETE (`2aed4d4a`) | `docs/bugs/v1.1.0-bugfix-gcp-login-log-dir-and-retention.md`; `gcp.sh` now writes timestamped logs to `~/.local/share/k3d-manager/logs/gcp_login_pw_<ts>.log`; prunes files older than `GCP_LOG_RETENTION_DAYS` (default 7); Claude applied directly |
| Continue not clicked after second chooser — consent page blocks Allow | COMPLETE (`e71f302b`) | `docs/bugs/v1.1.0-bugfix-gcp-login-continue-after-second-chooser.md`; post-chooser Continue handler added inside secondChooserVisible block |
| `gcloud auth login` exit 1 — auth log deleted before error check | COMPLETE (`3569a718`) | `docs/bugs/v1.1.0-bugfix-gcp-login-gcloud-exit-diagnostics.md`; `rm -f` moved after exit check; gcloud output logged on failure |
| Auth code extracted from `<code>` HTML element instead of URL | COMPLETE (`e646714f`) | gcp_login.js now extracts code from URL query param (`?code=...`) first; `<code>` tag dropped (matches gcloud command snippets, not the auth code) |

| Persistent Playwright log (`gcp.sh`) | COMPLETE (`982de6b8`) | Playwright stderr teed to `~/.local/share/k3d-manager/gcp_login_pw.log`; Claude applied directly |
| Use print-access-token to validate gcloud auth in status describe guard | COMPLETE (`e9749112`) | `docs/bugs/v1.1.0-bugfix-gcp-status-token-validity-check.md`; `_provider_k3s_gcp_status` now probes `gcloud auth print-access-token` instead of trusting `gcloud auth list`, suppressing stale deleted-account `invalid_grant` errors |


### Pending
- **GCP IAM auto-grant** — SUPERSEDED. `cloud_user` already has sufficient compute permissions; no IAM grant step needed. `gcp_grant_compute_admin` and all Playwright IAM automation dropped from v1.1.0 scope. Plan archived in `docs/plans/v1.1.0-gcp-iam-hybrid-plus.md` with SUPERSEDED notice.
- Live smoke test: `make up CLUSTER_PROVIDER=k3s-gcp GHCR_PAT=<pat>` against running GCP node
- **ESO deploy_eso bugfix** — COMPLETE (`320ae211`). `docs/bugs/v1.1.0-bugfix-eso-deploy-unbound-arg.md` — `deploy_eso` now guards `$1` with `${1:-}` so gcp_provision_stack can call it without args under `set -u`; shellcheck + BATS re-run.
- **Stale SA key bugfix** — COMPLETE (`acfb0470`). `_gcp_load_credentials` probes cached project via `gcloud projects describe`; deletes key + re-extracts on new sandbox.
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
- **PLAN — GCP IAM Hybrid+** — UPDATED (`docs/plans/v1.1.0-gcp-iam-hybrid-plus.md`). Plan now documents CDP port bootstrap, identity guard selectors, IAM UI steps, fallback exit codes, and verification gates so Gemini automation doesn’t misfire.
- **GCP topology parity gap** — OPEN (`docs/bugs/2026-04-13-gcp-single-node-topology-mismatch.md`). `k3s-gcp` provisions one node instead of the standard 3-node cluster shape used by AWS; provider should match server + 2 agents.
- **Provider Make lifecycle inconsistency** — ASSIGNED (`docs/bugs/v1.1.0-bugfix-makefile-gcp-up-provision-split.md`). `make up` for GCP runs full stack instead of cluster only; spec written, assigned to Codex.
- **Provider SSH alias inconsistency** — OPEN (`docs/bugs/2026-04-13-provider-ssh-alias-inconsistency.md`). SSH aliases should be standardized across providers (`ubuntu-tunnel`, `ubuntu-1`, `ubuntu-2`) with dynamic IP refresh.
- **GCP Playwright login auth URL extraction bug** — OPEN (`docs/issues/2026-04-17-gcp-login-auth-url-extraction-failure.md`). `gcp_login` starts `gcloud auth login --no-launch-browser` but the current grep only matches `https://accounts.google.com...`; no auth URL is extracted, so Playwright never runs.
