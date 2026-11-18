# Plan: `_run_parallel` and the vCluster CLI lock are not exclusive on Ubuntu 26.04 (uutils `mkdir`) (v0.5.7)

**Filed:** 2026-11-18
**Branch:** `release/v0.5.7` (lib-foundation)
**Status:** PLANNED — ready for dispatch
**Covers:** `docs/bugs/2026-11-14-lib-foundation-run-parallel-collision-test-flakes-on-linux.md` (Root cause 2026-11-18)
**Risk:** low-medium (two lock claims in `scripts/lib/system.sh`; behaviour on GNU/macOS unchanged; proofs below)
**Reviewed:** Claude only (root cause reproduced by Fable and Claude; operator chose the scope)
**Agent:** Luna (Codex)

## Problem

GitHub `ubuntu-latest` is `ubuntu-26.04`, whose `/usr/bin/mkdir` is uutils coreutils 0.10.0. When two processes `mkdir`
the same path at once, both can exit 0. Two lock claims in `scripts/lib/system.sh` rely on `mkdir` failing when the
directory exists:

1. `_run_parallel_worker` (`:875`): `while ! mkdir "${out}/.${key}.lock" 2>/dev/null; do` — two items that sanitize to
   the same key both claim it and overwrite each other's `.log/.rc/.sec/.item` (PR #89 CI, run 44298944446).
2. `_foundation_vcluster_lock` (`:2170-2177`): `while ! mkdir -- "${lock_dir}" 2>/dev/null; do` — two concurrent
   `foundation_ensure_vcluster_cli` callers can both hold the lock. Released by `rmdir -- "${lock_dir}"` (`:2209`).

## Proof of external behaviour

- uutils race (Claude, Docker `ubuntu:26.04` aarch64, 2026-11-18, `mkdir (uutils coreutils) 0.10.0`): two concurrent
  `mkdir` of one path both exit 0 in 136/500; `gnumkdir` 0/500. A sequential `mkdir` of an existing dir returns 1.
- Runner: run 44298944446 log `Image: ubuntu-26.04`, `Version: 20261103.629`.
- Replacement (Claude, 2026-11-18): `( set -o noclobber; : >"$f" ) 2>/dev/null` raced by two processes, both succeed
  0/500 on `ubuntu:26.04` bash 5.3.9 and 0/500 on macOS `/bin/bash` 3.2.57; on an existing directory it returns 1 on both.
  bash opens the file with `O_CREAT|O_EXCL` under noclobber, so no external tool is involved.

## Before You Start

1. Read the bug doc above (sections "CI evidence 2026-11-18, second run" and "Root cause").
2. Read `scripts/lib/system.sh:865-915` and `:2165-2240`, `scripts/tests/lib/run_parallel.bats` in full, and
   `scripts/tests/lib/system.bats` `foundation_vcluster_fixture` (`:131`) and the vCluster tests (through `:730`).

## Fix

1. **`_run_parallel_worker` (`:875`):** change the claim to
   `while ! ( set -o noclobber; : >"${out}/.${key}.lock" ) 2>/dev/null; do`. The lock is now a file. Keep the
   `rm -rf "$out"/.*.lock` cleanup in `_run_parallel` (`:913`) unchanged (it removes files and old directory locks).
2. **`_foundation_vcluster_lock` (`:2172`):** change the claim to
   `while ! ( set -o noclobber; : >"${lock_dir}" ) 2>/dev/null; do`; keep the retry count and `sleep 0.25`.
   In `_foundation_vcluster_release` change `rmdir -- "${lock_dir}" 2>/dev/null || true` to
   `rm -f -- "${lock_dir}" 2>/dev/null || true`. Change no other line in `foundation_ensure_vcluster_cli`.
3. **`scripts/tests/lib/run_parallel.bats`:** remove the diagnostic lines added in `884e3aa` (`:57-63`, from
   `echo "job saw:"` through the `xargs:` line); keep `missing:`, `ls -la`, the item mapping and `return 1`.
4. **`scripts/tests/lib/system.bats:694`:** the lock-held probe checks `-d`; change it to `-e` (the lock is a file).

## Files

| File | Change |
|---|---|
| `scripts/lib/system.sh` | Fix 1, 2 |
| `scripts/tests/lib/run_parallel.bats` | Fix 3; test 1 |
| `scripts/tests/lib/system.bats` | Fix 4; tests 2-3 |

## Contract readers

Lock paths `<out>/.<key>.lock` and `${XDG_DATA_HOME}/lib-foundation/vcluster/<version>.lock` — grep
`_foundation_vcluster_lock|vcluster/.*\.lock|lock_dir|\.lock` over lib-foundation `scripts bin` and k3d-manager
`scripts bin Makefile`:
- writer/claimer `system.sh:875` and `:2172` — **change** (directory → file).
- remover `system.sh:913` (`rm -rf`, unchanged, handles both) and `:2209` — **changes** (`rmdir` → `rm -f`).
- reader `scripts/tests/lib/system.bats:694` (`-d`) — **changes** to `-e`; `:700`, `:713` (`! -e`) unchanged.
- No reader in k3d-manager (its lib-foundation subtree does not call either lock outside `system.sh`).
- Not in scope: `scripts/etc/contrib/statusline.sh:302` also uses a `mkdir` lock (macOS status line, a stale-lock cache,
  not correctness-critical); left unchanged.
- An old-format directory lock left by a crash before this change is not removed by `rm -f`; the vCluster claim then
  times out exactly as a stale directory lock does today. Accepted.

## Tests (these names exactly)

Both stub tests put a `mkdir` on `PATH` that mimics uutils in the race, from the capture above. Build it as:
`real="$(command -v mkdir)"`, then a script `bin/mkdir` with a comment `# mimics uutils coreutils 0.10.0 mkdir losing a
race (ubuntu:26.04, 2026-11-18): exits 0 when the directory already exists`, body
`for a in "$@"; do last="$a"; done; [ -d "$last" ] && exit 0; exec "$real" "$@"` (with `$real` expanded when written).
First assert the stub behaves: `mkdir "$d"; mkdir "$d"` returns 0 with the stub on `PATH`.

1. `run_parallel.bats`: `colliding keys stay separate even when mkdir succeeds on an existing directory` — stub on
   `PATH` and exported; `printf 'a b\0a_b\0' | _run_parallel --jobs 1 --out "$RP_ROOT/out" -- "$RP_JOB"`; both
   `a_b.item` and `a_b-2.item` exist and their contents are `a b` and `a_b` in some order. Red today (deterministic:
   with `--jobs 1` the second claim of `a_b` succeeds through the stub).
2. `system.bats`: `vcluster lock: a held lock is not taken again even when mkdir succeeds on an existing directory` —
   stub on `PATH`, plus a `sleep` stub that exits 0 at once (so the 120 retries take no time); call
   `_foundation_vcluster_lock "$BATS_TEST_TMPDIR/v.lock"` (status 0), then `run _foundation_vcluster_lock` on the same
   path: status nonzero. Red today.
3. `system.bats`: `vcluster lock: a released lock can be taken again` (positive control for 2) — same stubs; take the
   lock, remove it the way `_foundation_vcluster_release` does (`rm -f --`), take it again: status 0.

The existing collision test (`run_parallel.bats:48`) and vCluster concurrency/hold tests stay and must pass unchanged
(apart from Fix 3-4).

Pre-fix red: 1 and 2 fail on today's code; 3 passes. Mutations (apply by hand, run, revert): put back the `mkdir` claim
in `_run_parallel_worker` (1 red); put back the `mkdir` claim in `_foundation_vcluster_lock` (2 red); make the vCluster
claim `( : >"${lock_dir}" )` without noclobber (2 red); leave `rmdir` in the release (`system.bats` hold/concurrency
tests red on `! -e`).

## What NOT to Do

- Do not change `_run_parallel` except as stated, the retry count or sleep in `_foundation_vcluster_lock`, the summary
  format, key sanitizing, or `statusline.sh`.
- Do not add a dependency on `flock`, `ln`, `mkdir` flags or any external tool for the claim.
- Do not touch `CHANGE.md`, `docs/` or `memory-bank/`. Do not commit, push or open a PR; Claude verifies and commits.
- Do not skip hooks. Do not modify files outside the Files table.

## Rules

LF only; keep indentation, quoting and naming; no unsolicited refactors. Must work on macOS bash 3.2 and Linux bash 5.
If the spec contradicts the code, stop and say so.

## Gates

`bats scripts/tests/lib/run_parallel.bats scripts/tests/lib/system.bats`, then `shellcheck scripts/lib/system.sh`, then
the repo's full BATS suite as CI runs it.

## Definition of Done

- [ ] Fix 1-4; `git status` shows only the three files.
- [ ] Pre-fix red for 1 and 2, green for 3, recorded.
- [ ] Gates green; mutation table recorded.
- [ ] Report: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
interface:
  - "_run_parallel --jobs N --out DIR -- CMD (items whose sanitized keys collide)"
  - "_foundation_vcluster_lock LOCK_PATH / foundation_ensure_vcluster_cli VERSION"
must:
  - id: M1
    text: items whose sanitized keys collide each get their own result files (key, key-2, ...), whatever mkdir is installed
  - id: M2
    text: a held vCluster CLI lock is not granted to a second caller, and is granted again after release
  - id: M3
    text: behaviour on macOS bash 3.2 and GNU coreutils is unchanged (existing run_parallel and vCluster tests pass)
must_not:
  - id: N1
    text: a lock claim succeeds because mkdir reported success on an existing directory — red today
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: bats scripts/tests/lib/run_parallel.bats scripts/tests/lib/system.bats -f "mkdir succeeds on an existing directory|released lock can be taken again"
    intent: "Parallel runs no longer lose a result when two items get the same name, and two vCluster installs can no longer run at once, on the new Ubuntu 26.04 runners as well as on your Macs."
  - id: E2
    proves: [M1, M3]
    kind: live
    what: "Claude: PR #89 CI (ubuntu-26.04) green on three runs of the bats job, including the collision test."
    intent: "The CI failure on PR #89 is gone on GitHub's new runners."
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "go ahead to proposed fix, and _foundation_vcluster_lock should covered by the fix" (after
Claude proposed the noclobber claim, a stub-mkdir regression test, removing diagnostic `884e3aa`, and asked about the
vCluster lock). Scope: the two claims, their release, tests; CHANGE.md by Claude after landing.
