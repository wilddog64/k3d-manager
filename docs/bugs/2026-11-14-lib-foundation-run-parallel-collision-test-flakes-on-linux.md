# lib-foundation `run_parallel.bats` #157 (sanitized-collision test) flakes on Linux CI

**Status:** OPEN — captured, not triaged
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-18 (two test-only fixes proposed upstream; #157 not reproduced)
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
