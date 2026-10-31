# Bug: CI reds that a few seconds of local checks would catch reach the PR

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-31 ("1 and 2 seems to be a good suggestion. probably can give them a shot")
**Filed:** 2026-10-31
**Detected by:** Claude, after PR #153 (v1.43.12) went red four times on the same day
**Affected:** `.githooks/pre-push`; `bin/k3dm-codex-dispatch` (`land`); new `scripts/ci/fast_gate.sh`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-06-19-pre-push-hook-block-main-rollout.md` (the existing pre-push hook,
main-guard only)

## Observed failure

PR #153's CI went red four times on 2026-10-31. At least three of those reds could have been caught
on the Mac before the push:

| Round | Red | Caught locally by |
|---|---|---|
| 2 | sudoers path / fixture tests | the BATS suite that tests the touched script |
| 3 | dashboard `$window` panel total 79 → 81 (pytest) | the pytest file that names the touched dashboard |
| 4 | bare `! grep` in a new BATS test (`d6090c1f`) | `scripts/tests/lib/bats_negation_lint.bats`, 0.11 s |

Each red cost a ~15-minute CI round trip. Round 4 got through because `bin/k3dm-codex-dispatch land`
runs only the `--test` command it is given, and that command covered only the task's own two test files.

The operator considered GitHub's Copilot "Watch and fix" and declined it for release PRs: it pushes
unreviewed fixes to the branch, which conflicts with the spec, review and red-test rules.

## Root cause

1. The only local gate before a push is the pre-commit hook: `_agent_audit` plus doc-link, bug-evidence
   and repo-root checks on staged files. None of the repo-wide lint suites (`bats_negation_lint.bats`,
   `grep_q_pipe_guard.bats`) run before CI does.
2. `land` trusts the caller's `--test` scope. No fixed check set runs on every landing.
3. Nothing selects the existing tests that cover a touched file. The full suite takes ~15 minutes, so
   nobody runs it before every push.

## Fix

1. **`scripts/ci/fast_gate.sh [BASE]`** (new; `set -euo pipefail`; bash 3.2). It diffs `BASE..HEAD`
   (default: the merge base with `origin/<current branch>`, falling back to `origin/main`) and runs:
   - **a. The static lint set, always:** each BATS file listed in `scripts/etc/fast-gate/static.list`,
     which starts with `scripts/tests/lib/bats_negation_lint.bats`, `scripts/tests/lib/grep_q_pipe_guard.bats`
     and `scripts/tests/lib/ci_workflow_no_stage2.bats`. These files read the whole tree and take
     seconds.
   - **b. Touched tests:** every changed `*.bats` and `test_*.py` file.
   - **c. Tests that name a touched file:** every BATS or pytest file under `scripts/tests/` that
     contains the repo-relative path or the basename of a changed non-test file (`grep -lF`), capped
     at 40 files. If the cap is hit, run the first 40 and print `fast-gate: N more tests name touched files —
     run make test`.
   - **d. File-type checks on changed files only:** `shellcheck` on `*.sh`, `yamllint` on
     `.github/workflows/*.yml`, `scripts/check-doc-links.py` on `*.md`. Skip a tool that is not installed
     and say so in one line; never pass silently.

   pytest runs through the same interpreter discovery as `make test-pytest`, under
   `scripts/tests/tripwire.sh`. The script prints one line per check (`PASS`/`FAIL`/`SKIP`, seconds) and
   a total, and exits non-zero if any check failed.
2. **`make fast-gate`** runs the script.
3. **`.githooks/pre-push`:** after the existing main guard, run `scripts/ci/fast_gate.sh` with the
   push's remote base. If `K3DM_SKIP_FAST_GATE=1` is set, print a one-line notice and skip. The skip is
   operator-only, like `--no-verify`; add it to `docs/howto/agent-audit.md` next to the `--no-verify` rule.
4. **`bin/k3dm-codex-dispatch land`:** after the `--test` command passes, run `scripts/ci/fast_gate.sh`
   in the task worktree against `origin/<target>`. A failure refuses the land (`land_refused`, reason
   `fast-gate`), the same as a failed `--test`. `--no-test` does not skip it.
5. Docs: a `docs/howto/fast-gate.md` page (what runs, how long, how to add a static suite, the skip
   rule), linked from the README How-To list. A `CHANGELOG.md` entry.

## Files

- `scripts/ci/fast_gate.sh` (new)
- `scripts/etc/fast-gate/static.list` (new)
- `scripts/tests/lib/fast_gate.bats` (new)
- `.githooks/pre-push`
- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/codex_dispatch.bats`
- `Makefile`
- `docs/howto/fast-gate.md` (new)
- `docs/howto/agent-audit.md`
- `README.md`
- `CHANGELOG.md`

## What NOT to do

- Do not run the full suite in the hook. The target is under 60 s on the M4 for a typical push.
- Do not change `.githooks/pre-commit` or `_agent_audit` (lib-foundation).
- Do not make CI call the fast gate; CI keeps running everything.
- Do not let an agent set `K3DM_SKIP_FAST_GATE`.

## Acceptance

```yaml
must:
  M1: a push whose diff adds a bare `! cmd` line to a BATS file is refused by the pre-push hook, naming bats_negation_lint.bats
  M2: a change to a non-test file runs the existing tests that name that file's path or basename, and only those plus the static set and touched tests
  M3: land refuses a task whose worktree fails the fast gate, even when its --test command passes
  M4: the gate prints PASS/FAIL/SKIP with seconds for each check and a total, and exits non-zero on any FAIL
  M5: on the v1.43.12 merge diff the gate finishes in under 60 s on the M4
must_not:
  N1: a missing tool (shellcheck, yamllint, pytest) is never a silent pass; it prints SKIP with the tool name
  N2: K3DM_SKIP_FAST_GATE=1 skips the gate only with a printed notice; without it the gate always runs, including under land --no-test
  N3: the gate never runs a test file outside scripts/tests/ and never touches the real HOME, Pushgateway or cluster (tripwire stays in front of pytest)
  N4: the existing main-guard in pre-push still refuses a non-main ref pushed to main
evidence:
  E1:
    proves: [M1, M4, N4]
    kind: offline
    intent: >-
      You will see the hook, run in a scratch clone, refuse a push that adds a bare `! grep` line and name the
      lint suite, and still refuse a push to main. It failed if the push goes through, or if the test passes
      against today's pre-push hook.
    what: bats scripts/tests/lib/fast_gate.bats, hook run against a temp repo with a local bare remote
  E2:
    proves: [M2, N1, N3]
    kind: offline
    intent: >-
      You will see that touching a file named by exactly two test files selects those two, plus the static set,
      and nothing else; and that with yamllint off PATH the output says SKIP yamllint. It failed if an unrelated
      suite runs, or a missing tool prints PASS.
    what: bats scripts/tests/lib/fast_gate.bats with a fixture tree; the fixture asserts it is not the real repo root first
  E3:
    proves: [M3, N2]
    kind: offline
    intent: >-
      You will see land refuse a task whose diff adds a bare `!` line while its --test passes, also under --no-test,
      and land it once K3DM_SKIP_FAST_GATE=1 is set, with the notice printed. It failed if the land goes through
      without the variable.
    what: bats scripts/tests/bin/codex_dispatch.bats
  E4:
    proves: [M5]
    kind: live
    intent: >-
      You will see `make fast-gate` on the M4 against the v1.43.12 merge base finish under 60 s with a per-check
      table. It failed if it takes longer or skips a check without saying so.
    what: Claude runs make fast-gate BASE=<v1.43.12 merge base> on the M4 and records the output
interface:
  - scripts/ci/fast_gate.sh [BASE]
  - make fast-gate
  - .githooks/pre-push
  - bin/k3dm-codex-dispatch land --slug SLUG (--test CMD|--no-test)
  - K3DM_SKIP_FAST_GATE
```

**Intent approved:** operator, 2026-10-31 ("as well as those two bugs")
