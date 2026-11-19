# dirused M10a.1: delete-list review fixes (Argon findings on PR #35)

**Filed:** 2026-11-19
**Status:** READY — operator approved 2026-11-19
**Repo / branch:** wilddog64/dirused / `m10a-purge-delete-list` (on top of 7a48ec0, PR #35, not yet merged)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10a-purge-delete-list.md` (rev 4)
**Risk:** medium (delete feature; adds skip reasons and error handling only, never a new delete path)
**Implementer:** Luna (Codex). **Verifier:** Claude.
**Intent approved:** operator, 2026-11-19
Intent note: operator replied "approve" to the six fixes summarised in chat (2026-11-19).

## Problem

Argon blind review of PR #35 (2026-11-19), checked by Claude against 7a48ec0:

1. `/fromlist` dry run (`src/Dirused.Common/Purge.cs:92-102`) reports `would delete` for files that `/confirm`
   (`ProcessFile`, `Purge.cs:142-148`) skips: directory or reparse point, `LinkCount != 1`, final path outside the target,
   read-only. `Stat` (`Purge.cs:236-246`) does not set `IsReadOnly`. The operator builds `delete.txt` from this output.
2. `RunFromList` (`src/Dirused.Cli/Program.cs:171-183`) opens the purge log with no catch: an IO or access error crashes
   instead of printing the error and exiting 1 (the scan path does this at `Program.cs:68-69`). `Path.GetFullPath` at
   `Program.cs:54-64` and `ArgParser.cs:262` throws on invalid path text.
3. Parser: `/savelist` (`ArgParser.cs:162`) and `/fromlist` and its `/output` (`ArgParser.cs:118-124`) take the next
   token as a path even when it is a switch (`/fromlist /confirm /purge` sets the list path to `/confirm`).
   `args[j+1].All(char.IsAsciiDigit)` is true for `""`.
4. HTML for `/fromlist` renders empty per-target sections (`HtmlRenderer.cs:71` iterates `results`, not the filtered set).
5. `RunFromList` dry-run summary omits the failed count (`Program.cs:180`; the scan path prints it at `:148`).
6. `PurgeList.Read` accepts an empty target field and a time that is not UTC (`PurgeList.cs:30-40`).

## Change

1. **Dry run matches confirm.** `RealPurgeFileSystem.Stat` sets `IsReadOnly` from the attributes (as `Open` does at
   `Purge.cs:265`). In the dry-run list branch, after the volume/ID/size-or-time checks, in the same order and with the
   same status text as `ProcessFile`: `skipped: not a regular file`, `skipped: hard-linked`, `skipped: outside target`
   (final path vs the target root resolved with `fs.ResolveRoot`, as confirm does; a root that does not resolve gives
   `failed: cannot open target: <error>`), `skipped: read-only`. The dry run still opens no file with Delete access.
2. **No crashes on bad paths.** Wrap the purge-log open in `RunFromList` like `Program.cs:68-69` (print error, exit 1,
   nothing deleted). Invalid path text in `/savelist`, `/fromlist` or `/output` gives a usage error `invalid path: <text>`,
   exit 1.
3. **Parser.** A path argument to `/savelist`, `/fromlist` or `/output` that is a known switch, or empty or whitespace,
   is a usage error (`/savelist requires a path`, `/fromlist requires a path`, `/output requires a path`). `/purge`
   followed by an empty argument is not a days value.
4. **HTML:** `/fromlist` HTML renders only the purge tables: no empty per-target sections, no Nodes/Volumes tables.
5. **Summary:** the dry-run summary includes `; {Failed} could not be checked` exactly as `Program.cs:148`.
6. **Reader:** an empty target field, or a time whose parsed `Kind` is not `Utc`, is a bad line (`bad target`,
   `bad modification time`).

## Files

- `src/Dirused.Common/Purge.cs`
- `src/Dirused.Common/PurgeList.cs`
- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Cli/Program.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `tests/Dirused.Tests.Portable/PurgeListTests.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests/ProgramPurgeTests.cs`
- `CHANGELOG.md`

## What NOT to Do

- Do not add any path that deletes, renames or opens a file with Delete access in a dry run.
- Do not change scan-path `/purge` output, statuses or exit codes.
- Do not reformat or restructure code you are not changing.
- Do not update `memory-bank/`, create a PR, push, or skip hooks.
- Your sandbox cannot restore NuGet or start the test runner; that is expected. Finish all code and tests anyway;
  Claude runs `dotnet test` outside the sandbox.

## Acceptance

```yaml
must:
  - id: M1
    text: "/fromlist dry run reports 'skipped: read-only', 'skipped: hard-linked', 'skipped: not a regular file' and 'skipped: outside target' for list rows whose Stat shows those, each with a matching peer in the same run reported 'would delete'"
  - id: M2
    text: "a purge log that cannot be opened in /fromlist /confirm prints the error and exits 1 with nothing deleted; invalid path text in /savelist, /fromlist or /output is 'invalid path: <text>' exit 1"
  - id: M3
    text: "'/fromlist /confirm /purge', '/savelist /exact', an empty /savelist path and '/output /fromlist' are usage errors; positive control '/fromlist f /purge /output r.txt' parses"
  - id: M4
    text: "/fromlist /html output has no per-target section and no Nodes or Volumes table; the dry-run summary contains 'could not be checked'"
  - id: M5
    text: "a list line with an empty target or a non-UTC time is under 'Bad list lines:' and the run exits 3, with a valid peer still processed"
must_not:
  - id: N1
    text: "a /fromlist dry run reports 'would delete' for a read-only, hard-linked, reparse or outside-target file (red on 7a48ec0)"
  - id: N2
    text: "the /fromlist dry run calls Open on the fake file system (zero Open calls asserted alongside M1)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; new tests red on 7a48ec0; mutants each red: drop the dry-run read-only check, drop the hard-link check, drop the outside-target check, accept a switch as the /fromlist path; Windows CI green"
    intent: The dry run shows the same skip reasons /confirm will use, so the list you review is the list that gets deleted.
interface:
  - "skipped: read-only"
  - "skipped: hard-linked"
  - "skipped: not a regular file"
  - "skipped: outside target"
  - "invalid path: <text>"
  - "/fromlist requires a path"
  - "/savelist requires a path"
  - "/output requires a path"
  - "could not be checked"
```
