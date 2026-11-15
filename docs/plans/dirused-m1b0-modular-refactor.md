# M1b-0: split the M1a CLI into modules (no behaviour change)

**Status:** DRAFT — written 2026-11-15; waits on intent approval and a dispatch go
**Milestone:** M1 (second half), phase 0 of 3. Phases 1a (`dirused-m1b-remote-targets.md`, Luna) and 1b
(`dirused-m1b-fleet-runner.md`, Flash) start in parallel once this lands; each edits files the other does not touch.
**Plan:** k3d-manager `docs/plans/dirused-windows-disk-usage-tool.md` (Command line, Scan correctness, Multiple drives)
**Approval:** operator, 2026-11-15 ("next step is to start code implemenation. be sure to modulus and we can try to distribute
tasks between flash and luna")
**Intent approved:** pending
**Implementer:** Luna (Codex), who wrote M1a. **Verifier:** Claude, from the Acceptance block only.
**Repo / base:** wilddog64/dirused, branch `m1b0-modular-refactor` from `main` (74412c9).

## You will see / It failed if

- **You will see:** nothing new. Every M1a command prints the same output and exit code as before; the code is now in small
  files so the next two pieces of work can run side by side.
- **It failed if:** any M1a output or exit code changes, or the two follow-on specs would have to edit the same file.

## Context

M1a put argument parsing, `/all` expansion, the three renderers and their helpers in one `Program.cs` (63 lines), and the volume
line comes from `DriveInfo`, which throws on a UNC root. M1b adds remote targets and a fleet runner. To let Luna and Flash work
at once, this phase moves code into files with one job each and puts the interfaces they need in place. No new behaviour.

There is no .NET SDK on the macOS host; **the build and test gate is the `windows-latest` CI job named `windows`**. Do not try
to install an SDK. Claude pushes the branch and feeds CI errors back.

## Proof of external behaviour

windows-latest probe, run 43758987933 on wilddog64/dirused (throwaway branch `probe/unc-2026-11-15`, deleted), 2026-11-15,
image `windows-2025-vs2026` 20261103.298.1, Windows Server 2025 10.0.26100, pwsh 7.6.9, user `runneradmin` (High integrity,
`LocalAccountTokenFilterPolicy=1`):

- `GetDiskFreeSpaceExW`, `GetDiskFreeSpaceW` and `GetVolumeInformationW` succeed with the same total, free, cluster size (4096)
  and volume serial (`54CBA274`) for `C:\`, `\\localhost\c$\`, `\\localhost\c$\Windows\` and `\\?\UNC\localhost\c$\`.
  `\\localhost\D$\` gives D:'s values (serial `D6A74C87`). So one volume probe built on these three calls serves local and UNC
  roots, and `DriveInfo` is not needed.
- `\\nosuchhost-xyz\c$\` fails all three with Win32 error 53 (`ERROR_BAD_NETPATH`).

## Scope

Paths are in the dirused repo. Namespaces follow the folders.

1. **`src/Dirused.Cli/Options.cs`** — a record holding every parsed value: targets (as typed), `Top`, `Format`
   (`Text`/`Json`/`Csv`), and the M1b fields, parsed but not yet acted on: `File` (string?), `Summary` (bool),
   `Timeout` (TimeSpan?), `Parallel` (int?).
2. **`src/Dirused.Cli/ArgParser.cs`** — `static ParseResult Parse(string[] args)`: usage request, error message, or `Options`.
   Same switch rules, messages and exit codes as M1a. Parse `/file <path>`, `/summary`, `/timeout <n>[s|m|h]` and
   `/parallel <n>` into `Options`, then reject them in **one** guard method `RejectUnavailable(Options)` that returns the M1a
   message `not available yet (M1b)` — so phase 1b deletes one guard instead of editing the parser.
3. **`src/Dirused.Core/Targets/Target.cs`** — `record Target(string Display, TargetKind Kind, string Root, string Path)`,
   `TargetKind { LocalPath, LocalDrive, Unc, Node }`.
4. **`src/Dirused.Core/Targets/TargetResolver.cs`** — `IReadOnlyList<Target> Resolve(IEnumerable<string> typed, out IReadOnlyList<string> errors)`:
   classifies `.`, `<drive>:\path`, `<drive>:\`, `/all` (fixed, ready drives, moved from Program), `\\server\share\...` and bare
   `\\node`. UNC and node targets are rejected here with the M1a message `UNC targets arrive in M1b`, exit 1 — so phase 1a
   replaces only this file's UNC branch.
5. **`src/Dirused.Core/Volumes/VolumeProbe.cs`** — `Volume Probe(string root)` using `GetDiskFreeSpaceExW` (total, free),
   `GetDiskFreeSpaceW` (cluster size) and `GetVolumeInformationW` (serial, file system). Throws a `VolumeProbeException`
   carrying the Win32 error. `Scanner` gets its volume and cluster size from here; no `DriveInfo` in Core.
6. **`src/Dirused.Core/Native/Kernel32.cs`** — every existing `DllImport`/`LibraryImport` from `Scanner.cs` plus the three above,
   in one internal static class. Phase 1a adds `Native/NetApi32.cs` beside it.
7. **`src/Dirused.Core/ScanRunner.cs`** — `IReadOnlyList<TargetResult> Run(IReadOnlyList<Target> targets, Func<Target, CancellationToken, ScanResult> scan, RunOptions options, CancellationToken ct)`,
   sequential for now, results in input order. `RunOptions` holds `Parallel` and `Timeout`, unused here. Phase 1b fills it in.
8. **`src/Dirused.Cli/Renderers/`** — `IRenderer` with `TextRenderer`, `JsonRenderer`, `CsvRenderer` and a shared `Format`
   helper (the M1a Size, Quote and Row helpers). Byte-for-byte the M1a output.
9. **`src/Dirused.Cli/Program.cs`** — only: parse, resolve, run, render, return the exit code. No parsing, rendering or P/Invoke.
10. **Tests:** keep `ScannerTests.cs` passing untouched. Add `tests/Dirused.Tests/OutputCompatTests.cs` and
    `ArgParserTests.cs` (see Acceptance).

## Files

- `src/Dirused.Cli/Program.cs`, `Options.cs`, `ArgParser.cs`, `Renderers/*.cs`
- `src/Dirused.Core/Scanner.cs`, `ScanRunner.cs`, `Targets/*.cs`, `Volumes/VolumeProbe.cs`, `Native/Kernel32.cs`
- `tests/Dirused.Tests/OutputCompatTests.cs`, `ArgParserTests.cs`

## Out of scope

Any new behaviour (UNC scans, `\\node`, `/file`, `/summary`, `/timeout`, `/parallel` run in phases 1a and 1b); deletes; GUI;
`Vagrantfile`, `ansible/`, `Makefile`, `.github/workflows/`.

## Acceptance

```yaml
interface:
  - "unchanged M1a CLI: dirused <target>... [/top N] [/json|/csv], exit codes 0 ok, 1 failure or usage, 3 partial"
  - "Dirused.Core.Targets.TargetResolver.Resolve(typed, out errors) -> IReadOnlyList<Target>"
  - "Dirused.Core.Volumes.VolumeProbe.Probe(root) -> Volume, via GetDiskFreeSpaceExW/GetDiskFreeSpaceW/GetVolumeInformationW"
  - "Dirused.Core.ScanRunner.Run(targets, scan, RunOptions, ct) -> results in input order"
  - "Dirused.Cli.ArgParser.Parse(args) -> usage | error | Options, with File/Summary/Timeout/Parallel parsed and rejected in RejectUnavailable"
must:
  - "every M1a test in ScannerTests.cs passes without edits"
  - "text, /json and /csv output and exit codes for a fixed temp tree are identical to M1a's"
  - "/file, /summary, /timeout, /parallel and UNC targets still exit 1 with the M1a messages"
  - "VolumeProbe.Probe returns the same total, free, cluster size and serial for C:\\ and \\\\localhost\\c$\\"
must_not:
  - "Program.cs contains argument parsing, rendering or P/Invoke code"
  - "Dirused.Core uses System.IO.DriveInfo for the volume line or cluster size"
  - "a VolumeProbe call on an unreachable UNC root returns a zero-size volume instead of throwing with error 53"
evidence:
  - id: E1
    proves: [ "every M1a test in ScannerTests.cs passes without edits", "text, /json and /csv output and exit codes for a fixed temp tree are identical to M1a's" ]
    kind: offline
    how: "CI job windows green; OutputCompatTests builds a fixed temp tree (known sizes, one junction, one hard link) and compares text, JSON and CSV to expected strings written from the M1a format in Program.cs at 74412c9; git diff 74412c9 -- tests/Dirused.Tests/ScannerTests.cs is empty"
    intent: "Nothing you can see changes: the same commands print the same results."
  - id: E2
    proves: [ "/file, /summary, /timeout, /parallel and UNC targets still exit 1 with the M1a messages" ]
    kind: offline
    how: "ArgParserTests: each switch and a \\\\localhost\\c$ target returns exit 1 and the M1a message; positive control: /top 5 and /json parse to Options"
    intent: "Features that are not built yet still say so, instead of half-running."
  - id: E3
    proves: [ "VolumeProbe.Probe returns the same total, free, cluster size and serial for C:\\ and \\\\localhost\\c$\\", "a VolumeProbe call on an unreachable UNC root returns a zero-size volume instead of throwing with error 53" ]
    kind: offline
    how: "xUnit on windows-latest: probe C:\\ and \\\\localhost\\c$\\ and compare (total and serial equal, free within 1%); probe \\\\nosuchhost-xyz\\c$\\ and assert VolumeProbeException with error 53"
    intent: "The disk-space numbers come from a source that works the same for remote shares, so the remote work can reuse it."
  - id: E4
    proves: [ "Program.cs contains argument parsing, rendering or P/Invoke code", "Dirused.Core uses System.IO.DriveInfo for the volume line or cluster size" ]
    kind: offline
    how: "Claude review: grep Program.cs for switch literals, Console.Write of rows, DllImport/LibraryImport (none); grep src/Dirused.Core for DriveInfo (none outside TargetResolver's /all expansion)"
    intent: "The code is split so two agents can build the next parts at once without colliding."
```
