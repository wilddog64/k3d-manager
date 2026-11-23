# Review: lib-foundation PR #89 (v0.5.7 release) — blind diff review

**Filed:** 2026-11-18
**Repo / branch:** `lib-foundation` / `release/v0.5.7` (head 5492724; diff `f8025a2..5492724 -- scripts`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`) and Astra (codex, `gpt-6.2-astra`), each blind, role review

## Task

Review `git diff f8025a2..5492724 -- scripts` blind (CHANGE.md and docs are out of scope). Copilot is capped until
2026-12-01, so this review is the PR's review gate. Intended behaviour:

- **`_run_parallel_worker`** (`scripts/lib/system.sh`): each item is sanitized to a key and claims it exclusively by
  creating `<out>/.<key>.lock`; if the key is taken it tries `key-2`, `key-3`, ... Two items whose keys collide, even
  when running at the same moment, each get their own `.log/.rc/.sec/.item`. The claim must be exclusive whatever
  `mkdir` is installed (on Ubuntu 26.04, uutils `mkdir` can report success to two concurrent callers). Locks are kept
  until the next run, when `_run_parallel` removes them.
- **`_foundation_vcluster_lock` / `foundation_ensure_vcluster_cli`**: at most one caller holds the per-version lock;
  others retry (120 × 0.25 s) and then fail. The holder releases the lock on every exit path.
- Must work under macOS bash 3.2 and Linux bash 5, and with `set -euo pipefail` callers.
- **Tests** (`scripts/tests/lib/run_parallel.bats`, `scripts/tests/lib/system.bats`): a stub `mkdir` on `PATH` mimics
  uutils (exit 0 when the directory exists); the new tests must fail on the old `mkdir`-based claims.

Look for:
- any way two callers can hold the same lock or key (races, a lock path that already exists as a directory, a
  symlink at the lock path, `noclobber` semantics for non-regular files);
- a lock that is never released, released by the wrong caller, or left behind on an error or signal path;
- behaviour differences between bash 3.2 and bash 5, or under `set -e`/`set -u`;
- quoting or injection: unquoted expansions, keys or paths starting with `-`, paths with spaces;
- tests that cannot fail, test stubs that leak outside the test (PATH, files outside `BATS_TEST_TMPDIR`), or tests
  that depend on timing.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 5492724.
2. Read the changed hunks, then enough of `_run_parallel`, `_run_parallel_worker` and `foundation_ensure_vcluster_cli`
   to judge them.

## Files

| File | Change |
|---|---|
| `scripts/lib/system.sh` | read only |
| `scripts/tests/lib/run_parallel.bats` | read only |
| `scripts/tests/lib/system.bats` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT touch any cluster, Keychain or network endpoint; reason from the code (running the BATS files locally is fine).
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: Two independent models (Argon and Astra) check the v0.5.7 lock fix before you merge it, in place of Copilot this month; their findings are compared to judge whether Astra earns a place in spec and bug review.
interface: none
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** release PRs get a blind Argon review until 2026-12-01 (operator, 2026-11-17); "one more
agent can probably use spec/bug review: Astra ... it's expensive but worth a try" and "that's OpenAI so it is codex not
agy" (operator, 2026-11-18). Scope: one review each, read-only.
