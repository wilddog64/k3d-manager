# dirused M10b1: purge engine — one-read list parse and a scheduled mode that stops no service

**Status:** OPEN — SPEC rev 2, 2026-11-23; awaiting intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) (design, decisions D9 and D11, review adjudication). First of four sequential children.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (from main a2d0508)
**Risk:** medium — touches `Purge.Apply` (85 test call sites) and `PurgeList.Read`; behaviour with the new flag off must not change
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — "Skip held files for now"; "Held Tomcat logs only" (no growth relaxation in M10b)
**Proofs needed first:** none (no external behaviour)

## Why

A scheduled run (M10b3) must read the list copy once and hand those exact bytes to the parser, and it must never stop or start a
service: held rows are skipped (parent D9). This child adds both to the engine so M10b2 and M10b3 only call them.

## Change

1. `PurgeList.Parse(byte[] bytes, out ParsedPurgeList? list)` — same result as today's `Read` for the same content: UTF-8 with or
   without BOM, `\r\n` or `\n`, same header versions v1–v3, same bad-line reporting. `Read(path, out ...)` becomes
   `Parse(File.ReadAllBytes(path), out ...)`; its signature and results are unchanged. No other caller changes.
2. `Purge.Apply` gains one optional parameter appended after `error`: `bool scheduled = false`.
3. With `scheduled = true`, at the start of each held group's iteration (`Purge.cs:470+`), before the `/yes` window check, the prompt
   and any `IServiceControl` call: set every row of the group to
   `skipped: held by <group.ServiceKey> — scheduled runs do not stop services` (em dash U+2014), log each row as the held-skip paths
   do today, and continue. Classification may still use read-only service queries (`IServiceQuery`) as it does now.
4. With `scheduled = true`, no `IServiceControl` method is called anywhere in the run, even if a non-null `control` is passed.
5. Ordinary (not-held) rows: unchanged — exact volume, file ID, size and last-write match (`Purge.cs:1027-1033`).
6. With `scheduled = false` (default) nothing changes.

## Files

`src/Dirused.Common/PurgeList.cs`, `src/Dirused.Common/Purge.cs`, `tests/Dirused.Tests.Portable/ScheduledEngineTests.cs` (new).
Do not change any other file; existing tests must pass unchanged.

## Contract readers

- `Purge.Apply`: callers `src/Dirused.Cli/Program.cs:119`, `:204`, 85 test call sites — parameter optional and last; no edits needed.
- `PurgeList.Read`: caller `Program.cs:70`, `PurgeListTests` — behaviour preserved.
- New status text: writer `Purge.cs`; readers M10b3 report, `docs/purge.md` (M10b4).

## What NOT to Do

- Do not add a growth relaxation, a `planRun` flag or any change to identity checks.
- Do not change the `/yes` window, the prompt, or the M9b stop/delete/start path for `scheduled = false`.
- Do not touch `ArgParser`, `Program`, or any scheduling code. Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: B1-M1
    text: "PurgeList.Parse(bytes) on the bytes of each existing PurgeListTests fixture (v1, v2, v3, BOM, CRLF, LF, bad lines) gives the same rows, header version and bad-line messages as PurgeList.Read on the same file"
  - id: B1-M2
    text: "Purge.Apply with scheduled true, fake IServiceQuery reporting a listed file held by Tomcat85 and a recording IServiceControl: every row of that group has status exactly 'skipped: held by Tomcat85 — scheduled runs do not stop services', the file still exists in the fake file system, and the not-held row in the same run whose volume, ID, size and time match is deleted (positive control)"
  - id: B1-M3
    text: "Purge.Apply with scheduled true and yes true at a localNow of 14:00 (outside 19:00-06:00): held rows get the scheduled-skip status, not 'skipped: in use, outside 19:00-06:00 for /yes'"
must_not:
  - id: B1-N1
    text: "with scheduled true, any IServiceControl call is recorded (Stop, Start, Query on the control) — positive control: the same fixture with scheduled false, yes true, localNow 22:30 records Stop then Start for Tomcat85. Baseline red: on a2d0508 the test does not compile without the parameter; the named mutant 'ignore scheduled in the held loop' makes it red at run time"
  - id: B1-N2
    text: "with scheduled true, a not-held row whose size grew, whose last-write is newer, or whose file ID differs is deleted — each stays with 'skipped: file changed since list (...)'; positive control: the matching row deletes"
  - id: B1-N3
    text: "with scheduled false (default), any existing Purge or PurgeList test changes result — the whole existing Portable suite passes unchanged (preservation test, not a baseline-red item)"
evidence:
  - id: E-B1
    proves: [B1-M1, B1-M2, B1-M3, B1-N1, B1-N2, B1-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable. ScheduledEngineTests red on a2d0508 (compile). Mutants each red: (a) held loop ignores scheduled; (b) scheduled check placed after the /yes window check; (c) control called for Query when scheduled; (d) Parse drops the BOM handling; (e) Parse splits only on \\n leaving \\r; (f) ordinary-row check relaxed to size >= when scheduled"
    intent: "A scheduled run never stops or starts Tomcat: files Tomcat holds open are listed as skipped, and every other file is deleted only if it is exactly the file you reviewed."
interface:
  - "PurgeList.Parse(byte[] bytes, out ParsedPurgeList? list)"
  - "Purge.Apply(..., TextWriter? error = null, bool scheduled = false)"
  - "skipped: held by <service> — scheduled runs do not stop services"
```
