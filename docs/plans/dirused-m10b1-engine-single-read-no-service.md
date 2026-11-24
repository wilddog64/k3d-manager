# dirused M10b1: purge engine — one-read list parse and a scheduled mode that stops no service

**Status:** LANDED — `e19783f` on `m10b-scheduled-purge` (2026-11-24); 2 corrections (missing scheduled tests; a mutant hung a test); independent Sonnet verifier PASS, 10 mutants red; E-B1W windows CI run 45456774994 green (windows + portable)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) (design, decisions D9 and D11, review adjudication). First of four sequential children.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (integration branch for M10b1–M10b4, created from `main` `966b32b`, v0.0.27; one PR to main at the end)
**Risk:** medium — touches `Purge.Apply` (85 test call sites) and `PurgeList.Read`; behaviour with the new flag off must not change
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-23
**Intent approved:** operator, 2026-11-24
**Approval:** operator, 2026-11-23 — "Skip held files for now"; "Held Tomcat logs only" (no growth relaxation in M10b)
**Proofs needed first:** none (no external behaviour)

## Rev 3 (2026-11-24)

Rebased on `main` `966b32b`: M10b0 changed neither `Purge.cs` nor `PurgeList.cs`, so the change is as rev 2; only Program.cs
line numbers moved. Output asserts in new tests use writers with `NewLine = "\n"` and literal `"\n"` expectations (no
`Environment.NewLine` in the file), so the windows CI job passes.

## Why

A scheduled run (M10b3) must read the list copy once and hand those exact bytes to the parser, and it must never stop or start a
service: held rows are skipped (parent D9). This child adds both to the engine so M10b2 and M10b3 only call them.

## Change

1. `public static bool PurgeList.Parse(byte[] bytes, out ParsedPurgeList? list)` — same result as today's `Read` for the same
   content. Decode with `new StreamReader(new MemoryStream(bytes), Encoding.UTF8, detectEncodingFromByteOrderMarks: true)` and a
   `ReadLine` loop (so UTF-8 with or without BOM, UTF-16 LE/BE with BOM, and `\r\n`, `\n` or lone `\r` all behave as
   `File.ReadAllLines(path, Encoding.UTF8)` does today, `PurgeList.cs:37`); same header versions v1–v3, same bad-line reporting,
   same `false` for fewer than 2 lines or a bad header. `Read(path, out ...)` keeps its signature and its try/catch: it becomes
   `try { return Parse(File.ReadAllBytes(path), out list); } catch { list = null; return false; }`. No other caller changes.
2. `Purge.Apply` gains one optional parameter appended after `error`: `bool scheduled = false`.
3. With `scheduled = true` and `confirm = true`, a row classified as held by a Procrun Tomcat service (`classification.Reason ==
   "tomcat"`) is held back for the group loop **whether or not `control` is null**: change the hold-back condition at
   `Purge.cs:242` and the `holdBackForStop` argument at `:415` from `confirm && control != null` to
   `confirm && (control != null || scheduled)`. Recent held rows (`IsRecent`, `:232-257`) follow the same path.
4. In the group loop (`Purge.cs:470+`), **after** the cancel / `stopReason` check (`:472-482`) and **before** the `/yes` window
   check (`:494`), when `scheduled` is true: every row of the group gets
   `skipped: held by <group.ServiceKey> — scheduled runs do not stop services` (em dash U+2014) via `AssignStatus`, `skipped++`, **no
   purge-log line** (today's held-skip paths at `:501-507` and `:521-527` write none), `HeldSummary` counters unchanged; `continue`.
   A cancelled run still reports these rows `not attempted` as today.
5. With `scheduled = true`, `control.Open` is never called and no `IServiceHandle` method runs, even if a non-null `control` is
   passed. The stopped-service warning block at `Purge.cs:137` keeps its current condition (`services != null && control != null`).
6. Unchanged with `scheduled = true` (stated so nobody "fixes" them): rows held by a non-Tomcat process keep
   `failed: in use (<reason>)` (`:199`, `:1016`); ordinary rows keep the exact volume, file ID, size and last-write match
   (`:1027-1033`); `scheduled = true` with `confirm = false` behaves as today's dry run (out of scope; M10b3 always passes
   `confirm = true`).
7. With `scheduled = false` (default) nothing changes.

## Files

`src/Dirused.Common/PurgeList.cs`, `src/Dirused.Common/Purge.cs`, `tests/Dirused.Tests.Portable/ScheduledEngineTests.cs` (new).
Do not change any other file; existing tests must pass unchanged. The new test file defines its own fakes (the existing ones in
`PurgeListTests`/`PurgeHeldTests` are private); writers use `NewLine = "\n"` with literal `"\n"` expectations.

## Contract readers

- `Purge.Apply`: callers `src/Dirused.Cli/Program.cs:120`, `:205` (at `966b32b`), 85 test call sites — parameter optional and last; no edits needed.
- `PurgeList.Read`: caller `Program.cs:71`, `PurgeListTests` — behaviour preserved.
- New status text: writer `Purge.cs`; readers M10b3 report, `docs/purge.md` (M10b4).

## What NOT to Do

- Do not add a growth relaxation, a `planRun` flag or any change to identity checks.
- Do not change the `/yes` window, the prompt, or the M9b stop/delete/start path for `scheduled = false`.
- Do not touch `ArgParser`, `Program`, or any scheduling code. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B1-M1
    text: "PurgeList.Parse(bytes) returns the same bool, rows, header version and bad-line messages as PurgeList.Read on a temp file with the same bytes, for byte inputs defined in the test: a v1, v2 and v3 list each as UTF-8 without BOM + CRLF, UTF-8 with BOM + LF, UTF-16 LE with BOM + CRLF, and UTF-8 with lone CR line ends; a list with 2 bad lines; a 1-line file (false); a bad header (false). Read on a missing path returns false without throwing"
  - id: B1-M2
    text: "Purge.Apply with scheduled true, confirm true, control null, a fake IServiceQuery reporting a listed file held by Procrun Tomcat85: every row of that group has status exactly 'skipped: held by Tomcat85 — scheduled runs do not stop services', run.Skipped counts them, no purge-log line is written for them, the file still exists in the fake file system, and a not-held row in the same run whose volume, ID, size and time match is deleted (positive control). The same with a recording non-null control gives the same statuses"
  - id: B1-M3
    text: "scheduled true, yes true, localNow 14:00 (outside 19:00-06:00): held rows get the scheduled-skip status, not 'skipped: in use, outside 19:00-06:00 for /yes'; a cancelled run (stop requested before the group loop) reports the held rows 'not attempted', not skipped"
  - id: B1-M4
    text: "scheduled true: a row held by a non-Tomcat process keeps 'failed: in use (<reason>)'; a recent (IsRecent) Tomcat-held row gets the scheduled-skip status"
must_not:
  - id: B1-N1
    text: "with scheduled true, the recording IServiceControl records any Open call or any IServiceHandle call (Stop, Start, QueryState). Positive control: the same fixture with scheduled false, yes true, localNow 22:30 records Open, Stop, Start for Tomcat85. Baseline: compile failure on 966b32b (parameter absent); mutants (a) and (c) turn it red"
  - id: B1-N2
    text: "with scheduled true, a not-held row whose size grew, whose last-write is newer, or whose file ID differs is deleted — each stays 'skipped: file changed since list (...)'; positive control: the matching row deletes. Mutants (f1) size, (f2) last-write, (f3) file ID relaxed when scheduled each turn it red"
  - id: B1-N3
    text: "with scheduled false (default), any existing Purge or PurgeList test changes result — the whole existing Portable suite passes unchanged (preservation, not a baseline-red item)"
evidence:
  - id: E-B1
    proves: [B1-M1, B1-M2, B1-M3, B1-M4, B1-N1, B1-N2, B1-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4. ScheduledEngineTests do not compile on 966b32b. Mutants each red, with the test that catches it named: (a) group loop ignores scheduled [B1-N1, B1-M2]; (b) scheduled check placed after the /yes window check [B1-M3]; (c) control.Open called when scheduled [B1-N1]; (d) hold-back condition left as control != null [B1-M2 control-null case]; (e) skip placed before the cancel check [B1-M3]; (g) Parse ignores the BOM [B1-M1]; (h) Parse splits only on \\n [B1-M1]; (f1)-(f3) [B1-N2]"
    intent: "A scheduled run never stops or starts Tomcat: files Tomcat holds open are listed as skipped, and every other file is deleted only if it is exactly the file you reviewed."
  - id: E-B1W
    proves: [B1-N3]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "bool PurgeList.Parse(byte[] bytes, out ParsedPurgeList? list)"
  - "Purge.Apply(..., TextWriter? error = null, bool scheduled = false)"
  - "skipped: held by <service> — scheduled runs do not stop services"
```

## Review adjudication (rev 3, 2026-11-24)

Fable: NEEDS REWORK. Argon: READY WITH FIXES.

| Finding | Source | Action |
|---|---|---|
| Held rows reach the group loop only when `control != null` (`Purge.cs:242`, `:415`); M10b3 passes null, so the skip never fires | Fable 1, Argon 1 | Applied: Change 3; B1-M2 control-null case; mutant (d) |
| `Read` semantics (BOM incl. UTF-16, lone CR, I/O error → false) | Fable 2, Argon 3 | Applied: Change 1 StreamReader + ReadLine; try/catch kept; B1-M1 byte cases |
| B1-N1 named methods that do not exist on `IServiceControl` | Fable 3 | Applied: Open + IServiceHandle calls |
| "log as held-skip paths do" ambiguous | Fable 4, Argon 2 | Applied: no purge-log line, skipped++, HeldSummary unchanged |
| Skip placement vs cancel check | Fable 5 | Applied: after `:482`, before `:494`; B1-M3 cancel case; mutant (e) |
| Non-Tomcat held, confirm=false, recent held | Fable 6 | Applied: Change 6 + B1-M4 (non-Tomcat unchanged; recent gets skip) |
| Fixtures do not exist as files | Fable 7 | Applied: byte inputs defined in the test |
| CI evidence inside an offline item | Fable 8 | Applied: separate E-B1W after landing |
| Mutants not mapped; B1-N2 size only | Fable 9, Argon 4 | Applied: mapping in E-B1; f1-f3 |
| Stopped-service warning at `:137` in scheduled mode | Argon 1 | Kept unchanged (it already needs `control != null`); stated in Change 5 |
