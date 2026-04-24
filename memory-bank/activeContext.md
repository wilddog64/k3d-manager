# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.1.0` (as of 2026-04-20)

Renamed from `recovery-v1.1.0-aws-first` (2026-04-20). Old `k3d-manager-v1.1.0` (the messy branch)
preserved as `k3d-manager-v1.1.0-backup` on remote.

**v1.1.0 goal** — Unified ACG automation for AWS + GCP. Core provisioning logic is in place;
live E2E still needs a clean smoke test after the CLUSTER_NAME default fix.

## Completed (v1.1.0 Recovery)

| Task | Commit | Summary |
|---|---|---|
| Shared playwright vars | `3de58f4d` | `vars.sh` reconciled; sourced from `acg.sh` |
| Robot engine unification | `a986d5bb` | `acg_credentials.js`: CDP disconnect, `--provider` flag, IPv4, patient sign-in |
| GCP identity bridge | `9686e5c3` | `gcp.sh` plugin, `gcp_login.js` OAuth automation, `bin/acg-up` provider dispatch, core allowlist |
| Documentation alignment | `7f3bd0a6` | README + howto guides aligned to 127.0.0.1/vars.sh |
| GCP cluster provisioning | `c65f0c90` | Firewall, GCE instance, k3sup, timeout fix (300s) |
| GCP latch-on hardening | `e45d9a04` | `gcp_login.js` hardened with "Agree and continue" + "Confirm" buttons |
| Clean-slate login | `6ae2a6c3` | Logout + explicit email/password to unblock OAuth callback |
| CLUSTER_NAME default fix | `3a3806aa` | `core.sh` now falls back to `k3d-cluster` when `CLUSTER_NAME` is empty |
| Polite tab selection | `131dca33` | Hardened `acg_credentials.js` to avoid hijacking user's active page (RCA 1) |

## Latest Task: CLUSTER_NAME empty-string fix

**Status:** COMPLETE — spec: `docs/bugs/2026-04-20-k3d-cluster-name-empty-blocker.md`
**File:** `scripts/lib/core.sh` line 796
**Fix:** `${CLUSTER_NAME:-}` → `${CLUSTER_NAME:-k3d-cluster}`
**Commit:** `3a3806aa`
**Smoke test:** `make up` reached `bin/acg-up` but stopped on Chrome CDP startup (`docs/issues/2026-04-21-cluster-name-smoke-test-blocked-by-cdp.md`). User reports this path should start CDP in the background and use `~/.local/share/k3d-manager/profile/`.

## Latest Task: CDP Linux headless launch + profile path unification

**Status:** COMPLETE — spec: `docs/bugs/2026-04-21-cdp-linux-headless-launch-failure.md`
**Files:** `antigravity.sh`, `vars.sh`, `acg_credentials.js`, `acg_extend.js`, `gcp.bats`
**Fix:** Add `--headless=new --no-sandbox --disable-dev-shm-usage` to Linux Chrome launch; rename profile dir from `playwright-auth` → `profile` across all five files
**Commit:** `1ab14ebf`
**Validation:** D1/D2/D3 completed locally; D4 live `make up` on ACG sandbox remains pending user validation.

## Latest Task: ACG repo extraction plan

**Status:** PLANNED — `docs/plans/v1.1.0-acg-extraction-repo-split.md`
**Commit:** `8639592c`
**PR:** `N/A`
**Why:** Shared browser/CDP code is destabilizing AWS while GCP evolves.
**Direction:** Extract ACG automation into its own repo, test browser automation there, keep `k3d-manager` focused on orchestration.

## Latest Batch: 5 bugs specced 2026-04-24

| Bug | Spec | Action |
|-----|------|--------|
| acg-sync-apps app not found | `docs/bugs/2026-04-24-acg-sync-apps-argocd-app-not-found.md` | COMPLETE (`eaaf9a9e`) |
| acg-sync-apps port-forward hidden failure | `docs/bugs/2026-04-24-acg-sync-apps-port-forward-hidden-failure.md` | COMPLETE (`3bd96955`) |
| acg-sync-apps local port 8080 collision | `docs/bugs/2026-04-24-acg-sync-apps-local-port-8080-collision.md` | COMPLETE (`3a1e2554`) |
| acg-sync-apps port-forward reuse | `docs/bugs/2026-04-24-acg-sync-apps-port-forward-reuse.md` | OPEN |
| acg-extend isPanelOpen false positive | `docs/bugs/2026-04-24-acg-extend-ispanelopen-false-positive.md` | COMPLETE (`79b87e36`) |
| Vault preflight after sleep | `docs/bugs/2026-04-23-acg-up-vault-state-preflight-gap-after-mac-sleep.md` | COMPLETE (`e577579e`) |
| acg-down provider dispatch + GCP teardown | `docs/bugs/2026-04-24-acg-down-provider-dispatch-gcp-teardown.md` | COMPLETE (`706e0ba2`) |
| acg-credentials Open Sandbox provider-blind | `docs/bugs/2026-04-24-acg-credentials-open-sandbox-provider-blind.md` | DEFERRED to lib-acg |

2026-04-24 implementation batch complete for Bugs 1–4; Bug 5 remains deferred to lib-acg extraction.

## New Bug: acg-down credential check noise (2026-04-24)

**Status:** COMPLETE (`07ca18a6`) — spec: `docs/bugs/2026-04-24-acg-down-credential-check-noise.md`
**File:** `bin/acg-down` lines 49–51
**Fix:** Pre-check `aws sts get-caller-identity` silently before calling `acg_teardown`; skip with single clean `_info` when invalid. Eliminates ERROR-level noise that makes expired vs live-but-stale indistinguishable.
**Supersedes:** `ae2fca66` approach (catch-after-fail) — this fixes the noise problem that approach left behind.

## Prev Bug: acg-down expired credentials abort (2026-04-24)

**Status:** COMPLETE (`07ca18a6`) — spec: `docs/bugs/2026-04-24-acg-down-expired-credentials-abort.md`
**File:** `bin/acg-down` line 50
**Fix:** `acg_teardown --confirm` → `acg_teardown --confirm || _info "[acg-down] CloudFormation teardown failed — credentials may have expired (sandbox already removed). Continuing local cleanup."`
**Why:** Expired sandbox TTL causes `_acg_check_credentials` to return 1, aborting the script before Vault PF kill + k3d Hub delete run. Follow-up `07ca18a6` keeps the cleanup behavior and suppresses credential ERROR noise with a silent pre-check.

## New Bug: acg-up Step 3.5 aborts instead of creating missing Hub cluster (2026-04-24)

**Status:** COMPLETE (`73382eb2`) — spec: `docs/bugs/2026-04-24-acg-up-hub-cluster-not-created.md`
**File:** `bin/acg-up` lines 104–105
**Fix:** Replace `_err` (abort) with `deploy_cluster --provider k3d` — auto-create the Hub cluster when missing. Keep the `kubectl get nodes` unreachable check as the true OrbStack-broken guard.
**Why:** `make down` deletes the Hub cluster; `make up` never creates it (Step 2 provisions remote k3s-aws only). `make down → make up` always fails at Step 3.5.

## New Bug: k3d-provider EXIT trap leak (2026-04-24)

**Status:** COMPLETE (`258de0d1`) — spec: `docs/bugs/2026-04-24-k3d-provider-exit-trap-leak.md`
**File:** `scripts/lib/providers/k3d.sh` line 100
**Fix:** `trap '...' EXIT` → `trap '...' RETURN` in `_provider_k3d_configure_istio`
**Why:** EXIT trap registers on the caller shell; when `deploy_cluster --provider k3d` is called inline from `bin/acg-up` (Step 3.5, `73382eb2`), the trap fires on acg-up exit with `$istio_yamlfile` out of scope → unbound variable under `set -u`.

## New Bug: k3d-provider RETURN trap scope (2026-04-24)

**Status:** COMPLETE (`e6a9ec91`) — spec: `docs/bugs/2026-04-24-k3d-provider-return-trap-scope.md`
**File:** `scripts/lib/providers/k3d.sh` lines 100 and 142
**Fix:** Prepend `trap - RETURN;` inside both RETURN trap handlers — self-clears trap on first fire, preventing re-fire in parent functions where local variables are out of scope.
**Why:** Bash RETURN traps are shell-global, not function-scoped. After `_provider_k3d_configure_istio` returns, its trap re-fires when `_provider_k3d_deploy_cluster` returns, with `$istio_yamlfile` out of scope → unbound variable.

## New Bug: acg-up Step 4 fails on fresh Hub — no Vault/LDAP/ArgoCD (2026-04-24)

**Status:** COMPLETE (`c59f2c3a`) — spec: `docs/bugs/2026-04-24-acg-up-hub-cluster-bootstrap.md`
**File:** `bin/acg-up` lines 102–124
**Fix:** Add `_hub_newly_created` flag in Step 3.5; add Step 3.6 that runs `deploy_vault` then `deploy_argocd` via subprocess when Hub was just created.
**Why:** `make down` deletes the Hub cluster; Step 3.5 re-creates it but never bootstraps workloads; Step 4 `kubectl port-forward svc/vault -n secrets` fails because `secrets` ns doesn't exist on fresh Hub.
**Key constraint:** Call `deploy_vault` (no `--confirm`) via `"${REPO_ROOT}/scripts/k3d-manager"` subprocess — `--confirm` is not a recognized flag in `_vault_parse_deploy_opts`.

## New Bug: deploy_argocd hardcodes `ldap` namespace — always fails LDAP check (2026-04-24)

**Status:** COMPLETE (`032bfadb`) — spec: `docs/bugs/2026-04-24-argocd-ldap-namespace-hardcoded.md`
**File:** `scripts/plugins/argocd.sh` line 87
**Fix:** `_kubectl get ns ldap` → `_kubectl get ns "${LDAP_NAMESPACE:-ldap}"`
**Why:** `LDAP_NAMESPACE` defaults to `identity` (not `ldap`). `deploy_argocd` now checks `ns "${LDAP_NAMESPACE:-ldap}"`, matching the configured LDAP namespace and avoiding the direct `deploy_ldap --confirm` failure path when LDAP already exists in `identity`.

## New Bug: deploy_argocd does not source LDAP vars before namespace check (2026-04-24)

**Status:** COMPLETE (`1c3ead28`) — spec: `docs/bugs/2026-04-24-argocd-ldap-vars-not-sourced.md`; PR: N/A
**File:** `scripts/plugins/argocd.sh`
**Fix:** `argocd.sh` now sources `scripts/etc/ldap/vars.sh` before dependency checks and uses `_kubectl --no-exit` for Vault/LDAP namespace probes.
**Why:** The prior namespace fix used `LDAP_NAMESPACE`, but `argocd.sh` did not source LDAP vars in the `deploy_argocd` subprocess. `LDAP_NAMESPACE` was unset, so the dependency check fell back to `ldap` while LDAP was deployed to `identity`; `_kubectl` then exited during the dependency probe.
**Validation:** Live `./scripts/k3d-manager deploy_argocd --confirm` passed the dependency phase, installed ArgoCD, and exited 0. `_agent_lint` and `_agent_audit` passed. Current shellcheck and BATS still show the pre-existing ArgoCD help/bootstrap findings tracked in `docs/issues/2026-04-24-argocd-verification-preexisting-failures.md`. The earlier non-blocking EOF issue is now resolved by the plaintext-login fix below.

## New Bug: deploy_eso returns before webhook endpoints are ready (2026-04-24)

**Status:** COMPLETE (`e7b06b2b`) — spec: `docs/bugs/2026-04-24-eso-webhook-readiness-race.md`; PR: N/A
**File:** `scripts/plugins/eso.sh`
**Fix:** `deploy_eso` now waits for `external-secrets`, `external-secrets-webhook`, and `external-secrets-cert-controller` rollouts, then waits for `external-secrets-webhook` endpoints before returning. The already-installed fast path also verifies readiness.
**Why:** `deploy_vault` installs ESO and previously returned after only the main `external-secrets` deployment was ready. Fresh Hub Step 3.6 then ran `deploy_ldap`, which applied ExternalSecret resources while `external-secrets-webhook` could still lack endpoints, causing Kubernetes admission to fail with `no endpoints available for service "external-secrets-webhook"`.
**Validation:** `shellcheck -x scripts/plugins/eso.sh`, `bats scripts/tests/plugins/eso.bats`, `_agent_lint`, `_agent_audit`, and live `./scripts/k3d-manager deploy_eso --confirm` passed. Full `./scripts/k3d-manager test all` still has the known ArgoCD help-test failure tracked in `docs/issues/2026-04-24-argocd-verification-preexisting-failures.md`.

## New Bug: ArgoCD CLI login plaintext prompt blocks bootstrap (2026-04-24)

**Status:** COMPLETE (`fdbef8c4`) — spec: `docs/bugs/2026-04-24-argocd-cli-login-plaintext-prompt.md`
**File:** `scripts/plugins/argocd.sh`
**Fix:** `_argocd_ensure_logged_in()` now uses `--plaintext --skip-test-tls` and closes stdin with `</dev/null`.
**Why:** `_argocd_ensure_logged_in()` forwards Argo CD to `localhost:8080` via a plaintext `kubectl port-forward`, then calls `argocd login` non-interactively. The CLI printed `WARNING: server is not configured with TLS. Proceed (y/n)?` and then hit EOF, which stalled bootstrap.
**Validation:** Focused `_argocd_ensure_logged_in` test passes, and live `./scripts/k3d-manager deploy_argocd --confirm` now runs past the login step and completes bootstrap.

## New Bug: Step 3.6 deploy_argocd fails — deploy_ldap called directly with --confirm (2026-04-24)

**Status:** COMPLETE (`c650f032`) — spec: `docs/bugs/2026-04-24-acg-up-hub-bootstrap-ldap-missing.md`
**File:** `bin/acg-up` line 119 (add before deploy_argocd)
**Fix:** Add `"${REPO_ROOT}/scripts/k3d-manager" deploy_ldap --confirm` between deploy_vault and deploy_argocd in Step 3.6.
**Why:** `deploy_argocd` calls `deploy_ldap --confirm` directly when `ldap` ns missing; `_ldap_parse_deploy_opts` hits `_err "[ldap] unknown option: --confirm"`. Pre-deploying LDAP via dispatcher ensures namespace exists → argocd skips the direct call.

## New Bug: Step 3.6 deploy_vault/deploy_argocd hit dispatcher safety gate (2026-04-24)

**Status:** COMPLETE (`8b43122f`) — spec: `docs/bugs/2026-04-24-acg-up-hub-bootstrap-safety-gate.md`
**File:** `bin/acg-up` lines 118–119
**Fix:** Add `--confirm` to both dispatcher calls: `deploy_vault --confirm` and `deploy_argocd --confirm`.
**Why:** `scripts/k3d-manager` dispatcher requires `--confirm` or explicit options; `--confirm` is consumed/stripped by dispatcher so vault.sh never sees it.

## Open Items
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Local Hub orchestration is fragmented: `acg-up` assumes ArgoCD infrastructure, bootstrap remains separate, and local ArgoCD access still requires manual port-forward setup.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up` does not clearly summarize local Hub vs remote app-cluster readiness and does not guide optional local runtime startup.
- **ACG Extraction Boundary** — OPEN (`docs/bugs/2026-04-23-acg-extraction-boundary-gemini-coupling.md`). The `acg_*` interaction surface still keeps Gemini/browser automation coupled to `k3d-manager`; that subsystem should move out as one extraction unit.
- **Teardown State Drift** — COMPLETE (`docs/bugs/2026-04-23-acg-down-full-teardown-spec.md`). Implemented in `3fd6f4d6`; `acg-down` now tears down the local Hub by default and supports `--keep-hub` as the explicit opt-out.
- **acg-up Hub bootstrap LDAP missing** — COMPLETE (`c650f032`). `acg-up` Step 3.6 now pre-deploys LDAP through the dispatcher before ArgoCD, so `deploy_argocd` no longer falls into its direct `deploy_ldap --confirm` path on a fresh Hub.
- **acg-sync-apps + acg-status dual-cluster** — COMPLETE (`docs/bugs/2026-04-23-acg-sync-apps-and-acg-status-dual-cluster.md`). Implemented in `a5422141`; `acg-sync-apps` now polls port-forward readiness and uses configurable `ARGOCD_APP`, and `acg-status` now shows Hub cluster nodes + pods before tunnel status.
- **k3d-provider EXIT trap leak** — COMPLETE (`258de0d1`). `_provider_k3d_configure_istio` now uses a `RETURN` trap for temp file cleanup, preventing the trap from leaking into long-running caller shells like `bin/acg-up`.
- **acg-up Hub cluster bootstrap** — COMPLETE (`c59f2c3a`). `acg-up` now bootstraps Vault and ArgoCD on a freshly created Hub cluster before attempting the Vault port-forward path, so `make down → make up` no longer fails on missing `secrets` resources.
- **acg-up Hub bootstrap safety gate** — COMPLETE (`8b43122f`). `acg-up` Step 3.6 now passes `--confirm` through the dispatcher for both Hub bootstrap calls, satisfying the deploy safety gate without forwarding that flag into the underlying plugin parsers.
- **k3d-provider RETURN trap scope** — COMPLETE (`e6a9ec91`). Both k3d provider RETURN trap handlers now self-clear on first fire, preventing repeated cleanup execution in parent functions after inline `deploy_cluster --provider k3d` calls.
- **Vault Preflight After Sleep** — COMPLETE (`e577579e`). `acg-up` now verifies the local Hub cluster before Vault PF startup and fails early if Vault is sealed or unreachable after OrbStack restart / Mac sleep.
- **acg-up Hub cluster auto-create** — COMPLETE (`73382eb2`). `acg-up` now recreates the local Hub cluster during Step 3.5 when it was legitimately removed by `make down`, while keeping the unreachable-cluster check as the real OrbStack guard.
- **acg-down expired credentials abort** — COMPLETE (`07ca18a6`). `acg-down` now silently pre-checks AWS credentials, skips CloudFormation teardown with a clean INFO when the sandbox already expired, and still completes local Vault PF + Hub cleanup.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and accumulated historical docs are now a larger maintenance/size concern than Memory Bank itself.
- **Vault Sync Mismatch** — CRITICAL BLOCKER (`docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md`). Vault storage state and cached unseal material can still drift apart; current automatic recovery is not sufficient for every local failure state.
- **Vault Resilience Gap** — OPEN (`docs/bugs/2026-04-20-vault-readiness-gate-missing.md`, `docs/bugs/2026-04-22-vault-orphaned-port-forward-ghost-blocker.md`). `acg-up` can fail at Vault seeding because Vault is sealed after Mac sleep or because a ghost port-forward on `8200` routes to a dead pod.
- **macOS CDP Direct Launch** — OPEN (`docs/bugs/2026-04-21-cdp-macos-direct-launch-gcp-ensure-cdp.md`). macOS `open -a` can reuse an existing Chrome instance and fail to apply CDP flags; fix must stay aligned with the shared CDP ownership model.
- **GCP Login Linux Headless OAuth** — COMPLETE (`927cb452`). `gcp.sh` OS-split captures OAuth URL from gcloud output; `gcp_login.js` navigates directly via `GCP_AUTH_URL` on Linux. Shellcheck fix committed (unused `pid`/`i` vars renamed). Live test pending user execution on ACG GCP sandbox.
- **GCP Provisioning Error 1** — COMPLETE (`346c3df2`). `(( attempts++ ))` → `(( ++attempts ))` in `k3s-gcp.sh` lines 109 and 211. Spec complete; committed 2026-04-23.
- **Start Sandbox Disabled Timeout** — COMPLETE (`13d398ab`). Add `isEnabled()` guard before `startButton.click()` in `acg_credentials.js` line 352; if disabled, skip click and wait for credentials. Spec complete; committed 2026-04-23.

- **Whitespace enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files
- **SSH tunnel timeouts** — connection resets during heavy ArgoCD sync (infra, non-blocking)
- **ACG extraction** — treat browser automation repo split as the stabilization path before further provider automation work.

## Documentation Note
- Memory Bank size is still manageable (~37 KB total across the tracked files), but `docs/plans/` has grown much faster than Memory Bank. Future cleanup pressure is primarily in plans/archive hygiene rather than immediate Memory Bank trimming.
