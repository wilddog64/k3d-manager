# Bug: two overlapping dispatch-metrics runs crash on the shared Claude rollup temp file

**Status:** OPEN
**Priority:** P3
**Severity:** low — one metrics push is lost; the next run recovers
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from a traceback in `~/.local/share/k3d-manager/worktrees/metrics.log`
**Approval:** explicit 2026-10-25 ("go ahead for those two", after Claude offered to file the `rollup.json.tmp` race). Not critical (metrics script only).
**Component:** `bin/k3dm-dispatch-metrics` (`_claude_rollup`)

## Problem

`_claude_rollup` saves its cache by writing `<cache>.tmp` and then calling `os.replace(<cache>.tmp, <cache>)`.
The temp name is fixed. When two exporter runs overlap, the first `os.replace` moves the shared temp file
away, and the second fails:

```
FileNotFoundError: [Errno 2] No such file or directory: '.../claude-usage/rollup.json.tmp' -> '.../claude-usage/rollup.json'
```

The exception is not caught, so that run exits before it pushes anything.

Runs overlap because there are two callers. `bin/k3dm-codex-dispatch` runs the exporter in the background
under a lock directory, so its own runs never overlap. `make dispatch-metrics` runs it directly and does
not take that lock. `metrics.log` shows one occurrence on 2026-10-25.

The cache can be rebuilt. It holds per-message usage records and file offsets, and a run that loses the
race re-reads from the saved offsets next time. Last writer wins is acceptable; a crash is not.

## Fix

### F1. A private temp file per run

In `_claude_rollup`, create the temp file with `tempfile.mkstemp(dir=target.parent, prefix=target.name + ".",
suffix=".tmp")`, write the JSON through that descriptor, then `os.replace` it onto the target. If the write
or the replace fails, remove the temp file.

### F2. A failed cache save does not stop the run

If saving the cache raises `OSError`, write one line to stderr (`claude rollup cache not saved: <error>`) and
return the records anyway. The run goes on to push.

Do not change the cache format, its path, or how records and offsets are read.

## Tests

In `scripts/tests/bin/test_dispatch_metrics.py`:

1. **Overlap.** Monkeypatch `os.replace` so that its first call runs a second `_claude_rollup` (same projects,
   same cache) to completion before doing the real replace. Both calls return the records, no exception is
   raised, and the final cache loads as valid JSON.
2. **Save failure.** Monkeypatch `os.replace` to raise `FileNotFoundError`. `_claude_rollup` returns the
   records, writes the stderr line, and leaves no `*.tmp` file in the cache directory.
3. The existing `_claude_rollup` tests (dedup and incremental append) stay green.

Tests 1 and 2 must be red on a temp copy of the pre-fix script.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Two _claude_rollup calls that overlap on the same cache both return their records and leave a valid JSON cache.
  - id: M2
    text: A failure to save the cache is reported on stderr and the run continues with the records it read.
must_not:
  - id: N1
    text: No temp file is left in the cache directory after a failed save.
  - id: N2
    text: No change to the cache path, cache format, records returned or the metrics exported.
  - id: N3
    text: Tests never push to the real Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py green; tests 1 and 2 red on a temp copy of the pre-fix script; python -m py_compile bin/k3dm-dispatch-metrics clean.
  - id: E2
    kind: live
    proves: [M1]
    text: Claude checks metrics.log for a week after landing; no rollup.json.tmp traceback appears.
interface:
  - bin/k3dm-dispatch-metrics function _claude_rollup(projects, cache_path, context_out=None), as imported by test_dispatch_metrics.py
  - the cache file passed as cache_path and its directory
```

## Definition of Done

- [ ] F1–F2 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1 and 2 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(dispatch): give each Claude rollup cache save its own temp file`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT add a lock to `make dispatch-metrics` or change `bin/k3dm-codex-dispatch`.
- Do NOT push to the real Pushgateway; tests use `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions.
- Do NOT modify files outside the Files list.
