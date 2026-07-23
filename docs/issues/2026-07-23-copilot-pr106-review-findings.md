# Copilot PR #106 Review Findings — v1.16.0

PR #106 (ambient mesh app-tier + multi-cluster hardening). Copilot posted 9 inline comments.
8 fixed in this PR; 1 deferred with rationale.

## Fixed

### 1. `(( attempts++ ))` not `set -e`-safe — `scripts/plugins/shopping_cart.sh:1099`
`_ambient_install_cilium` (new this milestone) used `(( attempts++ ))` in the Cilium-rollout wait
loop. Post-increment returns the *old* value, so the first iteration (`attempts=0`) makes the
arithmetic command exit `1`, aborting the caller under `set -euo pipefail` before the retry cap is
reached — the same bug class the milestone fixed in `k3s-aws` (`520621a9`).

- **Before:** `(( attempts++ ))`
- **After:** `attempts=$(( attempts + 1 ))`

### 2. `RETURN` traps not self-uninstalling — `scripts/plugins/shopping_cart.sh` (244, 268, 974), `scripts/plugins/argocd.sh` (736, 906, 1089)
The milestone's `mktemp` trap-guards (`319762b9`) set a `RETURN` trap that never cleared itself, so
it stayed armed and would re-fire on every subsequent function return in the shell.

- **Before:** `trap 'rm -f "'"${VAR}"'" 2>/dev/null || true' RETURN`
- **After:** `trap 'trap - RETURN; rm -f "'"${VAR}"'" 2>/dev/null || true' RETURN`

### 3. `xargs -r` is GNU-specific — `scripts/check-stale-test-refs.sh:28`
`xargs -r` errors on macOS/BSD (`illegal option -- r`) and, under `set -euo pipefail`, aborts the
script. `_consumers` is already guarded non-empty two lines above, so `-r` is unnecessary.

- **Before:** `printf '%s\n' "${_consumers}" | xargs -r grep -lF -- "${_base}"`
- **After:** `printf '%s\n' "${_consumers}" | xargs grep -lF -- "${_base}"`

### 4. `GH_TOKEN` exposed in `wget` argv — `scripts/etc/argocd/platform-ops/app-cve-scan.sh:254`
`_dispatch_rebuild` (new this milestone, `89c2efd6`) passed `--header="Authorization: Bearer
${GH_TOKEN}"`, exposing the token in the process command line (`ps`, diagnostics). Moved the header
into a mode-`0600` `--config` file (mirrors the prior curl `--config` approach), keeping the token
out of argv. The stubbed `wget` in `app_cve_scan.bats` now parses `--config` and reads the header
from the file, so the `Authorization: Bearer …` assertion still gates the behavior.

### 5. New plugin BATS suites not gated by CI — findings 7/8/9
`grafana_dashboard_appsets.bats`, `argocd_metrics_servicemonitor.bats`, and
`appset_envsubst_coverage.bats` lived under `scripts/tests/plugins/` but CI ran only
`trivy_operator_observability.bats` from that directory. All three (plus the touched
`app_cve_scan.bats`) are pure-logic, pass standalone, and were added to the CI `bats` invocation.
The rest of `scripts/tests/plugins/` stays deferred (pre-existing stub-vs-real-`kubectl` failures),
matching the v1.15.0 (PR #105) decision.

Also required for these to actually run green in CI: the `lint` job's checkout now uses
`fetch-depth: 0`, because the newly-gated `stale_test_refs.bats` invokes the checker against
historical commits that a shallow clone cannot reach.

## Deferred (documented)

### 6. SSH command built as an unquoted string — `scripts/plugins/shopping_cart.sh:1072`
`_ambient_install_cilium` builds `ssh_cmd` as a string and relies on word-splitting at ~3 call
sites. The robust fix is a bash array (`ssh_cmd=(ssh … -i "$ssh_key" "$user@$ip")` +
`"${ssh_cmd[@]}"`). Deferred rather than bundled into this release PR because: (a) the inputs
(`ssh_user`/`external_ip`/`ssh_key`) are provider-internal (AWS/config), not user-supplied, so the
practical option/argument-injection risk is low; (b) the function is live cold-provisioning code
with no unit coverage, so an array refactor belongs in its own change with a test. Tracked for a
follow-up.

## Process note

The BATS test staleness that broke the first CI run (`provider_contract.bats` asserting 3 reapplied
appsets when `470ef7d8` had already added a 4th, `istio-ambient`) is the recurring lesson: when a
milestone commit changes a function's observable contract, update its test in the same commit. The
stale-ref checker exists to catch the *string*-level version of this; the count assertion needs the
same discipline.
