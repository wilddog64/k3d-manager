# dirused M10a: save the would-delete list to a file, and delete from that file

**Filed:** 2026-11-19
**Status:** DRAFT rev 2 — rev 1 Fable blind review NOT READY (4 blockers, all taken, see Review log); rev 2 awaits Fable re-review + Astra (after codex quota) and intent approval
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
the unit of deletion. Rule: **a list line deletes a file only if it is byte-for-byte the file that was reviewed** (same
volume, same file ID, same size, same modified time). Anything else is skipped. Growing live logs are out of scope here;
M9/M10b decide that rule.

## Behaviour

### `/savelist <file>` (with `/largest ... /purge`, never with `/confirm`)

1. **ID source = the scan.** `DirectoryReader` already returns `DirEntry.FileId` (`src/Dirused.Core/DirectoryReader.cs:71`)
   and the volume serial is in `Volume.SerialNumber` (`src/Dirused.Common/ScanResult.cs:12`). Pass the ID through
   `LargestCollector.Offer` (`src/Dirused.Common/Largest.cs:44`, new trailing `ulong? fileId = null`) from `Scanner.cs:164`;
   the fallback enumeration (`Scanner.cs:74-113`, `FileInfo`) passes null. IDs 0 and `ulong.MaxValue` count as null
   (`Scanner.cs:143`). The dry run still opens no file.
2. After the dry run, every row with status `would delete` **and** a non-null file ID is written. A `would delete` row with
   no ID is not written; the summary says `N file(s) not saved: no file ID (server does not report one)`.
3. **Format** (UTF-8 with BOM, CRLF written; CRLF or LF and BOM or no BOM accepted on read):
   - Line 1 exactly `# dirused delete list v1`. Then `#` lines: tool version, UTC time, full argument list, column names.
   - Data lines, tab-separated, 6 columns: `target` (`ScanRoot ?? Target`, as used at `Purge.cs:63`; not the display name
     set at `RemoteScan.cs:15`), `volumeSerial` (8 hex), `fileId` (16 hex), `bytes` (decimal), `lastWriteUtc` (round-trip
     `O` format, full ticks), `path` (the last column; may contain tabs).
   - Temp file in the same directory, then rename over the target.
4. `/savelist` path equal to the `/output` path or the purge log path is a usage error (same rule as `Program.cs:55`).

### `/fromlist <file> /purge [days] [/minsize <size>] [/confirm]`

5. **Allowed with it:** `/purge`, its days, `/minsize`, `/confirm`, `/html`, `/output`, `/json`, `/csv`, `/timeout`.
   Anything else (targets, `/file`, `/largest`, patterns, `/summary`, `/deep`, `/exact`, `/parallel`, `/largestcount`,
   `/savelist`) is a usage error. `/purge` is required. `/fromlist` path equal to `/output` or the purge log is a usage error
   (checked before `Program.cs:65` opens the output). These bypass `ArgParser.cs:224` (purge requires largest),
   `:229-231` and `:248` (zero targets) for `/fromlist` only.
6. **Reading:** first line (after BOM) must be `# dirused delete list v1`, else usage error `not a dirused delete list: <file>`
   exit 1, nothing done. Lines are not trimmed. A data line is split on the first 5 tabs. A line with fewer than 6 fields or
   a bad number/hex/time is `skipped: bad list line N` (never deleted). A path that appears twice is used once; the second is
   `skipped: duplicate list line N`.
7. **Grouping:** lines are grouped by `target` into one result per target. The text and HTML output print no volume line
   for these results (no scan ran); they print the target name and the same purge table and summary as today.
   `/timeout` applies per target as today.
8. **Checks, in order, per line:** the existing `Purge.Apply` pre-open chain (`Purge.cs:77-84`: absolute, strictly under
   `target`, not the purge log, `/minsize` and age on the **listed** bytes and time), then:
   - **Dry run (no `/confirm`):** a read-only stat through a new `IPurgeFileSystem.Stat(path)` (ReadAttributes, share
     read/write/delete, no Delete access) returns volume serial, file ID, size, modified time. Mismatch on serial or ID →
     `skipped: file changed since list (id)`; on size or time → `skipped: file changed since list (size or time)`; missing →
     `skipped: not found`; else `would delete`.
   - **`/confirm`:** the existing open (`Purge.cs:118-131`). The volume serial and file ID are compared on the **same handle**
     that later gets `MarkDelete` (read from `opened.Info`, which gains `VolumeSerial` and `FileIndex` init properties; the
     positional `PurgeFileInfo` record stays as is). Mismatch → the same `(id)` status. The existing `:127` size-and-time check
     then applies unchanged and is reported as `skipped: file changed since list (size or time)` for list entries.
9. Exit codes as today; any `bad list line` or `duplicate` counts as a purge that did not finish (exit 3). A list with zero
   data lines: exit 0, nothing deleted.

## Contract readers

- `LargestCollector.Offer` (`Largest.cs:44`): callers `Scanner.cs:113`, `Scanner.cs:164`, `tests/Dirused.Tests.Portable/LargestTests.cs:29-36` (unchanged, new parameter defaults).
- `LargestFile` (`Largest.cs:26`): add `FileId` and `VolumeSerial` as `[JsonIgnore]` init properties, so scan-path JSON is unchanged.
- `PurgeFileInfo` (`Purge.cs:9`): add init properties; positional callers `PurgeTests.cs:97-104,245` unchanged.
- `IPurgeFileSystem` (`Purge.cs:30`): new `Stat`; implementers `RealPurgeFileSystem`, fakes `PurgeTests.cs:232`, `ProgramPurgeTests.cs:278,286`.
- `Options` (`Options.cs`): `SaveList`, `FromList` (string?, last, default null); built at `ArgParser.cs:249`.
- `Program.cs`: `:55` and `:65` path checks; `:91` Fullness computed only for scan results; `:98` `Purge.Apply` call.

## External behaviour (proof owed, fails safe)

The scan ID comes from `FileIdBothDirectoryInformation` and the delete-time ID from `GetFileInformationByHandle`. They are
equal on NTFS; over SMB to `\\host\d$` this is expected but not yet observed. If they differ, every line is `skipped: file
changed since list (id)` and nothing is deleted. E2 step 1 is the proof (host, date, version recorded).

## Files

- `src/Dirused.Core/Scanner.cs`, `src/Dirused.Common/Largest.cs`, `Purge.cs`, `ArgParser.cs`, `Options.cs`, new `PurgeList.cs`
- `src/Dirused.Cli/Program.cs`, `src/Dirused.Common/Renderers/TextRenderer.cs`, `HtmlRenderer.cs` (no volume line for list results)
- `tests/Dirused.Tests.Portable/` (`ArgParserTests.cs`, `PurgeTests.cs`, `LargestTests.cs`, new `PurgeListTests.cs`)
- `tests/Dirused.Tests/ProgramPurgeTests.cs` (Windows end to end)
- `README.md`, `CHANGELOG.md`, help text in `ArgParser.cs`

## What NOT to Do

- Do not open files with Delete access during any dry run (`/savelist` or `/fromlist` without `/confirm`).
- Do not change scan-path `/purge` or `/confirm` behaviour, statuses, output, JSON or exit codes.
- Do not delete a list line's file on any parse error, duplicate, serial/ID mismatch, size or time change, or failed M8 check.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "/largest <p> /purge /savelist f writes line 1 '# dirused delete list v1' and exactly the would-delete rows that have a file ID (target, volumeSerial, fileId, bytes, lastWriteUtc, path); skipped rows and no-ID rows absent, no-ID count printed"
  - id: M2
    text: "/fromlist f /purge /confirm deletes exactly the listed files whose serial, ID, size and time match on the delete handle and pass the M8 checks; other files under the target untouched"
  - id: M3
    text: "removing a line from f means that file is not deleted, while the remaining lines are deleted in the same run"
  - id: M4
    text: "/fromlist without /confirm opens no file with Delete access, deletes nothing, and reports would delete / the skip statuses per line"
  - id: M5
    text: "a file that is not a dirused list (no v1 first line) is refused with 'not a dirused delete list' and exit 1"
must_not:
  - id: N1
    text: "a listed path whose file was replaced (new file ID, same size, backdated time) is deleted; the test asserts status 'skipped: file changed since list (id)' and, in the same run, a matching line is deleted"
  - id: N2
    text: "a line with a malformed or missing field is deleted; the test asserts 'skipped: bad list line N' and a valid line in the same list is deleted"
  - id: N3
    text: "/fromlist combined with a target, /file or /largest parses; the test asserts the exact usage message (pre-fix the message is 'Unknown switch', so the assertion on the new message is the red), with a positive control that /fromlist f /purge parses"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; new tests red on 4130598; mutants each red: skip serial/ID compare (N1), accept malformed line (N2), allow /fromlist with /file (N3), open with Delete in dry run (M4), compare ID from a separate open instead of opened.Info (M2 test with a fake that swaps the file between opens); Windows CI ProgramPurgeTests end to end: save, replace one file with a backdated same-size file, /fromlist /confirm"
    intent: Only files you reviewed in delete.txt can be deleted; a replaced file, a broken line or an edited list deletes nothing extra.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    command: "operator, jump box: (1) /savelist on one server's tomcat logs, dry run /fromlist shows 'would delete' (not '(id)'), which proves the scan ID matches the handle ID over \\host\d$; (2) on a scratch share folder: save, delete one line, /fromlist /confirm, only the remaining files are gone"
    intent: On the jump box, save a list, edit it, and see that only what's left in it gets deleted.
interface:
  - "/savelist <file>"
  - "/fromlist <file>"
  - "# dirused delete list v1"
  - "skipped: file changed since list (id)"
  - "skipped: file changed since list (size or time)"
  - "skipped: bad list line N"
  - "skipped: duplicate list line N"
  - "not a dirused delete list: <file>"
```

## Review log

- rev 1, 2026-11-19, Fable blind: NOT READY. Taken: B1 ID from scan via `Offer`, no dry-run open; B2 no-ID rows not saved,
  counted; B3 ID equality over SMB moved to proof owed (fails safe, E2 step 1); B4 checks split into dry-run stat and
  same-handle confirm, `:127` kept as the size/time rule; M5 same handle; M6 "hand-added" claim dropped (a line with a real
  ID is the operator's choice); M7 time now checked (exact, via `:127`); M8 must_nots assert exact statuses with positive
  controls; M9 target = `ScanRoot ?? Target`; M10 no volume line; M11 JsonIgnore; M12 volume serial column; minors:
  parser bypasses, allowed switches, init properties, path collisions, no trim, split limit, dedupe, versioned header,
  exit code, BOM, backdated replacement in the Windows test.
