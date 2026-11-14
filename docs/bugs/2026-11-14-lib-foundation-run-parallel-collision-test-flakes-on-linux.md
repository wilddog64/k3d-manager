# lib-foundation `run_parallel.bats` #157 (sanitized-collision test) flakes on Linux CI

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Waiting on:** investigation — since 2026-11-14
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
