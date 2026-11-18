# Bug: `codex-dispatch land` refuses with "Codex is still running" when the OS reused the worker's PID

**Status:** OPEN — captured 2026-11-18
**Priority:** P3 (land is refused with a misleading error; workaround: move `<slug>.run/pid` aside)
**Introduced by:** pre-existing (the `status`/`resume` PID-reuse fix in `2de716d8` did not cover `land`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-18
**Prior art:** `docs/bugs/2026-10-20-codex-dispatch-background-process-lost-no-terminal-status.md` (grep match on "PID reuse", `find-similar-docs` not run: the vector store is on the hub) — read, different code path: that fix added `_dispatch_worker_matches_start` for `status` and `resume`; `land` was not changed
**Found by:** Claude, landing `test-all-metrics-explicit-pushgateway` on the M4, 2026-11-18

## Symptom

`land --slug test-all-metrics-explicit-pushgateway` failed with `[codex-dispatch] ERROR: Codex is still running`.
The run had `exit` = `0` and `status` reported `exited successfully`. The recorded `pid` (8626) belonged to
`/System/Library/PrivateFrameworks/CacheDelete.framework/deleted`, started 15 minutes earlier: macOS had reused the PID.

## Cause

`bin/k3dm-codex-dispatch:1358` (land) checks liveness with a bare `kill -0 "$pid"`. `resume` (`:1639`) already uses
`[[ ! -f "$run/exit" ]] && _dispatch_worker_matches_start "$run"`, which compares the process start time recorded in
`<slug>.run/start` and ignores a run that has an `exit` marker.

## Workaround

`mv <slug>.run/pid <slug>.run/pid.stale` after confirming `<slug>.run/exit` exists, then re-run `land`.

## Fix

`docs/plans/codex-dispatch-land-pid-reuse.md`.
