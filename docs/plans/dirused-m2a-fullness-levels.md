# dirused M2a — mark full volumes: `/warn` (85%) and `/crit` (90%), colour, footer, exit 4

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused; new branch `m2a-fullness-levels` from `main` (3865f28, v0.0.4)
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low-medium (new exit code; one added CSV column; output text gains a tag)
**Implementer:** Luna (Codex). **Verifier:** Claude (pre-fix red, mutations, dirused-dev VM, CI).
**Follow-up (not here):** M2b — top 3 folders under red/yellow volumes in `/summary` (needs a walk; own spec). `/html` report later.

## Why

A teammate's suggestion, relayed by the operator 2026-11-17: "when scan a list of server, highlight 90% full as red, close to
90% as yellow (warning) maybe good for summary". Operator: "make it default 85% but allow to be adjust same for /crit";
a new exit code when a volume is red; top 3 folders only for red/yellow volumes (that part is M2b).

## Change

1. **Options / ArgParser.** New switches `/warn <n>` and `/crit <n>`: integers 1-100; defaults 85 and 90. Errors (exit 1):
   `/warn requires an integer between 1 and 100`, same for `/crit`, and `/warn must be below /crit` when warn ≥ crit after
   both are applied (so `/warn 95` alone fails against the default 90). Add both to `UsageText` and `ShortUsageText`, and
   exit code 4 to the usage text's exit-code list.
2. **Level.** New `public enum FullnessLevel { Ok, Warn, Crit }` and a pure helper
   `FullnessLevel Fullness.Of(double percentUsed, int warn, int crit)`: `Crit` when `percentUsed >= crit`, else `Warn` when
   `>= warn`, else `Ok`. Only results with a probed volume (`Volume.TotalBytes > 0`) get a level; failed targets have none.
3. **Text lines.** In `SummaryRenderer` and `TextRenderer`, the volume line of a `Warn` volume ends with ` [WARN]`, of a
   `Crit` volume with ` [CRIT]`; `Ok` lines are unchanged byte for byte. The tag is always written (also when redirected),
   so a saved report keeps it.
4. **Colour.** When writing to the real console and it is not redirected, and the `NO_COLOR` environment variable is unset
   or empty, the whole `Warn` line is yellow and `Crit` red, via `Console.ForegroundColor` then `Console.ResetColor()`
   (works in conhost and Windows Terminal; no ANSI escapes). Any other `TextWriter` (tests, redirect, file) gets plain text.
   Put this in one small helper both renderers call; renderers get the thresholds and a `bool color` through constructor
   parameters with defaults (85, 90, false), so existing constructor calls compile unchanged.
5. **Footer.** `/summary` text, when at least one volume line was printed:
   `<n> volume(s): <c> at or above <crit>%, <w> at or above <warn>%` (the `<w>` count excludes crit volumes). Not printed
   by `TextRenderer` (per-target output).
6. **JSON / CSV.** JSON: each target gains `"level": "ok" | "warn" | "crit"` (`null` for a target with no probed volume),
   in both normal and `/summary` JSON. Add it as an init property on `ScanResult` (default `null`) set in `Program.Run`
   after the scan. CSV `/summary`: add a final column `level` (header `...,percent_used,level`; `ok|warn|crit` for volume
   rows, empty for error rows). CSV without `/summary`: unchanged. No colour in JSON or CSV.
7. **Exit code 4.** `Program.Run` returns 4 when any target's level is `Crit`; otherwise 3 if any target is incomplete;
   otherwise 0. (4 takes precedence over 3: a full disk is the more urgent signal, and incomplete targets are still printed.)
   Usage errors stay 1.
8. **README.** Switch table, exit codes (add 4 and the precedence), one example: `dirused /file servers.list /summary /warn 80 /crit 95`.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/Options.cs` | Change 1 |
| `src/Dirused.Common/ArgParser.cs` | Change 1 |
| `src/Dirused.Common/ScanResult.cs` | `Level` init property (Change 6) |
| `src/Dirused.Common/Renderers/Fullness.cs` | new: enum, `Fullness.Of`, colour line helper (Changes 2, 4) |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | Changes 3-5 |
| `src/Dirused.Common/Renderers/TextRenderer.cs` | Changes 3-4 |
| `src/Dirused.Common/Renderers/CsvRenderer.cs` | Change 6 |
| `src/Dirused.Cli/Program.cs` | thresholds to renderers, colour flag, `Level`, exit 4 (Changes 4, 6, 7) |
| `README.md` | Change 8 |
| `tests/Dirused.Tests/FullnessTests.cs` | new: tests 1-8 |
| `tests/Dirused.Tests/SummaryTests.cs`, `tests/Dirused.Tests/OutputCompatTests.cs` | update only assertions the new CSV column or tag breaks; say which in the report |
| `tests/Dirused.Tests.Portable/FullnessColorTests.cs` | (added 2026-11-17 after run 2) new: test 9 |
| `tests/Dirused.Tests.Portable/RendererTests.cs`, `tests/Dirused.Tests.Portable/FleetRunnerTests.cs` | (added 2026-11-17 after run 1) same rule: update only the assertions the footer line, `level` JSON field or CSV column break. This project is what CI runs on Linux (`ci.yml:13`, `release.yml:19`) and must stay 36/36 |

## Contract readers

`grep -rn "percent_used\|PercentUsed\|return 3\|Exit codes" src tests README.md tools` (2026-11-17, 3865f28):
`SummaryRenderer.cs` (line + ordering), `CsvRenderer.cs` (summary header and row), `TextRenderer.cs` (volume line),
`Program.cs` (exit), `ArgParser.cs` usage, `README.md`, `tools/PACKAGE-README.txt` (check it for an exit-code list and update
it the same way if present; add it to your report). Scripts outside the repo that parse `/summary` CSV by column position
keep working (the column is appended last); scripts that test `exit == 3` now also see 4 — called out in README.

## Tests (`tests/Dirused.Tests/FullnessTests.cs`, these names exactly)

Renderer tests build `ScanResult`s with chosen `PercentUsed`; Program tests use a real temp directory.

1. `Test_FullnessLevelBoundaries` — `Of(84.9,85,90)` Ok, `Of(85,85,90)` Warn, `Of(89.9,85,90)` Warn, `Of(90,85,90)` Crit.
2. `Test_SummaryTagsWarnAndCritLines` — three volumes at 50, 86, 95 → the 50% line is exactly today's format (no tag), the
   86% line ends ` [WARN]`, the 95% line ends ` [CRIT]`; footer `3 volume(s): 1 at or above 90%, 1 at or above 85%`.
3. `Test_TextRendererTagsCritLine` — one 95% result via `TextRenderer` → first line ends ` [CRIT]`; no footer.
4. `Test_RedirectedOutputHasNoEscapeCodes` — renderer with `color: true` but a `StringWriter` → output has no `\u001b`, tags present.
5. `Test_WarnCritSwitchesValidated` — `/warn 0`, `/crit 101`, `/warn x`, `/warn 95` (default crit 90), `/warn 90 /crit 90` → exit 1
   with the messages above; `/warn 80 /crit 95` parses to 80/95; no switch → 85/90.
6. `Test_CritVolumeExitsFour` — `Program.Run([tempDir, "/summary", "/warn", "1", "/crit", "2"])` (any real volume is ≥2% used;
   assert the probed `PercentUsed >= 2` first) → exit 4, output has ` [CRIT]`. Positive control in the same test:
   `/warn 99 /crit 100` on the same dir → exit 0 and no tag (assert `PercentUsed < 99` first; skip the control with a message if
   the temp volume is that full).
7. `Test_JsonAndCsvCarryLevel` — `/summary /json` and `/summary /csv` with `/warn 1 /crit 2` → JSON target `level == "crit"`;
   CSV header ends `,level` and the volume row ends `,crit`.
8. `Test_CritWinsOverIncomplete` — a crit target plus an unreachable target (`\\nonexistent-host-dirused\share`, already used in
   existing tests if present; otherwise a missing local path) → exit 4; without the crit thresholds → exit 3.

9. `Test_ShouldColorOnlyForRealUnredirectedConsole` (Portable project) — pure `Fullness.ShouldColor(TextWriter output, bool color, bool redirected, string? noColor)`:
   `(Console.Out, true, false, null)` → true (positive control: proves the real console qualifies; `Console.Out` is `TextWriter+SyncTextWriter`, not `StreamWriter` — probed 2026-11-17, macOS, .NET SDK 11.0.100, net10.0);
   `(new StringWriter(), true, false, null)`, `(Console.Out, false, false, null)`, `(Console.Out, true, true, null)`, `(Console.Out, true, false, "1")` → false.

**Level needs a complete target (accepted deviation, run 1):** `Fullness.For` returns null unless `result.Complete && Volume.TotalBytes > 0`, matching `/summary`, which already lists incomplete targets as failures; so exit 4 never fires on a target the footer does not count.

Pre-fix red: all of 1-8 fail or do not compile on 3865f28 (new API). Mutations (apply by hand, run, revert; each must turn the
named test red): `>` instead of `>=` for crit (1); tag Ok lines too (2); emit ANSI escapes instead of ConsoleColor (4);
return 3 before checking crit (8); drop the warn<crit check (5); require `output.GetType() == typeof(StreamWriter)` in `ShouldColor` (9).

## What NOT to Do

- Do NOT add the top-3-folders feature, `/html`, or any directory walk to `/summary` (M2b and later).
- Do NOT change scanning, timeouts, `ScanRunner`, target parsing, or non-summary CSV.
- Do NOT use ANSI escape codes. Do NOT colour JSON or CSV.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep existing indentation, naming and brace style; LF endings; warnings are errors (no unused members); no refactors.
- Tests never touch a network share beyond the unreachable-host pattern existing tests already use.

## Gates

`dotnet test tests/Dirused.Tests.Portable -c Release -p:NuGetAudit=false` (must pass; runs on macOS), then `dotnet build -c Release` and `dotnet test` if the SDK is available in your sandbox; otherwise say so (Claude runs both on the
dirused-dev VM and CI).

## Definition of Done

- [ ] Changes 1-8; `git status` shows only files in the Files table.
- [ ] Tests 1-8 added; gate output or the reason it could not run.
- [ ] Report: changed files, test output, mutation table if run, and which existing assertions you updated. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: a volume at or above /warn (default 85) is tagged [WARN] and yellow on the console; at or above /crit (default 90) [CRIT] and red; both thresholds adjustable
  - id: M2
    text: dirused exits 4 when any volume is at or above /crit, ahead of 3 for incomplete targets
  - id: M3
    text: /summary text ends with a count of crit and warn volumes; JSON and /summary CSV carry a level field
must_not:
  - id: N1
    text: a 95% full volume prints the same as a 50% one and exits 0 — red today
  - id: N2
    text: a volume below /warn changes its output line
  - id: N3
    text: redirected output, JSON or CSV contains colour escape codes
  - id: N4
    text: /warn at or above /crit is accepted
evidence:
  - id: E1
    proves: [M1, N1, N2, N3]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~FullnessLevelBoundaries|FullyQualifiedName~TagsWarnAndCrit|FullyQualifiedName~TagsCritLine|FullyQualifiedName~NoEscapeCodes"
    intent: Full disks stand out in the server-list summary, yellow from 85% and red from 90%, and healthy ones look exactly as before.
  - id: E2
    proves: [M2]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~CritVolumeExitsFour|FullyQualifiedName~CritWinsOverIncomplete"
    intent: A scheduled run can alert on exit code 4 when any disk is past the red line.
  - id: E3
    proves: [M3, N4]
    kind: offline
    command: dotnet test --filter "FullyQualifiedName~JsonAndCsvCarryLevel|FullyQualifiedName~WarnCritSwitchesValidated"
    intent: Saved JSON and CSV reports say which disks are warn or crit, and a mistyped threshold is refused.
  - id: E4
    proves: [M1]
    kind: live
    command: "operator, office: dirused /file servers.list /summary (then again with /warn 50 /crit 60) — red/yellow lines and the footer on the console, exit code shown with echo %ERRORLEVEL%"
    intent: On the real server list, the colours and the count show up the way your teammate asked.
interface:
  - "dirused /warn <1-100> /crit <1-100> (defaults 85, 90)"
  - "exit code 4: any volume at or above /crit (takes precedence over 3)"
  - "JSON target field level: ok|warn|crit|null; /summary CSV final column level"
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** teammate's suggestion relayed by the operator; "make it default 85% but allow to be adjust same for /crit"; answers "Yes, new exit code" and "Only red/yellow" (top 3 → M2b); "when slot allowed, can you also dispatch dirused tasks?"
