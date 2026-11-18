# lib-foundation `run_parallel.bats` #157 (sanitized-collision test) flakes on Linux CI

**Status:** LANDED — lib-foundation `a561b16` on `release/v0.5.7` (noclobber lock claims for `_run_parallel_worker` and `_foundation_vcluster_lock`; root cause uutils `mkdir` on ubuntu-26.04); test fixes `7027b38`
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-18 (CI E2 passed; PR #89 needs Argon review and merge)
**Triage:** carry → v1.45.0; Priority raised P3 → P2 (Argon P2 accepted: drops a worker result); fix upstream in lib-foundation — operator grooming 2026-11-15 ("Accept as shown")
**Introduced by:** unknown
**Should have been caught by:** offline test
**Severity:** low — test-only so far; one red CI attempt on lib-foundation PR #85, green on rerun. If the cause is in
`_run_parallel` itself, a parallel run can drop one item's result
**Approval:** none yet (captured per "capture first, triage later", 2026-11-11)
**Prior art:** none above threshold — grep of `docs/bugs/` and `docs/issues/` for `run_parallel` found nothing;
`find-similar-docs` not run (store needs kube context `k3d-k3d-cluster`).
**Filed:** 2026-11-14
**Detected by:** Claude, lib-foundation PR #85 (release/v0.5.6) CI run 43594861512 attempt 1, 2026-11-14 12:27Z
**Affected:** lib-foundation `scripts/lib/system.sh` (`_run_parallel`, `_run_parallel_worker` ~line 865),
`scripts/tests/lib/run_parallel.bats` lines 47-56 — fix upstream, then subtree-pull
**Branch:** `k3d-manager-v1.44.0`

## Symptom

    not ok 157 bounds concurrency and records each result; sanitized collisions keep separate files
    #   `[ "$(cat "$RP_ROOT/out/a_b-2.rc")" -eq 0 ]' failed with status 2
    # PASS a b 0s
    # PASS sleep:a 1s ... PASS sleep:d 0s
    # cat: /tmp/bats-run-xFFhki/test/157/out/a_b-2.rc: No such file or directory

Attempt 2 of the same run was green. Not reproduced on macOS (0/40 local runs).

## Clues

- The summary lists `PASS a b` but no line for `a_b`: six items went in, five results came out.
- The key claim is an atomic `mkdir "${out}/.${key}.lock"`, so two workers cannot get the same key. The loss is more
  likely in how `_run_parallel` gathers results (keys found or read before the second worker's `.rc` is written),
  or the worker for `a_b` never ran.
- The test's `for key ...; do [ -f ... ] && [ -f ... ] && [ -f ... ]; done` cannot fail on the first five keys
  (an `&&` list does not trip errexit except on its last element), so it hides which files are missing.

## Next step

Loop the test in a Linux container (ubuntu, bash 5, GNU xargs) until it reproduces, then read
the result-gathering code in `_run_parallel`. Also make the loop assertion fail per key.

## Investigation 2026-11-18 (Claude)

**#157 (sanitized collision, missing `a_b` result): not reproduced in 850 runs.**
- 300 runs of the test alone: `ubuntu-bats` image (bats 1.10, bash 5.2.21, GNU xargs 4.9), aarch64, `--cpus 2`.
- 400 runs instrumented, on 1 CPU with 3 busy loops.
- 150 runs of the whole `run_parallel.bats`: ubuntu 24.04 amd64 (emulated), bats 1.13.0 (the CI version), `env -i HOME PATH` as in CI.
- What the code allows: the summary printed under errexit, so `xargs` returned 0 and every worker exited 0, but one
  `.item` file was missing. That leaves either two workers both winning `mkdir "${out}/.${key}.lock"` (and the second
  overwriting the first's files), or `xargs` never starting one worker. Neither looks possible from the code, and the CI
  log for run 43594861512 has expired.

**A second flake was found: test 4 ("summary has sorted result lines followed by slowest and total"), 10/150 on emulated amd64.**
`grep -Eq '^FAIL fail-item 0s \(rc 7\)$'` fails. Cause: `_run_parallel_worker` times each job as the difference
of two whole-second `date +%s` readings (`scripts/lib/foundation/scripts/lib/system.sh:878-882`). A job of a few
milliseconds that straddles a second boundary reports `1s`. The odds equal the job's run time as a fraction of a
second: rare on a fast runner, about 7% under emulation. This is a test defect, not a `_run_parallel` defect: the
assertion should accept `[0-9]+s`, as the SLOWEST and TOTAL lines already do.

**Next step:** fix upstream in lib-foundation, both test-only. (1) Test 4 accepts `[0-9]+s` for the fail-item line.
(2) The #157 loop assertion fails per key and dumps the out directory listing, so the next CI red says which case it was.

## CI evidence 2026-11-18 (new assertion, lib-foundation PR #89, run 44237174229)

The per-key assertion caught it on its first CI run: `missing: a_b-2.log`. The out directory held **five** claim locks
(`.a_b.lock`, `.sleep_{a,b,c,d}.lock`) and five `.item` files; `a_b.item` = `a b`. The sixth item `a_b` (the last one)
left no lock and no files, yet `xargs` exited 0 (the summary printed). Two workers would leave two locks in any order,
so "two workers won one lock" is ruled out: the last item's worker never reached its `mkdir` claim before `xargs`
returned.

Frequency: test 157 failed in 4 of the last 9 CI runs (43429853156, 43429856059, 43598270591, 44237174229), always with
`a_b-2` (the last item) missing; 0/850 locally. Local check: running bats with `SIGCHLD` set to `SIG_IGN` (ubuntu 24.04,
GNU xargs 4.9.0) did not reproduce it (0/30 both ways).

Open question: did the last worker run late (xargs returned before it), or never start? Next diagnostic: on failure,
wait and list the out directory again, print `$RP_LOG` (which items the job saw) and the shell's signal masks.

## CI evidence 2026-11-18, second run (diagnostic `884e3aa`, run 44298944446) — corrects the section above

Both colliding items ran: the job log shows `<a_b>` and `<a b>`. The out directory still held one lock, `.a_b.lock`, and
one set of `a_b.*` files (`a_b.item` = `a_b`; summary lists only `PASS a_b`); no `.a_b-2.lock`, also after a 2 s wait;
no workers still running. Both workers therefore ended with key `a_b`: both `mkdir .a_b.lock` claims succeeded, or the
lock vanished between them. The previous section's "the last item's worker never claimed" was wrong — two successful
claims on one path also leave one directory.

Runner facts: GNU findutils xargs **4.10.0** (local repro images had 4.9.0), nproc 4, SigIgn 0x1004 (SIGQUIT, SIGPIPE),
SIGCHLD not ignored. No `mkdir` override in `scripts/lib`. Fable investigating (read-only).

## Root cause (2026-11-18, Fable; verified by Claude)

GitHub `ubuntu-latest` is now `ubuntu-26.04` (run 44298944446: `Image: ubuntu-26.04`, version 20261103.629). There,
`/usr/bin/mkdir` is uutils coreutils 0.10.0 (`rust-coreutils`, `/usr/lib/cargo/bin/coreutils/mkdir`), not GNU. When two
processes `mkdir` the same path at once, both can exit 0, so the `_run_parallel_worker` claim loop
(`while ! mkdir "${out}/.${key}.lock"`) is not exclusive: both colliding items take key `a_b` and overwrite each other's
files. Fable cites uutils 0.10.0 `src/uu/mkdir/src/mkdir.rs:342` (`Err(_) if path.is_dir() => Ok(())`; upstream main
adds `config.recursive &&`).

Claude's check in Docker `ubuntu:26.04`, 2026-11-18: concurrent `mkdir` of one path, both exit 0 in 136/500 (uutils) vs
0/500 (`gnumkdir`). A sequential `mkdir` of an existing dir still returns 1, so only the race is affected. Fable: real
`_run_parallel` collision 15/200 with uutils vs 0/200 with GNU mkdir; ubuntu:24.04 0/2000 — why 850 local runs passed.

This is a library bug on Ubuntu 26.04 (any colliding keys running concurrently lose a result), not only a test flake.
`_foundation_vcluster_lock` (`scripts/lib/system.sh:2172`) uses the same `mkdir` lock pattern.

## CI verification 2026-11-18 (E2)

PR #89 run 44301926748 on `5492724` (fix `a561b16`), attempts 1-3: all check-runs green (bats, shellcheck, acg); each
bats job on `Image: ubuntu-26.04` shows `ok` for the collision test and the three stub-`mkdir` lock tests.
