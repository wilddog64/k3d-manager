# Bug: webhook doctor terminates a command before successful exit

**Status:** LIVE-VERIFIED — 2026-10-29 on M4 with controlled race and operator doctor check
**Priority:** P2
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Fix commit:** `b591a13c803b44377fcea91207ea68142a9fdf5c`
**Live evidence:** 2026-10-29 · run m4-doctor-controlled-exit-and-operator-health · env m4-air · scenario controlled-eof-race-timeout-and-real-healthy-doctor · commit cf00c30f · proves fix
**Related:** `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`; `docs/bugs/2026-10-27-webhook-diagnostics-wrong-default-port.md`

The bounded command helper terminated its child as soon as output streams
closed if the child had not exited yet. A controlled successful child was
reported with returncode-15, timed_out=false. This can incorrectly reject
a credential lookup; it does not establish why the operator's Keychain
lookup was unavailable.

Fix waits within the remaining deadline, preserving output and time bounds.
Two pre-fix red regressions now pass; full26 Python +5 BATS, Ruff, audit/lint
and normal hooks pass. No credential or live service changes.
[Actual output and next check](../issues/2026-10-27-webhook-doctor-command-exit-race.md).

## Live verification — 2026-10-29

On M4 the current checkout contains fix `b591a13c`. A controlled child closed
its output before successfully exiting; the current doctor helper waited and
returned exit 0. A second child exceeded its deadline and was terminated with
`timed_out: true`. The operator's actual doctor invocation also retrieved the
reader credential and reported authenticated HTTP healthy. The timing scenario
was controlled; the original locked-Keychain symptom was a separate cause and
this does not claim a naturally occurring Keychain race was observed. Full
commands and output: [verification record](../issues/2026-10-29-live-verification-queue-review.md).
