# dirused: the delete list shows modification times in local time, readable at a glance

**Status:** LIVE-VERIFIED 2026-11-20 — E2 PASS 2026-11-20 (operator, jump box): v2 list m9a2.txt with Pacific -08:00 times; /fromlist m9a2.txt /purge on v0.0.25 same 3 rows, 0 skipped. Earlier: LANDED dirused@aa41dc0 (Flash), PR #37 merged 2e62aed, tag v0.0.24; Sonnet verifier from Acceptance: M1–M4, N1–N3 pass, mutants a–g red, 169/169 (also TZ Tokyo, Los Angeles); Windows CI green; Argon blind review clean. Claude moved the CHANGELOG entry under [Unreleased].
**Live evidence:** 2026-11-20 · operator jump box us03p02ffm01 · dirused v0.0.24/0.0.25 · commit 2e62aed · proves E2
**Tracked:** dirused (OOB repo), not a k3d-manager release; no `docs/ideas.md` row (operator 2026-11-20).
**Repo / branch:** wilddog64/dirused / task branch from main 2ca49a2 (v0.0.23)
**Version:** v0.0.24
**Risk:** low: it changes only the delete-list file format. Scans, deletes and every purge check are untouched. `/fromlist` compares
times exactly, so the new format must read back to the same instant, down to the tick.
**Implementer:** Flash or Luna, whichever slot is free (operator 2026-11-20). **Verifier:** Claude.
**Filed:** 2026-11-20
**Intent approved:** operator, 2026-11-20
**Approval:** operator 2026-11-20 ("make LastWriteUtc human readable (local time base on setting) ... dispatch to either Flash or Luna")
**Origin:** M9a E2 (operator, jump box, 2026-11-20): `type m9a.txt` shows `lastWriteUtc` as `2026-11-20T16:08:16.0126039Z`,
which an operator in Pacific time has to convert by hand.

## Why

The delete list (`/savelist`) is meant to be read by a person before `/fromlist /confirm` runs it. Its time column is
round-trip ISO 8601 in UTC (`PurgeList.cs:47`, `"O"` format), so `2026-11-20T16:08:16.0126039Z` is really 08:08 on the jump box.

## Behaviour

### 1. List format v2 (writer)

- Header line 1 becomes `# dirused delete list v2`.
- The `# utc=` line becomes `# created=<local time>`, in the same format as the time column below.
- The column header becomes `# target\tvolumeSerial\tfileId\tbytes\tlastWrite\tpath`.
- The `lastWrite` field is the file's modification time converted to the time zone of the machine running dirused
  (`TimeZoneInfo.Local`, which follows the Windows time zone setting), written as
  `yyyy-MM-dd HH:mm:ss.fffffff zzz` with the invariant culture, e.g. `2026-11-20 08:08:16.0126039 -08:00`.
  - The 7-digit fraction stays, because `/fromlist` compares times exactly (`Purge.cs:197`, `Purge.cs:404`): a value rounded
    to the second would make every row look changed.
  - The offset is printed for each row, so rows on either side of a daylight-saving change are unambiguous, and a list
    written in one time zone reads back correctly in another.
- `PurgeList.Write` takes an optional `TimeZoneInfo? zone = null` (null means `TimeZoneInfo.Local`) as its last parameter,
  so tests can fix the zone. Existing call sites do not change.
- Everything else stays the same: the encoding (UTF-8 with BOM), CRLF line endings, `# purge` and `# tool version` lines,
  the row filter and column order, and the temp-file-then-move write.

### 2. Reader accepts v1 and v2

- `PurgeList.Read` accepts header `# dirused delete list v1` (lists written by v0.0.23 and earlier: unchanged rules, the time
  must be `"O"` with Kind Utc, and an offset time stays `bad modification time`) and `# dirused delete list v2`.
- In a v2 list the time field must parse with `DateTimeOffset.TryParseExact(field, "yyyy-MM-dd HH:mm:ss.fffffff zzz",
  CultureInfo.InvariantCulture, DateTimeStyles.None, ...)`. The stored value is `.UtcDateTime`, which is exactly what the
  scan recorded. Anything else, including a v1-style `...Z` time inside a v2 list, is `bad modification time`.
- Any other header line is still refused (`Read` returns false), as today.
- `PurgeList.Header` keeps its name and becomes the v2 string. Add `PurgeList.HeaderV1` for the old string.

### 3. Docs

- `docs/purge.md` "Delete List Format" (`:202-226`): show a v2 example, describe `lastWrite` (local time with offset, why the
  fraction stays), and note that v1 lists are still read.
- `CHANGELOG.md`: a v0.0.24 entry.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/PurgeList.cs` | v2 writer, `zone` parameter, reader for v1 and v2, `HeaderV1` |
| `tests/Dirused.Tests.Portable/PurgeListTests.cs` | new tests; update the existing `"# dirused delete list v1"` writer assertion (`:19`) to v2 |
| `docs/purge.md` | Delete List Format section |
| `CHANGELOG.md` | v0.0.24 entry |

## Contract readers

Contract: the delete-list file (`/savelist` writer, `/fromlist` reader).
- Writer: `src/Dirused.Common/PurgeList.cs:44-47` (`Write`), called from `src/Dirused.Cli/Program.cs`
  (`git grep -n "PurgeList.Write"`); the call site is unchanged because the new parameter is optional.
- Reader: `PurgeList.cs:19-42` (`Read`), called from `Program.cs` for `/fromlist`; the parsed `LargestFile.LastWriteUtc` keeps Kind Utc.
- Consumers of the parsed time: `Purge.cs:145-146` (age), `Purge.cs:197` and `:404` (exact equality with the file's current time).
  They are unchanged and rely on the v2 round trip giving the same ticks.
- Tests that hard-code the header or format: `PurgeListTests.cs:19` (writer asserts v1, update to v2), `:25-29` and `:37`, `:63`
  (they build v1 lists through `PurgeList.Header` or a literal; keep them as v1 tests by switching them to `PurgeList.HeaderV1` /
  the v1 literal so the v1 reader stays covered).
- Out of scope: the JSON renderer's `lastWriteUtc` field (`LargestTests.cs:58`) is machine output and stays UTC.
- Documentation: `docs/purge.md:202-226`.

## What NOT to Do

- Do not change any purge check, status text or exit code, or the JSON/CSV output.
- Do not drop the fraction or the offset from `lastWrite`.
- Do not stop reading v1 lists.
- Do not add a NuGet package. Do not push, open a PR or skip hooks. Leave changes uncommitted.

## Acceptance

```yaml
must:
  - id: M1
    text: "/savelist writes header '# dirused delete list v2', a '# created=' line and column 'lastWrite'; with zone fixed at UTC-08:00 a file modified 2026-11-20T16:08:16.0126039Z is written '2026-11-20 08:08:16.0126039 -08:00'"
  - id: M2
    text: "write then read a v2 list round-trips: each parsed LastWriteUtc equals the scanned value tick for tick with Kind Utc, including a row written in a zone during daylight time (-07:00) and one in standard time (-08:00), and when the reader's local zone differs from the writer's"
  - id: M3
    text: "a v1 list written by v0.0.23 (header v1, '...Z' times) still reads with the same files and errors as today"
  - id: M4
    text: "docs/purge.md shows a v2 example and describes lastWrite; CHANGELOG has v0.0.24"
must_not:
  - id: N1
    text: "the v2 time loses precision: a time with a non-zero sub-second part read back must not differ from the original (paired: a whole-second time also round-trips)"
  - id: N2
    text: "a malformed v2 time (v1-style '...Z' value inside a v2 list, missing offset, or no fraction) is accepted; each is 'bad modification time' (paired with a valid v2 row in the same file that is read)"
  - id: N3
    text: "an unknown header (e.g. '# dirused delete list v3') is read; Read returns false (paired with v1 and v2 headers that read)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable (fixed TimeZoneInfo via CreateCustomTimeZone and a zone with a DST rule). New tests red on 2ca49a2. Mutants each red: write with format 'yyyy-MM-dd HH:mm:ss zzz' (N1); drop the offset from the format (M2); accept DateTimeStyles.AssumeUniversal for a v2 time without offset (N2); stop accepting HeaderV1 (M3). Windows CI green."
    intent: "You will see the saved list carry times like 2026-11-20 08:08:16 -08:00, read back to exactly the same instant, and old v0.0.23 lists still accepted."
  - id: E2
    proves: [M1, M2, M4]
    kind: live
    command: "operator, jump box, read-only: dirused \\\\us03p02ffm01\\d$\\tomcat /largest /purge /savelist m9a2.txt; type m9a2.txt shows v2 and Pacific times; dirused /fromlist m9a2.txt /purge shows the same rows and statuses as the scan, 0 skipped; the v0.0.23 m9a.txt still reads"
    intent: "On the jump box you will see the saved list show local Pacific times, and replaying it shows the same files with nothing skipped."
```

## Worker definition of done

- Change only the files in the table. Your sandbox may not restore NuGet or run the test runner; finish the code and tests anyway and
  say so. Claude runs `dotnet test` outside the sandbox.
- Report each command, its rc and the proving lines; list every error seen.
