# dirused UNC scans fail: volume root passed to `GetVolumeInformation` without a trailing backslash

**Status:** LIVE-VERIFIED — a9b4d78 merged in 245bedd (PR #4, 2026-11-15); live 2026-11-16 on dirused-dev VM: `dirused \\localhost` C$ and D$ volume totals equal Get-Volume exactly
**Priority:** P1 — every UNC and `\\node` scan fails; blocks the open dirused PR #4 (M1b phase 1a)
**Introduced by:** pre-existing in `Scanner.Scan` (phase 0); first reachable in wilddog64/dirused ab27363 (M1b phase 1a, not yet merged)
**Should have been caught by:** offline test (E1 caught it on windows-latest)
**Introducing change reviewed:** yes (Claude verification; Windows tests cannot run on the Mac)
**Fix commit:** a9b4d78 (wilddog64/dirused; merged in 245bedd)
**Live evidence:** 2026-11-16 · run claude-vagrant-winrm-dirused-localhost · env dirused-dev-vm · scenario unc-admin-shares-match-get-volume · commit 245bedd · proves E1
**Prior art:** none. Exact slug: no match. `make find-similar-docs` was unavailable (vector store context `k3d-k3d-cluster` missing).
**Filed:** 2026-11-15
**Parent spec:** `docs/plans/dirused-m1b-remote-targets.md` (E1)
**Intent approved:** operator, 2026-11-15
**Repo / branch:** wilddog64/dirused, `m1b1a-remote-targets`
**Implementer:** Luna (Codex). **Verifier:** Claude, from the Acceptance block only.

## You will see / It failed if

- **You will see:** `dirused \\server\c$\apps` and `dirused \\node` print volume lines and folder totals.
- **It failed if:** a UNC target prints `ERROR: ... (123)` or "volume label syntax is incorrect".

## Evidence

CI `windows`, run 43772219892, 2026-11-15, windows-latest:

    RemoteTargetTests.LoopbackMatchesLocalAndCountsHardLinksOnce [FAIL]
    Dirused.Core.Volumes.VolumeProbeException : The filename, directory name, or volume label syntax is incorrect.
      at VolumeProbe.Probe(String root) VolumeProbe.cs:line 17      (GetVolumeInformation)
      at Scanner.Scan(String target) Scanner.cs:line 19

## Cause

`Scanner.Scan` takes `root = Path.GetPathRoot(full)`. For `\\localhost\c$\Temp\x`, that is `\\localhost\c$`, with no
trailing separator; for `C:\x` it is `C:\`. Win32 `GetVolumeInformation` requires a trailing backslash on a UNC root
(`\\server\share\`) and returns ERROR_INVALID_NAME (123) without one. `GetDiskFreeSpaceEx` (line 15) accepts either form,
which is why the failure is at line 17. The phase-0 probe (run 43758987933) passed `\\localhost\c$\` with the backslash,
so it never hit this.

## Fix

In `src/Dirused.Core/Volumes/VolumeProbe.cs` only: at the top of `Probe`, append `\` to `root` when it does not end with
`\` or `/`, and use that root for all three calls and for the returned `Volume`. Do not touch `Scanner.cs` (phase 1b changes it).

## Files

- `src/Dirused.Core/Volumes/VolumeProbe.cs`
- `tests/Dirused.Tests/RemoteTargetTests.cs` (only if a test needs a compile fix)

## Acceptance

```yaml
interface:
  - "VolumeProbe.Probe(root) accepts a root with or without its trailing separator"
must:
  - "a UNC scan of a folder reports the same totals as a local scan of that folder"
  - "a local drive root still probes and scans as before"
must_not:
  - "a UNC target fails with error 123 or 'volume label syntax is incorrect'"
evidence:
  - id: E1
    proves: [ "a UNC scan of a folder reports the same totals as a local scan of that folder", "a UNC target fails with error 123 or 'volume label syntax is incorrect'" ]
    kind: offline
    how: "CI windows job on PR #4: RemoteTargetTests.LoopbackMatchesLocalAndCountsHardLinksOnce red at ab27363 (run 43772219892), green after the fix"
    intent: "A folder on another machine adds up exactly like the same folder scanned locally."
  - id: E2
    proves: [ "a local drive root still probes and scans as before" ]
    kind: offline
    how: "positive control: the full Windows and portable suites stay green on PR #4 (local scans, E3 C:\\Windows\\Web exit 0, E6 drive forms)"
    intent: "Local drives keep working exactly as they do today."
```
