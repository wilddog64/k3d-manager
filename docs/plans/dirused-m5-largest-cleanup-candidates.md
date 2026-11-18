# dirused M5: `/largest`, the largest cleanup-candidate files (logs, dumps, backups, temp)

**Filed:** 2026-11-18
**Status:** LANDED — PR wilddog64/dirused#28 merged 9d8735f; released v0.0.15 (pre-release, 2 zips + sha256) 2026-11-18. Awaiting operator E2
**Repo / branch:** wilddog64/dirused / `m5-largest` (from main 594eff6)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low-medium (read-only: the scanner collects one more bounded list; no file is deleted or opened; default output unchanged without the switch)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

Operator, 2026-11-18: "can we add /largest to identify largest files in /top N directories. trying to hunt down largest
files like *.log, java heap dump, *.bak, and those common known temp files or transition file. these can be a default
settings but allow override."

Today the scan lists folders and files only down to `/deep` (default 1, `Scanner.cs:95,105,131,155`), so a 18 GB heap
dump three levels down shows only as part of its top folder's size. The walk already visits every file at every depth
to sum sizes (`Scanner.Walk`), so finding the big candidates costs no extra disk reads.

## Operator decisions (2026-11-18, question answers)

1. **One list per target:** the K largest matching files anywhere under the target, largest first, with size,
   last-modified date and full path (the path shows which top folder holds it).
2. **Patterns:** `/largest` alone uses the defaults; `/largest "a;b"` replaces them; `/largest "+a;+b"` adds to them;
   `/largest *` lists any file.
3. **With `/summary`:** candidates are listed only for volumes at or above `/warn` (the ones that already get top 3 folders).
4. **Count:** 20 per target by default; `/largestcount N` overrides.

## Change

### Default patterns (`src/Dirused.Common/Largest.cs`, new, portable)

File-name match only, case-insensitive, Windows wildcard rules via
`System.IO.Enumeration.FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true)`:

| Group | Patterns |
|---|---|
| Logs | `*.log`, `*.log.*` (rotated: `app.log.1`, `app.log.gz`), `*.out` (`catalina.out`, `nohup.out`) |
| Heap and crash dumps | `*.hprof`, `*.phd`, `javacore*.txt`, `*.dmp`, `*.mdmp`, `*.trc`, `*.etl` |
| Backups | `*.bak`, `*.bkp`, `*.old`, `*.orig`, `*.backup` |
| Temp | `*.tmp`, `*.temp`, `~$*`, `*.~*`, `*.swp`, `*.$$$` |
| Partial transfers | `*.part`, `*.partial`, `*.crdownload`, `*.filepart` |

`hs_err_pid*.log` is covered by `*.log`. No `core.*` (it would match `core.dll`).

`Largest.cs` holds: `DefaultPatterns`; `ParsePatterns(string? arg, out IReadOnlyList<string> patterns, out string? error)`;
`Matches(string fileName, IReadOnlyList<string> patterns)`; and `LargestCollector(int count, patterns)` with
`Offer(string path, string name, long bytes, DateTime lastWriteUtc)` that keeps only the `count` largest matches (a bounded
min-heap, `PriorityQueue`; ties by path, ordinal ignore-case) and counts `Matches` and `MatchedBytes` over **all** matches.
Memory stays bounded by `count` on a drive with millions of files.

Pattern list rules (`ParsePatterns`): items split on `;` or `,`, trimmed; a leading `+` is noted and stripped; then
empty items are dropped (so `"+"` or `"+*.log;+"` leaves no empty pattern).
- No argument: `DefaultPatterns`.
- All items start with `+`: `DefaultPatterns` plus those items (with `+` removed), duplicates dropped.
- No item starts with `+`: exactly those items. `*` alone means any file.
- A mix of `+` and plain items: error `/largest: use + items to add to the defaults, or a plain list to replace them`.
- An item containing `\`, `/` or `:`, or nothing left after dropping empties: error `/largest patterns match file names only, e.g. "*.log;*.bak"`.

Collector ordering: final list is `LogicalBytes` descending, then `Path` ascending (OrdinalIgnoreCase). The heap's
eviction order is the exact reverse (smallest bytes first; on equal bytes, the path that sorts **last** is evicted
first), so with `count = 1` and two equal 10 MB files `C:\a.log`, `C:\z.log` the result is `C:\a.log`.

### Switches (`src/Dirused.Common/ArgParser.cs`, `Options.cs`)

- `Options` gains `IReadOnlyList<string>? Largest = null` (null = off) and `int LargestCount = 20`.
- `/largest [patterns]`: the next argument is taken as the pattern list only if it is not a switch and contains `*`,
  `?`, `;` or `,`, or starts with `+`; otherwise `/largest` alone (defaults) and the next argument is parsed as usual
  (a target or switch). So `dirused /largest C:\` and `dirused C:\ /largest` both use the defaults. A single exact
  name is written with a trailing `;` (`/largest "catalina.out;"`), and a relative folder whose name starts with `+`
  is written `.\+name`; README says both.
- `/largestcount <n>`: 1-1000, error `/largestcount requires an integer from 1 to 1000`; without `/largest`, error
  `/largestcount requires /largest`.
- Usage text, after the `/exact` line:
  `  /largest [patterns] Largest log, dump, backup and temp files under each target`
  `                      (default patterns listed in README; "+*.x" adds, "*.x;*.y" replaces, * any file)`
  `  /largestcount <n>   How many /largest files per target, 1-1000 (default: 20)`

### Scanner (`src/Dirused.Core/Scanner.cs`, `DirectoryReader.cs`, `Targets/RemoteScan.cs`)

- `DirEntry` gains `DateTime LastWriteUtc`: read `LastWriteTime` from `FILE_ID_BOTH_DIR_INFO` at offset 24
  as `DateTime? LastWriteUtc`: `null` when the raw value is `<= 0` or `> DateTime.MaxValue.ToFileTimeUtc()` (NAS and
  FAT shares can return such values; `DateTime.FromFileTimeUtc` would throw `ArgumentOutOfRangeException`, which
  `IsScanError` does not catch, and abort the target). The fallback path uses `FileInfo.LastWriteTimeUtc` (same guard).
  A null date renders `-` in text and HTML and `null` in JSON.
- `Scan(target, deep, exact, ct)` gains an optional `LargestCollector? largest = null`. In both file branches of `Walk`
  (`:100-112`, `:136-160`), at **every** depth (not limited by `/deep`), call `largest?.Offer(path, name, countedLength,
  lastWriteUtc)` when `countedLength > 0` and the file is not a placeholder (cloud placeholders, attribute bits already
  tested at `:139`, free no local disk). The fallback branch (`:100-112`) does not compute that flag today: compute the
  same placeholder test from `entry.Attributes` there, used only for the `Offer` decision (its size counting stays as
  is). Hard-link duplicates already count 0 and so are skipped.
- `ScanResult` gains `LargestFiles? Largest { get; init; }` (record `LargestFiles(IReadOnlyList<string> Patterns, long
  Matches, long MatchedBytes, List<LargestFile> Files, bool Complete)`, `LargestFile(string Path, long LogicalBytes,
  DateTime? LastWriteUtc)`; `Complete` is the walk's own completeness), with `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]` so JSON without `/largest` is
  byte-for-byte unchanged. An incomplete scan keeps what it collected (`Complete` already says incomplete).
- `RemoteScan.Scan` passes the collector through (the `ProbeSummary` overload at `Program.cs:73` runs no walk and gets
  no collector; under `/summary` only the `TopFolders.Attach` scan at `:83` collects). `ArgParser.cs` builds `Options`
  at two sites (`:152` and `:170`); both pass the new fields. `Program.cs` creates one collector per target scan when
  `options.Largest != null` (a fresh collector per scan, never shared across parallel scans).

### `/summary` (`src/Dirused.Common/TopFolders.cs`, `Program.cs:83`)

When `/largest` is on, the top-folder scan of each warn/crit volume also collects candidates, and `Attach` copies
`Largest` (with `Complete` from that walk) onto that volume's result; the volume's own `Complete` stays as today
(`TopFoldersNote` precedent, `TopFolders.cs:29`). OK volumes get none. `/summary` without `/largest` is unchanged.
Without `/summary`, a normal scan collects for every target.

### Output (`src/Dirused.Common/Renderers/`)

- **Text** (`TextRenderer`, and `SummaryRenderer` under the top folders lines): after a target's rows,
  `Largest candidate files (20 of 1,284 matches, 61.2 GB):` then one line per file:
  `  18.4 GB  2026-10-02  C:\app\dumps\java_pid4412.hprof` (date `yyyy-MM-dd` local time). Sizes use the same formatter
  as the rows around them: `Format.Short` in `TextRenderer` (`18G`, matching its entry rows), `Format.Size` in
  `SummaryRenderer` (`18.4 GB`); the header total uses the same one. No match: `Largest candidate files: none matched`.
  When `Largest.Complete` is false, append ` (scan incomplete)` to the header.
- **JSON:** `largest` object per target as above (camelCase: `patterns`, `matches`, `matchedBytes`, `files[]` with
  `path`, `logicalBytes`, `lastWriteUtc` ISO 8601). Summary JSON keeps `largest` on warn/crit volumes.
- **CSV (non-summary):** header unchanged; after each target's rows, rows `largest,<target>,<path>,<logical_bytes>,<logical_bytes>`
  (on-disk column repeats logical; dates are not in CSV). Summary CSV unchanged (it lists no folders today either).
- **HTML:** a `<h2>Largest candidate files</h2>` table after the volumes (summary) or entries (normal) section, columns
  Host, Size, Modified, Path (`Format.Size`). Rows come from the deduplicated `volumes` list (summary, from
  `SummaryRenderer.Prepare`) or from `results` (normal), **only those with `Largest != null`**, in that order; each
  group starts with `<tr class="group"><th colspan="4">{host} {target}: K of M matches, S{ (scan incomplete)}</th></tr>`.
  Values HTML-escaped with the existing `E(...)` helper. Omitted entirely when no result has `Largest`.

### Docs

- `README.md`: a `/largest` section with the default pattern table above, the three override forms with examples, and
  "dirused only lists candidates; it never deletes or opens files".
- `CHANGELOG.md` `[Unreleased]`: "`/largest` lists the largest log, dump, backup and temp files under each target
  (patterns overridable); `/largestcount` sets how many."

## Tests

Portable (`tests/Dirused.Tests.Portable/LargestTests.cs`, new):
- **L1_DefaultsMatchKnownCandidates:** `server.log`, `app.log.3`, `catalina.out`, `java_pid4412.hprof`, `javacore.20261102.txt`,
  `db.bak`, `~$report.docx`, `setup.exe.crdownload`, `MEMORY.DMP` (upper case) match; `core.dll`, `logo.png`, `backup.zip`,
  `notes.txt`, `catalog.json` do not (positive and negative controls in one test).
- **L2_ParseOverrideForms:** no argument → defaults; `"*.hprof;*.dmp"` → exactly 2; `"+*.trc2,+*.out2"` → defaults + 2;
  `*` → matches `anything.xyz`; `"catalina.out;"` → exactly `catalina.out`; `"+"` and `"+*.log;+"` → no empty pattern
  (the first is the file-names-only error, the second is defaults + `*.log`); mixed `"+*.a;*.b"` → the mix error;
  `"logs\*.log"` and `";;"` → the file-names-only error.
- **L3b_CollectorTieBreak:** `count = 1`, offer `C:\z.log` then `C:\a.log`, both 10 MB → `C:\a.log`; offered in the
  other order → still `C:\a.log` (red for a comparator that evicts the lower path).
- **L3_CollectorKeepsTopKAndCountsAll:** `new Random(42)`, offer 1,000 files with random sizes, 300 matching, count 20 → exactly the 20
  largest matching in descending order (checked against a LINQ sort of the same input); `Matches == 300`; `MatchedBytes`
  equals the sum of all 300.
- **L4_ArgParserLargestSwitches:** `["/largest", "C:\\"]` → defaults, target `C:\`; `["C:\\", "/largest", "*.bak"]` →
  `["*.bak"]`; `["C:\\", "/largest", "catalina.out;"]` → `["catalina.out"]`, targets only `C:\`; `["/largest", "/json", "C:\\"]`
  → defaults and JSON; `["/largestcount", "5", "C:\\"]` → `/largestcount requires /largest`; `/largestcount 0` and `1001` → range
  error; no `/largest` → `Options.Largest == null` (positive control: the existing default-options test still passes).
- **L5_RenderersOmitLargestWhenOff:** text, JSON, CSV and HTML output of the existing renderer fixtures is unchanged
  (compare to the output with `Largest == null`, and assert `"largest"` and `Largest candidate files` absent).
- **L6_RenderersShowLargest:** a result with 2 files and `Matches = 1284` renders the text header
  `Largest candidate files (2 of 1,284 matches,` and both paths; JSON has `"matchedBytes"` and `"lastWriteUtc"`; CSV has
  `largest,` rows; HTML has `<h2>Largest candidate files</h2>`, a `<tr class="group">` row, and escapes a path
  containing `&`; zero matches renders `none matched`; `Complete = false` renders `(scan incomplete)`; a null date
  renders `-`; text size uses `Format.Short` and summary text uses `Format.Size` (assert each formatter's output).
- **L6b_HtmlSummaryOnlyWarnCritGroups:** summary HTML with a warn volume (with `Largest`) and an OK volume (null) has
  exactly one group row, naming the warn volume.
- **L7_SummaryAttachesOnlyToWarnCrit:** extend `TopFoldersTests`: with a collector-bearing scan fake, a warn volume and a
  crit volume get `Largest`, the OK volume gets null.

Windows (`tests/Dirused.Tests/ScannerTests.cs`, existing fixture style with a temp tree, root asserted under the temp dir):
- **W1_LargestFindsDeepFilesBeyondDeep:** a tree with `a\b\c\heap.hprof` (3 MB), `a\x.log` (1 MB), `a\big.iso` (5 MB):
  scan with `deep = 1` and default patterns → `Largest.Files` is `heap.hprof`, then `x.log`; `big.iso` absent (not a
  pattern); `Directories` still lists only depth 1 (positive control that `/deep` is unchanged).
- **W2_LargestLastWriteDate:** set `heap.hprof` LastWriteTimeUtc to 2025-03-11; the collected entry carries that date.
  Unit-test the raw filetime guard (a static helper, e.g. `DirectoryReader.ToUtcOrNull(long)`): `0`, `-1` and
  `long.MaxValue` → null, a valid value → its date.
- **W3_ScanWithoutLargestUnchanged:** the same tree without a collector → `Largest == null` and `Directories`/`Files`
  identical to a run before this change (assert the existing ScannerTests still pass untouched).

Red on main 594eff6: L1-L4, L6 fail to compile there (no `Largest` type); paste the compiler errors as the red proof, plus
W1 from Windows CI on the PR.

## Files

- `src/Dirused.Common/Largest.cs` (new)
- `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`, `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Common/TopFolders.cs`
- `src/Dirused.Common/Renderers/TextRenderer.cs`
- `src/Dirused.Common/Renderers/SummaryRenderer.cs`
- `src/Dirused.Common/Renderers/JsonRenderer.cs`
- `src/Dirused.Common/Renderers/CsvRenderer.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `src/Dirused.Core/Scanner.cs`, `src/Dirused.Core/DirectoryReader.cs`, `src/Dirused.Core/Targets/RemoteScan.cs`
- `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/LargestTests.cs` (new)
- `tests/Dirused.Tests.Portable/TopFoldersTests.cs`
- `tests/Dirused.Tests/ScannerTests.cs`
- `README.md`, `CHANGELOG.md`

## Contract readers

- `DirEntry` (record struct, `DirectoryReader.cs:10`): constructed at `DirectoryReader.cs:74` and by test readers that
  build `DirEntry` values for `new Scanner(reader)` (grep `new DirEntry(` in `tests/` before editing and update every
  call; add the new field last with a default so positional calls keep compiling where possible).
- `ScanResult` JSON shape: read by people and scripts consuming `/json`, and by `RendererTests.cs`/`OutputCompatTests.cs`.
  New property is omitted when null (L5 proves byte-identical output without `/largest`).
- CSV columns: header unchanged; new `largest` kind rows only with `/largest`.
- Usage text: read by `ArgParserTests.cs:142` and `FleetRunnerTests.cs:226` (usage assertions); update them only for the
  added lines.
- `RemoteScan.Scan` overloads: callers `Program.cs:73,74,83`; keep existing overloads, add the collector as an optional parameter.

## What NOT to Do

- Never delete, move, open or read the contents of a file. This is a listing only.
- Do not change default output (no `/largest`): text, JSON, CSV, HTML, exit codes and `/deep` listing stay as they are.
- Do not keep every matching file in memory; only the bounded top `count`.
- Do not match on full paths or folders, and do not follow reparse points (unchanged walk rules).
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Amendment 1 (Claude, after blind Argon review, 2026-11-18)

Folded into the sections above: (1) the optional argument also accepts `;`/`,` lists, exact names by trailing `;`,
`+` folders by `.\`; (2) each renderer keeps its own size formatter; (3) `LargestFiles.Complete` carries the walk's
completeness, since `/summary` keeps the volume `Complete`; (4) the fallback branch computes the placeholder test, and
invalid raw filetimes become null instead of throwing; (5) `+` is stripped before empties are dropped; (6) HTML groups
only results with `Largest`, from the deduplicated list under `/summary`; (7) `ProbeSummary` gets no collector, both
`Options` sites updated; (8) heap tie-break defined, with a seeded L3 and a tie test L3b.

## Acceptance

```yaml
must:
  - id: M1
    text: "`dirused <target> /largest` lists, after the normal output, the 20 largest files under the target at any depth whose names match the default patterns, largest first, with size, last-modified date and path, plus the total match count and bytes"
  - id: M2
    text: "a plain pattern list replaces the defaults, a list of + items adds to them, and * lists any file; /largestcount N changes how many (1-1000)"
  - id: M3
    text: "with /summary, candidates appear only for volumes at or above /warn"
  - id: M4
    text: "text, JSON, CSV (non-summary) and HTML each show the list when /largest is given"
must_not:
  - id: N1
    text: "a matching file below the /deep level is missed (W1) — red today: no /largest exists"
  - id: N2
    text: "output without /largest changes in any format (L5)"
  - id: N3
    text: "a non-matching file (big.iso, core.dll) is listed under the default patterns (L1, W1)"
  - id: N4
    text: "an OK volume under /summary gets a candidate list (L7)"
  - id: N5
    text: "the collector keeps more than count files or miscounts matches (L3)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4, N5]
    kind: offline
    command: portable suite (L1-L7) locally; Windows CI on the PR for W1-W3 (red on 594eff6 by compile error and W1)
    intent: The new switch finds the big logs, dumps, backups and temp files anywhere under a folder, your own patterns work, and nothing changes when you don't use it.
  - id: E2
    proves: [M1, M3]
    kind: live
    command: "operator, work laptop or office: `dirused C:\\ /largest` and `dirused \\\\<node> /all /summary /largest /html`; the console list and the HTML table name real large log/dump/backup files with sizes and dates; OK volumes in the summary show no list"
    intent: On a real machine, one command shows you which big log, dump or backup files to clean up first.
interface:
  - "dirused <target> /largest [\"*.a;*.b\" | \"+*.a;+*.b\" | *] [/largestcount N]"
  - "text: Largest candidate files (K of M matches, S):  <size>  <yyyy-MM-dd>  <path>"
```

**Intent approved:** operator, 2026-11-18
**Intent approval note:** "cool, go dispatch this" (after the spec, its E1/E2 intents and the Argon findings summary were shown)

## Verification (Claude, 2026-11-18)

- Red proof: every new test uses types that do not exist on 594eff6 (`Largest`, `LargestCollector`, `ScanResult.Largest`), so the suite cannot compile there.
- Blind Argon diff review: 4 findings, all spec-intended, no change: (1) a repeated `/largest` is last-wins like `/warn`; (2) an exact name needs a trailing `;`;
  (3) `/summary` attaches only to warn/crit, and summary CSV is unchanged (operator choice); (4) CSV `largest` rows repeat logical bytes in the on-disk column, as specified (possible later refinement).
