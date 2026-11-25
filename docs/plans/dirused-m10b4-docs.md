# dirused M10b4: docs for scheduled purge

**Status:** OPEN — SPEC rev 3, 2026-11-25; split into M10b4a (docs, Flash) and M10b4b (drift test, Luna) at operator request; awaiting blind review (Fable, Argon) and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §9. Fourth of four; after [M10b3](dirused-m10b3-runplan-windows.md) (landed: b3d `009fb14`).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** low — docs and one offline test
**Children:** [M10b4a](dirused-m10b4a-docs.md) (Flash), [M10b4b](dirused-m10b4b-docs-drift-test.md) (Luna)
**Verifier:** Claude, offline
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — split, docs as the last child; operator, 2026-11-25 — "dispatch across Flash and Luna", blind review by Fable and Argon

## Rev 3 changes (checked against `009fb14`)

- Rev 2's README check compared against `ArgParser.ShortUsageText`, which has no `/schedule` lines. The `/schedule` lines live in
  `ArgParser.UsageText` (`src/Dirused.Common/ArgParser.cs:70-75`).
- Rev 2 left out `/schedule /trust ["acct"]` and `/schedule /untrust "acct"` (M10b2c), and the list states `task missing` and
  `unreadable plan` (`src/Dirused.Common/SchedulePlans.cs:36-65`).
- Rev 2's grep check was one-off. M10b4b turns it into a test, so docs that fall behind the code fail CI.

## Contract between the children

The two children share no file. M10b4a writes only `docs/purge.md`, `README.md` and `CHANGELOG.md`. M10b4b writes only
`tests/Dirused.Tests.Portable/DocsDriftTests.cs`. The test reads the docs and the source; it never edits them.

Facts both children rely on, each from `009fb14`:

1. **Usage lines.** Every `UsageText` line that starts with `  /schedule` (and its indented continuation lines) appears verbatim
   in `README.md` once each, ignoring line endings.
2. **Refusals.** Every C# string literal in `src/` that starts with `refused: ` has a fixed text prefix: the text up to the first
   `{`, the first ` (` or the closing quote, with trailing `: ` or space trimmed. Each prefix appears in `docs/purge.md`. Today's set (12 literals,
   11 distinct prefixes): `refused: error during run`, `refused: list changed since it was scheduled`, `refused: not a dirused plan`,
   `refused: not a plan id`, `refused: not started from the plan's program copy`, `refused: not the scheduled time`,
   `refused: plan already has a report`, `refused: plan already started`, `refused: plan folder contains a link`,
   `refused: plan folder permissions changed`, `refused: program copy changed since it was scheduled`. The bare `"refused: "`
   literal is a builder prefix and is excluded (a prefix of only `refused:` is skipped).
3. **List states.** `docs/purge.md` names each `/schedule /list` state: `scheduled`, `running`, `done (`, `cancelled`,
   `missed (did not run)`, `task missing`, `interrupted (`, `permissions changed — not run`, `unreadable plan`.
4. The `docs/purge.md` heading `## Scheduled purge` exists (anchor `#scheduled-purge`) and replaces today's
   `## Scheduled purge (preview)` section, whose "scheduling is unavailable" text is now false.

## Order

Both children can run at the same time. Land M10b4a first; M10b4b's test fails on today's docs (that is its red) and passes only
on M10b4a's docs. Then the integration check E-B4 on the branch head.

## Acceptance

```yaml
must:
  - id: B4-M1
    text: "With both children landed, DocsDriftTests passes on the branch head on linux and windows CI, and git diff from 009fb14 touches only docs/purge.md, README.md, CHANGELOG.md and tests/Dirused.Tests.Portable/DocsDriftTests.cs"
must_not:
  - id: B4-N1
    text: "docs/purge.md still says scheduling is unavailable or that /confirm schedules nothing"
evidence:
  - id: E-B4
    proves: [B4-M1, B4-N1]
    kind: offline
    command: "git diff --stat 009fb14..HEAD; dotnet test --filter FullyQualifiedName~DocsDriftTests; grep -n -i 'unavailable\\|schedules nothing' docs/purge.md returns nothing; windows CI run on the head is green"
    intent: "The guide tells you how to preview, schedule, check and cancel a purge, why held logs are skipped, and what each state and refusal means, and CI fails if a new refusal or option is added without updating it."
interface:
  - "docs/purge.md#scheduled-purge"
```
