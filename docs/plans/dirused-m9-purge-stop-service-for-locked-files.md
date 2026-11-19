# dirused M9: /purge stops the service holding a locked file, deletes it, and starts the service again

**Status:** DRAFT — operator request 2026-11-18; external-behaviour proof owed (below), then spec review (Fable + Astra
blind: high risk, it stops production services), then intent approval
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
