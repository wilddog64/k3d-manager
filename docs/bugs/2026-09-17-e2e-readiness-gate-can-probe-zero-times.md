# e2e readiness gate can return "not ready" after zero probes

**Filed:** 2026-09-17
**Status:** FIXED `aa71c1f4` (2026-09-18) — verified independently by Claude
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

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.35.0`
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
3. Read this spec in full, then read `scripts/plugins/e2e.sh` lines 1-20 (the `E2E_*` defaults)
   and 156-187 (the function), and `scripts/tests/plugins/e2e.bats` lines 240-300 (the four
   readiness cases and how they stub).

Branch: `k3d-manager-v1.35.0`. Do not create another branch.

## Fix

A timeout loop must always probe at least once — the budget bounds how long to keep trying, not
whether to try. Convert the pre-test `while` into a do-while so the first probe is unconditional,
and move the deadline check to the bottom.

Replace exactly this block in `scripts/plugins/e2e.sh` (lines 166-185):

```bash
  while now=$(date +%s); (( now < deadline )); do
    # Soft probe: a failed /readyz must RETURN non-zero, never exit. A bare
    # _run_command calls _err -> exit on failure, which (bypassing this if)
    # would kill the whole harness on the first not-ready probe.
    if KUBECONFIG="$kubeconfig" _run_command --no-exit --quiet -- \
        kubectl get --raw='/readyz' >/dev/null 2>&1; then
      _info "[e2e] vCluster API is ready"
      return 0
    fi
    # vcluster 0.36.x's background-proxy port-forward dies on the syncer's
    # startup restart and never reconnects; recreate it so the pinned-port
    # kubeconfig can reach the current pod on the next probe. Refresh on its
    # own (slower) cadence so we do not hammer a still-starting syncer.
    if [[ -n "$name" ]] && (( now >= next_refresh )) \
        && declare -f _vcluster_refresh_connection >/dev/null 2>&1; then
      _vcluster_refresh_connection "$name"
      next_refresh=$(( now + E2E_VCLUSTER_READY_REFRESH_INTERVAL ))
    fi
    sleep "$E2E_VCLUSTER_READY_INTERVAL"
  done
```

with:

```bash
  # Do-while: the deadline bounds how long to keep retrying, never whether to
  # try at all. date +%s is integer-second, so a pre-test guard can see the
  # clock tick past a short deadline before the first probe and return
  # not-ready having asked nothing.
  while :; do
    # Soft probe: a failed /readyz must RETURN non-zero, never exit. A bare
    # _run_command calls _err -> exit on failure, which (bypassing this if)
    # would kill the whole harness on the first not-ready probe.
    if KUBECONFIG="$kubeconfig" _run_command --no-exit --quiet -- \
        kubectl get --raw='/readyz' >/dev/null 2>&1; then
      _info "[e2e] vCluster API is ready"
      return 0
    fi
    # vcluster 0.36.x's background-proxy port-forward dies on the syncer's
    # startup restart and never reconnects; recreate it so the pinned-port
    # kubeconfig can reach the current pod on the next probe. Refresh on its
    # own (slower) cadence so we do not hammer a still-starting syncer.
    if [[ -n "$name" ]] && (( now >= next_refresh )) \
        && declare -f _vcluster_refresh_connection >/dev/null 2>&1; then
      _vcluster_refresh_connection "$name"
      next_refresh=$(( now + E2E_VCLUSTER_READY_REFRESH_INTERVAL ))
    fi
    now=$(date +%s)
    (( now < deadline )) || break
    sleep "$E2E_VCLUSTER_READY_INTERVAL"
  done
```

Lines 156-165 (the argument handling, the three `local`s, the initial `date +%s`, `deadline`,
`next_refresh` and the `_info`) and line 186 (`_err`) are unchanged.

Note what this deliberately preserves: the refresh check still runs against the `now` from
before the probe, on its own slower cadence, and the `sleep` no longer fires on the iteration
that breaks.

Do **not** "fix" this by widening the test's timeout to 2 or 3 seconds. That lowers the failure
probability without removing the defect and re-arms it on a slower or more loaded host. Do not
change the `E2E_VCLUSTER_READY_TIMEOUT=600` default at line 11, and do not touch the soft-probe
(`--no-exit`) contract — the comment there records a real past bug.

## Tests

Add one case to `scripts/tests/plugins/e2e.bats`, beside the existing readiness cases
(~line 262). It must fail against the current code and pass after the fix.

Stub `date` so the boundary crossing is deterministic — first call 100, every later call 101 —
and assert on the **probe log**, not on the return code. The return code was already correct;
the bug is that nothing was probed:

```bash
@test "readiness gate always probes at least once even if the deadline has already passed" {
  export E2E_VCLUSTER_READY_TIMEOUT=1
  local date_calls=0
  date() {
    date_calls=$(( date_calls + 1 ))
    if (( date_calls == 1 )); then echo 100; else echo 101; fi
  }
  _run_command() { echo "$*" >> "$RUN_LOG"; return 1; }
  local rc=0
  ( _e2e_wait_vcluster_ready "$BATS_TEST_TMPDIR/kc" ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
  run grep -F -- "get --raw=/readyz" "$RUN_LOG"
  [ "$status" -eq 0 ]
}
```

Adjust the stub to whatever this file's existing conventions require — read the surrounding
cases first and match them. Requirements that are not negotiable: `date` is stubbed (never read
the host clock), the assertion is that a probe was logged, and the three existing
`E2E_VCLUSTER_READY_TIMEOUT=1` cases at `:262`, `:272` and `:289` still pass.

**Verify the test actually catches the bug.** Before applying the fix, run the new case against
the unmodified `e2e.sh` and confirm it FAILS. Paste that failure. A test that passes both before
and after proves nothing, and submitting one is the failure mode here.

## Rules

- `set -euo pipefail`; double-quote every expansion.
- `shellcheck -S error` clean on every file touched.
- Minimal patch — no unsolicited refactors, no reformatting of surrounding lines.
- No inline comments in shell blocks beyond the one comment shown in the replacement above.
- No bare `!` in BATS; no whole-line `grep -F` of a source line.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.

## Definition of Done

- [ ] The new case fails against unmodified `e2e.sh` — failure output pasted.
- [ ] `_e2e_wait_vcluster_ready` probes unconditionally before any deadline check.
- [ ] Lines 156-165 and the `_err` at 186 unchanged; `E2E_VCLUSTER_READY_TIMEOUT` default still 600.
- [ ] The three existing `E2E_VCLUSTER_READY_TIMEOUT=1` cases still pass.
- [ ] `make test` green. Run it UNPIPED and paste the real numbers:
      `make test > /tmp/maketest.log 2>&1; echo "EXIT=$?"` then `grep -c '^ok ' /tmp/maketest.log`
      and `grep -n '^not ok' /tmp/maketest.log`. **Never pipe `make test` into `tail`, `head` or
      `tee` to read its exit code — you would report the pipe's status, not make's. That mistake
      was made on the previous task.** Baseline on this branch is 946 total.
- [ ] Run `make test` a second time. This defect is a race: one green run is one sample, not
      proof. Both runs must be green, and report both.
- [ ] `make test-bin` green (108 cases).
- [ ] `shellcheck -S error` clean.
- [ ] CHANGELOG `### Fixed` entry under `[Unreleased]`.
- [ ] Commit message exactly:
      `fix(e2e): always probe the vCluster readiness gate at least once`
- [ ] `git push origin k3d-manager-v1.35.0` succeeded and
      `git rev-parse HEAD` == `git rev-parse origin/k3d-manager-v1.35.0`.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA.

## What NOT to Do

- Do NOT mark the test `skip`, delete it, or remove it from discovery.
- Do NOT widen the test's timeout as the fix. See above.
- Do NOT revert the CI-discovery change to re-hide the suite.
- Do NOT touch a live cluster, vCluster, or `kubectl`. Code plus BATS only.
