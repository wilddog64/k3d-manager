# dirused M1c-A — `/summary` drops hosts sharing a volume serial; `/all` adds the local machine with targets

**Status:** dispatched
**Parent:** `docs/plans/dirused-m1c-summary-top-and-fast-scan.md` (A1, A2 only; A3 `/summary /top N` and Part B are later rounds)
**Bugs:** `docs/dirused/bugs/2026-11-16-dirused-summary-drops-hosts-sharing-volume-serial.md`, `docs/dirused/bugs/2026-11-16-dirused-all-scans-local-host-with-remote-targets.md`
**Tracked:** separately from k3d-manager releases; this file sits in k3d-manager only so `codex-dispatch start` can read it
**Intent approved:** operator, 2026-11-16
**Approval words:** "at the moment can you dispatch dirused bugs fix to flash"
**Repo / branch:** wilddog64/dirused, `m1c-summary-all-bugs` from `main` at 1926d2e
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** Claude, from the Acceptance block only; live evidence by Claude (`make vm-live`).

## You will see / It failed if

- **You will see:** `dirused /summary /file servers.list` prints one line per reachable host, including cloned hosts whose D: volumes share a serial number;
  `dirused /all /summary \\host1 \\host2` lists only those hosts' drives; `dirused /all /summary` alone lists the local drives.
- **It failed if:** a reachable host is missing from the summary with no error line, or a run with targets plus `/all` prints a drive of the machine running dirused.

## Evidence (operator, 2026-11-16)

`servers.list` = `\\us03l12agt01\d$`, `\\us03l12agt02\d$`, `\\us03l11agt11\d$`, `\\us03l11agt12\d$`. `dirused /summary /file servers.list` printed only agt01 (1.0%)
and agt11 (0.8%), with no error lines. `dirused /summary \\us03l12agt02\d$` alone printed `used 9.1 GB, ... 4.6% used`, so agt02 is reachable and different.

## Cause

1. `SummaryRenderer.Prepare` (`src/Dirused.Common/Renderers/SummaryRenderer.cs:27-37`) removes duplicates with the key `serial:{SerialNumber}` (or
   `drive:{Drive}` when the serial is 0), with no host in it. Cloned machines share volume serials, so every later host is dropped. Text, JSON and CSV
   all call `Prepare` (`CsvRenderer.cs:15`, `JsonRenderer.cs:14`).
2. `TargetResolver.ResolveDetailed` (`src/Dirused.Core/Targets/TargetResolver.cs:19`) turns `/all` into every local fixed drive, whatever else is given.

## Fix

**A1.** In `Prepare`, prefix the key with the result's host: for a target starting with `\\` (after any `\\?\UNC\` form), the server name, compared
case-insensitively; empty for a local target. Duplicates are then removed only within one host; two local drive letters on one volume still count once.

**A2.** In `ResolveDetailed`: if the typed list holds `/all` and no other target, behave as today. If it holds `/all` plus any other target, add no local drives;
instead, for every UNC target (bare `\\host` or a share like `\\host\d$`), enumerate `\\host` through the existing `INodeShares` path (same share filter and error
mapping as a bare node). Each host is enumerated once, even if named several times; a share target on a host that is enumerated is not scanned twice. A local-path target
(e.g. `C:\data`) stays as typed. `/file` targets are already merged into the typed list before `ResolveDetailed` (ArgParser.cs:78-86); confirm this and keep it.
Update help text at `src/Dirused.Common/ArgParser.cs:20` and `:26` to: `/all  All drives: local when no targets, else every drive on each target host`.

Make two commits per item, or one test-only commit then one fix commit: the tests must fail on the current code (the CI `windows` and portable jobs are the red proof).
Push the branch; do not open a PR (Claude does). Do not change any output when only one host is involved.

## Files

- `src/Dirused.Common/Renderers/SummaryRenderer.cs` (`Prepare` key only)
- `src/Dirused.Core/Targets/TargetResolver.cs` (`/all` branch of `ResolveDetailed`)
- `src/Dirused.Common/ArgParser.cs` (help text lines only)
- `tests/Dirused.Tests.Portable/RendererTests.cs`
- `tests/Dirused.Tests/RemoteTargetTests.cs`
- `README.md` (the `/all` line only, if it describes `/all`)

## Acceptance

```yaml
interface:
  - "SummaryRenderer.Prepare(results) -> one volume per (host, serial or drive)"
  - "TargetResolver.ResolveDetailed(typed, nodeShares) with /all"
must:
  - "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV"
  - "two local drive letters on one volume still appear once in /summary"
  - "/all with targets resolves to every admin drive share on each target host, each host once, and no local drive"
  - "/all with no other target resolves to the local fixed drives"
must_not:
  - "a reachable host is missing from /summary output with no error line naming it"
  - "a run with targets plus /all includes a drive of the machine running dirused"
evidence:
  - id: E1
    proves: [ "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV", "a reachable host is missing from /summary output with no error line naming it" ]
    kind: offline
    how: "portable xUnit in RendererTests: complete results for \\\\a\\d$ and \\\\b\\d$ with the same SerialNumber give two text lines, two JSON volumes and two CSV volume rows; red on the test-only commit, green on the fix"
    intent: "A fleet summary shows every server, even cloned ones with the same disk ID."
  - id: E2
    proves: [ "two local drive letters on one volume still appear once in /summary" ]
    kind: offline
    how: "positive control in the same test class: two local results (C:\\ and C:\\mnt) with one SerialNumber give one line; and \\\\A\\d$ plus \\\\a\\d$ (same host, case differs, same serial) give one line"
    intent: "One machine's disk is still counted once, so totals do not double."
  - id: E3
    proves: [ "/all with targets resolves to every admin drive share on each target host, each host once, and no local drive", "a run with targets plus /all includes a drive of the machine running dirused" ]
    kind: offline
    how: "Windows xUnit in RemoteTargetTests with a fake INodeShares (h1: C$, D$; h2: D$): ResolveDetailed([/all, \\\\h1\\d$, \\\\h2, \\\\h1]) gives exactly \\\\h1\\C$\\, \\\\h1\\D$\\, \\\\h2\\D$\\ (no local drive letter, h1 enumerated once); red on the test-only commit, green on the fix"
    intent: "With a list of servers, /all means every drive on those servers and never your own machine."
  - id: E4
    proves: [ "/all with no other target resolves to the local fixed drives" ]
    kind: offline
    how: "positive control: ResolveDetailed([/all]) equals the DriveInfo fixed, ready drives and never calls the fake INodeShares"
    intent: "On its own, /all still scans your own drives as before."
  - id: E5
    proves: [ "two remote hosts whose volumes share a serial number both appear in /summary text, JSON and CSV", "/all with targets resolves to every admin drive share on each target host, each host once, and no local drive", "a reachable host is missing from /summary output with no error line naming it" ]
    kind: live
    how: "Claude runs make vm-live on the dirused-dev VM with the fix build: dirused /summary \\\\localhost\\c$ \\\\127.0.0.1\\c$ (two host names, one serial) prints two lines; dirused /all /summary \\\\localhost prints its drive shares and no bare C:\\ line; then the operator reruns dirused /summary /file servers.list on the fleet and sees all four hosts"
    intent: "On real Windows and on your servers, all four hosts show up and /all stays on the listed servers."
```
