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

## Open Items
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Local Hub orchestration is fragmented: `acg-up` assumes ArgoCD infrastructure, bootstrap remains separate, and local ArgoCD access still requires manual port-forward setup.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up` does not clearly summarize local Hub vs remote app-cluster readiness and does not guide optional local runtime startup.
- **ACG Extraction Boundary** — OPEN (`docs/bugs/2026-04-23-acg-extraction-boundary-gemini-coupling.md`). The `acg_*` interaction surface still keeps Gemini/browser automation coupled to `k3d-manager`; that subsystem should move out as one extraction unit.
- **Teardown State Drift** — COMPLETE (`docs/bugs/2026-04-23-acg-down-full-teardown-spec.md`). Implemented in `3fd6f4d6`; `acg-down` now tears down the local Hub by default and supports `--keep-hub` as the explicit opt-out.
- **acg-sync-apps + acg-status dual-cluster** — COMPLETE (`docs/bugs/2026-04-23-acg-sync-apps-and-acg-status-dual-cluster.md`). Implemented in `a5422141`; `acg-sync-apps` now polls port-forward readiness and uses configurable `ARGOCD_APP`, and `acg-status` now shows Hub cluster nodes + pods before tunnel status.
- **Vault Preflight After Sleep** — OPEN (`docs/bugs/2026-04-23-acg-up-vault-state-preflight-gap-after-mac-sleep.md`). `acg-up` does not robustly re-classify local Vault state after Mac sleep / clamshell resume before attempting KV seeding.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and accumulated historical docs are now a larger maintenance/size concern than Memory Bank itself.
- **Vault Sync Mismatch** — CRITICAL BLOCKER (`docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md`). Vault storage state and cached unseal material can still drift apart; current automatic recovery is not sufficient for every local failure state.
- **Vault Resilience Gap** — OPEN (`docs/bugs/2026-04-20-vault-readiness-gate-missing.md`, `docs/bugs/2026-04-22-vault-orphaned-port-forward-ghost-blocker.md`). `acg-up` can fail at Vault seeding because Vault is sealed after Mac sleep or because a ghost port-forward on `8200` routes to a dead pod.
- **macOS CDP Direct Launch** — OPEN (`docs/bugs/2026-04-21-cdp-macos-direct-launch-gcp-ensure-cdp.md`). macOS `open -a` can reuse an existing Chrome instance and fail to apply CDP flags; fix must stay aligned with the shared CDP ownership model.
- **GCP Login Linux Headless OAuth** — COMPLETE (`927cb452`). `gcp.sh` OS-split captures OAuth URL from gcloud output; `gcp_login.js` navigates directly via `GCP_AUTH_URL` on Linux. Shellcheck fix committed (unused `pid`/`i` vars renamed). Live test pending user execution on ACG GCP sandbox.
- **GCP Provisioning Error 1** — ASSIGNED TO GEMINI (`docs/bugs/2026-04-23-gcp-node-readiness-timeout-bash-pitfall.md`). `(( attempts++ ))` → `(( ++attempts ))` in `k3s-gcp.sh` lines 109 and 211. Spec complete; assigned 2026-04-23.

- **Whitespace enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files
- **SSH tunnel timeouts** — connection resets during heavy ArgoCD sync (infra, non-blocking)
- **ACG extraction** — treat browser automation repo split as the stabilization path before further provider automation work.

## Documentation Note
- Memory Bank size is still manageable (~37 KB total across the tracked files), but `docs/plans/` has grown much faster than Memory Bank. Future cleanup pressure is primarily in plans/archive hygiene rather than immediate Memory Bank trimming.
