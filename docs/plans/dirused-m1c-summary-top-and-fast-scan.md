# dirused M1c — summary fixes, `/summary /top N`, faster remote scans

**Status:** draft — Part A waiting on intent approval; Part B waiting on proof (P1, P2). A3 superseded by `docs/plans/dirused-m1d-top-level-default.md` (2026-11-17); Part B B1 superseded by `docs/plans/dirused-m1e-listing-file-ids.md` (2026-11-17, proof done there); B2 and B3 remain
**Repo / branch:** wilddog64/dirused; Part A `m1c-summary-top` from `main` at 1926d2e; Part B `m1c-fast-scan` after Part A merges
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15); this file sits in k3d-manager only so `codex-dispatch start` can read it
**Bugs fixed:** `docs/dirused/bugs/2026-11-16-dirused-summary-drops-hosts-sharing-volume-serial.md`, `docs/dirused/bugs/2026-11-16-dirused-all-scans-local-host-with-remote-targets.md`
**Operator decisions (2026-11-16):** `/all` with targets = every drive on each target, never the local machine; `/all` alone = local fixed drives. `/summary /top N` = N largest **top-level** folders per drive ("go with your suggestion"). Speed-up items #1–#3 in this release; on-host/MFT scanning goes to `docs/dirused/ideas.md`.
**Intent approved:** operator, 2026-11-16
**Approval words:** "approve dirused" (Part A, including A3 `/summary /top N`; Part B still waits on proof P1, P2)
**Implementer:** Part A Flash or Luna (one agent); Part B the other, after proof. **Verifier:** Claude, from Acceptance only; live evidence by Claude (`make vm-live`).

## Why

1. `/summary` with several hosts silently drops every host whose volume serial number matches an earlier one (cloned agents share D: serials). The report looks complete.
2. `/all` always adds the machine running dirused, even in a fleet run.
3. The operator wants the 3 largest folders per drive next to each summary line.
4. A remote scan costs three SMB round trips per file (`Scanner.cs` `Remember()` open + `GetFileInformationByHandle`, `Allocated()` `GetCompressedFileSize`), so `/summary /top` across a fleet would be too slow without Part B.

## Part A — dispatchable after intent approval

### A1. Duplicate key includes the host
`SummaryRenderer.Prepare` (src/Dirused.Common/Renderers/SummaryRenderer.cs:27-37) keys on `serial:` or `drive:` only. Prefix the key with the
target's host: the UNC server for a remote target (case-insensitive), empty for a local one. Text, JSON and CSV all call `Prepare`
(CsvRenderer.cs:15, JsonRenderer.cs:14), so all three are fixed by this one change. Two local drive letters on one volume still count once.

### A2. `/all` follows the targets
`TargetResolver.ResolveDetailed` (src/Dirused.Core/Targets/TargetResolver.cs:19):
- no other targets (none positional, none from `/file`): unchanged, local fixed ready drives;
- with targets: no local drives. Every target host is enumerated as a bare `\\node` (existing `INodeShares` path), so `\\host\d$` widens to
  all admin drive shares on `host`; a host named twice is enumerated once; a local-path target stays as typed.
Help text (ArgParser.cs:20, :26): "/all  All drives: local when no targets, else every drive on each target host".

### A3. `/summary /top N`
- `/summary` without `/top`: unchanged (volume probe only, `ProbeSummary`, no walk).
- `/summary` with an explicit `/top N`: walk each drive and print, under its summary line, the N largest **top-level** folders of that
  drive by size on disk, indented 4 spaces: `    <size>  <path>`. Files directly in the drive root are not listed.
- Track whether `/top` was typed (the default 50 must not trigger a walk).
- JSON: each volume gains `"top": [{"path","onDiskBytes","logicalBytes"}]`; CSV: one extra row per folder with `kind=dir`. Without `/top`, JSON and CSV output stays byte-identical.
- A drive whose walk has errors still prints its summary line and the folders it could size, followed by the existing error line; exit code 3 as today.
- Memory: keep one running total per top-level folder; do not keep a list of every file for this mode.

## Part B — after proof P1 and P2

### Proof required before dispatch (Claude, read-only, dirused-dev VM)
- **P1 baseline:** time `dirused \\<host>\d$ /top 3` (today's full scan) on the VM share and on one operator agent host (operator runs it); record file count, wall time, host, date, build.
- **P2 SMB behaviour:** a small probe on the VM calling `GetFileInformationByHandleEx(FileIdBothDirectoryInfo)` on a directory handle over `\\localhost\c$` and a real remote share; record that FileId, EndOfFile and AllocationSize come back non-zero and match `GetFileInformationByHandle` / `GetCompressedFileSize` for 20 sample files (including one compressed and one sparse file).
If P2 shows AllocationSize is missing or wrong over SMB, B1 keeps `GetCompressedFileSize` and only drops the open; the spec is revised before dispatch.

### B1. Bulk directory reads
Replace the per-file `Remember()` + `Allocated()` calls in `Scanner.Walk` with one `GetFileInformationByHandleEx(FileIdBothDirectoryInfo)` loop per
directory: file ID (hard-link duplicate check keyed on volume serial + FileId), logical size, allocated size, attributes. Reparse points and
cloud placeholders are skipped exactly as today.

### B2. Parallel walk inside one drive
Walk subfolders with a bounded worker pool (default 8, new `/threads <n>` 1–32), totals combined safely; `/parallel` (hosts) unchanged.
Results (sizes, order, errors) are identical to the sequential walk.

### B3. Keep only what is printed
Top-N files and directories kept with a bounded heap instead of a full list sorted at the end.

## Contract readers
Not a shared k3d-manager contract. dirused output formats are a user contract: JSON/CSV readers are `tests/Dirused.Tests/OutputCompatTests.cs` and
`tests/Dirused.Tests.Portable/RendererTests.cs`; no output changes without `/top`.

## Acceptance

```yaml
interface:
  - "dirused <targets> /all /summary [/top N] [/json|/csv]"
  - "SummaryRenderer.Prepare(results) -> one volume per (host, serial or drive)"
must:
  - "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV"
  - "two local drive letters on one volume still appear once in /summary"
  - "/all with targets lists every admin drive share on each target host and no local drive"
  - "/all with no targets lists the local fixed drives"
  - "/summary /top 3 prints, under each summary line, the 3 largest top-level folders of that drive by size on disk"
  - "/summary without /top does no directory walk and its text, JSON and CSV output is unchanged"
  - "Part B: bulk and parallel scans give the same sizes, order and errors as the sequential scan, and a remote scan is faster than the P1 baseline"
must_not:
  - "a reachable host is missing from /summary output with no error line naming it"
  - "a run with targets plus /all includes a drive of the machine running dirused"
  - "/summary /top 3 prints no folder lines"
evidence:
  - id: E1
    proves: [ "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV", "two local drive letters on one volume still appear once in /summary", "a reachable host is missing from /summary output with no error line naming it" ]
    kind: offline
    how: "portable xUnit in RendererTests: results for \\\\a\\d$ and \\\\b\\d$ with the same SerialNumber give two text lines, two JSON volumes, two CSV rows; positive control: C:\\ and a mount point on one serial give one; red on the test-only commit, green on the fix"
    intent: "A fleet summary shows every host, even cloned machines with the same disk ID, while one machine's drive is still counted once."
  - id: E2
    proves: [ "/all with targets lists every admin drive share on each target host and no local drive", "/all with no targets lists the local fixed drives", "a run with targets plus /all includes a drive of the machine running dirused" ]
    kind: offline
    how: "Windows xUnit in RemoteTargetTests with a fake INodeShares: [/all, \\\\h1\\d$, \\\\h2] resolves to h1's and h2's drive shares only (each host once, no local drive letter); [/all] alone resolves to DriveInfo fixed drives; red on the test-only commit, green on the fix"
    intent: "With a list of servers, /all means every drive on those servers and never your own machine; on its own it still means your drives."
  - id: E3
    proves: [ "/summary /top 3 prints, under each summary line, the 3 largest top-level folders of that drive by size on disk", "/summary /top 3 prints no folder lines" ]
    kind: offline
    how: "Windows xUnit in SummaryTests on a temp tree (folders a 3 MB, b 2 MB with a 5 MB nested child, c 1 MB, d 0.5 MB): /summary /top 3 prints b, a, c indented under the summary line, nested child not listed separately; red on the test-only commit, green on the fix"
    intent: "Adding /top 3 to a summary shows the three biggest folders on each drive right under its line."
  - id: E4
    proves: [ "/summary without /top does no directory walk and its text, JSON and CSV output is unchanged" ]
    kind: offline
    how: "positive control: OutputCompatTests golden output for /summary text/JSON/CSV unchanged; a scan delegate that throws if called is never invoked without /top"
    intent: "A plain summary stays as fast as today and prints exactly what it printed before."
  - id: E5
    proves: [ "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV", "/all with targets lists every admin drive share on each target host and no local drive", "/summary /top 3 prints, under each summary line, the 3 largest top-level folders of that drive by size on disk" ]
    kind: live
    how: "Claude runs make vm-live on the dirused-dev VM with the fix build: /summary over \\\\localhost\\c$ and \\\\127.0.0.1\\c$ (same serial, two hosts) prints two lines; /all /summary \\\\localhost prints its drive shares and no bare C:\\; /summary /top 3 prints 3 folder lines; operator reruns dirused /summary /file servers.list on the fleet and sees all four hosts"
    intent: "On real Windows and on your fleet, all four servers show up, /all stays on the listed servers, and the top 3 folders appear."
  - id: E6
    proves: [ "Part B: bulk and parallel scans give the same sizes, order and errors as the sequential scan, and a remote scan is faster than the P1 baseline" ]
    kind: live
    how: "Part B only: ScannerTests compares the new scan with the sequential reference on a temp tree with hard links, a sparse and a compressed file (offline); then Claude times the same P1 command on the VM share and the operator on the same agent host, recording before and after"
    intent: "The faster scan reports exactly the same numbers as before, and it is measurably faster on your servers."
```

## Out of scope
On-host scanning and MFT reads (idea row); any change to non-summary text output; `/parallel` semantics.
