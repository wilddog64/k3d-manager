# dirused M10b4: docs for scheduled purge

**Status:** OPEN — SPEC rev 4, 2026-11-25; rev 3 reviewed blind by Fable and Argon (both READY WITH FIXES; all findings verified against `009fb14` and applied, see Review log); awaiting intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §9. Fourth of four; after [M10b3](dirused-m10b3-runplan-windows.md) (landed: b3d `009fb14`).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** low — docs and one offline test
**Children:** [M10b4a](dirused-m10b4a-docs.md) (Flash), [M10b4b](dirused-m10b4b-docs-drift-test.md) (Luna)
**Verifier:** Claude, offline
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — split, docs as the last child; operator, 2026-11-25 — "dispatch across Flash and Luna", blind review by Fable and Argon

## Contract between the children

The two children share no file. M10b4a writes only `docs/purge.md`, `README.md` and `CHANGELOG.md`. M10b4b writes only
`tests/Dirused.Tests.Portable/DocsDriftTests.cs`. The test reads the docs and the source; it never edits them. Both child specs
repeat this contract, because a worker cannot read this file.

Facts both children rely on, each from `009fb14`:

1. **Section.** `docs/purge.md` has a line exactly `## Scheduled purge` (anchor `#scheduled-purge`), replacing today's
   `## Scheduled purge (preview)` (`docs/purge.md:3`). "The section" means from that line to the next line starting `## `.
2. **Usage lines.** The six `UsageText` lines at `src/Dirused.Common/ArgParser.cs:70-75` (five `/schedule` switches and one
   continuation) appear in `README.md`'s `### Purging listed files` code block, replacing `README.md:101-102`. A line matches
   when it is equal after trimming leading and trailing whitespace on both sides: README's block is indented 2 spaces less than
   `UsageText`, and that is fine.
3. **Refusals.** Every C# string literal in `src/` (excluding `bin/` and `obj/`) whose text starts with `refused: ` has a fixed
   prefix: the text up to the first `{`, the first ` (` or the closing quote, with trailing spaces and `:` trimmed; a prefix of only
   `refused` (the builder literal `"refused: "` at `PlanRunner.cs:98`) is skipped. At `009fb14` there are 15 such lines in `src/`
   giving 11 distinct prefixes: `refused: error during run`, `refused: list changed since it was scheduled`,
   `refused: not a dirused plan`, `refused: not a plan id`, `refused: not started from the plan's program copy`,
   `refused: not the scheduled time`, `refused: plan already has a report`, `refused: plan already started`,
   `refused: plan folder contains a link`, `refused: plan folder permissions changed`,
   `refused: program copy changed since it was scheduled`. Each appears in the section.
4. **List states.** Each of these appears in the section in backticks, as written (a trailing `(` means the state continues):
   `` `scheduled` ``, `` `running` ``, `` `done ( `` , `` `cancelled` ``, `` `expired` ``, `` `missed (did not run)` ``,
   `` `task missing` ``, `` `interrupted ( ``, `` `permissions changed — not run` ``, `` `unreadable plan` ``, `` `refused: ``.
   (`expired` and `refused: …` reach `/schedule /list` through the report outcome, `SchedulePlans.cs:52`.)

## Order

Both children can run at the same time. **Land M10b4a first.** M10b4b's three docs facts fail on today's docs (that is its red) and
pass only on M10b4a's docs, so M10b4b is landed after M10b4a with the full portable suite as its land test, and is not pushed before
M10b4a. Then the integration check E-B4 on the branch head.

## Acceptance

```yaml
must:
  - id: B4-M1
    text: "With both children landed, DocsDriftTests passes on the branch head on linux and windows CI, and git diff from 009fb14 touches only docs/purge.md, README.md, CHANGELOG.md and tests/Dirused.Tests.Portable/DocsDriftTests.cs"
must_not:
  - id: B4-N1
    text: "The '## Scheduled purge' section of docs/purge.md still says scheduling is unavailable or that /confirm schedules nothing"
evidence:
  - id: E-B4
    proves: [B4-M1, B4-N1]
    kind: offline
    command: "git diff --stat 009fb14..HEAD; dotnet test tests/Dirused.Tests.Portable --filter FullyQualifiedName~DocsDriftTests; sed -n '/^## Scheduled purge$/,/^## /p' docs/purge.md | grep -i -E 'scheduling is unavailable|schedules nothing' returns nothing (on 009fb14 the same grep on the '(preview)' section hits line 7); windows CI run on the head is green"
    intent: "The guide tells you how to preview, schedule, check and cancel a purge, why held logs are skipped, and what each state and refusal means, and CI fails if a new refusal or option is added without updating it."
interface:
  - "docs/purge.md#scheduled-purge"
```

## Review log

Rev 3 (`52bbe180`) reviewed blind by Fable (Agent subagent) and Argon (`gemini-4-argon-medium` via agy), 2026-11-25. Both READY WITH
FIXES. Claude verified each finding against `009fb14`; none refuted.

| Finding | Found by | Fix in rev 4 |
|---|---|---|
| `grep 'unavailable'` hits held-file text at `purge.md:131,157,224`, so correct docs fail | both | grep scoped to the section, exact phrases |
| README `### Purging listed files` block is 2 spaces less indented than `UsageText`; "verbatim" unworkable | both | trim both sides; lines go in that block |
| `/schedule /list` also shows `expired` and `refused: …` (report outcome, `SchedulePlans.cs:52`) | both | added to fact 4 |
| Trust failures become `refused: <PlanTrust line>` via the skipped builder literal (`PlanRunner.cs:91-98`) | Fable | M10b4a documents them as a row |
| List-state scope differs between parent and b | Argon | facts 3 and 4 both scoped to the section |
| Heading match not pinned | Fable | exact line `## Scheduled purge` |
| `scheduled`/`running`/`cancelled` can't fail as bare substrings | Fable | backticked forms |
| b cites prefixes it cannot see; b lands red | Fable | prefixes inlined; land order and test set stated; synthetic-docs control |
| Literal count wrong (said 12) | Fable | 15 lines, 11 prefixes |
| Scan includes `bin/`/`obj/`; naive regex misparses `PlanRunner.cs:44,132` | Fable, Argon | excluded; anchor on `"refused: ` |
| Empty-set guard not exercised | Fable | mutant (e) |
| E-B4a misses CHANGELOG "not available yet" check | Fable | added |
| Docs child missing facts: elevated-window refusal, Pacific machine zone, `/yes`, 24 h expiry, Windows preview extras, `/runplan` absent from `UsageText` | Fable, Argon | added to M10b4a |
| "once each" in fact 2 asserted by neither child | Fable, Argon | dropped |
