# Bug: `codex_dispatch.bats` fails from 2026-11-08, because its fixture spec has no intent approval

**Status:** LANDED — the fixture spec carries `**Intent approved:**`; `codex_dispatch.bats` 105/105 on 2026-11-08 (local date past the rule date), two sampled tests red on the pre-fix file under the same date
**Priority:** P2
**Waiting on:** live check — since 2026-11-08 (green push CI on the release branch head)
**Introduced by:** `f1bab51e` (v1.43.15, intent-verification)
**Should have been caught by:** offline test
**Severity:** medium — CI is red on the release branch, so `make hub-promote` refuses the head without `BREAK_GLASS=1`, and `make test` fails locally from the same date
**Approval:** operator, 2026-11-08 ("Claude fixes directly")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** Claude, reading the first push CI run on the release branch head
**Affected:** `scripts/tests/bin/codex_dispatch.bats` (fixture spec, `:33`); behaviour comes from `scripts/lib/spec_intent.py:40`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

CI run 42444123512 on `edcfaab4` (started 2026-11-08T03:46:49Z): the `lint` job failed with exit code 2 in the
offline suite. 77 tests failed, all in `codex_dispatch.bats`, each ending in:

    [codex-dispatch] ERROR: refused: spec-intent: .../fixture/docs/plans/v9.9.9-demo.md: missing **Intent approved:** header

The same tests passed on 2026-11-07.

## Root cause

`spec_intent.check()` dates a spec by its `**Filed:**` line and, without one, by the date of its first commit
(`spec_intent.py:40`). Specs dated on or after `INTENT_RULE_DATE` (2026-11-08) need `**Intent approved:**`.
The `codex_dispatch.bats` fixture spec has no `**Filed:**` line and is committed while the test runs, so its date is
the current day. Before 2026-11-08 the gate passed it; from 2026-11-08 UTC it refuses every `dispatch start`.

The gate is correct. The tests depended on the wall clock: the intent-verification change was tested on
2026-11-07, the one day where the fixture's date still sat before the rule date.

## Reproduction (pre-fix)

Claude's M4 session, 2026-11-07 PT, before the local date rolled over:

- `bats -f 'S1 writes coverage marker once' scripts/tests/bin/codex_dispatch.bats` → `ok 1`
- `GIT_COMMITTER_DATE=2026-11-08T12:00:00Z GIT_AUTHOR_DATE=2026-11-08T12:00:00Z bats -f 'S1 writes coverage marker once' scripts/tests/bin/codex_dispatch.bats`
  → `not ok 1` with the same `missing **Intent approved:** header` refusal

## Fix

The fixture spec carries `**Intent approved:** test, 2026-11-07`. It has no Acceptance evidence block, so the
header is its only gap, and the gate passes it whatever date it gets. The dispatcher tests then run a spec that
the gate checks and accepts, rather than one that is always older than the rule.

## Second instance: `test_all_existing_specs_are_exempt_as_of_this_commit`

The same assumption sits in `scripts/tests/bin/test_spec_intent.py`. The test ran the gate over every doc in
`docs/plans/` and `docs/bugs/`. From 2026-11-08, any doc filed without `**Intent approved:**` failed it, though
`CLAUDE.md` requires the header only before dispatch. This doc tripped it when first written
(`make test-pytest`, 2026-11-08: `missing **Intent approved:** header`).

Fix: the test checks only the docs that existed at `c5d28596`, the commit that fixed the rule's date scope
(1841 paths, read with `git ls-tree`; CI's `lint` job checks out with `fetch-depth: 0`). That keeps its guard:
a pre-rule doc that the gate misdates still fails it. Evidence, 2026-11-08, Claude's M4 session:

- new test, current tree → `1 passed`
- old test with an unapproved doc filed 2026-11-08 → `1 failed` (the probe doc listed); new test → `1 passed`
- new test with `docs/bugs/2026-11-02-hub-data-export-never-ran.md` redated to `**Filed:** 2026-11-08` →
  `1 failed`; the file was restored and compared with `cmp`
- `python3 -m pytest -q scripts/tests/bin/test_spec_intent.py` → `12 passed`
