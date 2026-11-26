# Bug: `k3dm-cloud-request` dies in cloud sessions because their Python lacks `posix_spawn(setsid=True)`

**Status:** LANDED — 2026-11-25 (Neon, verified by Claude: new tests red on base, named mutants caught)
**Priority:** P1 (proposed) — the cloud request path is broken from cloud sessions, its only intended submitter; workaround unproven (a different Python in the image might support the option)
**Introduced by:** cloud session image change after 2026-11-05 (last successful cloud request `393bebf3`) meeting `scripts/lib/webhook/proc.py:44` (`925c43e7`, v1.37.0)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-25
**Triage:** fix now in v1.46.0 with the pre-push fix (blocks plan 1's live check)
**Branch:** `k3d-manager-v1.46.0`
**Implementer:** Gemini 4 Neon (`--agent agy --model gemini-4-neon-high`), model trial (operator, 2026-11-25)
**Intent approved:** operator, 2026-11-25
**Prior art:** `make find-similar-docs` not run (vector store unavailable); exact-slug pass found nothing; `docs/bugs/2026-11-25-cloud-request-helper-push-runs-fast-gate-and-times-out.md` read — same helper, different root cause
**Filed:** 2026-11-25
**Detected by:** cloud session run for v1.46.0 plan 1 E-P1-live (operator relayed the output, 2026-11-25)

## Observed

Cloud session, repo `wilddog64/k3d-manager` at `eb1d7624`, `/usr/local/bin/python3` 3.13.18, glibc 2.39 (as reported by
the session): `bin/k3dm-cloud-request make-e2e --wait` and `bin/k3dm-cloud-request cluster-status --wait` both printed
`posix_spawn: setsid unavailable on this platform` and exited 4. A read-only `git ls-remote` afterwards showed
`cloud-requests` still at `6548a5de`: nothing pushed.

## Cause

`_spawn_capture_text` calls `os.posix_spawn(exe, cmd, _env, file_actions=..., setsid=True)` (`scripts/lib/webhook/proc.py:44`).
CPython raises `NotImplementedError("setsid unavailable on this platform")` when it was built without
`POSIX_SPAWN_SETSID`. The helper's first git call (`ls-remote`) raises, which `main` turns into rc 4.

## Fix

In `_spawn_capture_text`, call `os.posix_spawn(..., setsid=True)` as today; only if that raises `NotImplementedError`, call
it again with `setpgroup=0` instead (the child leads its own process group, so the timeout's `os.killpg(child_pid, ...)`
still kills the whole tree). No `subprocess`/`fork` (the module exists to avoid fork on macOS). Nothing else changes.

## Files

- `scripts/lib/webhook/proc.py`
- `scripts/tests/bin/test_proc_spawn_fallback.py` (new)

## Scope

- Change: `scripts/lib/webhook/proc.py`.
- Tests: new `scripts/tests/bin/test_proc_spawn_fallback.py`.
- Out of scope: every caller (`bin/k3dm-cloud-bridge`, `bin/k3dm-cloud-request`, `bin/k3dm-webhook`,
  `scripts/lib/webhook/{agent,auth,bug_count,lifecycle,smoke,status}.py`).

## Contract readers

`_spawn_capture_text` (return `(rc, output, timed_out)`, child in its own session or group, group-killed on timeout) is
read by the ten files above (`grep -rln _spawn_capture_text bin scripts/lib`, 2026-11-25). None changes: the return value
and the kill-on-timeout behaviour stay the same; only the spawn attribute differs on platforms without setsid support.

## Acceptance

```yaml
must:
  - id: S-M1
    text: When os.posix_spawn raises NotImplementedError for setsid=True, _spawn_capture_text retries with setpgroup=0 and returns (0, output, False) for a command that prints text.
  - id: S-M2
    text: In that fallback, the child is the leader of its own process group (the command reports getpgrp() == getpid()).
  - id: S-M3
    text: In that fallback, a command that outlives the timeout returns timed_out True and its grandchild is gone afterwards (group kill still works).
must_not:
  - id: S-N1
    text: Must not fail on a platform without setsid support (red on pre-fix code - NotImplementedError escapes).
  - id: S-N2
    text: Must not stop using setsid=True where it works - the first posix_spawn call still passes setsid=True, and no fallback call is made when it succeeds (positive control).
evidence:
  - id: E-S1
    proves: [S-M1, S-M2, S-N1]
    kind: offline
    intent: "Cloud sessions whose Python cannot start a new session still run the helper's git commands and get their output, so a request from a cloud session reaches the hub again."
    command: python3 -m pytest scripts/tests/bin/test_proc_spawn_fallback.py -q
  - id: E-S2
    proves: [S-M3]
    kind: offline
    intent: "A command that hangs in such a session is still stopped at its timeout together with everything it started, so nothing is left running."
    command: python3 -m pytest scripts/tests/bin/test_proc_spawn_fallback.py -q
  - id: E-S3
    proves: [S-N2]
    kind: offline
    intent: "On your Macs and the hub nothing changes: commands still start the way they do today, and the fallback is only used where the first way is refused."
    command: python3 -m pytest scripts/tests/bin/test_proc_spawn_fallback.py -q
  - id: E-S4
    proves: [S-M1]
    kind: live
    intent: "In a cloud session, bin/k3dm-cloud-request cluster-status --wait gets its answer from the hub."
    command: bin/k3dm-cloud-request cluster-status --wait (cloud session, operator relays, after land)
interface:
  files: [scripts/lib/webhook/proc.py, scripts/tests/bin/test_proc_spawn_fallback.py]
  red_on_base: [S-N1]
```

## Review log

| Rev | Reviewer | Verdict | Applied |
|---|---|---|---|
| 1 (`d7d0ce69`) | Argon (blind, 2026-11-25, 116 s) | READY AFTER SHOULD-FIX — 2 should-fix, 1 nit | Both verified by Claude and sent to the running Neon worker as a resume correction: tests wrap the real `posix_spawn` (raise on setsid, delegate otherwise, target assertion, no fake PID); keep one CodeQL-annotated sink. Nit: hub-only raw `posix_spawn` calls stay out of scope. |
