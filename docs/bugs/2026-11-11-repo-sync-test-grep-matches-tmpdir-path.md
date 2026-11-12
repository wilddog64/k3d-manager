# repo_sync.bats "never promotes or pushes" fails when the temp path contains hub-rollback or hub-promote

**Status:** LANDED — fixed by Claude 2026-11-11 in the commit that adds this doc
**Priority:** P3
**Introduced by:** unknown (the unanchored grep predates v1.43.15's dispatch slugs that contain the words)
**Should have been caught by:** review
**Prior art:** none above threshold — exact-slug glob empty; `make find-similar-docs` not run (vector store context missing earlier today)
**Approval:** Claude, 2026-11-11 (test-only fix, found blocking a land)

## Symptom

`make codex-land SLUG=2026-11-11-hub-rollback-confirmation-hides-dropped-commits` failed its fast gate on
`scripts/tests/bin/repo_sync.bats:433` (`return 1`), although the suite passes 18/18 from the main checkout and from the
task worktree.

## Root cause

The test asserts `! grep -Eq ' push |hub-promote|hub-rollback' "$GIT_LOG" "$MAKE_LOG"`. The words are unanchored, and
the git stub logs every argument, including `-C <scratch path>`. `land` sets `TMPDIR=$run/state/tmp`
(`bin/k3dm-codex-dispatch:1165`), so for a task whose slug contains `hub-rollback` the scratch path itself matched.
Reproduced 2026-11-11: with `TMPDIR=<scratchpad>/x-hub-rollback-y/tmp` the test is red, with `<scratchpad>/plain/tmp`
it is green.

## Fix

Anchor the words on whitespace, as the same file's line-310 assertion already does:
`(^|[[:space:]])(push|hub-promote|hub-rollback)([[:space:]]|$)`. Checked: 18/18 with the hostile TMPDIR; the pattern
still matches `-C /x push origin deploy/hub`, `--no-print-directory hub-promote REF=x` and `hub-rollback`, and no longer
matches `-C /x/2026-11-11-hub-rollback-confirm/tmp fetch origin`.
