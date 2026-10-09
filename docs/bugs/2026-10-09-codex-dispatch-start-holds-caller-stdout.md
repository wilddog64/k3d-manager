# Bug: `codex-dispatch start` keeps the caller's stdout open until Codex exits

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `50fdf67b` 2026-10-09 (Codex via worktree dispatch; Claude verified 18/18 BATS, shellcheck clean, mutation red)
**Priority:** P3 — `start` appears to hang when its output is piped; the run itself is fine
**Severity:** low

## Symptom

`make codex-dispatch SPEC=… | tail -3` did not return until the Codex run finished, about 10 minutes
later. Unpiped, `start` returns at once. Any caller that captures `start`'s output inherits the hang,
including a pipe, `$(…)`, or a Claude tool call with a timeout.

## Cause

`_dispatch_start` launches Codex as `( … ) &`. Inside, Codex's own output goes to `codex.log`, but
the subshell keeps the caller's stdout and stderr open. `$?` is written to `<run>/exit`. A reader on
the other end of a pipe waits for every writer to close, so it waits for the whole subshell.

## Fix

Give the background subshell its own stdio, and detach it from the caller's session:

```bash
  (
    ...
  ) </dev/null >/dev/null 2>&1 &
```

Codex already redirects its own output into `codex.log`, so nothing is lost. Keep the
`printf '%s\n' "$!" >"$run/pid"` line.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | background subshell gets `</dev/null >/dev/null 2>&1` |
| `scripts/tests/bin/codex_dispatch.bats` | regression test |

## Tests

New test in `scripts/tests/bin/codex_dispatch.bats`, with `STUB_SLEEP=5`:
- `start` piped through `cat` returns in under 3 seconds:
  `timeout 3 bash -c 'dispatch … | cat'` (define `dispatch` inside, or call the script path
  directly) exits 0.
- `<run>/exit` appears later, after the stub finishes.

Mutation check: remove the redirection. The test must fail on the timeout.

## Rules

- `shellcheck bin/k3dm-codex-dispatch`: zero warnings.
- `bats scripts/tests/bin/codex_dispatch.bats`: all green. Paste the output.
- If `timeout` is missing on macOS, use `gtimeout` when present, or a bash `SECONDS` loop with
  `kill`. Do not add a dependency.
- Do not commit. `.git` is read-only in the sandbox.
