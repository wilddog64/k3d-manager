# Bug: web-console TOTP tests connect as soon as the socket file exists, before the daemon listens

**Status:** OPEN — captured 2026-11-22
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-25 — test-only race condition where TOTP unit tests connect before the socket enters listen state
**Triage:** backlog — pull into a release that already touches `scripts/tests/python/test_console_totpd.py` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** `1026dbe2` (web-console part C TOTP gate, tests `test_N1_and_M2_lockout_and_hmac_calls` and `test_N1_and_E1_wire_rejections`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run. Same class as `docs/bugs/2026-11-22-hub-promote-tty-driver-10s-deadline-fails-under-load.md` (test readiness check weaker than the condition it needs), different file.
**Detected by:** Claude, 2026-11-22, CI run 45105406314 on `e3eb53ca` (job test-python)
**Severity:** test-only. CI can go red with no code defect.

## What happened

Both tests failed with `ConnectionRefusedError: [Errno 111]` in CI on `e3eb53ca` (2 failed, 2716 passed). They passed on the same
branch at `748fd732`. The commit under test (remote-promote 2b) does not touch the web console.

## Root cause

`scripts/libexec/k3dm-console-totpd.py` creates the socket with `bind()` (line 396), then `chmod` (397), then `listen(16)` (398).
The tests start the daemon in a thread and poll only for `os.path.exists(sock_path)` (up to 50 × 0.05 s), then `connect()`.
A Unix socket file exists from `bind()` on, but a connect before `listen()` is refused. `ECONNREFUSED`, not `ENOENT`, shows the
file was there. Under CI load the connect can land inside that window.

## Fix direction

In the tests, wait until a `connect()` succeeds (retry on `ECONNREFUSED`/`ENOENT` within the same deadline) instead of waiting
for the path, in all four spots that use the exists loop (lines ~194, ~283, ~384, ~427). No daemon change needed.
