# Review: dirused PR #19 (M3 `/html` multi-node report, `/output`) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m3-html-output` (head 2af7fb0; diff `aa54c2b..2af7fb0`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff aa54c2b..2af7fb0` blind. Intended behaviour:

- `/html` sets `Options.Html`; when no `/output` is given, `Options.Output` is `C:\temp\output.html`.
- `/output <path>` requires a non-blank path (`/output requires a path`).
- Before any target is resolved, `ReportOutput.TryOpen` creates the parent folder and opens the file (UTF-8, no BOM).
  On failure: stderr `Cannot write report '<path>': <message>`, exit 1, no scan.
- With `/html`: console output is byte-identical to the same command without `/html` (including `/csv` and `/json`),
  and `HtmlRenderer` writes the file; stderr `HTML report: <full path>`.
- Without `/html` but with `/output`: the normal renderer writes to the file instead of stdout (no colour);
  stderr `Report: <full path>`. CSV error lines still go to stderr.
- `TopFolders.Attach` runs when `Summary && (Format != Csv || Html)`; CSV output must not change.
- `HtmlRenderer`: self-contained page (no script, no external URL); every result string HTML-encoded; nodes table one
  row per host ordered by highest % used; volumes table from `SummaryRenderer.Prepare` with Host column, `crit`/`warn`
  row classes; failures table only when a target failed; same footer as the console; per-target entry tables outside
  summary mode. Local targets show `Environment.MachineName` as host.
- Exit codes unchanged.

Look for:
- any path where console output differs with `/html` added (colour detection, ordering, top-folder attach side effects
  on the text or JSON renderers);
- the output file left open, truncated after a scan error, or opened after the scan starts;
- an exception type from `TryOpen` that escapes uncaught (e.g. `PathTooLongException`, `DirectoryNotFoundException`
  on a drive that does not exist) and how `Program` reports it;
- `/output` value that starts with `/` or `-` (a switch) being taken as the path, and whether that is what a user expects;
- any unencoded string interpolated into the HTML, or attribute injection via the bar `width`;
- the nodes table counting a volume under the wrong host, or a failed-only host ordering;
- culture-dependent number formatting in the HTML;
- tests that cannot fail, or that write outside a temp folder;
- usage text, README or PACKAGE-README disagreeing with the code; L15 passing when no file was written.

## Before You Start

1. Read `src/Dirused.Cli/Program.cs`, `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/ReportOutput.cs`,
   `src/Dirused.Common/Renderers/HtmlRenderer.cs`, `src/Dirused.Common/Renderers/SummaryRenderer.cs`,
   `src/Dirused.Common/TopFolders.cs`, `README.md`, `tools/live-check.ps1`, `tools/PACKAGE-README.txt` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is 2af7fb0.

## Files

| File | Change |
|---|---|
| `src/Dirused.Cli/Program.cs` | read only |
| `src/Dirused.Common/Renderers/HtmlRenderer.cs` | read only |
| `src/Dirused.Common/ReportOutput.cs` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run tests that need Windows; reason from the code. `dotnet test tests/Dirused.Tests.Portable -m:1 -p:NuGetAudit=false` may be run.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the HTML report change before you try it at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "/html /output <default: c:/temp/output.html>", "yes, and make table to present multiple nodes" (M3); dirused PRs get a blind Argon review per the PR review budget.
