# dirused M1e — hard links counted once, from the directory listing

**Status:** draft — waiting on intent approval
**Repo / branch:** wilddog64/dirused; `m1e-listing-file-ids` from `main` at 96e8d83 (M1d merged, PR #11)
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15); out-of-band repo, no ideas-backlog step (operator, 2026-11-17). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Operator words (2026-11-17):** "go for 1" — merge M1d now, fix the hard-link overcount next in M1e.
**Supersedes:** `docs/plans/dirused-m1c-summary-top-and-fast-scan.md` Part B, B1 (bulk directory reads). Proof below replaces its P2. B2 (parallel walk) and B3 (bounded heap) stay in M1c.
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** independent agent from Acceptance only; live evidence by Claude (`make vm-live` plus timing on the dirused-dev VM) and the operator (office host, with v0.0.3).

## Why

M1d made a bare scan fast by not opening each file, but hard-link dedup needed that open, so the default now counts a hard-linked
file once per link. On the dirused-dev VM, `\\localhost\c$\Windows` shows 20G with the default and 11.9G with `/exact` (WinSxS keeps
many hard links), and the top-level rows add up to more than the volume's 20G used (E3, 2026-11-17).

Windows can return each entry's file ID in the directory listing itself, many entries per request, so dedup does not need a per-file open.

## Proof (Claude, read-only, dirused-dev VM BENTO, Windows 11 ARM64, 2026-11-17T03:44Z and 03:50Z)

Probe: `GetFileInformationByHandleEx(FileIdBothDirectoryRestartInfo, then FileIdBothDirectoryInfo)` on a directory handle opened
with `FILE_LIST_DIRECTORY` and `FILE_FLAG_BACKUP_SEMANTICS`, path `\\?\UNC\localhost\c$\...` (SMB loopback), 64 KB buffer.
Scripts and output: scratchpad `e3/probe.ps1`, `probe-out.txt`, `probe2.ps1`, `probe2-out.txt` (session e25df53e).

| Check | Result |
|---|---|
| Hard-link pair `C:\bench\hl\a`, `b` (mklink /H) listed over SMB | both `FileId=3096224743964019`, `EndOfFile=5002` |
| 20 files in `\\localhost\c$\Windows\System32`, listing vs `GetFileInformationByHandle` (index, size, links) | 20/20 FileId and length match; link counts 1–3 |
| Walk `\\localhost\c$\Windows` with listing only, each FileId counted once | 12.14 GiB logical (`/exact` 11.9 GiB, default today 20G); 142,397 entries, 34,928 duplicate links, 55,246 listing calls, 11.6s |
| `AllocationSize` from the listing for `C:\Windows` | 2.77 GiB, against `/exact` 7.6 GiB on disk: wrong for WOF-compressed system files, so **not used** |

Not proven: a real remote host (only SMB loopback here). The office check (E4) covers it; if a server rejects the listing class,
the fallback in C2 keeps the scan working.

## Change

### C1. Directory reader (new `src/Dirused.Core/DirectoryReader.cs`, `src/Dirused.Core/Native/Kernel32.cs`)
- `DirectoryReader.Read(string path)` returns the entries of one directory: name, attributes, `EndOfFile` and `FileId` (64-bit).
- It opens the directory with `CreateFile(path, FILE_LIST_DIRECTORY (0x1), share all (7), OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS (0x02000000))`,
  using the same `\\?\` / `\\?\UNC\` extended form `Scanner` uses today.
- It calls `GetFileInformationByHandleEx` with class 11 (`FileIdBothDirectoryRestartInfo`), then class 10, until `ERROR_NO_MORE_FILES` (18).
- The buffer is 64 KB, and entries follow `NextEntryOffset`.
- Struct offsets: `EndOfFile` 40, `FileAttributes` 56, `FileNameLength` 60, `FileId` 96, `FileName` 104.
- `.` and `..` are skipped.
- `Kernel32` gains the `GetFileInformationByHandleEx` P/Invoke.

### C2. Scanner uses the reader (`src/Dirused.Core/Scanner.cs`)
- `Walk` lists each directory with `DirectoryReader.Read`. Reparse-point skipping, error capture (`ScanError` per directory), depth filter and totals stay as M1d left them.
- **Dedup, default and `/exact`:** a file whose `FileId` was already seen in this scan counts 0 logical and 0 on disk, the same rule `/exact` applies today.
  - Cloud placeholders (the attribute mask `Scanner` uses today) are not deduplicated, as today.
  - One scan covers one volume, because reparse points are skipped, so `FileId` alone is the key.
- **Default on-disk size:** the length rounded up to the cluster, as in M1d.
- **`/exact`:** `Remember()` (the per-file open) is removed. `Allocated()` (`GetCompressedFileSize`) runs once per **unique** file. `PerFileCalls` counts only `Allocated()` calls.
- **Fallback:** if opening or listing a directory fails with `ERROR_INVALID_PARAMETER` (87), `ERROR_INVALID_FUNCTION` (1) or `ERROR_NOT_SUPPORTED` (50):
  - that directory is listed the M1d way (`EnumerateFileSystemInfos`), and its files are not deduplicated;
  - `Scanner` exposes `public long FallbackDirectories`, counting directories listed this way;
  - every other error stays a `ScanError` as today.
- The test seam is an `internal` constructor that takes a `Func<string, IReadOnlyList<DirEntry>>` reader, for the fallback test.

### C3. README
- Drop the M1d note that the default counts hard links per link, if present.
- Say that the default and `/exact` both count a hard-linked file once, and that `/exact` adds true on-disk sizes.

## Files

| File | Change |
|---|---|
| `src/Dirused.Core/DirectoryReader.cs` | new: one-directory listing with file IDs |
| `src/Dirused.Core/Native/Kernel32.cs` | `GetFileInformationByHandleEx` P/Invoke |
| `src/Dirused.Core/Scanner.cs` | walk via the reader; dedup by FileId in both modes; drop `Remember()`; fallback counter |
| `tests/Dirused.Tests/ScannerTests.cs` | tests 1–6; Test4 now expects one count in the default mode |
| `tests/Dirused.Tests/RemoteTargetTests.cs` | test 7 |
| `README.md` | C3 |

## Contract readers

No shared k3d-manager contract changes. dirused output is a user contract, and this change keeps every field and column. Only the values change, for trees with hard links (totals drop to the deduplicated size). Readers:
- `tests/Dirused.Tests/OutputCompatTests.cs`
- `tests/Dirused.Tests.Portable/RendererTests.cs`
- the `RunTotals` helper in `tests/Dirused.Tests/RemoteTargetTests.cs`

`Scanner.PerFileCalls` readers: `tests/Dirused.Tests/ScannerTests.cs` (Test2). Its meaning narrows to `Allocated()` calls.

## Tests

All Windows-only (`tests/Dirused.Tests`, run by dirused CI on `windows-latest`).

1. **Default dedup.** A temp tree has a 1 MiB file and a hard link to it in another subfolder. A default scan's root total is 1 MiB logical, not 2. Exactly one of the two file rows is non-zero.
2. **Default makes no per-file calls.** Test 1's tree with `PerFileCalls == 0`.
3. **`/exact` without opens.** On the same tree:
   - `/exact` totals equal what main 96e8d83's `/exact` reports for that tree: logical 1 MiB, and on-disk equal to `GetCompressedFileSize` rounded up to the cluster;
   - `PerFileCalls` equals the number of unique files (1), not the number of links (2).
4. **Long directory.** A directory of 3,000 files with 100-character names, enough to need several 64 KB listing calls. Every file is counted once, and the total equals the sum of the lengths written.
5. **Fallback.** Through the internal seam, a reader that throws `Win32Exception(87)` for one subfolder:
   - that subfolder's files are still counted, via enumeration;
   - `FallbackDirectories == 1`;
   - the scan is `Complete`.
   A reader that throws `Win32Exception(5)` (access denied) yields a `ScanError` and `FallbackDirectories == 0` (positive control: not every error falls back).
6. **Reparse points still skipped.** A junction to a sibling folder adds nothing; the existing junction assertion still holds.
7. **Loopback equals local.** `LoopbackMatchesLocalAndCountsHardLinksOnce` runs in the default mode as well as `/exact`. Local and `\\localhost` totals are equal, and the hard link is counted once in both.

Mutations, each of which must turn a test red:
- skip the `seen` check in the default mode (test 1);
- keep `Remember()` in `/exact` (test 3: `PerFileCalls` becomes 2);
- read only the first listing buffer (test 4);
- fall back on every error code (test 5's control);
- add file IDs across placeholder files (no test: placeholders cannot be created on CI; noted).

Gates: `dotnet test tests/Dirused.Tests.Portable` locally, then dirused CI (`windows`, `portable`) green.

## Acceptance

```yaml
must:
  - id: M1
    text: a default scan counts each hard-linked file once, so a folder's size matches /exact's logical size for trees with hard links
  - id: M2
    text: the default scan still makes no per-file call; /exact makes one allocation call per unique file and never opens files
  - id: M3
    text: directories whose listing class the server rejects are still scanned, without dedup, and are counted
  - id: M4
    text: JSON, CSV and text keep every field, column and format from M1d
must_not:
  - id: N1
    text: a default scan counts a hard-linked file more than once (red on main 96e8d83)
  - id: N2
    text: /exact opens each file (CreateFile per file) to dedup it (red on main 96e8d83)
  - id: N3
    text: an access-denied directory is silently re-listed by the fallback instead of reported as a scan error
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    command: dotnet test tests/Dirused.Tests --filter "FullyQualifiedName~ScannerTests|FullyQualifiedName~Loopback"
    intent: A plain dirused counts hard-linked system files once, so C:\Windows shows its real size, and stays as fast as M1d.
  - id: E2
    proves: [M3, N3]
    kind: offline
    command: dotnet test tests/Dirused.Tests --filter "FullyQualifiedName~Fallback"
    intent: A server that cannot list file IDs still gets scanned, and permission problems are still reported, not hidden.
  - id: E3
    proves: [M1, M2, M4]
    kind: live
    command: on the dirused-dev VM, time dirused \\localhost\c$ and /exact on main 96e8d83 and on the PR build; record times, the Windows row and output shape
    intent: On a real Windows share, C:\Windows shows about 12G instead of 20G, the default stays about 20 seconds, and /exact gets faster.
  - id: E4
    proves: [M1, M3]
    kind: live
    command: operator runs dirused \\<one office agent> with the v0.0.3 build and reports wall time and the Windows row
    intent: On your office servers the default is fast and its sizes add up to the drive's used space.
interface: dirused command line (text, JSON, CSV output)
```
