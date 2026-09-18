# e2e readiness gate can return "not ready" after zero probes

**Filed:** 2026-09-17
**Status:** OPEN — unassigned
**Branch:** `k3d-manager-v1.35.0`
**Component:** `scripts/plugins/e2e.sh` — `_e2e_wait_vcluster_ready` (lines 156-166)
**Severity:** low in production, medium in CI
**Surfaced by:** `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md` — this is the one
real failure the CI-discovery enumeration turned up, reported rather than fixed per that spec's
STOP rule.
**Not a duplicate of:** `2026-08-16-e2e-vcluster-api-readiness-race.md`, which asked for this
readiness gate to exist. This is a defect *inside* that gate.

## Problem

`_e2e_wait_vcluster_ready` samples the clock twice:

```bash
now=$(date +%s)
deadline=$(( now + E2E_VCLUSTER_READY_TIMEOUT ))
next_refresh=$(( now + E2E_VCLUSTER_READY_REFRESH_INTERVAL ))
_info "[e2e] Waiting for vCluster API to be ready (timeout ${E2E_VCLUSTER_READY_TIMEOUT}s)"
while now=$(date +%s); (( now < deadline )); do
```

`date +%s` has integer-second resolution. If the wall clock crosses a second boundary between
the first sample and the loop guard — a window that includes a subshell fork, an arithmetic
expansion, an `_info` call and a second subshell fork — then with
`E2E_VCLUSTER_READY_TIMEOUT=1` the guard evaluates `101 < 101` and is already false.

The loop body never executes. The function returns non-zero having issued **zero** `/readyz`
probes: it reports a negative result without ever asking the question.

## Reproduction

Deterministic, with a stubbed `date` that returns `100` on its first call and `101` on every
later call:

```
not ok 1 boundary crossing yields zero probes
#   `[ "$status" -eq 0 ]' failed
# probes logged: 0
```

In the wild it shows as `scripts/tests/plugins/e2e.bats:262` — *"readiness gate honours
E2E_VCLUSTER_READY_TIMEOUT and fails when never ready"* — failing at line 269 on the
`grep -F -- "get --raw=/readyz"` assertion, because nothing was ever logged. It passes 8/8 in
isolation and fails only under full-suite load, where the fork latency makes the boundary
crossing likely.

## Why this matters now

The three tests at `e2e.bats:262`, `:272` and `:289` all set
`E2E_VCLUSTER_READY_TIMEOUT=1`, so all three sit on the race; the first is the one that asserts
a probe was logged. `scripts/tests/plugins/e2e.bats` was **dark in CI** until the CI-discovery
fix gated the full `make test` discovery. From that commit on, this race is an intermittently
red CI on the release branch.

Production impact is real but small: the default is `E2E_VCLUSTER_READY_TIMEOUT=600`, so the
window is roughly one second in six hundred per call, and the caller
(`e2e_verify_vcluster`) treats the failure as "vCluster never came up" and tears down a cluster
that may have been fine.

## Fix

A timeout loop should always probe at least once — the budget bounds how long to keep trying,
not whether to try. Convert the pre-test loop into a do-while so the first probe is
unconditional, keeping the deadline check for subsequent iterations. Do **not** paper over it by
widening the test's timeout to 2 or 3 seconds: that lowers the failure probability without
removing the defect, and re-arms it for whoever next runs on a slower or more loaded host.

Do not change `E2E_VCLUSTER_READY_TIMEOUT`'s 600s default, and do not touch the soft-probe
(`--no-exit`) contract at lines 170-171 — the comment there records a real past bug.

## Tests

- With a stubbed `date` that crosses a second boundary between the deadline computation and the
  loop guard, `_e2e_wait_vcluster_ready` still issues at least one `/readyz` probe. Assert on
  the probe log, not on the return code — the return code was already correct.
- The existing three `E2E_VCLUSTER_READY_TIMEOUT=1` cases keep passing.
- Stub `date`; do not read the host clock.

## What NOT to Do

- Do NOT mark the test `skip`, delete it, or remove it from discovery.
- Do NOT widen the test's timeout as the fix. See above.
- Do NOT revert the CI-discovery change to re-hide the suite.
- Do NOT touch a live cluster, vCluster, or `kubectl`. Code plus BATS only.
