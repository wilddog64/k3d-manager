# M1b-1a: remote targets — UNC paths and `\\node`

**Status:** APPROVED — written 2026-11-15; intents approved by the operator 2026-11-15; dispatch after phase 0 (`dirused-m1b0-modular-refactor.md`) merges
**Milestone:** M1 (second half), phase 1a. Runs in parallel with phase 1b (`dirused-m1b-fleet-runner.md`, Flash); the two
specs share no file.
**Plan:** k3d-manager `docs/plans/dirused-windows-disk-usage-tool.md` (Command line, Scan correctness, Multiple drives)
**Approval:** operator, 2026-11-15 ("be sure to modulus and we can try to distribute tasks between flash and luna")
**Open decision (operator):** the plan marks a bare `\\node` scanning every `<letter>$` admin share as "proposed, decide before
the M1 spec". This spec implements it; approving its intents approves that behaviour.
**Intent approved:** operator, 2026-11-15
**Approval note:** operator "approved" (2026-11-15) covers the intents below, `\\node` = every `<letter>$` admin share, and Luna for phase 0. Scope item 5 and E6 added 2026-11-15 on the operator's "yes" to the extra target forms.
**Implementer:** Luna (Codex). **Verifier:** Claude, from the Acceptance block only.
**Repo / base:** wilddog64/dirused, branch `m1b1a-remote-targets` from `main` after phase 0 merges.

## You will see / It failed if

- **You will see:** `dirused \\node\d$\apps` measures that folder on another machine with the same columns as a local scan, and
  `dirused \\node` prints one volume line per fixed drive on that machine (`C$`, `D$`, …) followed by its largest folders and files.
- **It failed if:** a remote scan totals differently from a local scan of the same folder, `\\node` counts `C:\Windows` twice
  (through `ADMIN$`) or skips a drive with no warning, or an unreachable machine leaves no row and exit 0.

## Context

After phase 0, `TargetResolver` classifies UNC and node targets and rejects them; `VolumeProbe` already works on UNC roots;
`Scanner` already builds `\\?\UNC\` paths. This phase turns the rejection into real targets. Build and test gate: the
`windows-latest` CI job `windows` (UNC and `NetShareEnum` run only on Windows); `dotnet build` works on the macOS host as a
compile check.

## Proof of external behaviour

windows-latest probe, run 43758987933 (wilddog64/dirused, 2026-11-15, image `windows-2025-vs2026` 20261103.298.1, Server 2025
10.0.26100, user `runneradmin`, High integrity, `LocalAccountTokenFilterPolicy=1`, LanmanServer running):

- `Win32_Share` and `net view \\localhost /all` list `ADMIN$` (`C:\Windows`), `C$`, `D$` (type `2147483648`, special disk) and
  `IPC$` (`2147483651`, special IPC). So `<letter>$` selects the drives and excludes `ADMIN$` and `IPC$`.
- `Test-Path` succeeds for `\\localhost\c$\Windows`, `\\127.0.0.1\c$\Windows` and `\\<COMPUTERNAME>\c$\Windows`.
- Volume calls on `\\localhost\c$\` match `C:\` (same total, free, cluster size, serial `54CBA274`); `\\localhost\D$\` gives
  D:'s serial `D6A74C87`; `\\nosuchhost-xyz\c$\` fails with error 53.
- `fsutil file queryfileid` returns the same file id (`0x…0001000000009cf0`) for `C:\Windows\notepad.exe` and
  `\\localhost\c$\Windows\notepad.exe`, so the hard-link key (volume serial + file index) holds over SMB loopback.
- `Get-ChildItem -LiteralPath '\\?\UNC\localhost\c$\Windows\Web' -Recurse` enumerates (31,035,632 bytes).

Not proven here (needs ACG, plan "CLI gate"): a second real machine, a non-admin account, and remote UAC filtering without
`LocalAccountTokenFilterPolicy`. Evidence from `\\localhost` alone does not close the M1 CLI gate.

## Scope

1. **UNC path targets** `\\server\share[\path]`: in `TargetResolver`, become `TargetKind.Unc` with `Root = \\server\share\`.
   The volume line comes from `VolumeProbe.Probe(Root)`; the walk uses the existing `\\?\UNC\` handling. Display keeps the
   typed form.
2. **Bare node targets** `\\node` (no share): enumerate disk shares with `NetShareEnum` level 1 (new
   `src/Dirused.Core/Native/NetApi32.cs`, free the buffer with `NetApiBufferFree`). Keep shares whose type has
   `STYPE_DISKTREE` and `STYPE_SPECIAL` and whose name matches `^[A-Za-z]\$$`; expand to one `Unc` target per share
   (`\\node\C$\`, `\\node\D$\`, …), sorted by letter. Never `ADMIN$`, `IPC$`, printer or non-admin disk shares.
   Put the enumeration in `src/Dirused.Core/Targets/NodeShares.cs` behind an interface so tests can stub it.
3. **Errors, per target (one failed target never stops the rest):**
   - network path not found (53), bad net name (67), host unreachable (1231): the target shows `UNREACHABLE: <target> (<code>)`,
     is marked incomplete, exit 3;
   - access denied (5) on the share or `NetShareEnum`: `ACCESS DENIED: <target> — admin shares need an administrator on the
     target` and exit 3;
   - a node with zero `<letter>$` shares: `NO DRIVES: <node>`, exit 3.
   Same in `/json` (the target's `errors`, `complete: false`) and `/csv` (no rows, error on stderr).
4. **Credentials:** the current Windows token only. No user, password or credential switch; nothing calls `WNetAddConnection2`.
5. **Target forms (operator, 2026-11-15: "d:/ can probably be more portable across OS"),** all in `TargetParser`:
   - `//server/share[/path]` parses as UNC, and `//node` as a node, the same as the backslash forms (phase 1b routes
     arguments starting with `//` to the target parser instead of the switch branch);
   - a drive letter alone, `C:` or `c:`, means that drive's root (`C:\`);
   - drive targets take either separator, any case: `d:/`, `d:\`, `d:/apps`, `D:\apps\logs`, mixed. Root and walk use
     backslashes; output shows the target as typed;
   - a relative path (`subdir`, `..\x`, `sub/dir`) resolves against the current directory, as `.` does today.
6. **README:** add UNC, `\\node` and the target forms above to the usage section, with the admin-rights note.

## Files

- `src/Dirused.Core/Targets/TargetResolver.cs` (UNC branch only), `src/Dirused.Core/Targets/NodeShares.cs`,
  `src/Dirused.Common/Targets/TargetParser.cs` (only if UNC classification needs it)
- `src/Dirused.Core/Native/NetApi32.cs`
- `tests/Dirused.Tests/RemoteTargetTests.cs`
- `README.md` (usage section)

Not touched (phase 1b owns them): `ArgParser.cs`, `Options.cs`, `ScanRunner.cs`, `Scanner.cs`, `Renderers/`. If UNC
classification in `src/Dirused.Common/Targets/TargetParser.cs` needs a change, it is this phase's file (1b does not touch it).

## Out of scope

`/file`, `/summary`, `/timeout`, `/parallel` (phase 1b); deletes (M2); mapped drive letters; volumes mounted into a folder; GUI.

## Acceptance

```yaml
interface:
  - "dirused \\\\server\\share[\\path] [/top N] [/json|/csv]"
  - "dirused \\\\node  -> one target per <letter>$ admin disk share, in letter order"
  - "exit codes: 0 ok, 1 usage, 3 any target incomplete, unreachable, denied or without drives"
  - "target forms: C:\\x | c:/x | C: | relative | \\\\server\\share | //server/share | \\\\node | //node"
must:
  - "a UNC scan of a folder reports the same directory and file totals as a local scan of that folder"
  - "\\\\node lists every <letter>$ disk share and prints one volume line per drive"
  - "an unreachable node prints an UNREACHABLE line naming it and exits 3"
  - "a hard link reached through UNC is counted once"
  - "d:/x, d:\\x and D:\\x scan the same folder with the same totals"
must_not:
  - "a UNC target exits 1 with 'UNC targets arrive in M1b'"
  - "\\\\node scans ADMIN$, IPC$ or a non-<letter>$ share"
  - "an unreachable or access-denied target is missing from the output or exits 0"
  - "any switch or code path takes a user name, password or credential"
  - "TargetParser rejects //server/share, C: or a relative path"
evidence:
  - id: E1
    proves: [ "a UNC scan of a folder reports the same directory and file totals as a local scan of that folder", "a hard link reached through UNC is counted once", "a UNC target exits 1 with 'UNC targets arrive in M1b'" ]
    kind: offline
    how: "xUnit on windows-latest: temp tree under C:\\ with a 1 MiB file, a hard link to it and a junction; scan C:\\<tree> and \\\\localhost\\c$\\<tree>, assert equal totals, exit 0, the hard-linked MiB counted once"
    intent: "A folder on another machine adds up exactly like the same folder scanned locally."
  - id: E2
    proves: [ "\\\\node lists every <letter>$ disk share and prints one volume line per drive", "\\\\node scans ADMIN$, IPC$ or a non-<letter>$ share" ]
    kind: offline
    how: "xUnit: \\\\localhost resolves to exactly C$ and D$ on windows-latest (compare to Win32_Share filtered by name); stubbed NodeShares returning ADMIN$, IPC$, C$, data, D$ resolves to C$ and D$ only"
    intent: "Naming a machine scans each of its drives once, C: and D: alike, and never counts the Windows folder twice."
  - id: E3
    proves: [ "an unreachable node prints an UNREACHABLE line naming it and exits 3", "an unreachable or access-denied target is missing from the output or exits 0" ]
    kind: offline
    how: "xUnit: dirused C:\\Windows\\Web \\\\nosuchhost-xyz\\c$ exits 3, prints the Web results and UNREACHABLE: \\\\nosuchhost-xyz\\c$ (53); stubbed NodeShares throwing error 5 gives ACCESS DENIED and exit 3; positive control: C:\\Windows\\Web alone exits 0"
    intent: "A machine that is off or locks you out shows up as a clear failure, never as a missing row."
  - id: E4
    proves: [ "any switch or code path takes a user name, password or credential" ]
    kind: offline
    how: "Claude review: grep src for WNetAddConnection, CredUI, password, credential (none); ArgParser unchanged by this branch"
    intent: "dirused never asks for or stores a password; it runs as you."
  - id: E5
    proves: [ "\\\\node lists every <letter>$ disk share and prints one volume line per drive" ]
    kind: live
    how: "Claude on the operator's dirused-dev Vagrant VM (C: and D:), when the operator says the VM is free: dirused \\\\localhost shows C: and D: volume lines matching Get-Volume within 1%. Real multi-machine UNC stays owed to the ACG CLI gate"
    intent: "On a Windows box like yours, naming the machine shows both drives with the right numbers."
  - id: E6
    proves: [ "d:/x, d:\\x and D:\\x scan the same folder with the same totals", "TargetParser rejects //server/share, C: or a relative path" ]
    kind: offline
    how: "Portable xUnit on TargetParser: //server/share -> Unc with Root \\\\server\\share\\, //node -> Node, C: and c: -> LocalDrive C:\\, sub/dir -> LocalPath (each null on pre-fix code); positive control: C:\\x and \\\\server\\share unchanged. Windows xUnit: scan C:/<tree>, c:\\<tree> and C:\\<tree> (temp tree with a 1 MiB file), equal totals and exit 0"
    intent: "Type a path the Windows way or the Mac/Linux way, d:\\ or d:/, and dirused measures the same folder."
```
