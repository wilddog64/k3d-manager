# hub-promote pushes run the pre-push hook with REF and BREAK_GLASS exported, so refusal tests fail

**Status:** OPEN
**Priority:** P2 — the promote half-completes (deploy/hub moves, tag push refused); workaround: push the tag with --no-verify
**Introduced by:** unknown
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-16
**Prior art:** docs/bugs/2026-11-08-hub-promote-no-op-promote-tags-and-breaks-rollback.md (name match) — read, different root cause; `make find-similar-docs` printed nothing (not run successfully)

## Symptom (2026-11-16, m4-air.local, operator's pane, promote of b5b931df)

`make hub-promote REF=b5b931df BREAK_GLASS=1`: the deploy/hub push succeeded
(`+ 50a42198...b5b931df -> deploy/hub (forced update)`), then the tag push ran the pre-push fast gate over 77 files and
was refused: `[hub-promote] ERROR: deploy/hub moved, but tag push failed (hub-promote/20261116T121447Z)`.
Failing tests, all "must refuse" assertions:

- `scripts/tests/bin/hub_promote.bats:712` and `:952` (N2: rollback refuses ...; BREAK_GLASS=1 permits) — `[ "$status" -ne 0 ]` failed
- `scripts/tests/bin/makefile_appsets.bats:109` (#8 promote without REF refuses) — `[ "$status" -eq 2 ]` failed

The same commit was green on all 7 CI check-runs.

## Likely cause (not yet proven)

Make exports command-line variables to every recipe child, so `git push` -> `.githooks/pre-push` -> BATS inherit
`REF=b5b931df` and `BREAK_GLASS=1`. The tests that expect a refusal without REF / without break-glass then see them set.
To prove before dispatch: rerun one failing test with `REF=x BREAK_GLASS=1 bats -f ...` (red) and without (green).

## Workaround used

`git push --no-verify origin refs/tags/hub-promote/20261116T121447Z` (tag now b276477d on origin), then
`make appsets-check && make platform-ops && make hub-promote-status` — all succeeded.

## Fix options (operator decision)

1. `bin/k3dm-hub-promote` pushes with `env -u REF -u BREAK_GLASS` (and any other make-exported promote vars).
2. The affected tests `unset REF BREAK_GLASS` in setup.
Both are cheap; 2 also protects any developer shell that has them exported.
