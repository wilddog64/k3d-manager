# dirused M10b4b: docs drift test for scheduled purge

**Status:** OPEN — SPEC rev 2, 2026-11-25; rev 1 reviewed blind by Fable and Argon, fixes applied (see parent's Review log)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b4](dirused-m10b4-docs.md). The contract is repeated below because the worker cannot read the parent.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (base `009fb14`)
**Risk:** low — one new offline test file
**Implementer:** Luna (`--model gpt-6-luna`)
**Verifier:** Claude, offline
**Filed:** 2026-11-25
**Intent approved:** operator, 2026-11-25 ("approved dirused M10b4")
**Approval:** operator, 2026-11-25 — split across Flash and Luna

## Contract (from the parent)

A sibling task rewrites `docs/purge.md`, `README.md` and `CHANGELOG.md`. You write only
`tests/Dirused.Tests.Portable/DocsDriftTests.cs`. Your test reads docs and source and never edits them.

**Your three docs facts fail on today's docs; that is expected and is this task's red.** Do not change docs, code or other tests to
make them pass. Your synthetic-docs controls (below) must pass. Claude lands this task after the docs task, with the full suite.

The docs, once updated, will satisfy:

1. `docs/purge.md` has a line exactly `## Scheduled purge`. "The section" is from that line to the next line starting `## `.
2. Each `/schedule` line of `ArgParser.UsageText` (`src/Dirused.Common/ArgParser.cs:70-75`: five switch lines and one continuation)
   appears in `README.md`, compared with leading and trailing whitespace trimmed on both sides (README's block is indented
   differently from `UsageText`).
3. Each refusal prefix found in `src/` appears in the section. At `009fb14` the scan must find exactly these 11:
   `refused: error during run`, `refused: list changed since it was scheduled`, `refused: not a dirused plan`,
   `refused: not a plan id`, `refused: not started from the plan's program copy`, `refused: not the scheduled time`,
   `refused: plan already has a report`, `refused: plan already started`, `refused: plan folder contains a link`,
   `refused: plan folder permissions changed`, `refused: program copy changed since it was scheduled`.
4. Each of these appears in the section, backticks included: `` `scheduled` ``, `` `running` ``, `` `done ( ``,
   `` `cancelled` ``, `` `expired` ``, `` `missed (did not run)` ``, `` `task missing` ``, `` `interrupted ( ``,
   `` `permissions changed — not run` `` (em dash, U+2014), `` `unreadable plan` ``, `` `refused: ``.

## Change

New xUnit class `DocsDriftTests` in `tests/Dirused.Tests.Portable/DocsDriftTests.cs`, matching the style of the other files there
(namespace, `[Fact]`, the assertion library already in use). The project globs `*.cs`; do not edit it.

**Design:** put each check in an `internal static` helper that takes text and returns the list of missing items, so the same logic
runs against the real files and against synthetic text:
- `Section(string purgeDoc)`: the text from the exact line `## Scheduled purge` to the next line starting `## `, or `null` if
  that exact line is absent (`## Scheduled purge (preview)` does not count).
- `MissingUsageLines(string usageText, string readme)`.
- `RefusalPrefixes(IEnumerable<string> sourceTexts)` and `MissingRefusals(IEnumerable<string> prefixes, string section)`.
- `MissingStates(string section)`.

Rules:
- **Repo root:** walk up from `AppContext.BaseDirectory` to the first directory containing `dirused.sln`. Assert it was found and
  that `docs/purge.md`, `README.md` and `src/Dirused.Common/ArgParser.cs` exist under it before any other check.
- **Line endings:** normalise `\r\n` to `\n` in every file read; Windows CI checks out with CRLF and the repo has no
  `.gitattributes`.
- **Usage lines:** from `ArgParser.UsageText` (reference the constant; do not copy it) take each line starting with `  /schedule`
  plus following lines that are indented and whose trimmed text does not start with `/`. Assert at least 5 switch lines were
  collected. Compare each, trimmed, with README lines, trimmed.
- **Refusal scan:** read every `*.cs` under `src/`, skipping any path with a `bin` or `obj` directory segment. Anchor the match on
  the opening quote: `\$?"(refused: [^"{\r\n]*)`. Do not match whole string literals: `PlanRunner.cs:132` has several literals
  on one line and `PlanRunner.cs:44` has quotes inside an interpolation hole. Cut each match at the first ` (`, trim trailing
  spaces and `:`, skip a result equal to `refused`, and de-duplicate. Assert at least 10 prefixes.
- On failure, each fact lists every missing item in one message.

Facts:
- `Readme_contains_every_schedule_usage_line`, `Purge_doc_section_names_every_refusal`, `Purge_doc_section_names_every_list_state`:
  run the helpers on the real files. The section must exist (assert `Section(...) != null` first).
- `Refusal_scan_finds_the_known_prefixes`: on the real `src/`, the scan's result contains all 11 prefixes in contract 3.
- Synthetic controls, which pass on any docs: (a) a synthetic section containing all contract 3 and 4 strings gives no missing
  items, and removing any one item reports exactly that item; (b) `Section` returns `null` for a doc whose heading is
  `## Scheduled purge (preview)`; (c) `RefusalPrefixes` over two synthetic sources, `Refuse($"refused: x y: {id}")` and
  `a == "b" ? "c" : "refused: z (w {q})"`, returns exactly `refused: x y` and `refused: z`; (d) `MissingUsageLines` passes when
  README has the lines with different indentation and fails when one is missing.

## Files

`tests/Dirused.Tests.Portable/DocsDriftTests.cs` only.

## Land

After M10b4a lands on the branch: `land --test "dotnet test tests/Dirused.Tests.Portable"` (full portable suite, docs facts
included). Do not push this task's commit before M10b4a's.

## Acceptance

```yaml
must:
  - id: B4b-M1
    text: "With docs satisfying the contract, all DocsDriftTests facts pass on linux and windows"
  - id: B4b-M2
    text: "The refusal scan finds the 11 contract 3 prefixes at 009fb14, and a new 'refused: x' literal in any src file is reported missing from the docs without editing the test"
  - id: B4b-M3
    text: "The synthetic controls pass on the worker's branch (docs not yet updated)"
must_not:
  - id: B4b-N1
    text: "Any of the three docs facts passes on the docs at 009fb14 (README lacks /schedule /list, purge.md has no exact '## Scheduled purge' line)"
  - id: B4b-N2
    text: "A docs fact passes when the repo root is not found or when the refusal scan finds fewer than 10 prefixes"
  - id: B4b-N3
    text: "Any file other than DocsDriftTests.cs changes"
evidence:
  - id: E-B4b-red
    proves: [B4b-N1, B4b-M3]
    kind: offline
    command: "on 009fb14 plus only DocsDriftTests.cs: dotnet test tests/Dirused.Tests.Portable --filter FullyQualifiedName~DocsDriftTests shows exactly the 3 docs facts failed and every other DocsDriftTests fact passed"
    intent: "Before the docs are updated, the test catches that they are out of date."
  - id: E-B4b-green
    proves: [B4b-M1, B4b-M2]
    kind: offline
    command: "on the branch with M10b4a landed: dotnet test tests/Dirused.Tests.Portable reports 0 failed; windows CI on that head is green"
    intent: "Once the docs are updated, the test passes on both Linux and Windows."
  - id: E-B4b-mutants
    proves: [B4b-M2, B4b-N2]
    kind: offline
    command: "with M10b4a landed, in a scratch copy, each change makes the named fact fail: (a) add the literal \"refused: test only\" to any src/Dirused.Common file -> Purge_doc_section_names_every_refusal; (b) delete one /schedule line from README.md -> Readme_contains_every_schedule_usage_line; (c) delete '`task missing`' from purge.md -> Purge_doc_section_names_every_list_state; (d) rename dirused.sln -> all three docs facts fail on the root assertion; (e) delete src/Dirused.Common/PlanRunner.cs -> Purge_doc_section_names_every_refusal fails on the 10-prefix floor"
    intent: "Adding a new refusal or option without updating the docs makes CI fail."
  - id: E-B4b-scope
    proves: [B4b-N3]
    kind: offline
    command: "git diff --stat on the worker's commit lists only tests/Dirused.Tests.Portable/DocsDriftTests.cs"
    intent: "The test task changed nothing but the test."
interface:
  - "tests/Dirused.Tests.Portable/DocsDriftTests.cs: DocsDriftTests"
```
