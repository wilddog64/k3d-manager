# `land --allow-out-of-scope` lands a worker's changes to agent instruction and hook files

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Severity:** medium — no known exploit, but one landed edit to an instruction or hook file steers every later agent
session, and the override that lets it through is used routinely for unrelated reasons
**Approval:** operator, 2026-11-08 ("got file P3 to make land refuse change")
**Intent approved:** operator, 2026-11-08 ("approve both": E1 and E2)
**Prior art:** `docs/bugs/2026-10-09-codex-dispatch-task-can-widen-its-own-scope.md` (found by grep, not scored) —
read, different root cause: that fix stopped a task from editing its own spec's file list; this is the operator
override. `find-similar-docs` not run: embeddings credential unavailable in this shell (rc 44 / rc 36).
**Filed:** 2026-11-08
**Detected by:** Claude, reviewing dev.to "Your AGENTS.md is an attack surface" (sarahreid, 2026-10-27) against this
repo, 2026-11-08
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_scope_verdict`, `_dispatch_land`)
**Branch:** `k3d-manager-v1.43.15`

## Symptom

`bin/k3dm-codex-dispatch land` refuses a task whose diff touches a file outside the spec's `## Files` list, unless
`--allow-out-of-scope` is passed. That flag lifts the check for every path at once. It is passed routinely and for
narrow reasons: a test file the spec forgot, a `### Part 2 files` table the scope parser does not read, a changelog
named differently (memory-bank archive, 2026-10-23 to 2026-11-01, at least five lands). Nothing distinguishes "this
test file is out of scope" from "this hook script is out of scope".

The files that instruct or run inside agent sessions are in the repo:

| Path | What reads it |
|---|---|
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` | Codex, Claude Code, Gemini, Copilot, every session |
| `scripts/lib/foundation/{AGENTS,CLAUDE,GEMINI}.md`, `scripts/lib/foundation/.github/copilot-instructions.md` | the same agents when they work in that subtree |
| `.claude/settings.json`, `.claude/hooks/remind-clear-after-land.sh` | Claude Code runs the hook after every Bash call: code execution, not text |

A worker that edits one of these, through a spec defect or text quoted into a spec (Slack, Copilot review comments,
`cloud-requests`), lands it whenever the operator or Claude passes `--allow-out-of-scope` for another file. Every
later session then follows it. A spec that lists such a file in `## Files` lands it with no flag at all.

## Root cause

`_dispatch_scope_verdict` (`bin/k3dm-codex-dispatch:759`) has one class of path: in the spec's list or not. The
override (`allow`, line 799) applies to the whole set. There is no class of path that needs its own explicit consent.

## Fix

1. In `bin/k3dm-codex-dispatch`, define the protected set as path globs matched against the same changed-path list the
   scope verdict builds (committed diff from base, unstaged diff, untracked files): any path whose basename is
   `AGENTS.md`, `CLAUDE.md` or `GEMINI.md`; any `.github/copilot-instructions.md`; anything under a `.claude/`,
   `.codex/` or `.gemini/` directory; any `.mcp.json`; any `.envrc`. Match at any depth, so the subtree copies count.
2. `land` refuses when any changed path is in the set, **whether the scope verdict is in-scope, out-of-scope, or
   out-of-scope allowed**, unless the new flag `--allow-instruction-files` is passed. `--allow-out-of-scope` never
   covers these paths.
3. On refusal: print `instruction-file: <path>` for each, then the diff of those paths only (committed and unstaged;
   for an untracked file, its content), exit non-zero, leave the release branch untouched, and record
   `land_refused` with `reason: scope` and `detail: instruction-files`. Keep `reason: scope`: `bin/k3dm-dispatch-metrics`
   knows only `landed`, `tests`, `scope`, `rebase` (line 30), and this must not change the exporter.
4. With `--allow-instruction-files`, land proceeds as today, and the landed ledger event carries
   `instruction_files: [<paths>]`.
5. Add `--allow-instruction-files` to the usage line (line 299) and to `docs/howto/codex-dispatch.md` and
   `docs/architecture/codex-dispatch.md` beside `--allow-out-of-scope`, with one sentence on why it is separate.

## Contract readers

| Reader | Changes? |
|---|---|
| `bin/k3dm-codex-dispatch:299` usage line | yes: new flag |
| `bin/k3dm-codex-dispatch:1028` flag parser | yes: new flag |
| `Makefile:468` `codex-land` | no: it passes neither override today; an instruction-file land runs `bin/k3dm-codex-dispatch` directly |
| `.claude/hooks/remind-clear-after-land.sh:6` | no: matches the command text `k3dm-codex-dispatch land`, unchanged |
| `bin/k3dm-dispatch-metrics:30`, `:903`, `:1153` (`land_refused` reason) | no: reason stays `scope`; `detail` is a new field it ignores |
| `bin/k3dm-dispatch-logs:59` (`land_refused` reason `tests`) | no: only reads `tests` |
| `docs/howto/codex-dispatch.md`, `docs/architecture/codex-dispatch.md` | yes: document the flag |

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | protected set, refusal, new flag, usage |
| `scripts/tests/bin/codex_dispatch.bats` | tests for the Acceptance block |
| `docs/howto/codex-dispatch.md` | flag doc |
| `docs/architecture/codex-dispatch.md` | flag doc |

## Do not

- Do not change `--allow-out-of-scope` behaviour for any path outside the protected set.
- Do not add a new `land_refused` reason value or touch `bin/k3dm-dispatch-metrics`.
- Do not edit any file in the protected set in this task: the tests create them inside the BATS fixture repo only.
- Do not run tests against the real repo or the real ledger: the existing fixture in `codex_dispatch.bats` builds a
  scratch repo and ledger; assert it is pointed there before acting.

## Acceptance

```yaml
must:
  - id: M1
    text: A task whose diff changes AGENTS.md, landed with --allow-out-of-scope and without --allow-instruction-files, is refused with a non-zero exit, prints "instruction-file: AGENTS.md", and the release branch HEAD is unchanged.
  - id: M2
    text: The same task landed with --allow-out-of-scope --allow-instruction-files lands, and the landed ledger event lists AGENTS.md in instruction_files (paired positive control for M1).
  - id: M3
    text: The protected set matches at any depth and for every listed form - scripts/lib/foundation/CLAUDE.md, .claude/hooks/x.sh, .github/copilot-instructions.md, a nested .envrc and .mcp.json are each refused.
  - id: M4
    text: The refusal output contains the diff of the protected paths (an added line from the change is visible).
  - id: M5
    text: A task that changes no protected path lands exactly as before - in scope with no flag; out of scope only with --allow-out-of-scope.
  - id: M6
    text: The refusal is recorded as land_refused with reason "scope" and detail "instruction-files".
must_not:
  - id: N1
    text: --allow-out-of-scope alone never lands a change to a protected path.
  - id: N2
    text: Listing a protected path in the spec's Files table does not by itself let it land.
  - id: N3
    text: An uncommitted or untracked protected file in the task worktree is not missed (it is refused like a committed one).
  - id: N4
    text: A refused land writes no "land" ledger event and moves no ref.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3, N4]
    kind: offline
    how: BATS in scripts/tests/bin/codex_dispatch.bats using the existing scratch-repo fixture; each must_not test shown red against the pre-fix bin/k3dm-codex-dispatch.
    intent: "Proves, without touching the real repo, that land stops any change to agent instruction or hook files unless you pass the new flag on purpose, and that ordinary lands behave as before."
  - id: E2
    proves: [M1, M2, N1]
    kind: live
    how: Claude dispatches a throwaway task on the real dispatcher whose spec asks for one comment line appended to AGENTS.md; land with --allow-out-of-scope is refused and prints the line; then abandon the task (never land it). Separately, the next real land of an unrelated task succeeds unchanged.
    intent: "Shows on the real dispatcher that a worker's edit to AGENTS.md is stopped at land with the diff in front of you, and that normal lands are unaffected."
interface:
  - bin/k3dm-codex-dispatch land --slug SLUG (--test CMD|--no-test) [--allow-out-of-scope] [--allow-instruction-files]
  - ledger event land_refused fields reason, detail; ledger event land field instruction_files
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- `case` globs in bash match `/` with `*`, so `*/.claude/*` and `.claude/*` together cover every depth; a test for
  each form in M3 guards against a pattern that only matches the root.
- This does not stop the operator or Claude from editing instruction files directly on the release branch; that path
  is reviewed by the person committing. It closes the worker → land path only.
