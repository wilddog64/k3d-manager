# Bug: `producer | grep -q` under pipefail reports a present match as absent

**Status:** open — e2e.sh instances fixed in the e2e-sandbox-provision task (v1.43.4); the rest unaudited
**Priority:** P3
**Approval:** pending
**Found:** 2026-10-17, by the independent acceptance verifier for e2e-sandbox-provision

## Symptom

`kubectl config get-contexts -o name | grep -qx -- "$ctx"` intermittently said `ubuntu-k3s` was
absent right after it was created. The verifier's harness failed 3 of 59 full-suite runs (M2 once,
M1b twice), each time with the call log showing the context listed and then reported missing.

## Root cause

`grep -q` exits on its first match. When the producer writes anything after that line, the write
hits a closed pipe, the producer dies with SIGPIPE (rc 141), and `pipefail` turns the pipeline's
status into a failure. The `if ! ...` reads that as "no match". It is a race: it fires only when
the producer is still writing after grep has exited, so it passes most of the time.

`scripts/plugins/e2e.sh` sets `set -euo pipefail` at top level, so every plugin sourced into the
same dispatcher shell after it also runs under pipefail — a file without its own `pipefail` line
is not safe on that basis. Most `bin/` scripts set it themselves.

## Fix pattern

Let grep read to EOF instead of exiting early:

    producer | grep -x -- "$x" >/dev/null

or capture first: `out="$(producer)"` then match against `$out`.

Regression test shape (deterministic): stub the producer as a shell function that prints the match,
`sleep 0.3`, then prints another line. Under `grep -q` the second write always hits a closed pipe.
See the two "more contexts follow it in the listing" tests in
`scripts/tests/plugins/e2e_sandbox_preflight.bats`.

## Remaining scope

`grep -rE '\| *grep -q'` finds about 50 occurrences across `scripts/` and `bin/` (excluding
vendored `node_modules`). Audit each: it matters only where the producer can write after the
matching line AND the shell has pipefail on. Fix those with the pattern above; leave the rest.
