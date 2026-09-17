# PR #127 review findings: stale smoke test, unbound trap variable, duplicated grep

Date: 2026-09-17. Branch: `k3d-manager-v1.34.0`. PR: #127.
Scope: fix the CI-failing stale BATS assertion and two Copilot-flagged defects.
No PR action taken here (creation/merge is out of scope for this fix pass).

## Finding 1 — stale BATS assertion for a deliberately removed fallback

**File:** `scripts/tests/lib/webhook.bats:333`
**What was flagged:** CI failure. The test `status smoke login falls back to the
deployed Keycloak admin Secret` asserted that `bin/k3dm-webhook` contains the
literal string `keycloak-admin-secret`.

**Root cause:** Commit `384b0202` ("fix(webhook): login checks use the
operator's own accounts and public URLs") intentionally deleted the
`keycloak-admin-secret` seeded-password fallback, because that fallback let a
stale password read as green in `make status`. The implementation
(`_smoke_keycloak_admin` in `bin/k3dm-webhook`, ~line 1934) now reads
`KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` from the `keycloak-secrets` Secret
in the `identity` namespace and authenticates with `client_id: admin-cli`
against the master realm. The test was never updated to match, so it asserted
behavior that no longer exists — it happened to keep passing only because the
string `admin-cli` is still present and `grep -F` doesn't care why.

**Before:**
```bash
@test "status smoke login falls back to the deployed Keycloak admin Secret" {
    run grep -F -- 'keycloak-admin-secret' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -eq 0 ]
    run grep -F -- 'admin-cli' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -eq 0 ]
}
```

**After:**
```bash
@test "status smoke Keycloak admin login uses the operator keycloak-secrets account" {
    run grep -F -- 'keycloak-secrets' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -eq 0 ]
    run grep -F -- 'KEYCLOAK_ADMIN_PASSWORD' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -eq 0 ]
    run grep -F -- 'admin-cli' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -eq 0 ]
    run grep -F -- 'keycloak-admin-secret' "${BATS_TEST_DIRNAME}/../../../bin/k3dm-webhook"
    [ "${status}" -ne 0 ]
}
```

The test now asserts the current contract (operator's own `keycloak-secrets`
account, `KEYCLOAK_ADMIN_PASSWORD`, `admin-cli` client) plus a disappearance
gate proving the stale seeded-password fallback stays deleted.

**Process note:** the assertion encoding removed behavior survived because no
full CI run happened on this branch between the behavior change (`384b0202`)
and PR #127 being opened — a stale test can only ride along silently when the
gate that would catch it doesn't run in between. Rule to prevent recurrence:
any commit that deletes or renames a code path referenced by a BATS assertion
must `grep` the test suite for the removed literal in the same commit/PR, and
CI must run at least once on the branch before a PR is opened, not just before
merge.

## Finding 2 — EXIT trap references `_tmp` before it is assigned

**File:** `bin/cluster-status-summary:13`
**What was flagged:** Copilot review. The script runs `set -euo pipefail`
(line 2). Line 13 installs an EXIT trap referencing `_tmp`, but `_tmp` is not
assigned until line 18. If anything between lines 13 and 18 fails (e.g. the
keychain read on line 16), the EXIT trap fires with `_tmp` unbound, the trap
itself errors under `set -u`, and the `_keychain_err` temp file leaks instead
of being cleaned up.

**Before:**
```bash
_token_from_env="${K3DM_WEBHOOK_TOKEN:-}"; _keychain_err="$(mktemp -t k3dm-keychain.XXXXXX)"; trap 'rm -f "${_tmp}" "${_keychain_err}"' EXIT
```

**After:**
```bash
_token_from_env="${K3DM_WEBHOOK_TOKEN:-}"; _keychain_err="$(mktemp -t k3dm-keychain.XXXXXX)"; trap 'rm -f "${_tmp:-}" "${_keychain_err}"' EXIT
```

**Root cause:** the trap was installed before all variables it references
were assigned, and `set -u` treats an unset variable expansion as a hard
error even inside a trap body.

**Process note:** any `trap ... EXIT` installed before all referenced
variables are assigned must default-expand those variables (`${var:-}`) under
`set -u`, since the trap can fire at any point after installation, not just
at normal script exit.

## Finding 3 — duplicated grep assertion, Copilot comment 4042080404

**File:** `scripts/tests/plugins/e2e_observability.bats:18`
**What was flagged:** Copilot inline comment 4042080404. The test
`Hermes dashboard exposes current findings and history` grepped
`hermes_sensor_status` twice identically, so the "history" half of the test
name asserted nothing about history.

**Root cause:** the history panel (`scripts/etc/argocd/platform-ops/grafana-dashboard-hermes.yaml:59`,
`"id": 6, "type": "timeseries", "title": "Sensor status history"`) exists in
the dashboard but the test never checked for it — the second assertion was a
copy-paste of the first instead of a distinct check.

**Before:**
```bash
@test "Hermes dashboard exposes current findings and history" {
  run grep -F -- 'hermes_sensor_status' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'hermes_sensor_status' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Current Hermes findings"' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
}
```

**After:**
```bash
@test "Hermes dashboard exposes current findings and history" {
  run grep -F -- 'hermes_sensor_status' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Current Hermes findings"' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
  run grep -F -- '"title": "Sensor status history"' "${HERMES_DASH}"
  [ "${status}" -eq 0 ]
}
```

**Process note:** a test name asserting two behaviors ("current findings and
history") needs a distinct assertion body per behavior — a duplicated grep
line is a signal the test was extended by copy-paste without checking that
the second copy actually targets the second behavior.

## Gates run

- `bats scripts/tests/lib/webhook.bats` — 64/64 passing, including the
  renamed test 18.
- `bats scripts/tests/plugins/e2e_observability.bats` — 15/15 passing.
- `shellcheck bin/cluster-status-summary` — clean, zero warnings.
- `bash -n bin/cluster-status-summary` — clean.
