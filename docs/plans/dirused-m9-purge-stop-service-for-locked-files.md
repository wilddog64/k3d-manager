# dirused M9: /purge stops the service holding a locked file, deletes it, and starts the service again

**Status:** DRAFT rev 1 (spec below, 2026-11-19) — proofs 1–5 in; next spec review (Fable + Astra blind: high risk, it
stops a production service), then operator intent approval, then dispatch
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Depends on:** M8 (`docs/plans/dirused-m8-purge-largest-files.md`) merged and released.
**Filed:** 2026-11-18
**Intent approved:** no

## Why

Operator, 2026-11-18: "some of the file like those large *.log or java dump files are hold by tomcat. so purge may not be
successful if log or java dump files are hold by tomcat process. as a result, /purge should be able to detect if files are
locked by process and provide a graceful way to stop process, delete large files, then start process ... if /force or /yes
is not specified, the prompt user to enter y/n to continue".

M8 opens each file with share mode 0, so a file Tomcat holds fails with a sharing violation and is reported
`failed: in use`. Nothing is deleted. M9 deals with those files.

## Operator decisions (2026-11-18, AskUserQuestion)

- **Separate milestone.** M8 ships first, unchanged: a locked file is reported and skipped.
- **Auto-detect the service, operator confirms.** dirused runs against `\\host\d$` and over SMB it only sees that a file
  is in use, not which process holds it. It asks the remote service manager for services whose install folder contains
  the locked file. The prompt names the service, its locked files and their sizes. No match means the file is skipped.
- **Always restart.** The service is started again however the deletes went. If it does not reach Running within the
  timeout: a loud error and exit 3.

## Proposed behaviour (draft)

1. With `/purge /confirm`, files that fail M8's open with `ERROR_SHARING_VIOLATION` (32) are collected as `locked`, not
   reported as failed yet.
2. After the pass, for each target with locked files, query the target host's service manager (`OpenSCManagerW(\\host)`,
   `EnumServicesStatusExW` for running Win32 services, `QueryServiceConfigW` for the binary path). A service's install root
   is the binary's folder, or that folder's parent when it is named `bin` (Tomcat procrun:
   `D:\tomcat\bin\Tomcat9.exe //RS//Tomcat9` → `D:\tomcat`). Map the host-local root to the share path the scan used
   (`D:\` ↔ `\\host\d$\`). A locked file belongs to the service with the deepest root that contains it. If two services
   tie, or none matches, the file is reported `failed: in use (no service found)`.
3. Prompt for each service, on stderr, defaulting to No:
   `Stop service Tomcat9 on us03p02ffm01 to delete 2 locked file(s), 9.8 GB? This stops the service until the deletes finish. [y/N]`
   followed by the file list. `/yes` answers yes without asking. If stdin is not a terminal and `/yes` was not given,
   the answer is No and the files are reported `skipped: in use, not confirmed`.
4. On yes: stop the service and wait for Stopped (`/stoptimeout`, default 120 s). If it has running dependent services,
   refuse and list them (no cascade stop). Then retry each of its locked files through **all** of M8's checks again
   (age, size, handle checks, unchanged since scan); a file that changed is skipped as in M8. Then start the service and
   wait for Running (same timeout).
5. The start happens in a `finally`, and also on Ctrl+C: a console cancel handler sets a flag, and the restart still runs
   before exit. The purge log records `service-stop`, `service-start`, and `service-start-failed`, each with a timestamp.
6. Exit 3 if any file failed or the service did not reach Running.
7. `/yes` is valid only with `/purge /confirm`. Dry run: report each locked file found by a probe open (read access,
   share 0, closed immediately) as `would stop <service>` without stopping anything.

## External-behaviour proof owed before dispatch (rule: prove external behaviour)

Read-only, on ffm01, by the operator or Claude, recording host, date and version:

1. **Which files Tomcat holds.** Commons-daemon (procrun) usually keeps its `stdout.*.log` and `stderr.*.log` redirect
   files open until the service restarts. If that file is still written to, its modified time is recent, and M8's
   `/purge 7` age rule excludes it anyway. M9 helps only with files that are held but older than the cutoff. Check the
   9.8 GB `stderr.2026-11-03` file: its modified time, and whether Tomcat holds it
   (Sysinternals `handle.exe stderr.2026-11-03`, or Resource Monitor → CPU → Associated Handles).
2. **Java dumps.** Is a finished `.hprof` file still held? It normally is not, once the JVM finishes writing.
3. **Service config.** `sc.exe \\us03p02ffm01 qc <tomcat service>` (read-only). The binary path confirms the install-root
   rule in step 2, and also shows the start type and dependencies.
4. **Rights.** Querying the service config works with the operator's account (`sc qc` above). Stopping a service needs
   `SERVICE_STOP` on the remote host; confirm the account is a local admin there (it already reads `d$`).

If proof 1 shows the held file is always the current, recently written one, M9 changes to "restart Tomcat so it releases
the old file" or is dropped. That is the operator's call once the proof is in.

## Open points for the spec review

- Whether stopping a service should also require a new switch (e.g. `/stopservices`), beyond `/confirm` plus the prompt.
- Timeouts: one `/stoptimeout`, or separate stop and start timeouts.
- Whether a tie between services is common on these hosts (several Tomcats under one folder).
- The test seam: an `IServiceControl` fake for portable tests; a Windows test with a throwaway service is probably not
  possible on CI runners (service install needs admin). Check before writing the Acceptance block.

## Amendment 1 (operator, 2026-11-19): scope and "starts without issue"

Operator: "this include stop tomcat, delete largest files if there are tomcat logfiles and java heap dump, then start
tomcat. ensure tomcat start without issue".

- **Scope:** the service stop happens only when at least one locked file is a Tomcat log or a Java heap dump. Those are
  files under the Tomcat install root matching `logs\*.log`, `logs\*.txt`, `*stdout*`, `*stderr*`, `catalina.out`, or
  `*.hprof` / `java_pid*.hprof` anywhere under the root. A locked file of any other kind is reported
  `failed: in use (not a Tomcat log or heap dump)` and never causes a stop. The exact list is settled with proof 1.
- **"Starts without issue" means more than Running.** After the start, dirused waits until all three hold:
  (a) the service is Running;
  (b) the service is still Running after a settle period (default 60 s), so it has not crashed straight after starting;
  (c) Tomcat's own startup line appears. A new `catalina.<date>.log` / `catalina.out` written after the start contains
      `Server startup in`, and no `SEVERE` line appears between the start and that line.
  An HTTP probe of the Tomcat connector (port from `conf\server.xml`) is optional and decided at spec review.
- **If the start fails:** one automatic retry (stop, then start). If that also fails: exit 3 and a loud error naming the
  host, the service and the last 20 lines of the catalina log. The purge log records `service-start-failed`. The
  scheduled run (M10) records the same result in its run report.
- **Proof owed, added to the list above:** proof 5. Where Tomcat writes its startup line on ffm01, and its exact text
  (read-only: the newest `catalina.*.log`).

## Proof 1 partial evidence (operator screenshot, dirused 0.0.20, us03p02ffm01, 2026-11-19)

`/largest /purge` dry run listed `tomcat85-stderr.2026-11-04.log` 117G and `tomcat85-stdout.2026-11-04.log` 7.2G, both with
modified time 2026-11-18, and `tomcat85-stderr.2026-11-03.log` 9.8G modified 2026-11-04; all three `would delete`
(default `/purge 1`). Reading: procrun opened the `2026-11-04` pair at the last service start and still writes to them, so
the held files are the *current* ones, not old ones. The 2026-11-18 time is more than a day old even though the files are
open, which fits NTFS updating the directory-entry time lazily while a handle is open. A `/confirm` run would therefore
likely get `failed: in use` on the two 11-04 files and free only the 9.8G file. This supports Amendment 1 (stop, delete,
start) over "drop M9". Still owed: `handle.exe tomcat85-std` on ffm01 to confirm which process holds which file, and proofs 2–4.

## Proof 4 partial evidence (operator screenshots, 2026-11-19)

- `where handle.exe` → not found; `where sc.exe` → `C:\Windows\System32\sc.exe`. Sysinternals is not installed, so proof 1
  falls back to Resource Monitor, and M9 cannot depend on `handle.exe` at run time. If dirused must name the process
  holding a file, use the Windows Restart Manager API (`RmStartSession`/`RmRegisterResources`/`RmGetList`, built in).
- The operator's account is an administrator but runs with a filtered UAC token; elevation is a UAC prompt (operator uses
  `gsudo`). Open: a remote `sc \\host stop` runs over a network logon, where a domain admin normally gets the full
  token without a local prompt (the account already reads `d$`, which needs it). To prove read-only before the spec:
  from a non-elevated prompt, `sc.exe \\us03p02ffm01 qc tomcat85-std` and `sc.exe \\us03p02ffm01 sdshow tomcat85-std`
  (the DACL shows whether Administrators hold stop rights, `RP`/`WP` in the `BA` entry).
- Proof 3 partial (operator, 2026-11-19, `sc qc` on us03p02ffm01): `BINARY_PATH_NAME` = `D:\Tomcat\Tomcat\bin\Tomcat85.exe //RS//Tomcat85`.
  Procrun (commons-daemon) service named `Tomcat85`; install root `D:\Tomcat\Tomcat` (parent of `bin`), which is the root
  the Amendment 1 install-root rule should resolve. Still owed: the rest of the `qc` output (service key name, START_TYPE,
  DEPENDENCIES, SERVICE_START_NAME), `sdshow`, and whether the prompt was non-elevated.
- Services console (operator screenshot, 2026-11-19, host assumed us03p02ffm01): display name `Apache Tomcat 9`, Running,
  Automatic, log on as a `PROD\msa…` domain managed service account. The display name says Tomcat 9 while the binary and
  procrun name say `Tomcat85`, so dirused must address the service by its key name (from `sc qc`), never by display name,
  and must not infer the Tomcat version from either. Start/stop rights come from the service DACL, not the run-as account.
- **Proof 3 complete** (operator, 2026-11-19, from the jump box: `sc.exe \\us03p02ffm01 qc tomcat85` → SUCCESS):
  SERVICE_NAME `tomcat85`; TYPE `10 WIN32_OWN_PROCESS`; START_TYPE `2 AUTO_START`; BINARY_PATH_NAME
  `D:\Tomcat\Tomcat\bin\Tomcat85.exe //RS//Tomcat85`; DISPLAY_NAME `Apache Tomcat 9`; DEPENDENCIES none;
  SERVICE_START_NAME `PROD\msa01tomcat$` (group managed service account). Own process and no dependencies: stopping it
  stops nothing else. Remote config query works from the jump box. Still owed for proof 4: `sc.exe \\us03p02ffm01 sdshow tomcat85`
  from a non-elevated prompt.
- **Proof 4 (operator, 2026-11-19, from the jump box: `sc.exe \\us03p02ffm01 sdshow tomcat85`):**
  `D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;…;;;WD)`.
  This is the stock Windows service DACL: built-in Administrators (`BA`) hold `RP` (start) and `WP` (stop); interactive
  and service users (`IU`, `SU`) can only query. So stop/start needs the account's remote token to include Administrators
  on ffm01, which the existing `d$` access already shows. Proven read-only up to that point; an actual remote stop is first
  exercised in M9's live check (operator, maintenance window). The `S:` audit entry logs every failed access, so a
  refused stop is visible to the server's security log. M9 needs no local elevation on the jump box.
- **Proof 1 (operator, 2026-11-19, verbal "yes" to "does Tomcat85.exe hold the old `stderr.2026-11-03` file?"):** the
  procrun service keeps an old, past-cutoff redirect file open, so `/purge /confirm` skips it as locked and only a stop
  frees it. M9 stays in scope as designed (stop, delete, start). No screenshot; the M9 live check re-confirms it.

## Amendment 2 (operator, 2026-11-19): heap dumps anywhere in the scan

- **Proof 2 (operator screenshot, 2026-11-19):** `\\us03p02ffm01\d$\tomcat` holds `EnvironmentPropertiesManager` and
  `tomcat` (the install root `D:\Tomcat\Tomcat`). Heap dumps are "somewhere in this directory", not necessarily under the
  install root. Operator: "/largest should be able to find *.hprof if this file grows huge".
- **Change to Amendment 1 scope:** `*.hprof` / `java_pid*.hprof` count as heap dumps anywhere under the scanned target,
  not only under the install root. Tomcat log patterns stay limited to the install root.
- **Design constraint found:** dirused reads ffm01 over `d$` from the jump box, so the Restart Manager cannot name the
  remote process holding a file (it only sees local processes). A file is "held" when opening it over SMB fails with a
  sharing violation; the stop decision uses the path rules above, not the holder's identity.
- Still owed: proof 5 (newest `catalina.*.log` startup line text on ffm01).
- **Proof 5 partial (operator screenshot, 2026-11-19, `\\us03p02ffm01\d$\tomcat\tomcat\logs`):** daily JULI files
  `catalina.YYYY-MM-DD` (Explorer hides the extension), one per day with activity. Most are 1 KB; about weekly there is a
  14–38 KB file (10-14, 10-21, 10-28, 11-04, 11-11, 11-18 at 10:29 PM), which looks like a restart day. Today's
  `catalina.2026-11-19` exists at 0 KB. So the post-start check reads the catalina file for the current local date, and
  must tolerate it existing empty before the startup lines arrive. Still owed: the exact `Server startup in` line, from
  `catalina.2026-11-18`.
- **Proof 5, catalina format (operator screenshot of `catalina.2026-11-18`, 2026-11-19):** JULI one-line format
  `dd-MMM-yyyy HH:mm:ss.SSS LEVEL [thread] class.method message`, e.g. `18-Nov-2026 20:48:03.643 INFO [https-openssl-nio-443-exec-2] …`.
  Correction to the line above: the 28 KB on 11-18 is HTTP parse errors (INFO) and RMI accept-loop `WARNING`s, not a
  restart; file size does not mark restart days. Notepad found no `server startup` (searched Down from the cursor without
  wrap, so not conclusive). The post-start check must ignore pre-start lines and treat only `SEVERE` after the start as
  failure; INFO/WARNING noise like this is normal. Still owed: one real `Server startup in` line (findstr across all files).
- **Proof 5 complete (operator, jump box, 2026-11-19 13:56, `findstr /c:"Server startup in" \\us03p02ffm01\d$\tomcat\tomcat\logs\catalina.*`):**
  files are `catalina.YYYY-MM-DD.log`; line text
  `04-Nov-2026 23:57:06.258 INFO [main] org.apache.catalina.startup.Catalina.start Server startup in [13830] milliseconds`.
  Five starts on record: 14-Oct 08:12 (10659 ms), 03-Nov 20:36 (10621) and 20:37 (9256), 04-Nov 23:49 (12878) and
  23:57 (13830). Startup takes about 9–14 s, so a 120 s wait for the line has ample margin. Matching rule for the spec:
  a line in the current local-date `catalina.*.log` whose timestamp is at or after the service start time and which
  contains `org.apache.catalina.startup.Catalina.start Server startup in [`. Last start was 04-Nov, so Tomcat has run
  since then, which fits proof 1 (an old stderr file still held).
- **All proofs (1–5) are in.** Next: the M9 spec.

## Operator decision 3 (2026-11-19, AskUserQuestion): held files may have grown

The files worth freeing are the ones Tomcat is writing now (`tomcat85-stderr.2026-11-04.log`, 117G). After the stop such
a file is larger than at scan time and its modified time becomes the stop time, so M8's "unchanged since scan" and age
checks would skip it. Operator chose **"Same file, may grow"**: after the stop, a held Tomcat log or heap dump is deleted
when it is the same file (same volume serial and file ID as recorded at scan or in the list), at least as large as
recorded, and still matches its pattern. Age, `/minsize` and size are judged at scan or list time and not re-checked.
Every other file keeps M8's strict checks.

---

# Spec rev 1 (2026-11-19)

**Repo / branch:** wilddog64/dirused / `m9-purge-stop-tomcat` (from main 1eb1455, v0.0.22)
**Version:** v0.0.23
**Risk:** medium — stops and starts a production service, but only off-hours: the team restarts Tomcat after 7:00 PM (operator, 2026-11-19: "less risky than others but still need more care"). Review stays Fable + Astra blind.
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check: operator, maintenance window on us03p02ffm01.

## Problem

On us03p02ffm01, procrun (`D:\Tomcat\Tomcat\bin\Tomcat85.exe //RS//Tomcat85`, service key `tomcat85`) keeps its stdout and
stderr redirect files open while the service runs (proofs 1, 3). `/purge /confirm` opens each file exclusively
(`RealPurgeFileSystem.Open`, `src/Dirused.Common/Purge.cs:254`, share mode 0), gets `ERROR_SHARING_VIOLATION` (32) and
reports `failed: <message>` (`ProcessFile`, `Purge.cs:149`). The largest files on the host are never freed.

## Behaviour

### 1. Held-file detection

- `PurgeOpen` gains `public int ErrorCode { get; }` (set by the error constructor; 0 otherwise). `RealPurgeFileSystem.Open`
  passes the Win32 code. A file is **held** when `ErrorCode == 32`.
- `IPurgeFileSystem` gains a default-implemented `bool? ProbeHeld(string path, out string? error)` (default: null,
  "probe unavailable"). The real one opens with `FILE_READ_DATA` (0x1), share mode 0, `OPEN_EXISTING`, closes at once, and
  returns true on error 32, false on success, null with the error otherwise. It never requests `DELETE` access.

### 2. Which held files may cause a stop ("Tomcat files")

For a scan or list target on host H (see 3), a held file is a Tomcat file of service S when:
- **log:** it is under S's install root and its name matches `*.log`, `*.txt` in a `logs` folder directly under the
  root, or `*stdout*`, `*stderr*`, `catalina.out` anywhere under the root; or
- **heap dump:** its name matches `*.hprof` and it is anywhere under the scanned target (Amendment 2), and S is the only
  candidate service on H.

Candidate services: running Win32 services on H whose binary path contains `//RS//` (procrun). Install root: the folder
of the binary, or that folder's parent when it is named `bin` (`D:\Tomcat\Tomcat`). If two candidates' roots both
contain a log, the deepest root wins; a tie, or a heap dump with zero or several candidates, gives
`failed: in use (no service found)`. A held file that is not a Tomcat file gives
`failed: in use (not a Tomcat log or heap dump)`. Neither ever causes a stop.

### 3. Host and path mapping

- `\\H\X$\rest` → host H, local path `X:\rest`. A local path `X:\rest` → the local machine. Any other UNC share →
  no mapping: `failed: in use (no service found)`.
- Service install roots (host-local paths from `QueryServiceConfigW`) are compared with the file's host-local path,
  case-insensitively, with `Purge.IsStrictlyUnder`.

### 4. Service control seam

New `src/Dirused.Common/ServiceControl.cs`:

```csharp
public sealed record ServiceEntry(string Name, string BinaryPath, bool Running, IReadOnlyList<string> RunningDependents);
public interface IServiceControl
{
    IReadOnlyList<ServiceEntry> ListProcrun(string host, out string? error);
    bool Stop(string host, string name, TimeSpan timeout, out string? error);   // true when Stopped within timeout
    bool Start(string host, string name, TimeSpan timeout, out string? error);  // true when Running within timeout
    bool IsRunning(string host, string name, out string? error);
}
public interface ITomcatStartupProbe
{
    // true when a "Server startup in [" line from org.apache.catalina.startup.Catalina.start, timestamped at or after
    // since - 2 min, appears in <root>\logs\catalina.*.log, with no SEVERE line between since - 2 min and that line
    StartupResult WaitForStartup(string shareRoot, DateTime sinceLocal, TimeSpan timeout, CancellationToken ct);
}
public sealed record StartupResult(bool Started, bool SevereSeen, IReadOnlyList<string> LastLines);
```

`RealServiceControl` uses P/Invoke `advapi32` (`OpenSCManagerW(\\H)`, `EnumServicesStatusExW`, `OpenServiceW`,
`QueryServiceConfigW`, `EnumDependentServicesW`, `ControlService(SERVICE_CONTROL_STOP)`, `StartServiceW`,
`QueryServiceStatusEx`), polling every 2 s. No new NuGet package. `host` "." or empty means local.
`RealTomcatStartupProbe` reads `catalina.*.log` files modified at or after `sinceLocal - 2 min`, parsing the JULI
timestamp `dd-MMM-yyyy HH:mm:ss.SSS` (invariant culture); the 2 min absorbs clock skew between the jump box and H, and the
previous start on record (proof 5) is days older. `LastLines` holds the newest 20 lines read.

### 5. Flow (`/purge /confirm`, scan path and `/fromlist`)

1. The normal pass runs unchanged, except that a file whose `Open` returns `ErrorCode == 32` and passed every
   scan/list-time check is held back as **held** (no status yet).
2. After the pass, held files are grouped by (host, service) using 2–3. Unmatched held files get their `failed:` status.
3. For each group, ask: on stderr
   `Stop service tomcat85 on us03p02ffm01 to delete 2 held file(s), 124.2 GB? Tomcat is down until the deletes finish. [y/N]`
   then one line per file (size, path). `/yes` answers yes without asking. If stdin is redirected and `/yes` is absent,
   the answer is No. No → each file `skipped: in use, not confirmed`.
4. A service with running dependents is refused: each file `failed: in use (service has running dependents: <names>)`.
5. Yes → write purge-log line `service-stop`, `Stop(timeout 120 s)`. Stop fails or times out → files
   `failed: could not stop <service>: <error>`, then still run step 7 (start).
6. Stopped → for each held file, `fs.Open` again and apply, in order: not found → `skipped: no longer exists`; held again
   → `failed: in use after stopping <service>`; volume serial or file ID differs from the recorded one, or either is
   null → `skipped: changed since scan (id)` (list rows: `skipped: file changed since list (id)`); not a regular file,
   hard-linked, outside target, read-only → the M8 statuses; length smaller than recorded →
   `skipped: changed since scan (smaller)`; otherwise delete as M8 does (mark, log line, close, verify), status
   `deleted`, freed bytes = the length at delete time.
7. Start, in a `finally` that also runs after Ctrl+C (the existing cancel handler only sets the flag; remaining held
   files become `not attempted: cancelled`, the start still runs): write `service-start`, `Start(120 s)`, then require
   (a) Running, (b) still Running after a 60 s settle, (c) `WaitForStartup(root, startTime, 120 s)` with
   `Started && !SevereSeen`. Any failure → one retry (stop 120 s, start, a–c again). Second failure → purge-log
   `service-start-failed`, error on stderr naming host, service and `LastLines`, exit 3.
8. Purge-log lines for service events use the existing `LogLine` with path `<service>@<host>`, bytes 0, status
   `service-stop` / `service-start` / `service-started` / `service-start-failed: <reason>`.

### 6. Dry run (no `/confirm`)

A file that would otherwise be `would delete` and for which `ProbeHeld` returns true is classified with 2–3 (services
listed via `ListProcrun`; nothing is stopped): `would delete after stopping <service>`, or the matching `failed: in use (…)`
status. Counts and bytes treat `would delete after stopping …` as would-delete. `/savelist` writes rows whose status
starts with `would delete` (`PurgeList.cs:14`).

### 7. Switch

`/yes`: valid only with `/purge /confirm` (scan path or `/fromlist`), otherwise usage error
`/yes needs /purge /confirm`. `Options` gains `bool Yes = false` appended last.

## Files

- `src/Dirused.Common/Purge.cs`
- `src/Dirused.Common/ServiceControl.cs` (new)
- `src/Dirused.Common/PurgeList.cs`
- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Options.cs`
- `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/PurgeServiceTests.cs` (new)
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests.Portable/PurgeListTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `PurgeOpen` constructors: `Purge.cs` (`RealPurgeFileSystem.Open`, `FailAndClose`) and test fakes
  (`grep -rn "new PurgeOpen(" tests/`); the new property has a default so existing calls compile.
- `IPurgeFileSystem`: `RealPurgeFileSystem` and test fakes; `ProbeHeld` is default-implemented.
- `Purge.Apply` call sites: `Program.cs:112` and `Program.cs:180`; new optional parameters (`IServiceControl?`,
  `ITomcatStartupProbe?`, `Func<ServiceGroup,bool> confirmStop`) default to null, meaning held files keep today's status.
- `"would delete"` readers: `Purge.cs:111,114`, `PurgeList.cs:14`, renderers (`grep -rn "would delete" src/`).
- `Options` record: constructed at `ArgParser.cs:132,243,282`; the new field is last with a default.
- Purge log (`C:\temp\dirused-purge.log`): human-read only; new line kinds are additive.

## What NOT to Do

- Do not stop any service for a file that is not a Tomcat file (2), or without a yes (prompt or `/yes`).
- Do not skip the start: every path after a stop attempt must reach step 7, including exceptions and Ctrl+C.
- Do not relax any check for files that were not held.
- Do not open any file with `DELETE` access in a dry run; do not call `Stop` or `Start` in a dry run.
- Do not cascade-stop dependents.
- Do not add a NuGet package.
- Do not update `memory-bank/`, create a PR, push, or skip hooks. Your sandbox cannot restore NuGet or run the test
  runner; finish all code and tests anyway — Claude runs `dotnet test` outside the sandbox.

## Acceptance

```yaml
must:
  - id: M1
    text: "a held tomcat85-stderr file under the install root, same volume and file ID, larger than recorded, with /yes: Stop then delete then Start in that order, startup verified, file status 'deleted', exit 0, purge log has service-stop, service-start, service-started"
  - id: M2
    text: "a held *.hprof outside the install root but under the scanned target is attributed to the single procrun service and deleted after the stop; with two procrun services it is 'failed: in use (no service found)' and nothing is stopped"
  - id: M3
    text: "without /yes and with redirected stdin, Stop is never called and each held Tomcat file is 'skipped: in use, not confirmed'; a typed 'y' at the prompt proceeds"
  - id: M4
    text: "start not verified (not Running, stopped during settle, no startup line, or SEVERE after start) triggers exactly one retry; a second failure gives service-start-failed in the purge log, an error with host, service and last lines, exit 3"
  - id: M5
    text: "Start is called after a stop even when a delete throws, when cancellation is requested after the stop, and when Stop times out"
  - id: M6
    text: "dry run reports 'would delete after stopping tomcat85' for held Tomcat files, counts them as would-delete, and /savelist writes them; Stop/Start are never called and no Delete-access open happens"
  - id: M7
    text: "/fromlist /confirm /yes applies the same flow, with list-row id statuses"
  - id: M8
    text: "the startup probe accepts the proof-5 line '04-Nov-2026 23:57:06.258 INFO [main] org.apache.catalina.startup.Catalina.start Server startup in [13830] milliseconds' only when timestamped at or after start - 2 min, and reports SevereSeen for a SEVERE line after start"
must_not:
  - id: N1
    text: "a held file that is not a Tomcat file causes Stop (test pairs it with a Tomcat file in the same run that does cause Stop; red on main 1eb1455 because nothing stops)"
  - id: N2
    text: "a held file whose file ID differs after the stop, or that is smaller than recorded, is deleted (paired with a same-ID larger peer that is deleted)"
  - id: N3
    text: "a service with running dependents is stopped (paired with a dependent-free service that is)"
  - id: N4
    text: "a file that was not held is deleted when its size or time changed since scan (M8 strict checks kept; paired with a held peer that is deleted)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, N1, N2, N3, N4]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable with fake IServiceControl, ITomcatStartupProbe and IPurgeFileSystem; new tests red on main 1eb1455; mutants each red: remove the finally start, drop the Tomcat-file check, drop the ID check after stop, drop the smaller check, drop the dependents check, skip the retry; Windows CI green"
    intent: Tomcat is only stopped for its own logs and heap dumps, only after you say yes, and it is always started again and checked before dirused says done.
  - id: E2
    proves: [M1, M3, M4, M6]
    kind: live
    command: "operator, after 7:00 PM, jump box: dry run over \\\\us03p02ffm01\\d$\\tomcat shows 'would delete after stopping tomcat85' for the held stderr/stdout files; then /confirm (prompt, answer y) frees them; dirused reports the startup line; operator confirms the app responds"
    intent: In a window you choose, run it against ffm01, watch Tomcat stop, the big log files go, and Tomcat come back with its startup line.
interface:
  - "/yes"
  - "/yes needs /purge /confirm"
  - "would delete after stopping <service>"
  - "skipped: in use, not confirmed"
  - "failed: in use (no service found)"
  - "failed: in use (not a Tomcat log or heap dump)"
  - "failed: in use (service has running dependents: <names>)"
  - "failed: in use after stopping <service>"
  - "failed: could not stop <service>: <error>"
  - "skipped: changed since scan (id)"
  - "skipped: changed since scan (smaller)"
  - "service-stop / service-start / service-started / service-start-failed"
```

## Operator requirement 4 (2026-11-19): a design document for the purge logic

Operator: "document the logic in a proper document as logic looks a bit not easy to understand if there is no document".
Rev 2 (M9a and M9b) adds `docs/purge.md` in the dirused repo and lists it under Files: the whole `/purge` decision path in
one place (scan, list, dry run, confirm), every check in order with its status text, the held-file and Tomcat stop/start
flow, the startup check, exit codes, and the purge log format, with a flow diagram. M9a writes the document for the existing
logic plus held-file detection; M9b extends it with stop, delete, start and verify. The README links to it.
