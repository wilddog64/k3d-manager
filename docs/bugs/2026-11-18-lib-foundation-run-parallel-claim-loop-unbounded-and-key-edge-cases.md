# lib-foundation `_run_parallel`: claim loop never gives up, and key/output edge cases

**Status:** OPEN — captured 2026-11-18 from the PR #89 blind reviews (Argon, Astra 6.2, Fable)
**Priority:** P3 — no current caller hits these (the one caller, `Makefile:1773`, passes `scripts/tests/...` paths to a fresh stage dir)
**Triage:** backlog — pull into a release that already touches `scripts/lib/system.sh` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** pre-existing (present at lib-foundation `f8025a2`, before v0.5.7)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Latent edge cases and test flakiness in `_run_parallel` (unbounded claim loop on invalid paths, dot-prefixed keys, shared `--out`) not triggered by current callers.)
**Waiting on:** operator decision — since 2026-11-18 (grooming)
**Prior art:** `docs/bugs/2026-11-14-lib-foundation-run-parallel-collision-test-flakes-on-linux.md` (exact-slug review) — read, different root cause (non-exclusive claim, fixed in v0.5.7). `make find-similar-docs` not run (vector store unreachable, 2026-11-18).
**Filed:** 2026-11-18
**Approval:** operator, 2026-11-18: "we should caputre lder findings in P3 for grooming"

All references are lib-foundation `scripts/lib/system.sh` at `15d5001` (v0.5.7 merge).

## Findings

1. **Claim loop never gives up (`:875`)** — Fable (reproduced), Astra. `while ! ( set -o noclobber; : >"${out}/.${key}.lock" )`
   treats every failure as "key taken". A key longer than NAME_MAX (Fable: 260-char item) or a missing/unwritable `--out`
   makes the worker spin forever, forking a subshell per try; `_run_parallel` hangs in `xargs`. Medium if hit.
2. **Startup cleanup removes another run's live locks (`:913`)** — Astra. `rm -rf "$out"/.*.lock` runs at start, so two
   concurrent runs sharing one `--out` can both claim the same key and write the same `.log/.rc/.sec/.item`.
3. **Dot-prefixed keys are skipped when collecting results (`:946`)** — Astra. `for arg in "$out"/*.item` does not match
   `.hidden.item` (no `dotglob`), so a failing item `.hidden` (or `./x`, sanitized to `._x`) is silently left out and
   the run can report success.
4. **`mkdir -p "$out"` without `--` (`:911`)** — Astra. An `--out` starting with `-` is parsed as options.
5. **Concurrency test requires a peak of exactly 2 (`scripts/tests/lib/run_parallel.bats:44`)** — Astra. A slow
   scheduler can give peak 1 on a correct run (test-only).

## Possible fix (for grooming)

Bound the claim loop (or fail on any error other than EEXIST, e.g. check `[[ -e lock ]]` after a failed claim and
return non-zero otherwise); include dot files when collecting (`shopt -s dotglob` locally or a second glob); `mkdir -p --`;
assert peak `<= 2` and `>= 1` with a separate overlap control. Item 2 needs a decision: document "one run per `--out`"
or use a per-run lock subdirectory.
