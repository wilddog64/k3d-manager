# dirused M10b4b: docs drift test for scheduled purge

**Status:** OPEN — SPEC rev 1, 2026-11-25; awaiting blind review and intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b4](dirused-m10b4-docs.md). The contract is repeated below because the worker cannot read the parent.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (base `009fb14`)
**Risk:** low — one new offline test file
**Implementer:** Luna (`--model gpt-6-luna`)
**Verifier:** Claude, offline
**Filed:** 2026-11-25
**Intent approved:** pending
**Approval:** operator, 2026-11-25 — split across Flash and Luna

## Contract (from the parent)

A sibling task rewrites `docs/purge.md`, `README.md` and `CHANGELOG.md`. You write only
`tests/Dirused.Tests.Portable/DocsDriftTests.cs`. Your test reads docs and source and never edits them. It **fails on today's docs**
(the sibling has not landed yet); that is expected and is this task's red.

## Change

New xUnit class `DocsDriftTests` in `tests/Dirused.Tests.Portable/DocsDriftTests.cs`, matching the style of the other files there
(namespace, `[Fact]`, assertion library already in use). The project file globs `*.cs`; do not edit it.

- **Repo root:** walk up from `AppContext.BaseDirectory` to the first directory containing `dirused.sln`. Assert it was found and
  that `docs/purge.md`, `README.md` and `src/Dirused.Common/ArgParser.cs` exist under it before any other check, so a wrong root
  fails loudly instead of passing on empty input.
- **Line endings:** normalise `\r\n` to `\n` in every file read. Windows CI checks files out with CRLF.
- `Readme_contains_every_schedule_usage_line`: take `ArgParser.UsageText` (reference the constant, do not copy it). Collect each line
  starting with `  /schedule` plus the following lines that start with spaces only and are not a new switch (the next line whose
  trimmed text starts with `/` ends the block). Assert at least 5 such switch lines were collected (there are 5 at `009fb14`:
  `ArgParser.cs:70-75`). Assert each collected line appears in `README.md` with trailing spaces trimmed on both sides.
- `Purge_doc_names_every_refusal`: scan every `*.cs` under `src/` for C# string literals (regular `"..."` and interpolated
  `$"..."`) whose text starts with `refused: `. For each, take the prefix up to the first `{`, the first ` (` or the end of the literal, trim
  trailing spaces and a trailing `:`, and skip it if what remains is only `refused`. Assert at least 10 distinct prefixes were found
  (11 at `009fb14`). Assert each appears verbatim in `docs/purge.md`. On failure, list every missing prefix in one message, not
  only the first.
- `Purge_doc_names_every_list_state`: assert each of `scheduled`, `running`, `done (`, `cancelled`, `missed (did not run)`,
  `task missing`, `interrupted (`, `permissions changed — not run`, `unreadable plan` appears in the `## Scheduled purge` section of
  `docs/purge.md` (from that heading to the next `## ` heading), not elsewhere in the file. Assert the heading exists first.

## Files

`tests/Dirused.Tests.Portable/DocsDriftTests.cs` only.

## Acceptance

```yaml
must:
  - id: B4b-M1
    text: "With docs that contain every usage line, refusal prefix and list state, all three DocsDriftTests facts pass on linux and windows"
  - id: B4b-M2
    text: "The refusal scan finds the 11 prefixes listed in the parent contract at 009fb14, and a new 'refused: x' literal added to any src file is found without editing the test"
must_not:
  - id: B4b-N1
    text: "Any DocsDriftTests fact passes on the docs at 009fb14 (each must fail there: README lacks /schedule /list, purge.md lacks the refusals and has no '## Scheduled purge' heading)"
  - id: B4b-N2
    text: "A fact passes when the repo root is not found or a scanned set is empty"
  - id: B4b-N3
    text: "Any file other than DocsDriftTests.cs changes"
evidence:
  - id: E-B4b-red
    proves: [B4b-N1]
    kind: offline
    command: "on 009fb14 plus only DocsDriftTests.cs: dotnet test --filter FullyQualifiedName~DocsDriftTests reports 3 failed"
    intent: "Before the docs are updated, the test catches that they are out of date."
  - id: E-B4b-green
    proves: [B4b-M1]
    kind: offline
    command: "on the branch with M10b4a landed: dotnet test --filter FullyQualifiedName~DocsDriftTests reports 3 passed; windows CI on that head is green"
    intent: "Once the docs are updated, the test passes on both Linux and Windows."
  - id: E-B4b-mutants
    proves: [B4b-M2, B4b-N2]
    kind: offline
    command: "with M10b4a landed, each of these makes the named fact fail, then revert: (a) add 'refused: test only' as a literal in any src/Dirused.Common file -> Purge_doc_names_every_refusal; (b) delete one /schedule line from README.md -> Readme_contains_every_schedule_usage_line; (c) delete 'task missing' from purge.md -> Purge_doc_names_every_list_state; (d) rename dirused.sln in a scratch copy -> all three fail on the root assertion"
    intent: "Adding a new refusal or option without updating the docs makes CI fail."
  - id: E-B4b-scope
    proves: [B4b-N3]
    kind: offline
    command: "git diff --stat on the worker's commit lists only tests/Dirused.Tests.Portable/DocsDriftTests.cs"
    intent: "The test task changed nothing but the test."
interface:
  - "tests/Dirused.Tests.Portable/DocsDriftTests.cs: DocsDriftTests"
```
