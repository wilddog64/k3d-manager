# dirused M2b — `/summary` lists the top 3 folders of a yellow or red volume

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused / `m2b-top-folders` (from `main` 3eff57b, v0.0.5)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low-medium (adds a bounded folder walk to `/summary`, which was walk-free)
**Implementer:** Luna (Codex). **Verifier:** Claude (portable tests, Windows CI, mutation checks); live run by the operator at the office.

## Problem

M2a (v0.0.5) tags a volume ` [WARN]` (at or above `/warn`, default 85) or ` [CRIT]` (at or above `/crit`, default 90) in
`/summary`. The operator then has to run a second, full scan of that server to see what is filling it. Operator decision
(2026-11-17): show the top 3 folders, but only for yellow/red volumes, so ok volumes stay walk-free and a fleet `/summary`
stays fast.

## Behaviour

- `/summary` (text or `/json`): after the volume scan, every target whose `Level` is `Warn` or `Crit` gets a second,
  depth-1, non-exact scan of its target path (the same scan a bare `dirused <target>` runs). Targets with level `Ok` or no
  level are never walked.
- That second scan runs through `ScanRunner` with the same `/parallel`, and `/timeout` when given, else **60s** per target.
- The summary result keeps its own `Volume`, `Level`, `Complete` and `Errors`. It gains `Directories` = the 3 largest
  depth-1 folders of the second scan by `LogicalBytes` descending, ties by path (ordinal, ignore case). Files are not listed.
- If the second scan is not complete (timed out, cancelled, a folder unreadable), the folders it did gather are still listed,
  followed by one note line `    top folders incomplete: <path>: <reason>` from its first error.
- Exit code and the footer are unchanged by the second scan: a red volume still exits 4; an incomplete second scan does not
  turn exit 0 into 3.
- `/summary /csv` is unchanged and runs no second scan.

Text, after the volume line it belongs to (folder lines are never coloured):

```
\\srv1\C$ used 93.1 GB, free 6.9 GB, total 100.0 GB, 93.1% used [CRIT]
    41.0 GB  \\srv1\C$\Users
    22.0 GB  \\srv1\C$\Windows
     9.8 GB  \\srv1\C$\inetpub
C:\ used 40.2 GB, free 59.8 GB, total 100.0 GB, 40.2% used
2 volume(s): 1 at or above 90%, 0 at or above 85%
```

Folder line = four spaces + size (`Format.Size`) left-padded to the widest size among that volume's folder lines + two
spaces + `Entry.Path`.

## Changes

1. New `src/Dirused.Common/TopFolders.cs`:
   ```csharp
   public static class TopFolders
   {
       public const int Count = 3;
       public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(60);
       public static IReadOnlyList<ScanResult> Attach(IReadOnlyList<Target> targets, IReadOnlyList<ScanResult> results,
           Func<Target, CancellationToken, ScanResult> scan, RunOptions options, CancellationToken ct);
   }
   ```
   `results[i]` belongs to `targets[i]`. Picks the indices whose `Level` is `Warn` or `Crit`; returns `results` unchanged
   (same list contents) if there are none; else runs `ScanRunner.Run` on just those targets and returns a new list where
   each picked result is `r with { Directories = <top 3>, TopFoldersNote = <note or null> }`.
2. `src/Dirused.Common/ScanResult.cs`: add `[JsonIgnore] public string? TopFoldersNote { get; init; }` (the text after
   `top folders incomplete: `, i.e. `<path>: <reason>`).
3. `src/Dirused.Cli/Program.cs`: after the `.Select(x => x with { Level = ... })` / `.ToList()`, when
   `options.Summary && options.Format != OutputFormat.Csv`:
   `results = TopFolders.Attach(targets, results, (t, token) => RemoteScan.Scan(byTarget[t], 1, false, token), new RunOptions(options.Parallel, options.Timeout ?? TopFolders.DefaultTimeout), cts.Token).ToList();`
   (`results` becomes a mutable local of type `List<ScanResult>`; nothing else in `Program.cs` changes.)
4. `src/Dirused.Common/Renderers/SummaryRenderer.cs`: after each volume line, print its folder lines (format above) from
   `r.Directories` ordered by `LogicalBytes` desc then path, at most `TopFolders.Count`, then the note line if
   `r.TopFoldersNote` is set. Failed-target lines and the footer are unchanged.
5. `src/Dirused.Common/Renderers/JsonRenderer.cs`: in summary mode keep each target's `directories` (empty unless it is a
   warn/crit target with top folders); `files` stays empty.
6. `src/Dirused.Common/ArgParser.cs` usage text and `README.md` Switches block (keep the two identical):
   `/summary            Volume usage; a /warn or /crit volume also lists its top 3 folders (default: off)`.
   README: one sentence under the `/warn`/`/crit` paragraph saying the top-3 walk obeys `/timeout` (60s per target when
   `/timeout` is not given) and never affects the exit code.
7. `tools/live-check.ps1`: new `L13` after `L12`:
   `Invoke-Dirused @('C:\Windows\Web', '/summary', '/warn', '1', '/crit', '2')`;
   `Test-Check 'L13' '/summary lists the top folders of a [CRIT] volume' (($r.rc -eq 4) -and ($r.out -match '(?m)^    \S.*  C:\\Windows\\Web\\'))`.
   `tools/PACKAGE-README.txt`: `L1-L12` → `L1-L13` (both places).
8. `tests/Dirused.Tests/SummaryTests.cs` `E2_...`: append `"/warn", "99", "/crit", "100"` to the text `/summary` run and the
   `/summary /json` run so E2 stays level-independent on a nearly full CI runner (its `C:` was 79.9% on 2026-11-17).
   No other change to E2.

## Tests

`tests/Dirused.Tests.Portable/TopFoldersTests.cs` (portable, fake `scan` delegate, no real file system):

1. `Test_AttachWalksOnlyWarnAndCritTargets` — four results with levels `Ok`, `Warn`, `Crit`, `null`; the fake scan records
   each target it gets; assert exactly the Warn and Crit targets were scanned and the Ok/null results come back with empty
   `Directories` and null `TopFoldersNote`.
2. `Test_AttachKeepsTop3FoldersByLogicalSize` — fake scan returns 5 directories (one tie) and 2 files; assert `Directories`
   is the 3 largest by `LogicalBytes`, tie broken by path, no files; `Volume`, `Level`, `Complete`, `Errors` of the summary
   result are unchanged.
3. `Test_AttachNotesIncompleteSecondScan` — fake scan returns 2 directories, `Complete = false`, errors
   `[("X:\\a\\b", "Access is denied.")]`; assert both folders kept, `TopFoldersNote == "X:\\a\\b: Access is denied."`, summary
   result's `Complete` and `Errors` unchanged.
4. `Test_AttachTimeoutLeavesVolumeLevel` — fake scan blocks until its token is cancelled; `RunOptions(Timeout: 200ms)`;
   assert note contains `TIMED OUT after`, `Level` still `Crit`, `Directories` empty.
5. `Test_SummaryRendererPrintsFoldersUnderTheirVolume` — one Crit result with 3 folders + note, one Ok result; assert exact
   lines: Crit volume line, 3 padded folder lines, note line, Ok volume line, footer.
6. `Test_SummaryJsonKeepsTopFolders` — `JsonRenderer(summary: true)` keeps the Crit target's 3 `directories`, empty `files`.

`tests/Dirused.Tests/SummaryTests.cs` (Windows CI), new `E3_SummaryListsTopFoldersOfCritVolumeOnly`: temp root with folders
`a` (3 MB), `b` (2 MB), `c` (1 MB), `d` (512 KB) of real files; `Run(root, "/summary", "/warn", "1", "/crit", "2")` → exit 4,
volume line ends ` [CRIT]`, the next three lines end `\a`, `\b`, `\c` in that order, no line ends `\d`, last line is the
footer. Positive control in the same test: `Run(root, "/summary", "/warn", "99", "/crit", "100")` → exit 0 and exactly
2 lines (volume + footer).

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/TopFolders.cs` | new (Change 1) |
| `src/Dirused.Common/ScanResult.cs` | Change 2 |
| `src/Dirused.Cli/Program.cs` | Change 3 |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | Change 4 |
| `src/Dirused.Common/Renderers/JsonRenderer.cs` | Change 5 |
| `src/Dirused.Common/ArgParser.cs` | Change 6 (usage text only) |
| `README.md` | Change 6 |
| `tools/live-check.ps1`, `tools/PACKAGE-README.txt` | Change 7 |
| `tests/Dirused.Tests/SummaryTests.cs` | Change 8, test E3 |
| `tests/Dirused.Tests.Portable/TopFoldersTests.cs` | new, tests 1-6 |

## Contract readers

`grep -rn "Summary\|summary" src tools tests --include=*.cs --include=*.ps1` (2026-11-17, 3eff57b):
- `SummaryRenderer.Prepare` is also used by `JsonRenderer` (summary) and `CsvRenderer` (summary); dedupe and order are
  unchanged, CSV ignores `Directories`.
- `JsonRenderer` summary output: `directories` was always `[]`; now non-empty for warn/crit targets. Readers:
  `tools/live-check.ps1` L3 (reads `targets[].complete/target` only, runs with `/warn 99 /crit 100`), `SummaryTests.E2`
  (asserts `[]`, pinned to 99/100 by Change 8).
- `RendererTests.E1_SummaryKeepsHostsSharingVolumeSerialNumberInTextJsonAndCsv`: results built with empty `Directories`,
  so its expected text is unchanged.
- `ArgParser.UsageText` is printed by `/help` (live-check L10 matches `Exit codes` and `/parallel` only).

## What NOT to Do

- Do NOT walk a target whose level is `Ok` or null, and do NOT walk in `/summary /csv`.
- Do NOT let the second scan change `Level`, `Complete`, `Errors`, the footer or the exit code.
- Do NOT colour folder lines; do NOT emit ANSI escapes.
- Do NOT change non-summary output, `/top`, or CSV.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Match the surrounding style (primary constructors, expression bodies, `with` copies); LF endings; no refactors.
- Windows-only tests stay in `tests/Dirused.Tests`; everything else goes in `tests/Dirused.Tests.Portable`.

## Gates

- `dotnet build -m:1 -p:NuGetAudit=false` — 0 warnings added, 0 errors.
- `dotnet test tests/Dirused.Tests.Portable -m:1 -p:NuGetAudit=false` — all pass, including tests 1-6.
- `pwsh -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path tools/live-check.ps1), [ref]$null, [ref]$e); $e.Count'` prints `0`.
- `tests/Dirused.Tests` (E3, E2) runs on Windows CI only; it must compile here (`dotnet build`).

## Definition of Done

- [ ] Changes 1-8 and tests; `git status` shows only Files-table files.
- [ ] Gate output pasted (test counts).
- [ ] Report: diff summary. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: in /summary text and JSON, a warn or crit volume is followed by its 3 largest depth-1 folders, largest first
  - id: M2
    text: ok and level-less targets are never walked, and /summary /csv never walks
  - id: M3
    text: the second walk is bounded by /timeout (60s default) and never changes the level, footer or exit code; an incomplete walk adds one "top folders incomplete" note
must_not:
  - id: N1
    text: a [WARN] or [CRIT] volume line in /summary is printed with no folder lines under it — red today
  - id: N2
    text: summary JSON for a crit target has an empty directories array — red today
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: dotnet test tests/Dirused.Tests.Portable (TopFoldersTests 1-6); mutations — drop the Warn/Crit filter (test 1 red), Take(4) (tests 2 and 5 red)
    intent: The top-folders logic is proven on fake scans before it touches a real disk.
  - id: E2
    proves: [M1, N1]
    kind: offline
    command: Windows CI on the PR head — SummaryTests.E3 (crit lists a, b, c; d absent; 99/100 lists none) and E2 green
    intent: The real Windows walk lists the right folders, in order, only for a red volume.
  - id: E3
    proves: [M1, M2, M3]
    kind: live
    command: "operator, office, after the next release: live-check.ps1 -Targets fleet.txt (L1-L13, F1-F2 PASS) and dirused /file servers.list /summary — each [WARN]/[CRIT] server shows 3 folder lines; ok servers none"
    intent: One run at the office shows, for each yellow or red server, what is filling it.
interface:
  - "TopFolders.Attach(targets, results, scan, RunOptions, ct); TopFolders.Count = 3; TopFolders.DefaultTimeout = 60s"
  - "ScanResult.TopFoldersNote (JsonIgnore)"
  - "summary text folder line: 4 spaces + padded size + 2 spaces + path; note: '    top folders incomplete: <path>: <reason>'"
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "show the top 3 folders, but only for red/yellow" ("Only red/yellow (Recommended)", 2026-11-17)
and "go head to write M2b spec and dispatch when there's a slot" (2026-11-17).
