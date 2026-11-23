# dirused M10a: save the would-delete list to a file, and delete from that file

**Filed:** 2026-11-19
**Status:** READY — rev 4 (Astra blind on rev 3: NOT READY, all taken, see Review log), rev 3 intent approved by operator 2026-11-19 ("approved"); rev 2 Fable blind review: no safety blocker, NOT READY on 6 majors (all taken, see Review log)
**Repo / branch:** wilddog64/dirused / `m10a-purge-delete-list` (from main 4130598, v0.0.21)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** `docs/plans/dirused-m10-scheduled-purge.md` Amendment 3 (operator, 2026-11-19: "files to delete should store in a
delete.txt and use that for deletion"; "go with your suggestion"). M10a is the list half, with no scheduling and no Tomcat
handling. M10b (`/schedule`) and M9 (Tomcat stop/start) build on it.
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the office jump box.
**Intent approved:** operator, 2026-11-19

## Why

Operator: "what if next time the pattern changed and not in our list?". Today `/confirm` runs a new scan with the given
patterns, so what is deleted is whatever matches at that moment, not the list that was reviewed. M10a makes the reviewed list
the unit of deletion. Rule: **a list line deletes a file only if the file at that path still has the reviewed identity and
metadata** (same NTFS volume serial, same 64-bit file ID, same size, same modified time to the tick). Anything else is
skipped. This detects replacement, rotation, growth and touch; it does not detect a deliberate in-place rewrite that
restores size and timestamp (out of scope: such a user can delete the file anyway).

**Trust model:** the list file is trusted operator input. Deleting lines is the supported edit; a valid line added by hand
is treated as the operator's choice. dirused does not bind a list to a digest of the reviewed version. (M10b protects its
scheduled copy with a user-only ACL.) Growing live logs are out of scope here;
M9/M10b decide that rule.

## Behaviour

### `/savelist <file>` (with `/largest ... /purge`, never with `/confirm`)

1. **ID source = the scan.** `DirectoryReader` already returns `DirEntry.FileId` (`src/Dirused.Core/DirectoryReader.cs:71`)
   and the volume serial is in `Volume.SerialNumber` (`src/Dirused.Common/ScanResult.cs:12`). Pass the ID through
   `LargestCollector.Offer` (`src/Dirused.Common/Largest.cs:44`, new trailing `ulong? fileId = null`) from `Scanner.cs:164`;
   the fallback enumeration (`Scanner.cs:74-113`, `FileInfo`) passes null. IDs 0 and `ulong.MaxValue` count as null
   (`Scanner.cs:143`). The dry run still opens no file. Only rows on a volume whose `Volume.FileSystem` is `NTFS`
   (`ScanResult.cs:14`) and whose serial is non-zero get an ID; others count as no-ID (64-bit IDs are not unique on ReFS).
2. After the dry run, every row with status `would delete` **and** a non-null file ID is written. A `would delete` row with
   no ID is not written; the summary says `N file(s) not saved: no file ID (server does not report one)`.
3. **Format** (UTF-8 with BOM, CRLF written; CRLF or LF and BOM or no BOM accepted on read):
   - Line 1 exactly `# dirused delete list v1`. Line 2 exactly `# purge days=<D> minsize=<bytes>` (the values used by this
     dry run). Then `#` lines: tool version, UTC time, full argument list, column names.
   - Data lines, tab-separated, 6 columns: `target` (`ScanRoot ?? Target`, as used at `Purge.cs:63`; not the display name
     set at `RemoteScan.cs:15`), `volumeSerial` (8 hex), `fileId` (16 hex), `bytes` (decimal), `lastWriteUtc` (round-trip
     `O` format, full ticks), `path` (the last column; may contain tabs).
   - Temp file in the same directory, then rename over the target.
4. `/savelist` path equal to the `/output` path or the purge log path is a usage error, checked always (not only with
   `/confirm` as `Program.cs:55` is). `/savelist` with `/summary` or `/confirm` is a usage error. A dry run with no rows to
   save writes the two header lines only and prints `delete list saved: 0 file(s)`; otherwise `delete list saved: N
   file(s), SIZE -> <file>`. A write failure prints the error and exits 1 (the dry-run output is still printed first).

### `/fromlist <file> /purge [/confirm]`

5. **Allowed with it:** `/purge` (required, no days argument), `/confirm`, `/html`, `/output`, `/json`, `/csv`. Anything
   else (targets, `/file`, `/largest`, patterns, purge days, `/minsize`, `/timeout`, `/summary`, `/deep`, `/exact`,
   `/parallel`, `/largestcount`, `/savelist`) is a usage error with the exact message
   `/fromlist can only be combined with /purge, /confirm, /html, /output, /json and /csv`. `/fromlist` without `/purge` is
   `/fromlist requires /purge`. These bypass `ArgParser.cs:224`, `:229-231` and `:248` for `/fromlist` only.
6. **Validation before any purge candidate, the purge log or the output is opened:** the list is read and validated before `Program.cs:59` opens the purge log and
   before `:65` opens the output (`ReportOutput.cs:18` truncates). `/fromlist` path equal to `/output` or the purge log is a
   usage error. Line 1 (after BOM) must be `# dirused delete list v1` and line 2 must parse as
   `# purge days=<D> minsize=<bytes>` with D in 1..3650 and minsize in 1..2^62; else `not a dirused delete list: <file>`,
   exit 1, nothing opened or written. ("Opens no file" in this spec means no purge candidate; startup self-update cleanup
   at `Program.cs:15-23` and the `/savelist` destination rename are outside it.)
7. **Age and size use the list's own values.** The pre-open chain uses D and minsize from line 2, never the CLI defaults
   (`ArgParser.cs:114,136`), so a reviewed row is not re-filtered by defaults.
8. **Line rules.** Lines after line 2 that start with `#`, and blank or whitespace-only lines, are ignored. Data lines are
   not trimmed and are split on the first 5 tabs. A data line is bad if it has fewer than 6 fields, a bad number, hex or time
   (`DateTime.TryParseExact(..., "O", InvariantCulture, DateTimeStyles.RoundtripKind)`), or `fileId` `0000000000000000` or
   `FFFFFFFFFFFFFFFF`, or `volumeSerial` `00000000`. Bad lines are never opened; they are reported in a separate block after
   the per-target output: `Bad list lines:` then `  line N: <reason>` each, and counted in a new `PurgeRun.ListErrors`.
   A path seen again (compare `OrdinalIgnoreCase`) is reported in the same block as `line N: duplicate of line M` and not used.
9. **List entries are marked explicitly.** `LargestFile` gains `[JsonIgnore] bool FromList` (init). Only rows with
   `FromList == true` get the Stat call, the serial/ID compare and the list statuses. Scan rows behave exactly as today even
   though they now carry `FileId`.
10. **Checks, per list entry, after the pre-open chain (`Purge.cs:77-84`):**
    - **Dry run:** new `IPurgeFileSystem.Stat(path)` opens with `FILE_READ_ATTRIBUTES` only, share read/write/delete,
      `OPEN_REPARSE_POINT | BACKUP_SEMANTICS`, and returns serial, file index, size and modified time (nullable when not
      reported). Missing file → `skipped: no longer exists` (same text as `Purge.cs:119`). Other Stat error →
      `failed: <error>`. Serial differs or null → `skipped: file changed since list (volume)`. ID differs or null →
      `skipped: file changed since list (id)`. Size or time differs → `skipped: file changed since list (size or time)`.
      Else `would delete`.
    - **`/confirm`:** the existing open (`Purge.cs:118-131`). `PurgeFileInfo` gains nullable init properties `VolumeSerial`
      and `FileIndex`, filled from the `ByHandle` read already done at `Purge.cs:228`; null means mismatch. The volume and id
      compares use `opened.Info` of the handle that later gets `MarkDelete`. The existing `:127` check then applies; for list
      entries its status text is `skipped: file changed since list (size or time)`.
11. **Output:** list results carry no `Volume` data. Text prints no volume line; HTML omits list results from the Nodes and
    Volumes tables (`SummaryRenderer.Prepare`, `HtmlRenderer.cs:13-52`) and shows only the purge tables; JSON and CSV emit
    the purge rows as today with volume fields empty. Ctrl-C works as today (`Program.cs:98`).
12. **Exit codes:** as today, plus exit 3 when `ListErrors > 0`. A list with zero data lines: exit 0, nothing deleted.

## Contract readers

- `LargestCollector.Offer` (`Largest.cs:44`): callers `Scanner.cs:113`, `Scanner.cs:164`, `tests/Dirused.Tests.Portable/LargestTests.cs:29-36` (unchanged, new parameter defaults).
- `LargestFile` (`Largest.cs:26`): add `FileId` and `VolumeSerial` as `[JsonIgnore]` init properties, so scan-path JSON is unchanged.
- `PurgeFileInfo` (`Purge.cs:9`): add init properties; positional callers `PurgeTests.cs:97-104,245` unchanged.
- `IPurgeFileSystem` (`Purge.cs:30`): new `Stat`; implementers `RealPurgeFileSystem`, fakes `PurgeTests.cs:232`, `ProgramPurgeTests.cs:278,286`.
- `Options` (`Options.cs`): `SaveList`, `FromList` (string?, last, default null); built at `ArgParser.cs:249`.
- `Program.cs`: `:55`, `:59`, `:65` path checks and ordering; `:91` Fullness only for scan results; `:98` `Purge.Apply`; `:139` exit 3 rule.
- `PurgeRun` (`Purge.cs:36`): add `ListErrors` (init, default 0) and the bad-line list.
- HTML/summary: `SummaryRenderer.Prepare`, `HtmlRenderer.cs:13-52`.

## External behaviour (proof owed, fails safe)

The scan ID comes from `FileIdBothDirectoryInformation` and the delete-time ID from `GetFileInformationByHandle`. They are
equal on NTFS; over SMB to `\\host\d$` this is expected but not yet observed. If they differ, every line is `skipped: file
changed since list (id)` and nothing is deleted. E2 step 1 is the proof (host, date, version recorded).

## Files

- `src/Dirused.Core/Scanner.cs`
- `src/Dirused.Common/Largest.cs`
- `src/Dirused.Common/Purge.cs`
- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Options.cs`
- `src/Dirused.Common/PurgeList.cs` (new)
- `src/Dirused.Cli/Program.cs`
- `src/Dirused.Common/Renderers/TextRenderer.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `src/Dirused.Common/Renderers/SummaryRenderer.cs` (rule 11: list results out of the Nodes/Volumes tables)
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests.Portable/PurgeTests.cs`
- `tests/Dirused.Tests.Portable/LargestTests.cs`
- `tests/Dirused.Tests.Portable/PurgeListTests.cs` (new)
- `tests/Dirused.Tests/ProgramPurgeTests.cs` (Windows end to end)
- `README.md`
- `CHANGELOG.md`

## What NOT to Do

- Do not open files with Delete access during any dry run (`/savelist` or `/fromlist` without `/confirm`).
- Do not change scan-path `/purge` or `/confirm` behaviour, statuses, output, JSON or exit codes.
- Do not delete a list line's file on any parse error, duplicate, serial/ID mismatch, size or time change, or failed M8 check.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "/largest <p> /purge /savelist f writes '# dirused delete list v1', '# purge days=D minsize=B', and exactly the would-delete rows that have a file ID; skipped and no-ID rows absent; no-ID count printed; 0-row run writes headers only"
  - id: M2
    text: "/fromlist f /purge /confirm deletes exactly the listed files whose volume, ID, size and time match on the delete handle; other files under the target untouched; age/minsize use line 2, not CLI defaults (a 500 MB row saved with minsize=100MB deletes)"
  - id: M3
    text: "removing a line from f means that file is not deleted, while the remaining lines are deleted in the same run"
  - id: M4
    text: "/fromlist without /confirm opens no file with Delete access and deletes nothing; Windows test: a file held open by another handle without FILE_SHARE_DELETE still reports 'would delete'"
  - id: M5
    text: "a non-list file (no v1 line 1 or no valid line 2) is refused with 'not a dirused delete list: <file>', exit 1, and the purge log and /output files are not created or truncated"
  - id: M6
    text: "bad lines (short, bad hex/number/time, id 0 or all-F, serial 0) and duplicates are listed under 'Bad list lines:' and make exit 3, while valid lines in the same list are processed; '#' and blank lines after line 2 are ignored and do not affect exit"
  - id: M7
    text: "usage errors: /fromlist with a target, /file, /largest, days, /minsize, /timeout or /savelist gives '/fromlist can only be combined with /purge, /confirm, /html, /output, /json and /csv'; /fromlist without /purge gives '/fromlist requires /purge'; /savelist with /confirm or /summary, and /savelist or /fromlist equal to /output or the purge log, are refused; positive control /fromlist f /purge parses"
  - id: M8
    text: "scan-path /purge and /purge /confirm output, statuses, JSON and exit codes are unchanged (existing suites pass untouched, and a scan row with FileId set gets no Stat call)"
must_not:
  - id: N1
    text: "a listed path whose file was replaced (new file ID, same size, backdated time) is deleted; asserts 'skipped: file changed since list (id)' while a matching line in the same run is deleted"
  - id: N2
    text: "a listed file with the same ID whose size changed (time equal), or whose time changed (size equal), is deleted; two cases, each asserts 'skipped: file changed since list (size or time)', the file survives, and a matching line is deleted in the same run"
  - id: N3
    text: "a line with a malformed field, id 0 or all-F is deleted or opened; asserts it under 'Bad list lines:', zero Open and zero Stat calls for its path on the fake, and a valid line deleted in the same run"
  - id: N4
    text: "a handle reporting null or different volume serial lets the line delete; asserts 'skipped: file changed since list (volume)', the file survives, and a matching peer in the same run is deleted"
  - id: N5
    text: "a list whose line 2 has days 0, negative, over 3650, or minsize 0 is processed; asserts 'not a dirused delete list' and no purge log or output created"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, N1, N2, N3, N4, N5]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable; pre-fix red is shown with executable-level tests only (Program.Run with /savelist and /fromlist on 4130598 gives 'Unknown switch'); tests that use the new interfaces are proven by the mutants below, recorded separately; separate mutants each red: skip ID compare (N1), skip volume compare only (N4), drop the :127 check for list rows (N2), accept id 0 (N3), accept days 0 in line 2 (N5), save a non-NTFS row (M1), use CLI default minsize instead of line 2 (M2), allow /fromlist with /file (M7), open with Delete in the dry run (M4), Stat for scan rows (M8), compare from a separate open instead of opened.Info (M2, fake swaps the file between opens); Windows CI ProgramPurgeTests end to end: save, replace one file with a backdated same-size file, append to another, /fromlist /confirm"
    intent: Only files you reviewed in delete.txt can be deleted; a replaced, grown or broken line deletes nothing.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    command: "operator, jump box: (1) /largest *.log /purge /savelist on one server's tomcat logs, then /fromlist dry run shows 'would delete' for the rotated logs (not '(volume)' or '(id)'): proves the scan ID matches the handle ID over \\host\d$ (record host, date, version); (2) scratch folder on a share with files older than 1 day: /largest *.tmp /purge /minsize 1KB /savelist (files of at least 1 KB), delete one line, /fromlist /confirm, only the remaining files are gone"
    intent: On the jump box, save a list, edit it, and see that only what's left in it gets deleted.
interface:
  - "/savelist <file>"
  - "/fromlist <file>"
  - "# dirused delete list v1"
  - "# purge days=<D> minsize=<bytes>"
  - "delete list saved: N file(s)"
  - "skipped: file changed since list (volume)"
  - "skipped: file changed since list (id)"
  - "skipped: file changed since list (size or time)"
  - "skipped: no longer exists"
  - "Bad list lines:"
  - "not a dirused delete list: <file>"
  - "/fromlist can only be combined with /purge, /confirm, /html, /output, /json and /csv"
  - "/fromlist requires /purge"
```

## Review log

- rev 1, 2026-11-19, Fable blind: NOT READY. Taken: B1 ID from scan via `Offer`, no dry-run open; B2 no-ID rows not saved,
  counted; B3 ID equality over SMB moved to proof owed (fails safe, E2 step 1); B4 checks split into dry-run stat and
  same-handle confirm, `:127` kept as the size/time rule; M5 same handle; M6 "hand-added" claim dropped (a line with a real
  ID is the operator's choice); M7 time now checked (exact, via `:127`); M8 must_nots assert exact statuses with positive
  controls; M9 target = `ScanRoot ?? Target`; M10 no volume line; M11 JsonIgnore; M12 volume serial column; minors:
  parser bypasses, allowed switches, init properties, path collisions, no trim, split limit, dedupe, versioned header,
  exit code, BOM, backdated replacement in the Windows test.
- rev 2, 2026-11-19, Fable blind: no safety blocker, NOT READY. Taken: 1 id 0/all-F rejected, handle values nullable =
  mismatch; 2 explicit `FromList` marker; 3 `/timeout` disallowed; 4 N2 grown/changed, N4 volume-only, duplicates, exit 3,
  collisions, exact usage messages, Windows held-file Stat test; 5 bad-line block + `ListErrors` + exit 3, `#`/blank lines
  ignored; 6 age/minsize from list line 2, days and `/minsize` disallowed with `/fromlist`. Minors: unconditional
  `/savelist` collision check, validate before `:59`/`:65`, HTML tables, `no longer exists` text, Stat flags, RoundtripKind,
  OrdinalIgnoreCase, `/savelist` with `/summary` refused, separate `(volume)` status, empty/write-failure behaviour.
- rev 3, 2026-11-19, Astra blind (codex gpt-6.2-astra): NOT READY. Claude adjudicated: B1 ID reuse / ReFS / restored
  timestamps: accidental match of volume+ID+size+tick time is not a realistic failure for this operator tool; taken as
  wording (no "byte-for-byte") plus NTFS-only saving. B2 list as authority: taken as an explicit trust model, no digest
  (the operator's approved flow is editing the list). B3 dry-run wording scoped to purge candidates. Major: N4 control,
  zero Open/Stat for bad lines, N2 split into size-only and time-only, pre-fix red via executable-level tests and mutants
  recorded separately; header bounds (N5), writer skips serial 0. Minor: E2 `/minsize 1KB`.
