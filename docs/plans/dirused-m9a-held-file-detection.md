# dirused M9a: /purge finds files Tomcat holds and says which service it would stop (read-only)

**Status:** LANDED — dirused@b4538997 (auto: land 2026-11-19; verify pending); 11-19 — rev 2, split from M9 rev 1 after Fable (FIX) + Astra (REWORK) blind reviews, adjudicated 2026-11-19
**Parent:** `docs/plans/dirused-m9-purge-stop-service-for-locked-files.md` (adjudication table, M9b outline)
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Repo / branch:** wilddog64/dirused / `m9a-held-file-detection` (from main 1eb1455, v0.0.22)
**Version:** v0.0.23
**Risk:** low — read-only: no service is stopped or started, and no new delete path. One change makes an existing delete
check stricter (scan-row identity, §6).
**Implementer:** Flash (`--agent agy --model gemini-3.8-flash-medium`, operator 2026-11-19). **Verifier:** Claude.
**Filed:** 2026-11-19
**Intent approved:** yes (operator "intents approved"), 2026-11-19

## Why

`/purge /confirm` opens each file with share mode 0 (`RealPurgeFileSystem.Open`, `src/Dirused.Common/Purge.cs:264`). The
procrun Tomcat service on us03p02ffm01 keeps its redirect logs open (proof 1), so those files fail with
`ERROR_SHARING_VIOLATION` (32) and are reported `failed: <message>` (`ProcessFile`, `Purge.cs:137`). M9b will stop
Tomcat to free them. M9a is the read-only half. It finds held files, works out which service holds them, and reports
that in the dry run, the confirm run and the saved list. It also writes `docs/purge.md`. Its live check measures the
SMB and SCM behaviour M9b depends on, against ffm01, with no risk.

## Operator decisions this spec carries

- **D1 (2026-11-19):** a held Tomcat redirect log (`<Name>-stdout.*.log`, `<Name>-stderr.*.log` in the service's
  `logs` folder) is exempt from the age rule. `/minsize` and size still apply. The file Tomcat writes now (117 GB on
  ffm01) is the target. Its directory-entry time is stale while open, and any handle open refreshes it, so the age rule
  cannot judge it.
- **D2 (2026-11-19):** a held heap dump never causes a stop. It is reported `in use (heap dump, holder unknown)`.
  Finished dumps are not held, so they purge as today. `/largest` still finds `*.hprof` anywhere (Amendment 2).
- Narrow patterns (stated to operator 2026-11-19): only the redirect logs above are Tomcat files. `catalina.*`,
  `*.txt` and generic `*.log` are not. Proof 1 showed only the redirect pair is held.

## Behaviour

### 1. Held detection

- `PurgeOpen` gains `public int ErrorCode { get; }`. The error constructor becomes
  `PurgeOpen(string error, bool notFound = false, int errorCode = 0)`. `RealPurgeFileSystem.Open` passes
  `Marshal.GetLastWin32Error()` from the **initial** `CreateFileW` only (`Purge.cs:264`). Later failures (ID query,
  mark) pass 0. A file is **held** when `ErrorCode == 32`.
- `IPurgeFileSystem` gains a default-implemented `bool? ProbeHeld(string path, out string? error)` (default `null`,
  error `"probe unavailable"`). The real one calls `CreateFileW(path, FILE_READ_DATA, 0, OPEN_EXISTING,
  OPEN_REPARSE_POINT | BACKUP_SEMANTICS)` and closes at once. It returns `true` on error 32, `false` on success, and
  `null` with the message otherwise. It never requests `DELETE`.
- **Why the probe matches the real open:** both use share mode 0, and share mode 0 conflicts with any existing handle
  that has data access. That is the condition that fails the real `Open`. Windows CI test W1 pins the agreement.

### 2. Service discovery (read-only SCM)

New `src/Dirused.Common/ServiceQuery.cs`:

```csharp
public sealed record ServiceEntry(string Key, string ProcrunName, string InstallRoot, bool Running);
public interface IServiceQuery
{
    // null + error when the service manager cannot be opened or enumerated; never partial results
    IReadOnlyList<ServiceEntry>? ListProcrun(string host, out string? error);
}
public static class ProcrunPath
{
    // "D:\Tomcat\Tomcat\bin\Tomcat85.exe //RS//Tomcat85" -> ("D:\Tomcat\Tomcat\bin\Tomcat85.exe", "Tomcat85")
    // quoted executable with spaces accepted; null when there is no //RS//<name> argument
    public static (string Exe, string Name)? Parse(string binaryPath);
    public static string InstallRoot(string exe); // exe folder, or its parent when the folder is named "bin"
}
```

- `RealServiceQuery` uses P/Invoke `advapi32` only: `OpenSCManagerW(host, null, SC_MANAGER_CONNECT |
  SC_MANAGER_ENUMERATE_SERVICE)`, `EnumServicesStatusExW` (`SERVICE_WIN32_OWN_PROCESS`, `SERVICE_STATE_ALL`),
  `OpenServiceW(SERVICE_QUERY_CONFIG | SERVICE_QUERY_STATUS)`, `QueryServiceConfigW`, `CloseServiceHandle`. No other
  access right, no `*_ALL_ACCESS`, no control call. Host `.` means local. If any call fails, return `null` with the
  error. A service whose config query fails also makes the whole list `null`, because a missing entry could hide a
  second candidate.
- The list is fetched once per host per run, and only when that host has a held file.

### 3. Host and path mapping

- `\\H\X$\rest`, `\\?\UNC\H\X$\rest` and the same with forward slashes → host H, local path `X:\rest`. H is used as
  given (name, FQDN or IP).
- `X:\rest` → the local machine **only** when `GetDriveTypeW("X:\")` is `DRIVE_FIXED`. A mapped, subst or removable
  drive gets no mapping. The drive-type check is behind an injectable `Func<string, bool> isFixedDrive` so portable
  tests can fake it.
- Any other path → no mapping.

### 4. Classification of a held file

Classification runs in this order. The first match decides. Statuses are in §5.

1. No host mapping → `no service found`.
2. Name matches `*.hprof` (case-insensitive) → `heap dump, holder unknown` (D2).
3. `ListProcrun(H)` returns null → `could not list services on <H>: <error>`.
4. Candidates: entries with `Running`. Each has a log folder `<InstallRoot>\logs`. The file is a Tomcat redirect log
   of S when its host-local parent folder equals S's log folder, compared case-insensitively on full paths. Its name
   must also match `<ProcrunName>-stdout.*.log` or `<ProcrunName>-stderr.*.log`, case-insensitively. On ffm01:
   `tomcat85-stderr.2026-11-04.log` under `D:\Tomcat\Tomcat\logs`.
5. Exactly one S matches → **Tomcat file of S**. Zero matches → `not a Tomcat log` when the file is under some
   candidate's install root, else `no service found`. Two or more matches → `no service found`.
6. **Same file:** for a Tomcat file, `fs.Stat` (attributes handle, share-all, which works on a held file) must return a
   volume serial and file ID equal to the recorded ones, both non-null and nonzero. Otherwise the status is
   `in use (id mismatch)`. This measures, on the real share, whether the scan's enumeration ID equals the handle's ID
   (Astra 4). M9b depends on it.

### 5. Statuses

- **Dry run** (no `/confirm`), scan path and `/fromlist`:
  - A file whose dry-run decision would be `would delete` is probed. Held + Tomcat file of S →
    `would delete after stopping <S>`. Held + any other classification → `skipped: in use (<reason>)`. Not held →
    `would delete`, unchanged. Probe `null` → `would delete`, unchanged, and the run prints one stderr line
    `in-use check failed for N file(s): <first error>`.
  - D1 age exemption: a file whose decision would be `skipped: modified within N day(s)` (`Purge.cs:91`) and whose name
    matches the redirect pattern is probed. If held and classified as a Tomcat file of S →
    `would delete after stopping <S>`. Otherwise the age status stays.
  - `/fromlist` rows: the redirect logs of a held Tomcat file legitimately grow. A row that would be
    `skipped: file changed since list (size or time)` (`Purge.cs:109`, `:157`) is probed when its name matches the
    pattern. If held, a Tomcat file of S, the same file (§4.6) and length ≥ recorded →
    `would delete after stopping <S>`. Otherwise the list status stays (Fable 4, Astra 10).
- **Confirm** (`/confirm`, M9a has no stop): the normal pass runs as today. A file whose `Open` fails with
  `ErrorCode == 32` is classified. A Tomcat file of S gets `failed: in use by <S> (stop not available yet)`. Any other
  classification gets `failed: in use (<reason>)`. A file skipped by the age rule or the list size/time rule that meets
  the dry-run conditions above gets the same `failed: in use by <S> (stop not available yet)`, so the operator sees
  it. Nothing is deleted that M8 would not delete.
- **One predicate:** add `public static bool Purge.IsWouldDelete(string? status)` (true for `would delete` and for any
  status starting `would delete after stopping `). Use it at every reader: dry-run counts and bytes (`Purge.cs` where
  `would delete` is counted), `PurgeList.Summarize` (`PurgeList.cs:14`) and the `/savelist` writer (`PurgeList.cs:47`).
  The writer still needs a valid ID and time, as today.
- **Summary line** (dry run and confirm, only when there are held files), on stdout after the report:
  `held files: N (Tomcat: <S> on <H>, root <InstallRoot>: K file(s), <size>; other: M)`.

### 6. Scan-row identity (pre-existing gap, Astra 1)

`ProcessFile` compares volume serial and file ID only for list rows (`Purge.cs:152-153`). If a selected log rotates
between scan and confirm, an unlocked replacement with the same length and time is deleted. Change: for scan rows, when
the scan recorded both a volume serial and a file ID (`LargestFile.VolumeSerial`/`FileId` non-null), compare them too.
A difference → `skipped: changed since scan (id)`. Rows without a recorded ID keep today's checks, so non-NTFS
behaviour is unchanged.

### 7. `docs/purge.md` (operator requirement 4)

New `docs/purge.md` in dirused. It covers the whole `/purge` decision path for the current code plus M9a: scan, list,
dry run and confirm; every check in order with its exact status text; held detection and classification (§1-4); the
D1 exemption; exit codes; the purge log line format; `/savelist` file format. Include one Mermaid flow diagram of the
per-file decision. README links to it from the `/purge` section. M9b extends it.

## Files

- `src/Dirused.Common/Purge.cs`
- `src/Dirused.Common/ServiceQuery.cs` (new)
- `src/Dirused.Common/PurgeList.cs`
- `src/Dirused.Cli/Program.cs` (pass `RealServiceQuery` and the drive check into `Purge.Apply`; print the summary line)
- `tests/Dirused.Tests.Portable/PurgeHeldTests.cs` (new)
- `tests/Dirused.Tests.Portable/PurgeListTests.cs`
- `tests/Dirused.Tests/ProgramPurgeTests.cs`
- `tests/Dirused.Tests/HeldProbeWindowsTests.cs` (new)
- `docs/purge.md` (new)
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `PurgeOpen` error constructor (`Purge.cs:25`): callers in `Purge.cs` (`RealPurgeFileSystem.Open`, `FailAndClose`) and
  test fakes (`grep -rn "new PurgeOpen(" tests/`). The new parameter has a default, so existing calls compile.
- `IPurgeFileSystem` (`Purge.cs:31`): `RealPurgeFileSystem` and test fakes. `ProbeHeld` is default-implemented, like
  `Stat` (`Purge.cs:35`).
- `Purge.Apply` (`Purge.cs:58`): call sites `Program.cs:112` and `Program.cs:180`. New optional trailing parameters
  `IServiceQuery? services = null, Func<string,bool>? isFixedDrive = null`. When null, held files keep today's
  `failed: <message>` and the dry run does not probe. Existing tests are unchanged.
- `"would delete"` exact-match readers: `Purge.cs` counts, `PurgeList.cs:14`, `PurgeList.cs:47`. Find the rest with
  `grep -rn '"would delete"' src/ tests/` and switch each to `Purge.IsWouldDelete`. Renderers print the status text
  and need no change (Fable 14: `TextRenderer.cs:87-91`, `HtmlRenderer.cs:84-93`).
- Scan-row identity (§6): `ProcessFile` (`Purge.cs:152-157`). The test writer fakes in `PurgeTests`/`PurgeListTests`
  that build scan rows with IDs must still pass. Check with `grep -rn "FileId" tests/`.
- `ProgramPurgeTests.cs:314`: expects `[would delete]` and exit 0 for a list row held by an ordinary `FileStream`
  reader. With M9a it becomes `skipped: in use (no service found)`. Exit stays 0 and the file-exists assertion stays.
  Update the expected status only.
- Purge log: no new line kinds in M9a.

## What NOT to Do

- No service control: no `ControlService`, `StartServiceW`, `SERVICE_STOP`, `SERVICE_START` or
  `SC_MANAGER_ALL_ACCESS` anywhere. That is M9b.
- Do not delete any file M8 would not delete. Do not relax any check on the confirm path.
- Do not request `DELETE` access in a dry run, including in `ProbeHeld`.
- Do not treat a partial service list as complete.
- Do not add `/yes` or any new switch. Do not add a NuGet package.
- Do not update `memory-bank/`, create a PR, push, or skip hooks. Your sandbox cannot restore NuGet or run the test
  runner. Finish all code and tests anyway; Claude runs `dotnet test` outside the sandbox.

## Acceptance

```yaml
must:
  - id: M1
    text: "dry run, fake services: a held tomcat85-stderr.2026-11-04.log in D:\\Tomcat\\Tomcat\\logs (via \\\\h\\d$), same ID, of the single running procrun service Tomcat85 (binary 'D:\\Tomcat\\Tomcat\\bin\\Tomcat85.exe //RS//Tomcat85') is 'would delete after stopping tomcat85', counted in would-delete bytes, and the held-files summary names tomcat85, h and the root"
  - id: M2
    text: "D1: the same held redirect log with last-write = now (would be 'skipped: modified within 1 day(s)') is 'would delete after stopping tomcat85'; a not-held file with last-write = now keeps the age status"
  - id: M3
    text: "classification statuses: held .hprof anywhere -> 'skipped: in use (heap dump, holder unknown)'; held catalina.2026-11-19.log under the root -> 'skipped: in use (not a Tomcat log)'; held file on a non-admin share or a non-fixed drive letter -> 'skipped: in use (no service found)'; ListProcrun null -> 'skipped: in use (could not list services on h: <error>)'; two services matching -> 'no service found'; Stat ID differs -> 'skipped: in use (id mismatch)'"
  - id: M4
    text: "confirm: a held Tomcat file is 'failed: in use by tomcat85 (stop not available yet)', is not deleted, and no Stop exists to call; a held other file is 'failed: in use (<reason>)'; exit code 3 as today"
  - id: M5
    text: "/fromlist dry run: a held listed redirect log that grew (same ID, length > recorded, newer time) is 'would delete after stopping tomcat85'; the same row not held stays 'skipped: file changed since list (size or time)'"
  - id: M6
    text: "/savelist writes 'would delete after stopping' rows, and a real save then /fromlist read round trip with two targets keeps the row, its target, and the CLI total; Summarize and the writer agree on the row count"
  - id: M7
    text: "ProcrunPath.Parse handles the ffm01 path, a quoted path with spaces ('\"C:\\Program Files\\Apache\\bin\\Tomcat9.exe\" //RS//Tomcat9'), and returns null without //RS//; InstallRoot strips a trailing bin folder only"
  - id: M8
    text: "scan-row identity: a scan row with a recorded ID whose file was replaced by one with the same length and time but a different ID is 'skipped: changed since scan (id)' under /confirm and is not deleted; a scan row without a recorded ID keeps today's behaviour"
  - id: M9
    text: "docs/purge.md exists, covers scan, list, dry run, confirm, every status text Purge.cs can emit, held classification, D1, exit codes and the log format, has a Mermaid diagram, and README links it"
must_not:
  - id: N1
    text: "a dry run requests DELETE access or a service list is fetched for a host with no held file (fake fs records access; fake services count calls; paired with a held file on another host that does fetch)"
  - id: N2
    text: "a partial service list is used: if any per-service config query fails, the list is null and the held file is 'could not list services', even when another service would have matched (paired with the same list succeeding -> Tomcat file)"
  - id: N3
    text: "the D1 exemption applies to a held file that is not a redirect log of the matched service (held stale catalina.*.log keeps the age status; paired with the redirect log that is exempted)"
  - id: N4
    text: "a confirm run deletes a held file or any file M8 would skip (paired positive control: an unheld eligible file in the same run is deleted)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, N1, N2, N3, N4]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable (fake IServiceQuery, fake fs with ProbeHeld/ErrorCode/Stat). Pre-fix baseline: each new test's assertion against 1eb1455 behaviour, run by Claude with the new interfaces stubbed to today's behaviour (services null), so the reds are assertion failures, not compile errors. Mutants each red: drop the held branch (M1); drop the D1 exemption (M2); drop the pattern-name check (N3); return a partial list (N2); compare IDs for list rows only (M8); exact 'would delete' in the /savelist writer (M6); probe with DELETE access (N1). Windows CI green."
    intent: Before anything is ever stopped, dirused can tell you exactly which big files Tomcat is holding, and it never deletes anything new while doing so.
  - id: E1W
    proves: [M1, N1]
    kind: offline
    command: "Windows CI (windows-latest, tests/Dirused.Tests): W1 ProbeHeld and the real Open agree (both held) for a file held by FileStream FileShare.ReadWrite, and by FileShare.ReadWrite|Delete; both free after release; W2 RealServiceQuery.ListProcrun(\".\") returns a non-null list without throwing (no procrun service expected on the runner) and a bad host returns null with an error; W3 GetDriveTypeW fixed for the system drive; W4 ProgramPurgeTests.cs:314 updated case passes"
    intent: The Windows calls behave on a real Windows machine the way the fakes assume.
  - id: E2
    proves: [M1, M2, M3, M5, M6]
    kind: live
    command: "operator, jump box, any time (read-only): dirused \\\\us03p02ffm01\\d$\\tomcat /largest /purge shows 'would delete after stopping tomcat85' for tomcat85-stderr.2026-11-04.log (117G) and tomcat85-stdout.2026-11-04.log whatever their time, and for tomcat85-stderr.2026-11-03.log; no 'id mismatch' on them; the summary names tomcat85, us03p02ffm01, root D:\\Tomcat\\Tomcat; then /savelist + /fromlist dry run shows the same rows"
    intent: Run it against ffm01 at any time of day. Nothing is stopped or deleted, and it should name tomcat85 and the three big logs. That proves dirused sees what M9b will act on.
interface:
  - "would delete after stopping <service>"
  - "skipped: in use (<reason>)"
  - "failed: in use by <service> (stop not available yet)"
  - "failed: in use (<reason>)"
  - "reasons: no service found | not a Tomcat log | heap dump, holder unknown | could not list services on <host>: <error> | id mismatch"
  - "skipped: changed since scan (id)"
  - "held files: N (Tomcat: <service> on <host>, root <root>: K file(s), <size>; other: M)"
  - "in-use check failed for N file(s): <error>"
```
