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

## Latest Task: CLUSTER_NAME empty-string fix

**Status:** COMPLETE — spec: `docs/bugs/2026-04-20-k3d-cluster-name-empty-blocker.md`
**File:** `scripts/lib/core.sh` line 796
**Fix:** `${CLUSTER_NAME:-}` → `${CLUSTER_NAME:-k3d-cluster}`
**Commit:** `3a3806aa`
**Smoke test:** `make up` reached `bin/acg-up` but stopped on Chrome CDP startup (`docs/issues/2026-04-21-cluster-name-smoke-test-blocked-by-cdp.md`). User reports this path should start CDP in the background and use `~/.local/share/k3d-manager/profile/`.

## Open Items

- **Whitespace enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files
- **SSH tunnel timeouts** — connection resets during heavy ArgoCD sync (infra, non-blocking)
- **CDP launcher profile path** — current scripts still point at `playwright-auth` / `acg-chrome-profile`; user says `.../profile/` was working yesterday and should be treated as the expected path until re-verified.
