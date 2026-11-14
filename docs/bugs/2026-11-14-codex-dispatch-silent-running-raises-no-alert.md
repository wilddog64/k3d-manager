# Bug: a dispatch that stays `running` with a silent log raises no alert

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Approval:** captured by Claude 2026-11-14 (operator "go ahead" to capturing it); fix not approved
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable (vector store needs the hub context, not on the M4); grep of codex-dispatch bug docs for stuck/hang/silent: 2026-10-09 metrics, scope, land and stdout docs, read, different root cause

## What happened

Correction 3 of `parallel-offline-tests-b` (agy, gemini-3.8-flash-medium) started 2026-11-13 17:34 PST. Its test
`makefile_test_all.bats` called `make test-all` with STAGE_* overrides, but the serial path ignored them and re-ran
`bats scripts/tests/bin`, which ran the same test again: 37 nested levels, 147 bats processes, 556 descendants of the
agy process, load average about 2. `agy-4.log` stopped at "root agent idle; waiting for 1 background task(s) to
finish". `codex-dispatch status` reported `running` for about 13 hours, until Claude killed the tree on 2026-11-14
around 15:00Z when the operator asked about progress.

Three Claude watchers (until-loops on `status`) were running the whole time and never fired, because they only checked
for a state other than `running`.

## Why it matters

`status` only learns about a run when the worker exits. Nothing compares the log's last write, or the size of the
process tree, with a limit. The `stall` gate in `bin/k3dm-codex-dispatch` (~389-412) counts unsuccessful attempts that
already finished, so it cannot see a run that never finishes. A stuck run uses up a WIP slot and machine time without
anyone noticing.

## Workaround in use

Claude's per-dispatch watcher now also stops on log silence (log mtime older than 45 minutes) and on a runaway process
count (more than 60 `bats-exec` processes under the worktree). Get the log mtime with `perl -e 'print
time-(stat shift)[9]'`: on the M4, GNU `stat` and `date` come first on PATH, so the BSD flags fail. Correction prompts
now require every `make`/`bats` command to run under `perl -e 'alarm shift; exec @ARGV' 1800`.

## Possible fix (not specified)

`status` (and `dispatch open`) reports `stalled` when a running run's log has not changed for N minutes, with its
age and process count. Optionally a Pushgateway gauge of log age, plus an alert. Restarting a stalled run automatically
is not proposed: a correction is needed first (see `feedback_no_rerun_without_fix`).
