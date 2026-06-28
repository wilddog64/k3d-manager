# GitGuardian False Positive: seed BATS test fixtures

**Date:** 2026-06-28
**Status:** FALSE POSITIVE — resolve in dashboard; repo guard already in place
**GitGuardian:** "1 internal secret incident detected" — Generic Password (2026-06-28 22:05 UTC)
**Flagged Commit:** `b03cf2892987c403b66b16b22a8e754648ac0469`
**Flagged File:** `scripts/tests/plugins/shopping_cart_seed_idempotent.bats`
**Branch:** `k3d-manager-v1.12.0`

---

## What GitGuardian Reported

A "Generic Password" matched on synthetic mock values inside the BATS test for
`shopping_cart_seed_sandbox_vault_kv`. Confirmed via
`ggshield secret scan path <fixture> --all-secrets` — the matches are test fixtures:

- `keycloak/admin` mock: `{"admin_password":"kc-admin","db_password":"kc-db"}`
- `minio/credentials` mock: `{"root-user":"src-minio-user","root-password":"src-minio-pass"}`
- `_vault_root_token="root-token"`

## Root Cause: False Positive

These are hardcoded **stub Vault responses** in a BATS test file — never connected to a
live Vault, never deployed. The real secrets in the seed code path are generated at runtime
via `openssl rand -base64 24` and are never committed. No real secret was exposed.

## Verification

| Match | Location | Real secret? |
|---|---|---|
| `kc-db` / `kc-admin` | keycloak/admin test mock | No — BATS fixture |
| `src-minio-pass` / `src-minio-user` | minio/credentials test mock | No — BATS fixture |
| `root-token` | `_vault_root_token` test export | No — BATS fixture |

All four release gates passed on `b03cf289` (shellcheck, `bash -n`, `bats 1..5`, `_agent_audit`).

## Resolution

**Repo guard (already in place):** `.gitguardian.yaml` ignores `scripts/tests/` — committed
since v1.11.0 (`75ebc934`). This governs `ggshield` CLI / CI / pre-commit scans, so local
and CI runs already skip this file.

**Dashboard incident:** GitGuardian's GitHub source-monitoring is server-side and does not
apply the repo `.gitguardian.yaml` to historical/realtime perimeter scans, which is why the
incident was raised despite the committed ignore. `ggshield` 1.52 has no incident-resolution
subcommand (only `secret scan` and `secret ignore`, the latter writing to the local config).
Resolve the existing incident by one of:

1. **Dashboard UI** — open the incident, mark **Resolve → False positive** (reason: test fixture).
2. **REST API** (key in keyring already has `incidents:write`):
   `POST https://api.gitguardian.com/v1/incidents/secrets/{id}/resolve`
   with `Authorization: Token $GITGUARDIAN_API_KEY`.

**Durable prevention:** add `scripts/tests/` as a path exclusion in the GitGuardian dashboard
(Sources → exclusions) so test fixtures stop creating incidents server-side.

## Prevention

`ggshield install --mode local pre-commit` (or `pre-push`) catches real secrets before they
leave the machine; the `scripts/tests/` ignore keeps fixtures from blocking commits.
