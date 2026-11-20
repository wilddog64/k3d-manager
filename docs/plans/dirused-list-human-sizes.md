# dirused: the delete list shows sizes a person can read (minsize=1GB, a size column)

**Status:** LIVE-VERIFIED 2026-11-20 — E2 PASS 2026-11-20 (operator, jump box 09:16 PST): v3 m9a3.txt minsize=1GB, size column 138G/9.8G/8.5G; /fromlist m9a3.txt and v2 m9a2.txt both same 3 rows, 0 skipped. Earlier: LANDED dirused@67ce6ee (Flash) 2026-11-20; Sonnet verifier from Acceptance: M1–M4, N1–N3 pass, 12 new tests red on 2e62aed, mutants red; 188/188; Claude fixed Windows test column count (spec defect) f491e45; CI 4/4 green; Argon blind no findings; PR #38 merged c91e9b7, tag v0.0.25.
**Live evidence:** 2026-11-20 · operator jump box us03p02ffm01 · dirused v0.0.25/0.0.25 · commit c91e9b7 · proves E2
**Tracked:** dirused (OOB repo), not a k3d-manager release; no `docs/ideas.md` row (OOB, as for v0.0.24).
**Repo / branch:** wilddog64/dirused / task branch from main 2e62aed (v0.0.24)
**Version:** v0.0.25
**Risk:** low: it changes only the delete-list file format. `/fromlist` compares each file's size to the byte (`Purge.cs:197`) and
re-applies minsize (`Purge.cs:144`), so the exact byte count and the exact minsize must survive; the readable values are added, not swapped in.
**Implementer:** Flash or Luna, whichever slot is free. **Verifier:** Claude.
**Filed:** 2026-11-20
**Intent approved:** operator, 2026-11-20
**Approval:** operator 2026-11-20 ("can we have minsize human readable b,m,g? including numbers under path")
**Origin:** v0.0.24 E2 (operator, jump box, 2026-11-20 08:50 PST): `type m9a2.txt` shows `# purge days=1 minsize=1073741824` and a
bytes column `147999209735`, which a person cannot read at a glance.

## Why

The delete list is read by a person before `/fromlist /confirm` runs it. v0.0.24 made the times readable; the sizes are still raw byte
counts. The console already prints `138G`, `9.8G`, `8.5G` for the same files.

## Behaviour

### 1. List format v3 (writer)

- Header line 1 becomes `# dirused delete list v3`.
- The purge line writes minsize in the largest unit that divides it exactly, in the spelling `/minsize` accepts:
  `# purge days=1 minsize=1GB` (1073741824), `minsize=1536MB`, `minsize=100MB`, `minsize=4KB`. A value that is not a whole number of
  KB (possible only for a list replayed from v1/v2 with an odd minsize) is written with `B`, e.g. `minsize=1000B`. Units are 1024-based,
  as in `ArgParser.TryParseMinSize` (`ArgParser.cs:287-295`).
- A new column `size` goes right after `bytes`:
  `# target\tvolumeSerial\tfileId\tbytes\tsize\tlastWrite\tpath`. Its value is `Format.Short(bytes)`
  (`src/Dirused.Common/Renderers/Format.cs:7`), the same text the console prints (`138G`, `9.8G`, `8.5G`, `512B`).
- `bytes` stays the exact byte count. Everything else is unchanged from v2 (UTF-8 with BOM, CRLF, `# tool version`, `# created=`,
  `# args=`, lastWrite format, row filter, temp-file-then-move write).

### 2. Reader accepts v1, v2 and v3

- v1 and v2: unchanged rules (numeric `minsize=<bytes>`, 6 columns).
- v3: the purge line must match `^# purge days=([0-9]+) minsize=([0-9]+)(B|KB|MB|GB|TB)$` (unit case-insensitive, number ≥ 1, the byte
  value within the existing bounds `1 .. 2^62`, checked multiplication); otherwise `Read` returns false, as for a bad v2 purge line.
- v3 rows have 7 fields. `size` (field 5) is display only: it must be non-empty, and its content is otherwise ignored. The file's size is
  taken from `bytes`, even when `size` disagrees.
- Any other header is still refused. Add `PurgeList.HeaderV2`; `PurgeList.Header` becomes the v3 string.

### 3. Docs

- `docs/purge.md` "Delete List Format": v3 example, describe `minsize` units and the `size` column (display only; `bytes` is what
  `/fromlist` checks), note that v1 and v2 lists are still read.
- `CHANGELOG.md`: one bullet under `## [Unreleased]` → `### Changed` (the repo builds release notes from Unreleased; do not add a
  version header).

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/PurgeList.cs` | v3 writer (minsize unit, size column), reader for v1/v2/v3, `HeaderV2` |
| `tests/Dirused.Tests.Portable/PurgeListTests.cs` | new tests; switch existing v2-format tests to `PurgeList.HeaderV2` so the v2 reader stays covered |
| `docs/purge.md` | Delete List Format section |
| `CHANGELOG.md` | Unreleased → Changed bullet |

## Contract readers

Contract: the delete-list file (`/savelist` writer, `/fromlist` reader).
- Writer: `PurgeList.Write` (`src/Dirused.Common/PurgeList.cs`), called from `src/Dirused.Cli/Program.cs:160`; signature unchanged.
- Reader: `PurgeList.Read`, called from `Program.cs:66` for `/fromlist`; `ParsedPurgeList.MinBytes` and `LargestFile.LogicalBytes` keep
  exact byte values.
- Consumers: `Purge.cs:144` (minsize from the list, "smaller than"), `Purge.cs:197` and `:199` (exact size equality / held-log growth),
  totals at `Purge.cs:157-158` and others. Unchanged; they rely on exact bytes.
- Formatter reused, not changed: `Format.Short` (`Renderers/Format.cs:7`).
- Tests that hard-code the format: `PurgeListTests.cs` (writer asserts `v2`, v2 round-trip tests build lists through `PurgeList.Header`;
  switch to `HeaderV2` / keep as v2 tests, update the writer asserts to v3).
- Out of scope: JSON/CSV/HTML output and the console line `delete list saved: 3 file(s), 156.2 GB`.

## What NOT to Do

- Do not replace `bytes` with the readable value, and do not round minsize.
- Do not change any purge check, status text or exit code, or the JSON/CSV output.
- Do not stop reading v1 or v2 lists.
- Do not add a NuGet package. Do not push, open a PR or skip hooks. Leave changes uncommitted.

## Acceptance

```yaml
must:
  - id: M1
    text: "/savelist writes header '# dirused delete list v3', purge line 'minsize=1GB' for 1073741824 (and '1536MB', '100MB', '4KB', '1000B' for those byte values), and a 'size' column after 'bytes' holding Format.Short(bytes), e.g. 147999209735 -> '138G'"
  - id: M2
    text: "write then read a v3 list round-trips: MinBytes equals the written minsize exactly and each LogicalBytes equals the scanned byte count exactly"
  - id: M3
    text: "v1 and v2 lists (numeric minsize, 6 columns) still read with the same files and errors as in v0.0.24"
  - id: M4
    text: "docs/purge.md shows a v3 example and describes minsize units and the size column; CHANGELOG has an Unreleased Changed bullet and no new version header"
must_not:
  - id: N1
    text: "the size column is used as the file size: a v3 row whose size says '1K' but bytes says 147999209735 must read LogicalBytes 147999209735 (paired: a row with matching size reads the same bytes)"
  - id: N2
    text: "a malformed v3 purge line (minsize=1.5GB, minsize=0GB, minsize=1XB, bare numeric minsize=1073741824 in a v3 list) is accepted; Read returns false for each (paired: minsize=1GB and minsize=1000B read)"
  - id: N3
    text: "a v3 row with 6 fields or an empty size field is accepted; each is reported as a bad row while a valid v3 peer in the same file is read"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. New tests red on 2e62aed. Mutants each red: read size instead of bytes (N1); write minsize with Format.Short (M2); accept a fractional minsize (N2); stop accepting HeaderV2 (M3). Windows CI green."
    intent: "You will see the saved list carry minsize=1GB and a size column like 138G, read back to exactly the same byte counts, with today's v0.0.24 lists still accepted."
  - id: E2
    proves: [M1, M2, M4]
    kind: live
    command: "operator, jump box, read-only: dirused /update; dirused \\\\us03p02ffm01\\d$\\tomcat /largest /purge /savelist m9a3.txt; type m9a3.txt shows v3, minsize=1GB and sizes 138G-style; dirused /fromlist m9a3.txt /purge shows the same rows and statuses as the scan; dirused /fromlist m9a2.txt /purge (the v0.0.24 list) still reads"
    intent: "On the jump box you will see the saved list show minsize=1GB and a size column you can read, and replaying it shows the same files as the scan."
```

## Worker definition of done

- Change only the files in the table. Your sandbox may not restore NuGet or run the test runner; finish the code and tests anyway and
  say so. Claude runs `dotnet test` outside the sandbox.
- Report each command, its rc and the proving lines; list every error seen.
