# dirused M10a: save the would-delete list to a file, and delete from that file

**Filed:** 2026-11-19
**Status:** DRAFT — awaiting spec review (Fable + Astra blind, Claude adjudicates; deletion path = medium risk) and intent approval
**Repo / branch:** wilddog64/dirused / `m10a-purge-delete-list` (from main 4130598, v0.0.21)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10-scheduled-purge.md` Amendment 3 (operator, 2026-11-19: "files to delete should store in a
delete.txt and use that for deletion"; "go with your suggestion"). M10a is the list half, with no scheduling and no Tomcat
handling. M10b (`/schedule`) and M9 (Tomcat stop/start) build on it.
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the office jump box.
**Intent approved:** no

## Why

Operator: "what if next time the pattern changed and not in our list?". Today `/confirm` runs a new scan with the given
patterns, so what is deleted is whatever matches at that moment, not the list that was reviewed. M10a makes the reviewed list
the unit of deletion.

## Behaviour

1. **`/savelist <file>`**, valid only with `/largest ... /purge` and without `/confirm`. After the dry run, dirused writes
   every row whose status is `would delete` to `<file>` (UTF-8, LF or CRLF accepted on read, CRLF written):
   - Header lines start with `#`: tool version, UTC time, the full argument list, and the column names.
   - One data line per file, tab-separated: `target`, `bytes`, `lastWriteUtc` (ISO 8601 `Z`), `fileId` (16 hex digits,
     volume-relative NTFS file index from `GetFileInformationByHandle`, taken when the dry run opens or stats the file),
     `path`.
   - Rows that are skipped, failed or below `/minsize` are never written. A run with no `would delete` rows writes the
     header only and says so.
   - The file is written to a temp name in the same directory and renamed into place; an existing file is replaced.
2. **`/fromlist <file>`**, used as `dirused /fromlist delete.txt /purge [days] [/minsize <size>] [/confirm]`. No targets,
   `/file`, `/largest` or patterns are allowed with it (usage error). dirused reads the list and does not scan.
   For each data line it applies, in order: the existing M8 checks of `Purge.Apply` (absolute path, strictly under its
   `target`, not the purge log, age against the file's current modified time, `/minsize` against the current size), then:
   - the file now at `path` has the same `fileId` → else `skipped: file changed since list (id)`;
   - its current size is at least `bytes` → else `skipped: file changed since list (smaller)`.
   A line that does not parse (wrong column count, bad number, bad hex, bad time) is reported `skipped: bad list line N`
   and never deleted. Lines starting `#` and blank lines are ignored. Deleting lines is the only supported edit.
3. Without `/confirm`, `/fromlist` is a dry run with the same output as today's `/purge` text/HTML/JSON/CSV, grouped by
   `target`. With `/confirm` it deletes through the existing M8 delete path (same open, mark-delete, purge log).
4. The pattern rules of M8b (`/confirm` needs explicit patterns) do not apply to `/fromlist`: the list is the selection.
   A list with zero data lines exits 0 and deletes nothing.

## Contract readers

- `Options` record (`src/Dirused.Common/Options.cs`): add `SaveList` and `FromList` (string?, last, default null). Built only
  in `ArgParser.cs:249`.
- `/output` (`ArgParser.cs:129`) is the HTML path; `/savelist` is separate and must not equal the `/output` path or the purge
  log path (usage error), same rule as `Program.cs:55`.
- `LargestFile` (`src/Dirused.Common/Largest.cs:26`): add `ulong? FileId` (JSON: omitted when null). Writers: `Largest.cs:48`
  and the new list reader. Readers: renderers ignore it; JSON shows it.
- `Purge.Apply` (`Purge.cs:51`): the file-ID and size checks run only for list entries (FileId set); scan-path behaviour is
  unchanged. `RealPurgeFileSystem` already calls `GetFileInformationByHandle` (`Purge.cs:228`); expose the file index in
  `PurgeFileInfo`.

## Files

- `src/Dirused.Common/ArgParser.cs`, `Options.cs`, `Largest.cs`, `Purge.cs`, new `PurgeList.cs` (read/write)
- `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/` (`ArgParserTests.cs`, `PurgeTests.cs`, new `PurgeListTests.cs`)
- `tests/Dirused.Tests/ProgramPurgeTests.cs` (Windows end-to-end)
- `README.md`, `CHANGELOG.md`, help text in `ArgParser.cs`

## What NOT to Do

- Do not change scan-path `/purge` or `/confirm` behaviour, statuses, output or exit codes.
- Do not delete a list line's file on any parse error, ID mismatch, smaller size, or failed M8 check.
- Do not write skipped rows to the list, and do not read `#` lines as data.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "/largest <p> /purge /savelist f writes exactly the would-delete rows (target, bytes, lastWriteUtc, fileId, path) under a # header; skipped rows absent"
  - id: M2
    text: "/fromlist f /purge /confirm deletes exactly the listed files that still pass M8 checks, same fileId and size >= listed; nothing else under the target is touched"
  - id: M3
    text: "removing a line from f means that file is not deleted (positive control: the remaining lines are deleted)"
  - id: M4
    text: "/fromlist without /confirm deletes nothing and shows would delete / skipped per line"
must_not:
  - id: N1
    text: "a list line whose file was replaced (new fileId at the same path) is deleted"
  - id: N2
    text: "a list line with no or malformed fileId, or a hand-added line, is deleted"
  - id: N3
    text: "/fromlist is combined with targets, /file, /largest or patterns without a usage error"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; new tests red on 4130598; mutants: skip fileId check (N1 red), accept malformed id (N2 red), drop size>=listed check (M2 red); Windows CI ProgramPurgeTests end to end with a real file replaced between save and confirm"
    intent: Only the files you reviewed in delete.txt can be deleted; a changed or added line deletes nothing.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    command: "operator, jump box: on a scratch folder, save a list, delete one line, run /fromlist /confirm, check only the remaining files are gone; then a dry-run /savelist on the server list"
    intent: On the jump box, save a list, edit it, and see that only what's left in it gets deleted.
interface:
  - "/savelist <file>"
  - "/fromlist <file>"
  - "skipped: file changed since list (id)"
  - "skipped: file changed since list (smaller)"
  - "skipped: bad list line N"
```
