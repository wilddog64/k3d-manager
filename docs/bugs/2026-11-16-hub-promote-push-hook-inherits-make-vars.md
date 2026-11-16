# hub-promote pushes run the pre-push hook with REF and BREAK_GLASS exported, so refusal tests fail

**Status:** OPEN
**Priority:** P2 — the promote half-completes (deploy/hub moves, tag push refused); workaround: push the tag with --no-verify
**Introduced by:** unknown
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-16 (operator: "fix in v1.44.1"; spec next)
**Branch:** k3d-manager-v1.44.1
**Triage:** patch → v1.44.1 — operator 2026-11-16 ("fix in v1.44.1")
**Prior art:** docs/bugs/2026-11-08-hub-promote-no-op-promote-tags-and-breaks-rollback.md (name match) — read, different root cause; `make find-similar-docs` printed nothing (not run successfully)

## Symptom (2026-11-16, m4-air.local, operator's pane, promote of b5b931df)

`make hub-promote REF=b5b931df BREAK_GLASS=1`: the deploy/hub push succeeded
(`+ 50a42198...b5b931df -> deploy/hub (forced update)`), then the tag push ran the pre-push fast gate over 77 files and
was refused: `[hub-promote] ERROR: deploy/hub moved, but tag push failed (hub-promote/20261116T121447Z)`.
Failing tests, all "must refuse" assertions:

- `scripts/tests/bin/hub_promote.bats:712` and `:952` (N2: rollback refuses ...; BREAK_GLASS=1 permits) — `[ "$status" -ne 0 ]` failed
- `scripts/tests/bin/makefile_appsets.bats:109` (#8 promote without REF refuses) — `[ "$status" -eq 2 ]` failed

The same commit was green on all 7 CI check-runs.

## Cause (proven offline, 2026-11-16, m4-air.local, Claude)

Two channels, both from `make hub-promote REF=... BREAK_GLASS=1`:
- **`MAKEFLAGS`** carries the command-line variables into any nested `make`. `makefile_appsets.bats` "#8 promote without
  REF refuses" runs `make`, so it sees `REF` again: red with `MAKEFLAGS=' REF=b5b931df BREAK_GLASS=1'` in the
  environment, green without. Plain `REF=x BREAK_GLASS=1` in the environment alone stays green.
- **Environment** `REF`/`BREAK_GLASS` reach `bin/k3dm-hub-promote` directly: `hub_promote.bats` N2 "rollback refuses
  promoter commits not in stack top; BREAK_GLASS=1 permits (E3)" is red with them set, green without (6 other N2 cases
  green either way).

Any fix must clear `MAKEFLAGS`, `MFLAGS` and `MAKELEVEL` as well as the variables themselves. Option 1 below without
the make variables would leave the first channel open.

## Original hypothesis

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

## Fix (operator chose option 1, 2026-11-16: "fix in v1.44.1")

Both pushes live in `record_move` (`bin/k3dm-hub-promote:159` deploy/hub, `:169` tag), used by promote and rollback.
Add one helper next to `git_cmd` (`:19`) and use it at both sites:

```bash
git_push() { _run_command --soft -- env -u REF -u BREAK_GLASS -u SKIP_CHECK_RUNS -u SKIP_CHECK_RUNS_REASON -u MAKEFLAGS -u MFLAGS -u MAKELEVEL git -C "$REPO_ROOT" push "$@"; }
```

The variables stay readable to `bin/k3dm-hub-promote` itself (it has already copied them into locals by then); only
`git push` and its hooks run without them. Nothing else changes: same remote, lease, refs, messages and exit paths.

## Files

- `bin/k3dm-hub-promote` — `git_push` helper; `:159` and `:169` call it
- `scripts/tests/bin/hub_promote.bats` — one new case (E1), modelled on the pre-push hook fixture at `:471`

## Contract readers

Env vars `REF`, `BREAK_GLASS`, `SKIP_CHECK_RUNS`, `SKIP_CHECK_RUNS_REASON`; make's `MAKEFLAGS`/`MFLAGS`/`MAKELEVEL`.
- writer: `Makefile:478` (`hub-promote`, command-line vars), `Makefile:487` (`hub-rollback`) — unchanged
- reader: `bin/k3dm-hub-promote:309`, `:315`, `:319` — unchanged (read before any push)
- reader (the defect): `.githooks/pre-push` → fast gate → `scripts/tests/bin/hub_promote.bats` N2 (`:952`) and
  `scripts/tests/bin/makefile_appsets.bats:109` — after the fix they no longer receive these from a promote
- `git_cmd` (`:19`) callers other than the two pushes — unchanged

## Acceptance

```yaml
must:
  M1: a promote run with REF, BREAK_GLASS=1, SKIP_CHECK_RUNS, SKIP_CHECK_RUNS_REASON and MAKEFLAGS=' REF=x BREAK_GLASS=1' exported runs the scratch clone's pre-push hook for both pushes with none of those seven variables set
  M2: the same promote still moves deploy/hub on the scratch origin and pushes the hub-promote tag (exit 0), exactly as without the variables
  M3: a rollback with the same variables exported runs its pushes the same way
must_not:
  N1: the pre-push hook sees REF, BREAK_GLASS, SKIP_CHECK_RUNS, SKIP_CHECK_RUNS_REASON, MAKEFLAGS, MFLAGS or MAKELEVEL during a promote or rollback push (red today; positive control: a sentinel variable HOOK_SENTINEL exported by the test IS seen by the same hook, so the hook ran and environment does reach it)
  N2: any existing hub_promote.bats or makefile_appsets.bats case changes result
interface:
  - bin/k3dm-hub-promote git_push (new private helper)
evidence:
  - {id: E1, proves: [M1, M2, M3, N1], kind: offline, intent: "You will see a test promote and roll back with the make variables exported, while a pre-push hook in the scratch clone writes down which of them it can see. It sees none of them but does see a test marker, so the hook really ran, and both pushes still land. Today the hook sees REF and BREAK_GLASS, so this fails."}
  - {id: E2, proves: [N2], kind: offline, intent: "You will see the full hub-promote and appsets test files still pass, so nothing else in promote or rollback changed."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "At the next real hub-promote, you will see deploy/hub move and the tag push succeed in one run, with no --no-verify needed."}
```

**Intent approved:** operator, 2026-11-16
