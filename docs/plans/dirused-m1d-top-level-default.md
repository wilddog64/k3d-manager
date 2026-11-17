# dirused M1d — fast top-level default, `/deep <level>`, `/exact`, readable sizes

**Status:** MERGED — PR wilddog64/dirused#11, merge 96e8d83 (2026-11-17); E3 done (4.7x faster); hard-link overcount fixed next in `dirused-m1e-listing-file-ids.md`; E4 waits for v0.0.3
**Repo / branch:** wilddog64/dirused; `m1d-top-level-default` from `main` at 784e1a6
**Tracked:** separately from k3d-manager releases (operator, 2026-11-15); out-of-band repo, no ideas-backlog step (operator, 2026-11-17: "this does not go to ideas.md as repo is OOB … can we dispatch these now?"). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Operator words (2026-11-17):** "instead of list all contents of a given drive, can we just list top level directories with the size (human readble 10k, 1m, 1G, ...)"; "what is logical 27.2 kb on disk 28.0 kb … can we make this more readable?"; "can we put size after the path?"; "yes, we can add /deep <level> and /exact but I am not sure if we want to have these to apply to multiple node from /file though".
**Supersedes:** `docs/plans/dirused-m1c-summary-top-and-fast-scan.md` A3 (`/summary /top N`): the new default is that view. M1c Part B (bulk directory reads, proof P1/P2) stays and now speeds up `/exact` only.
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** Claude, from Acceptance only; live evidence by Claude (`make vm-live` in the dirused repo) and the operator (office fleet timing).

## Why

A bare `dirused \\node` or drive root walks the whole drive and prints the 50 largest directories and files anywhere, each as
`<path>  logical 27.2 KB  on disk 28.0 KB`. Two problems:

1. **Slow over SMB.** `Scanner.Walk` (src/Dirused.Core/Scanner.cs) makes three extra calls per file on top of the directory listing:
   `CreateFile` + `GetFileInformationByHandle` in `Remember()` (hard-link dedup) and `GetCompressedFileSize` in `Allocated()`. Each is a network
   round trip; the listing itself already carries every file's length, many files per request.
2. **Hard to read.** Two long sizes per line, labels repeated on every line, deep paths from all over the drive. "Logical" is the file length;
   "on disk" is the space allocated in whole clusters (4 KB on NTFS, so 27.2 KB occupies 28 KB), smaller only for compressed or sparse files.
   For cleanup the difference rarely matters.

## Change

### C1. Options and parser (src/Dirused.Common/Options.cs, ArgParser.cs)
- `Options` gains `int Deep = 1` and `bool Exact = false`.
- `/deep [n]`: the level is optional. `/deep` alone = 2 levels (operator, 2026-11-17: "/deep can have a default of 2 levels so we have some rough
  idea"). When the next argument is all digits it is the level, 1–32, else error `/deep level must be an integer between 1 and 32`; any other
  next argument is not consumed (a folder named only with digits is written `.\3`). No `/deep` at all = 1 level (the bare default).
- `/exact`: flag.
- `/summary` alone: unchanged (volume usage only, no walk) — the fleet-level overview.
- `/summary` with `/deep` or `/exact`: `/deep` / `/exact` override it — the walk runs and the normal listing prints (it already starts with each
  volume line); no error, no warning (operator, 2026-11-17: "we still need summary for higher level overview but /deep and /exact can override it").
- Help text (keep every line within 80 columns; `ShortUsageText` gains `[/deep [N]] [/exact]`):
  `/deep [n]           List n directory levels, 1-32 (/deep alone: 2)` and
  `/exact              On-disk sizes and hard-link dedup (slower)`.

### C2. Fast scan by default (src/Dirused.Core/Scanner.cs)
- `Scan(target, ct)` gains the depth and exact settings (a `ScanSettings(int Deep, bool Exact)` record or two parameters; implementer's choice, one code path).
- **Fast (default):** a file's logical size is `FileInfo.Length` from the enumeration; its on-disk size is that length rounded up to the volume
  cluster size, computed locally. No `Remember()`, no `Allocated()`, no other per-file call. Hard links are counted once per link (documented).
- **`/exact`:** today's per-file behaviour unchanged (dedup + `GetCompressedFileSize`).
- The walk still descends the whole tree (sizes are always the full subtree), but `directories` and `files` keep only entries whose depth below
  the target is `<= Deep` (depth 1 = immediate children of the target). Memory no longer grows with the file count.
- Add an instance counter `public long PerFileCalls { get; private set; }`, incremented once in `Remember()` and once in `Allocated()`; tests read it.
- Reparse points, cloud placeholders, errors and cancellation: unchanged.

### C3. Text output (src/Dirused.Common/Renderers/TextRenderer.cs, Format.cs)
- New `Format.Short(long n)`: binary units `B K M G T P`; below 1024 → `<n>B`; otherwise one decimal when the value is below 10 and an integer
  otherwise, rounded half up: `0`→`0B`, `1023`→`1023B`, `1024`→`1.0K`, `27852`→`27K`, `1288490188`→`1.2G`, `227633266688`→`212G`.
- Volume line: `<drive>  used <S>, free <S>, total <S>, <p>% used` with `Format.Short`.
- Then one combined list of directories and files (depth `<= Deep`), largest first by on-disk size, ties by path (ordinal ignore case), capped by
  `/top`. No "Largest directories" / "Largest files" headings.
- Row: `<path><pad><size>`. Paths are padded with spaces to the longest path in that target's rows plus two; sizes are right-aligned to the widest
  size. When stdout is a console and a padded row would exceed `Console.WindowWidth`, that row uses two spaces instead of padding. Redirected
  output always pads.
- `/exact`: a row whose on-disk size differs from its logical size by more than one cluster gets ` (<S> on disk)` after the size (the size column
  shows logical). Without `/exact` nothing is appended.
- Errors and the incomplete marker: unchanged.

### C4. JSON and CSV (JsonRenderer.cs, CsvRenderer.cs)
- Raw byte counts, same field and column names as today. Rows follow the same depth filter as text (directories and files keep their separate
  `directories` / `files` arrays and `dir` / `file` kinds).
- JSON gains `"exact": true|false` per target result. CSV columns unchanged.

### C5. Many targets
`/deep` and `/exact` apply to every target exactly as for one (proposed by Claude; operator unsure, decided here, revisit after use). When the
resolved target count is above 1, `/deep` or `/exact` is given, and `/timeout` is not, print once to stderr before scanning:
`dirused: /deep and /exact walk every target in full; add /timeout <n> to bound each one, or use /summary for a quick fleet check`
and proceed. Exit codes unchanged.

### C6. Docs
README: new default output example, `/deep`, `/exact`, what "on disk" means, the hard-link note for fast mode; `/help` as in C1.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/Options.cs` | `Deep`, `Exact` (C1) |
| `src/Dirused.Common/ArgParser.cs` | `/deep [n]`, `/exact`, `/summary` override, help (C1) |
| `src/Dirused.Core/Scanner.cs` | fast default, depth filter, `PerFileCalls` (C2) |
| `src/Dirused.Core/Targets/RemoteScan.cs` | pass the scan settings through (C2) |
| `src/Dirused.Cli/Program.cs` | settings, `/summary` override, combined `/top`, multi-target warning (C2, C3, C5) |
| `src/Dirused.Common/Renderers/Format.cs` | `Format.Short` (C3) |
| `src/Dirused.Common/Renderers/TextRenderer.cs` | new layout (C3) |
| `src/Dirused.Common/Renderers/JsonRenderer.cs` | `exact` field (C4) |
| `src/Dirused.Common/Renderers/CsvRenderer.cs` | depth-filtered rows (C4) |
| `src/Dirused.Common/ScanResult.cs` | `Exact` on the result, if needed for C4 |
| `tests/Dirused.Tests/ScannerTests.cs` | tests 1–5 |
| `tests/Dirused.Tests/OutputCompatTests.cs` | new layout |
| `tests/Dirused.Tests/RemoteTargetTests.cs` | new layout |
| `tests/Dirused.Tests.Portable/RendererTests.cs` | tests 6, 7, 10; fixtures |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs` | tests 8, 9 |
| `README.md` | C6 |

## Contract readers

Not a shared k3d-manager contract (no k3d-manager file reads dirused output; grep 2026-11-17). dirused output is a user contract and the default
text output changes on purpose. Readers to update, by grep on main 784e1a6:
- `tests/Dirused.Tests/OutputCompatTests.cs:28-46` — re-derives text/CSV from a scan; update to the new layout.
- `tests/Dirused.Tests/RemoteTargetTests.cs:114` — asserts `Largest directories`; update.
- `tests/Dirused.Tests/ScannerTests.cs:58-60` — `/top 1` text and CSV header; CSV header unchanged.
- `tests/Dirused.Tests.Portable/RendererTests.cs:12-44` — text, CSV and JSON fixtures; text changes, JSON gains `exact`.
- `src/Dirused.Cli/Program.cs:29` — `.Take(options.Top)` on both lists; text now caps the combined list (C3).
- `README.md` output examples.

## Tests

Windows tests (`tests/Dirused.Tests`, real temp trees):
1. Tree with `a\x\y\big.bin` (1 MB), `b\small.txt`, `root.txt`: default text lists `a`, `b`, `root.txt` only, `a` first, `a`'s size includes `big.bin`.
2. Same tree, default scan: `PerFileCalls == 0`. With `/exact`: `PerFileCalls > 0` (positive control).
3. `/deep 2` lists `a\x` too, never `a\x\y`; `/deep` alone equals `/deep 2` byte for byte; no `/deep` equals `/deep 1` byte for byte.
4. A hard-linked file: `/exact` counts it once; default counts each link (documents the trade).
5. JSON default: `exact:false`, sizes in raw bytes, every path at depth 1; CSV header unchanged.

Portable tests (`tests/Dirused.Tests.Portable`):
6. `Format.Short` for every example in C3.
7. Text row padding: sizes right-aligned in one column; redirected output pads; an over-wide console row uses two spaces.
8. Parser: `/deep 0`, `/deep 33` rejected; `/deep` at the end of the line → level 2; `/deep C:\x` → level 2 with target `C:\x`; `/deep /json`
   → level 2 and JSON; `/summary /deep 2` and `/summary /exact` parse, and their options say walk (Summary
   overridden); `/summary` alone still selects the volume-only path (control); help lines within 80 columns.
9. Two targets plus `/deep 2` and no `/timeout` → the stderr line once; with `/timeout 5m` → no line; one target → no line (controls).
10. `/exact` row with a compressed-file fixture (on-disk < logical by > 1 cluster) shows `(… on disk)`; a 27.2 KB / 28 KB row shows nothing extra.

Mutations (each turns a test red): make `/deep` alone mean 1 (3, 8); make `/summary` win over `/deep` (8); call `Remember()` in fast mode (2); drop the depth filter (1, 3); print `logical`/`on disk` labels (7); pad by
the longest path across all targets instead of per target (7, if fixtures use two targets); skip the warning (9).

Gates: `dotnet test` on the dirused CI (Windows and portable jobs), all green on the PR head.

## Acceptance

```yaml
must:
  - id: M1
    text: a bare drive or host scan prints the volume line then one row per top-level directory and file, largest first, sizes covering the full subtree
  - id: M2
    text: the default scan makes no per-file open or allocation call; /exact restores today's on-disk sizes and hard-link dedup
  - id: M3
    text: /deep N lists entries down to N levels; /deep alone equals /deep 2; no /deep equals /deep 1
  - id: M4
    text: text rows are path first, size after, sizes in one right-aligned column in short units (27K, 1.2G); /exact adds "(S on disk)" only where it differs by more than one cluster
  - id: M5
    text: JSON and CSV keep raw byte counts and today's field and column names; JSON says whether the scan was exact
  - id: M7
    text: /summary alone stays the volume-only overview; /deep or /exact given with it overrides it and runs the listing
  - id: M6
    text: with more than one target, /deep or /exact and no /timeout, one stderr line suggests /timeout and /summary, and the run proceeds
must_not:
  - id: N1
    text: a bare scan calls CreateFile or GetCompressedFileSize once per file (red today)
  - id: N2
    text: the default text output lists a path deeper than one level below the target, or prints "logical" / "on disk" labels (red today)
  - id: N3
    text: /summary alone walks directories, or /summary with /deep or /exact skips the walk
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: dotnet test tests/Dirused.Tests --filter "FullyQualifiedName~Scanner|FullyQualifiedName~TopLevel"
    intent: A plain dirused on a drive shows only its top-level folders with their total sizes, without the slow per-file checks.
  - id: E2
    proves: [M4, M5, M6, M7, N3]
    kind: offline
    command: dotnet test tests/Dirused.Tests.Portable
    intent: Sizes read like 27K or 1.2G after each path in a neat column, scripts still get exact byte counts, and fleet runs warn before a slow deep scan.
  - id: E3
    proves: [M1, M2, M4]
    kind: live
    command: on the dirused-dev VM (make vm-live), time dirused \\localhost\c$ on main 784e1a6 and on the PR build; record both times, output shape and build
    intent: On a real Windows share the new default is faster than today and the output shows top-level folders with short sizes.
  - id: E4
    proves: [M1, M2]
    kind: live
    command: operator runs dirused \\<one office agent> with the old and new build and reports both wall times
    intent: On your office servers a plain dirused finishes noticeably faster than it does today.
interface: dirused command line (text, JSON, CSV output)
```

**Intent approved:** operator, 2026-11-17
**Approval words:** "approve intents and you can dispatch to the agents you pick"

## E3 result (2026-11-17)

dirused-dev VM BENTO (Windows 11 ARM64, VirtualBox), `dirused \\localhost\c$`, warm-up then alternating runs:
v0.0.2 95.8s / 94.8s (103 lines); PR build 8f81d0a 20.0s / 20.3s (15 lines), 4.7x faster. `make vm-live` 10/10 on 8f81d0a.
Accuracy cost seen: the default counts every hard link, so `C:\Windows` shows 20G against 11.9G logical with `/exact`
(WinSxS hard links), and the top-level rows add up to more than the volume's 20G used. Operator decision pending on a
mitigation before merge. E4 waits for the v0.0.3 release build (operator, 2026-11-17).
