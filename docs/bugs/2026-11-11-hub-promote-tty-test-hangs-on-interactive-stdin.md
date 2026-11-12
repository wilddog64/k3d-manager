# hub_promote.bats "non-TTY" test hangs forever when the suite runs from a terminal

**Status:** OPEN — found 2026-11-11 by Claude (Flash review child hung 40 min)
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-11 (fold into the open rollback dispatch, which owns `hub_promote.bats`)
**Introduced by:** `897cfe72` (v1.43.15, deploy/hub with hub-promote and hub-rollback)
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md` — read by title, same class (test inherits an interactive stdin), different file; none above threshold otherwise (`find-similar-docs` not run)
**Approval:** not yet

## Symptom

The Flash review child of `2026-11-11-hub-rollback-confirmation-hides-dropped-commits` sat idle for 40 minutes
(`agy.log`: "root agent idle; waiting for 1 background task(s) to finish"). Its `bats scripts/tests/bin/hub_promote.bats`
was blocked in test 7, `k3dm-hub-promote promote` under `/private/tmp/bats-run-*/test/7/scratch-repo`, on `ttys006`.
Claude stopped that scratch process (2026-11-11) and the suite carried on.

## Root cause

`scripts/tests/bin/hub_promote.bats:305` (test "N2: non-TTY and wrong confirmation refuse…") calls
`run env … k3dm-hub-promote promote …` without redirecting stdin. bats passes the runner's stdin through. Under CI or a
non-interactive shell `[[ -t 0 ]]` is false and the script refuses as the test expects; from an interactive terminal
it is true and the script waits at `Type 'promote' to continue:` forever.

## Fix direction

Add `< /dev/null` to that `run` (and any other call in the suite meant to have no TTY). Test: the suite completes when
run under `script -q /dev/null bats …` (a pseudo-terminal), and the N2 assertion still sees "requires a TTY".
