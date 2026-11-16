# M1a: local scanner and read-only CLI, with the windows-latest CI gate

**Status:** LIVE-VERIFIED — landed on dirused m1a-local-scanner (b00fd06 Luna, e4ca415 Claude test-cleanup fix), PR wilddog64/dirused#1 to main; E1–E7 CI run 43750903297, can-fail mutation run 43751127370 (2 red), E8 live on the Vagrant VM 2026-11-15 (/all volume lines match Get-Volume: D: exact, C: 0.005%)
**Milestone:** M1 (first half). M1b adds UNC targets, `\\node`, `/file`, `/summary`, `/timeout`, `/parallel`.
**Plan:** k3d-manager `docs/plans/dirused-windows-disk-usage-tool.md` (Stack, Command line, Scan correctness, Multiple drives)
**Intent approved:** operator, 2026-11-15
**Intent note:** the "You will see / It failed if" text is the plan's M1 row from the scoping approval (operator, 2026-11-06), cut to
the local half. Go for implementation: operator, 2026-11-15 ("if you complete the windows setup you can go ahead to go to code
implementation (either Flash or Luna)"). The operator re-reads the evidence intents below on return.
**Implementer:** Luna (Codex). **Verifier:** Claude, from the Acceptance block only.

## You will see / It failed if

- **You will see:** `dirused D:\` (or `.`, `C:\path`, `/all`) prints each volume's used, free and total space, matching Explorer, then
  the largest directories and the largest files, each sorted largest first.
- **It failed if:** a folder it could not read leaves a low total with no warning, or a junction or hard link is counted twice.

## Context

There is no .NET SDK on the macOS host and the worker sandbox cannot reach Windows, so **the build and test gate is the
`windows-latest` GitHub Actions job** this spec adds. Write code that compiles without being run locally; keep it plain and
explicit. Claude pushes the branch and feeds CI errors back. Do not try to install a .NET SDK.

## Scope

1. **Solution layout** (repo root `dirused.sln`):
   - `src/Dirused.Core/` — class library, `net10.0-windows`, scan engine, no console I/O.
   - `src/Dirused.Cli/` — console exe, `net10.0-windows`, assembly name `dirused`, argument parsing and output.
   - `tests/Dirused.Tests/` — xUnit test project referencing both.
   - `Directory.Build.props`: `Nullable` enable, `TreatWarningsAsErrors` true, `LangVersion` latest, `EnableWindowsTargeting` true.
   - `global.json` pinning SDK `10.0.404` with `rollForward: latestPatch`.
   - Every NuGet package pinned to an exact version (no `*`, no ranges). Use Central Package Management (`Directory.Packages.props`).
   - No GUI project in this spec.
2. **CI:** `.github/workflows/ci.yml`, on `push` and `pull_request`, `runs-on: windows-latest`, `permissions: contents: read`,
   `actions/checkout@v4`, `actions/setup-dotnet@v4` with `global-json-file: global.json`, then `dotnet restore`,
   `dotnet build -c Release --no-restore`, `dotnet test -c Release --no-build`, and
   `dotnet publish src/Dirused.Cli -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o out` followed by a smoke step
   that runs `out\dirused.exe --help` and `out\dirused.exe C:\Windows\Web /top 5` and fails on a non-zero exit (0 or 3 accepted for the scan).
3. **Targets accepted:** `.` (current directory), `<drive>:\path`, `<drive>:\` (whole drive), `/all` (every fixed local drive,
   `DriveInfo.DriveType == Fixed` and `IsReady`). UNC targets in this spec: print `UNC targets arrive in M1b` and exit 1.
4. **Switches:** every switch accepts `/name` and `--name` (case-insensitive). `-h`, `/help`, `--help`, `help`, `/?` print usage, exit 0.
   `/top N` (default 50, N ≥ 1), `/json`, `/csv` (mutually exclusive; both given → usage error). Unknown switch → message naming
   it, exit 1. Purge, monitor, threshold, gui and file switches → `not available yet (<milestone>)`, exit 1, and **nothing on disk changes**.
5. **Output (text):** per target:
   - a volume line: drive, used, free, total, percent used (from `DriveInfo`), human sizes (KB/MB/GB/TB, 1024-based, one decimal);
   - `Largest directories` (top N by size on disk, path and logical size and size on disk), largest first;
   - `Largest files` (top N by size on disk, same columns), largest first;
   - if anything was skipped: `INCOMPLETE: <n> directories could not be read` and the first 10 paths with the reason.
   `/json`: one JSON document `{ "targets": [ { "target", "volume": {...}, "directories": [...], "files": [...], "errors": [...], "complete": bool } ] }`
   with sizes in bytes. `/csv`: header `kind,target,path,logical_bytes,on_disk_bytes`, one row per directory and file.
6. **Scan correctness (plan "Scan correctness"):**
   - Reparse points (junctions, symlinks, mount points) are **never followed** and contribute 0 bytes; they are not errors.
   - Unreadable directories: counted, listed, target marked incomplete, exit code 3. Never a silent low total.
   - Long paths: enumerate with the `\\?\` prefix (or `\\?\UNC\`) so paths over 260 characters work.
   - Size on disk: `GetCompressedFileSizeW` for compressed/sparse files, rounded up to the volume cluster size
     (`GetDiskFreeSpaceW`); logical size from the file length.
   - Hard links: count each file once per volume, keyed by volume serial + file index (`GetFileInformationByHandle`,
     opened with `FILE_READ_ATTRIBUTES` and `FILE_FLAG_BACKUP_SEMANTICS`, no content read). Second and later links contribute 0.
   - Cloud placeholders (`FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` or `RECALL_ON_OPEN`, or `OFFLINE`): listed with their logical size,
     never opened for reading. The hard-link lookup must not open them either (skip the dedup lookup for them).
   - Directory sizes are the sum of their descendants (excluding skipped reparse points).
   - The scan opens files only for attributes; it never reads file contents and never writes anything.
7. **Exit codes:** 0 success, 1 failure/usage error, 3 partial (any target incomplete). (2 is reserved for M3's threshold.)
8. **README:** add a "Usage (M1a)" section listing the commands above.

## Files

Paths are in the dirused repo.

- `dirused.sln`
- `global.json`
- `Directory.Build.props`
- `Directory.Packages.props`
- `src/Dirused.Core/*`
- `src/Dirused.Cli/*`
- `tests/Dirused.Tests/*`
- `.github/workflows/ci.yml`
- `README.md`
- `.gitignore`

## Out of scope

UNC, `\\node`, `/file`, `/summary`, `/timeout`, `/parallel` (M1b); any delete, purge or plan (M2); threshold and monitor (M3); GUI.
No changes to `Vagrantfile`, `ansible/`, `Makefile` or `requirements-dev.txt`.

## Acceptance

```yaml
interface:
  - "dirused <target>... [/top N] [/json|/csv]  where target = . | <drive>:\\path | <drive>:\\ | /all"
  - "exit codes: 0 ok, 1 failure or usage, 3 partial"
  - "Dirused.Core: scan engine with no console I/O; Dirused.Cli: assembly name dirused"
must:
  - "CI workflow on windows-latest builds, tests and publishes a single-file win-x64 dirused.exe, then runs it"
  - "text output lists the volume line, then directories and files sorted by size on disk, largest first, capped at /top"
  - "an unreadable directory produces an INCOMPLETE line naming it and exit code 3"
  - "a junction or symlink to a large directory adds 0 bytes and is not traversed"
  - "two hard links to one file count once"
  - "a compressed or sparse file reports size on disk below its logical size"
  - "paths longer than 260 characters are scanned and listed"
  - "/all scans every fixed ready drive and prints one volume line per drive"
  - "/json output parses as JSON with sizes in bytes; /csv has the documented header"
must_not:
  - "a scan with an unreadable directory exits 0 or omits the INCOMPLETE line"
  - "a junction to a directory doubles that directory's bytes in its parent's total"
  - "a hard-linked file is counted once per link"
  - "any scan or rejected switch (purge, monitor, threshold, gui, file) creates, modifies or deletes a file"
  - "a cloud placeholder file is opened for reading"
evidence:
  - id: E1
    proves: [ "CI workflow on windows-latest builds, tests and publishes a single-file win-x64 dirused.exe, then runs it" ]
    kind: offline
    how: "GitHub Actions run on the branch: build, test, publish and smoke steps all green"
    intent: "The tool builds and runs on a real Windows runner on every push, so nobody has to trust a build they can't see."
  - id: E2
    proves: [ "an unreadable directory produces an INCOMPLETE line naming it and exit code 3", "a scan with an unreadable directory exits 0 or omits the INCOMPLETE line" ]
    kind: offline
    how: "xUnit test: temp tree, one subdirectory with a deny-list ACE for the current user (icacls or DirectorySecurity), run the CLI entry point, assert exit 3 and the path in the INCOMPLETE section; restore the ACL in cleanup"
    intent: "If dirused can't read a folder, it says so and exits 3 instead of showing a total that looks fine but is too low."
  - id: E3
    proves: [ "a junction or symlink to a large directory adds 0 bytes and is not traversed", "a junction to a directory doubles that directory's bytes in its parent's total" ]
    kind: offline
    how: "xUnit test: temp tree with a 1 MiB file in A and a junction B -> A (mklink /J), assert the root total equals A's total"
    intent: "Shortcut folders (junctions) don't make a drive look fuller than it is."
  - id: E4
    proves: [ "two hard links to one file count once", "a hard-linked file is counted once per link" ]
    kind: offline
    how: "xUnit test: create a 1 MiB file and a hard link to it (CreateHardLinkW or fsutil hardlink create), assert the root on-disk total counts 1 MiB once"
    intent: "A file with two names is counted once, so totals match Explorer."
  - id: E5
    proves: [ "a compressed or sparse file reports size on disk below its logical size", "paths longer than 260 characters are scanned and listed" ]
    kind: offline
    how: "xUnit tests: a sparse file (fsutil sparse setflag, then set length 64 MiB) reports on-disk < logical; a nested path over 300 characters is listed with its size"
    intent: "Sizes are what the files really take on disk, and very deep folders are not skipped."
  - id: E6
    proves: [ "text output lists the volume line, then directories and files sorted by size on disk, largest first, capped at /top", "/json output parses as JSON with sizes in bytes; /csv has the documented header" ]
    kind: offline
    how: "xUnit tests on a fixed temp tree: text ordering and /top cap; /json parsed with System.Text.Json; /csv header line"
    intent: "The biggest files and folders come first, and the JSON and CSV output can be read by scripts."
  - id: E7
    proves: [ "any scan or rejected switch (purge, monitor, threshold, gui, file) creates, modifies or deletes a file", "a cloud placeholder file is opened for reading" ]
    kind: offline
    how: "xUnit test: snapshot names, sizes and last-write times of a temp tree, run a scan and each rejected switch, assert the snapshot is unchanged and rejected switches exit 1; code review: placeholder files take the attributes-only path (no CreateFile with GENERIC_READ)"
    intent: "Looking never changes anything: M1 can't delete or modify a file, and it doesn't download cloud files."
  - id: E8
    proves: [ "/all scans every fixed ready drive and prints one volume line per drive" ]
    kind: live
    how: "Claude on the dirused-dev Vagrant VM (C: and D:): dirused /all prints a C: and a D: volume line whose used/free match Get-Volume within 1%"
    intent: "With apps on D: as at most companies, one command shows C: and D: together and the numbers match Windows."
```
