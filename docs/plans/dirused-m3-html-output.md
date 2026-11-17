# dirused M3 — `/html` report with a multi-node table; `/output <path>`

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused / `m3-html-output` (from main aa54c2b)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (additive switches; existing output must stay byte-identical)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live run by the operator at the office.

## Problem

The operator checks many servers with `/summary /file servers.list`, and wants a report they can open in a browser and
pass around. Console text is the only readable output today; `/json` and `/csv` print to the console and cannot be
sent to a file except by shell redirection.

## Operator decisions (2026-11-17)

- `/html` adds an HTML report file. The console output is **unchanged** (same text, same format switch, same colours).
- `/output <path>` chooses the file. With `/html` it is the HTML file; the default is `C:\temp\output.html`,
  overwritten on every run. The folder is created when missing.
- Without `/html`, `/output <path>` sends the normal output (text, `/json` or `/csv`) to that file instead of the
  console.
- The report presents multiple nodes in a table: one row per volume, with a Host column.
- If the file cannot be written, exit 1 before any scan starts.
- Exit codes are unchanged.

| Command | Result |
|---|---|
| `dirused C:\ /html` | writes `C:\temp\output.html`; console unchanged |
| `dirused C:\ /html /output D:\reports\fleet.html` | writes that file; console unchanged |
| `dirused C:\ /json /output x.json` | JSON goes to `x.json`; nothing on stdout |
| `dirused C:\ /csv /output x.csv` | CSV goes to `x.csv`; error lines still go to stderr |
| `dirused C:\ /output x.txt` | text report goes to `x.txt`, no colour; nothing on stdout |
| `dirused C:\ /output` | usage error `/output requires a path`, exit 1 |

## Change

1. **`Options`** (`src/Dirused.Common/Options.cs`): append `bool Html = false, string? Output = null` at the end of
   the record (after `Crit`), so existing positional calls still compile.
2. **`ArgParser`** (`src/Dirused.Common/ArgParser.cs`):
   - `case "html": html = true; break;`
   - `case "output":` takes the next argument as a path. It is required: `++i >= args.Length` or a blank value returns
     `/output requires a path`. Same shape as `/file`.
   - Add `public const string DefaultHtmlPath = @"C:\temp\output.html";`. When `html` is true and no `/output` was
     given, `Options.Output` is `DefaultHtmlPath`.
   - Pass `html` and `output` into both `new Options(...)` calls (`:129`, `:147`).
   - Usage text, in `ShortUsageText`, `UsageText`, `README.md` and `tools/PACKAGE-README.txt`:
     - `ShortUsageText` second line becomes `[/top N] [/json|/csv] [/html] [/output <path>] [/warn [1-100]] [/crit [1-100]]`;
       wrap to a third line if it passes 80 columns.
     - `UsageText`, after `/csv`:
       `  /html               Also write an HTML report (default file: C:\temp\output.html)`
       `  /output <path>      Write the report to <path>: the HTML file with /html,`
       `                      otherwise the text, JSON or CSV output (default: console)`
     - Keep column alignment and the 80-column limit.
3. **Output file opening.** New `src/Dirused.Common/ReportOutput.cs`:
   `public static bool TryOpen(string path, out StreamWriter? writer, out string fullPath, out string? error)`.
   - It creates the parent folder (`Directory.CreateDirectory` on `Path.GetDirectoryName(Path.GetFullPath(path))`),
     then opens `new StreamWriter(fullPath, append: false, new UTF8Encoding(false))`.
   - Any `IOException`, `UnauthorizedAccessException`, `ArgumentException`, `NotSupportedException` or
     `SecurityException` gives `false` and error `Cannot write report '<path>': <message>`.
   - `Program.cs` calls it after the parse checks and **before** `TargetResolver`, only when `options.Output` is set.
     On `false` it writes the error to `error` and returns 1; no target is resolved or scanned. The writer is disposed
     in the existing `finally`.
4. **Wiring** (`Program.cs`):
   - Without `/html`: the existing renderer writes to the file writer instead of `output`. Colour turns off by itself,
     because the colour check is `ReferenceEquals(output, Console.Out)`. After rendering, write `Report: <full path>`
     to `error`.
   - With `/html`: the existing console rendering is unchanged and still goes to `output`. Then
     `new HtmlRenderer(options.Summary, options.Warn, options.Crit, options.Top).Render(fileWriter, results)` and write
     `HTML report: <full path>` to `error`.
   - Top folders: `TopFolders.Attach` runs today when `options.Summary && options.Format != OutputFormat.Csv`. Make it
     `options.Summary && (options.Format != OutputFormat.Csv || options.Html)`. CSV output must stay byte-identical
     (`CsvRenderer` in summary mode does not print `Directories`; test H10 proves it).
   - Exit code logic is unchanged and runs after the report is written.
5. **`SummaryRenderer.ExtractHost`**: change `private` to `internal` so the HTML renderer can use it. No other change.
6. **New `src/Dirused.Common/Renderers/HtmlRenderer.cs`**, `public sealed class HtmlRenderer(bool summary, int warn, int crit, int top) : IRenderer`:
   - One self-contained HTML5 page: `<!doctype html>`, `<meta charset="utf-8">`, `<title>dirused report</title>`,
     inline `<style>` only. No scripts, no external links, fonts or images.
   - **Every** string from a result (target, drive, path, error reason, note, host) goes through
     `System.Net.WebUtility.HtmlEncode`.
   - Header: `dirused report`, the generation time (`DateTimeOffset.Now`, format `yyyy-MM-dd HH:mm:ss zzz`), the
     machine name (`Environment.MachineName`), and `warn 85% / crit 90%` with the actual thresholds.
   - **Host column rule:** host = `SummaryRenderer.ExtractHost(r.Target)`; when empty (local target), use
     `Environment.MachineName`.
   - **Nodes table** (`<table class="nodes">`), one row per host, in order of each host's highest % used, descending:
     `Host | Volumes | Crit | Warn | Highest % used`. A host whose only targets failed shows `0` volumes and
     `failed` in the last cell.
   - **Volumes table** (`<table class="volumes">`), built from `SummaryRenderer.Prepare(results).Volumes` (same dedup
     and same `% used` descending order as the console): `Host | Volume | Used | Free | Total | % used | Level | Top folders`.
     - Volume = `Volume.Drive`, or the target when `Drive` is empty (same as `SummaryRenderer`).
     - Sizes use `Format.Size`. `% used` shows `F1` and a bar: `<span class="bar"><span style="width:NN%"></span></span>`,
       with NN clamped to 0-100 and formatted with `CultureInfo.InvariantCulture`.
     - Level: the `<tr>` gets `class="crit"` or `class="warn"` from `Fullness.For(r, warn, crit)`; the cell text is
       `CRIT`, `WARN` or empty.
     - Top folders: in summary mode, the same top 3 the console shows (largest first, `<br>`-separated
       `size path`), or `incomplete: <note>` when `TopFoldersNote` is set. Outside summary mode, empty.
   - **Failures table** (`<table class="failed">`), only when some target is not `Complete`: `Host | Target | Reason`,
     reason = first error's `Reason` or `Unknown error` (same as `SummaryRenderer`).
   - **Footer line**, when there is at least one volume: the same text as the console footer,
     `N volume(s): X at or above <crit>%, Y at or above <warn>%`.
   - **Outside summary mode only**, after the tables: one `<section>` per complete target with
     `<h2>` = host and target, and a table `Size | Path` of its top `top` directories then files, using `Format.Size`
     of `LogicalBytes`.
   - CSS: readable at phone width (tables scroll inside `<div class="scroll">`), light and dark via
     `@media (prefers-color-scheme: dark)`, `crit` rows red-tinted, `warn` rows amber-tinted, numbers right-aligned.
7. **`tools/live-check.ps1`**: new `L15` after `L14`.
   - Run `Invoke-Dirused @('C:\Windows\Web', '/summary', '/html', '/output', "$env:TEMP\dirused-l15\report.html")`
     after removing that folder if it exists.
   - Pass when `rc -in 0,4`, the file exists, its text matches `<table class="volumes">`, and `out` matches
     `HTML report: `.
   - `tools/PACKAGE-README.txt`: `L1-L14` becomes `L1-L15`, in both places.
8. **`CHANGELOG.md`** `## [Unreleased]`: an `### Added` list with `/html` and `/output`, in the same user-facing style as
   the existing sections.

## Tests (portable, `tests/Dirused.Tests.Portable/`)

`ArgParserTests.cs`:
- H1 `C:\ /html` gives Html true and Output `C:\temp\output.html`.
- H2 `C:\ /html /output r.html` gives Output `r.html`.
- H3 `C:\ /output` errors `/output requires a path`; `C:\ /output ""` gives the same error.
- H4 `C:\ /json /output x.json` gives Format Json, Html false, Output `x.json`.
- H5 positive control: `C:\` alone gives Html false and Output null.

New `HtmlRendererTests.cs` (build `ScanResult`s directly, as `RendererTests.cs` does):
- H6 multi-node: targets `\\srv1\c$`, `\\srv1\d$`, `\\srv2\c$` with 95%, 50%, 87% used. The nodes table has `srv1`
  then `srv2` (highest % order); the volumes table rows are in order 95, 87, 50; the 95% row has `class="crit"`, the
  87% row `class="warn"`, the 50% row neither.
- H7 escaping: a target and an error reason containing `<script>&"` appear only encoded (`&lt;script&gt;&amp;&quot;`);
  the raw `<script>` text is absent.
- H8 a failed target appears in the failures table with its reason; with no failures there is no `class="failed"` table.
- H9 local target (`C:\`) shows `Environment.MachineName` in the Host cell.

New `ReportOutputTests.cs` (portable):
- H12 unwritable: a path below an existing **file** (`tmp/afile/r.html`, where `afile` is a file) gives `false`,
  a null writer, and an error starting with `Cannot write report`.
- H13 the parent folder is created: `tmp/new/sub/r.html` gives `true`, creates `new/sub`, and the file exists after
  the writer is disposed.

Windows suite, new `tests/Dirused.Tests/ProgramHtmlTests.cs`. It runs in the Windows CI job; locally it only has to
build. Use `Program.Run` with `StringWriter`s and a temp folder target that the test creates and fills with two small
files, as the other `Program.Run` tests in that project do:
- H10 console unchanged: `Run([dir, "/summary"])` and `Run([dir, "/summary", "/html", "/output", tmp/"r.html"])` give
  byte-identical stdout and the same exit code; the file exists and contains `<table class="volumes">`; stderr contains
  `HTML report: `. Repeat with `/csv` added to both runs: stdout byte-identical.
- H11 `/output` without `/html`: `Run([dir, "/json", "/output", tmp/"x.json"])` leaves stdout empty, the file parses as
  JSON, and stderr contains `Report: `.
- H14 unwritable end to end: `Run([dir, "/html", "/output", tmp/"afile"/"r.html"])` returns 1, stderr starts with
  `Cannot write report`, and stdout is empty.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/Options.cs` | Change 1 |
| `src/Dirused.Common/ArgParser.cs`, `README.md` | Change 2 |
| `src/Dirused.Common/ReportOutput.cs` (new), `src/Dirused.Cli/Program.cs` | Changes 3-4 |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | Change 5 |
| `src/Dirused.Common/Renderers/HtmlRenderer.cs` (new) | Change 6 |
| `tools/live-check.ps1`, `tools/PACKAGE-README.txt` | Changes 2 and 7 |
| `CHANGELOG.md` | Change 8 |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `HtmlRendererTests.cs` (new), `ReportOutputTests.cs` (new) | Portable tests |
| `tests/Dirused.Tests/ProgramHtmlTests.cs` (new) | Windows tests H10, H11, H14 |
| other Windows `tests/Dirused.Tests/*` | only usage-text assertions that the grep below finds |

## Contract readers

- `Options` is built only at `ArgParser.cs:129` and `:147` (`grep -rn "new Options(" src tests`, 2026-11-17). Both
  must pass the new fields. The new parameters come last, with defaults.
- `SummaryRenderer.ExtractHost` gets one new reader (`HtmlRenderer`); `VolumeKey` and `Prepare` behaviour is
  unchanged.
- `TopFolders.Attach` condition changes (Change 4). Readers of `Directories` in summary mode: `SummaryRenderer`,
  `JsonRenderer` (unchanged condition for them), `CsvRenderer` (does not read it in summary mode, `CsvRenderer.cs:8-11`).
- Usage text is asserted in `tests/Dirused.Tests.Portable/ArgParserTests.cs` and Windows `tests/Dirused.Tests`. Run
  `grep -rn "json|/csv\|/csv  \|Usage:" tests` and update every assertion that matches the old text. (The M2c Windows
  CI red came from a missed reader of this kind.)

## What NOT to Do

- Do NOT change the console output of any existing command, any exit code, or any other switch.
- Do NOT add JavaScript, external URLs, CDN links or web fonts to the HTML.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep the existing style. LF line endings. No refactors beyond Change 5.

## Gates

- `dotnet build -m:1 -p:NuGetAudit=false`: 0 errors, 0 new warnings.
- `dotnet test tests/Dirused.Tests.Portable -c Release -m:1 -p:NuGetAudit=false`: all pass. Paste the summary line.
- `dotnet build tests/Dirused.Tests -p:EnableWindowsTargeting=true -m:1 -p:NuGetAudit=false`: 0 errors.
- pwsh parse check of `tools/live-check.ps1` prints `0`:
  `pwsh -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path tools/live-check.ps1), [ref]$null, [ref]$e); $e.Count'`.
- `git diff --check` is clean.

## Definition of Done

- [ ] Changes 1-8 and tests H1-H14 are done, and `git status` shows only files from the Files table.
- [ ] Gate output is pasted into the report, along with a diff summary and one sample HTML file produced by H6
      (path in the report). Nothing is committed.

## Acceptance

```yaml
must:
  - id: M1
    text: /html writes a self-contained HTML report (default C:\temp\output.html, or the /output path) and leaves the console output byte-identical
  - id: M2
    text: the HTML report shows a nodes table (one row per host) and a volumes table with a Host column, crit/warn rows marked, same order and dedup as /summary
  - id: M3
    text: /output without /html sends the text, JSON or CSV output to the file instead of stdout
  - id: M4
    text: an unwritable /output path exits 1 before any scan, with "Cannot write report"
  - id: M5
    text: every result string in the HTML is HTML-encoded
must_not:
  - id: N1
    text: "dirused <dir> /summary /html fails with Unknown switch — red today (H1, H10)"
  - id: N2
    text: "dirused <dir> /json /output x.json prints JSON on stdout — red today (H4, H11: /output is an unknown switch)"
  - id: N3
    text: "a target containing <script> appears unencoded in the report (H7)"
evidence:
  - id: E1
    proves: [M1, M3, M4, N1, N2]
    kind: offline
    command: portable tests H1-H5, H12-H13 (H1 red on main aa54c2b); Windows CI tests H10, H11, H14 on the PR
    intent: Adding /html or /output never changes what you see in the console, and a bad path fails at once instead of after a long scan.
  - id: E2
    proves: [M2, M5, N3]
    kind: offline
    command: portable tests H6-H9; sample HTML from H6 opened by Claude
    intent: A report for several servers lists each server and each disk in one table, worst first.
  - id: E3
    proves: [M1, M2]
    kind: live
    command: "operator, office: live-check.ps1 -Targets fleet.txt — L1-L15 and F1-F2 PASS; operator opens C:\\temp\\output.html from a /summary /file fleet.txt /html run"
    intent: One office run proves the report works on Windows across the real fleet.
interface:
  - "/html: also write an HTML report (default C:\\temp\\output.html)"
  - "/output <path>: report destination; HTML file with /html, otherwise the console output"
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "/html /output <default: c:/temp/output.html>" and "yes, and make table to present multiple
nodes" (operator, 2026-11-17), confirming the command table above, including the console staying unchanged with `/html`.
