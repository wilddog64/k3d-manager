# 2026-05-17 — `./scripts/k3d-manager test all` reports pre-existing failures in unrelated suites

## What I tested

- Staged the two spec changes in:
  - `scripts/lib/acg/playwright/acg_extend.js`
  - `scripts/lib/acg/playwright/acg_credentials.js`
- Ran:
  - `node --check scripts/lib/acg/playwright/acg_extend.js`
  - `node --check scripts/lib/acg/playwright/acg_credentials.js`
  - `bash -lc 'source scripts/lib/foundation/scripts/lib/system.sh; _agent_audit'`
  - `bash -lc 'source scripts/lib/foundation/scripts/lib/system.sh; _agent_lint'`
  - `./scripts/k3d-manager test all`

## Actual output

```text
not ok 222 Fresh install
# (in test file scripts/tests/plugins/eso.bats, line 85)
#   `[[ "${helm_calls[2]}" == upgrade\ --install\ -n\ sample-ns\ external-secrets\ external-secrets/external-secrets\ --create-namespace\ --set\ installCRDs=true ]]' failed
not ok 223 Local ESO chart skips repo add
# (in test file scripts/tests/plugins/eso.bats, line 109)
#   `[ "${helm_calls[0]}" = "$expected" ]' failed
not ok 227 gcp_login runs gcloud in background and node when playwright available
# (in test file scripts/tests/plugins/gcp.bats, line 102)
#   `[ "$status" -eq 0 ]' failed
not ok 243 _keycloak_remove_client_attribute deletes stale pkce attribute rows
# (in test file scripts/tests/plugins/keycloak.bats, line 115)
#   `grep -q "client_attributes" "$exec_log"' failed
Test log saved to scratch/test-logs/all/20260517-040015.log
Collected artifacts in scratch/test-logs/all/20260517-040015
```

## Root cause

Unknown from this run. The failures are in existing BATS suites unrelated to the two-line `noWaitAfter` change.

## Recommended follow-up

- Inspect `scratch/test-logs/all/20260517-040015.log` for the failing assertions.
- Triage the failing `scripts/tests/plugins/eso.bats`, `scripts/tests/plugins/gcp.bats`, and `scripts/tests/plugins/keycloak.bats` cases separately if they are meant to be green on this branch.
