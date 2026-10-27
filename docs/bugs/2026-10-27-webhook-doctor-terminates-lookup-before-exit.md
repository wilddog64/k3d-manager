# Bug: webhook doctor terminates a command before successful exit

**Status:** VERIFIED — offline regression fixed; operator credential recheck pending
**Priority:** P2
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Fix commit:** `b591a13c803b44377fcea91207ea68142a9fdf5c`
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
