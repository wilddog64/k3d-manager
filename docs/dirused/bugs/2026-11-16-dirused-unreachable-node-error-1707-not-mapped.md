# dirused `\\node` for a host that does not resolve prints `ERROR (1707)` instead of `UNREACHABLE`

**Status:** LIVE-VERIFIED — L2 passes: `dirused \\nosuchhost-xyz` prints UNREACHABLE with a known code, rc=3; merged in wilddog64/dirused#7 as 1926d2e (operator, 2026-11-16); test 47d0572 red on CI before the fix, fix 562de4a green; live-check fix-up 82442a0 (L1/L2 accept 1707) after Argon review; CI green at b270d5e
**Priority:** P3 — wrong label only: the run still exits 3 and other targets still scan; the operator sees a raw code instead of "UNREACHABLE"
**Introduced by:** wilddog64/dirused ab27363 (M1b phase 1a `\\node` expansion; merged in 245bedd)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Claude verification)
**Live evidence:** 2026-11-16 · run operator-make-vm-live-tmux-work-1.1 · env dirused-dev-vm · scenario live-check-L1-L10 (10/10 pass, build 02:36:18Z) · commit 1926d2e · proves L2
**Fix commit:** 562de4a + 82442a0 (merged as 1926d2e, wilddog64/dirused PR #7)
**Approved:** operator 2026-11-16 ("approve two P3 bugs and can dispatch to Flash and Luna after /clear"); operator clarified one bug per agent: Flash (`gemini-3.8-flash-medium`, agy) implements; spec with Acceptance next
**Prior art:** `docs/bugs/2026-11-16-dirused-unreachable-host-error-64-not-mapped.md` (exact-slug neighbour; `make find-similar-docs` unavailable, vector store context `k3d-k3d-cluster` missing) — read, different code path: that fix mapped share-path codes 51/64 from the volume probe; this code comes from `NetShareEnum` while expanding a bare node.
**Filed:** 2026-11-16
**Intent approved:** operator, 2026-11-16
**Repo / branch:** wilddog64/dirused, `p3-unreachable-1707` from `main` at b475154
**Implementer:** Flash (agy `gemini-3.8-flash-medium`). **Verifier:** Claude, from the Acceptance block only; live evidence by Claude (`make vm-live`).

## You will see / It failed if

- **You will see:** `dirused \\nosuchhost-xyz` prints `UNREACHABLE: \\nosuchhost-xyz (1707)` and exits 3.
- **It failed if:** it prints `ERROR: \\nosuchhost-xyz (1707)`.

## Evidence

`make vm-live` (dirused branch `vm-live-check`, tools/vm-live.ps1), dirused-dev VM (BENTO, Windows 11 arm64), 2026-11-16T00:45Z,
dirused.exe built from main febe79d plus the uncommitted tooling:

    PASS L1 ... [dirused \\nosuchhost-xyz\c$ -> rc=3, 2.8s]
    FAIL L2 unreachable bare node prints UNREACHABLE with a known code and exits 3  [dirused \\nosuchhost-xyz -> rc=3, 0.1s]
        ERROR: \\nosuchhost-xyz (1707)

## Cause

A bare `\\node` is expanded with `NetApi32.NetShareEnum` (`src/Dirused.Core/Targets/NodeShares.cs:17`). For a name that
does not resolve, it returns 1707 (`RPC_S_INVALID_NET_ADDR`, "The network address is invalid"), and
`TargetResolver.ErrorMessage` (`src/Dirused.Core/Targets/TargetResolver.cs:33`) only treats 51, 53, 64, 67 and 1231 as
unreachable. A share path such as `\\nosuchhost-xyz\c$` goes through the volume probe instead and gets 53 (L1 passes).
1722 (`RPC_S_SERVER_UNAVAILABLE`) is the likely code for a host that resolves but is down; unproven.

## Fix

Add 1707 to the unreachable set in `TargetResolver.ErrorMessage`. Do not add 1722: no capture shows it yet.

`TargetResolver` is in `Dirused.Core` (Windows-only), so the test goes in the Windows suite `tests/Dirused.Tests/RemoteTargetTests.cs`,
not the portable one. Make two commits: first the test only (it must fail on the current code; the CI `windows` job is
the red proof), then the one-line mapping fix. Push both; do not open a PR (Claude does).

## Files

- `src/Dirused.Core/Targets/TargetResolver.cs` (`ErrorMessage` only)
- `tests/Dirused.Tests/RemoteTargetTests.cs`

## Acceptance

```yaml
interface:
  - "TargetResolver.ErrorMessage(target, code) -> UNREACHABLE: <target> (<code>) for 51, 53, 64, 67, 1231, 1707"
  - "dirused \\\\node -> exit 3 when the node cannot be reached"
must:
  - "a bare \\\\node whose share enumeration fails with 1707 prints UNREACHABLE: \\\\node (1707)"
  - "51, 53, 64, 67, 1231 stay UNREACHABLE; 5 stays ACCESS DENIED; 1722 and any other code stay ERROR"
  - "the run still exits 3 for an unreachable node"
must_not:
  - "error 1707 for a target prints ERROR instead of UNREACHABLE"
evidence:
  - id: E1
    proves: [ "a bare \\\\node whose share enumeration fails with 1707 prints UNREACHABLE: \\\\node (1707)", "error 1707 for a target prints ERROR instead of UNREACHABLE" ]
    kind: offline
    how: "Windows xUnit in RemoteTargetTests: a fake INodeShares that throws Win32Exception(1707); ResolveDetailed([\\\\nosuchhost-xyz]) gives one error equal to 'UNREACHABLE: \\\\nosuchhost-xyz (1707)', and ErrorMessage(t, 1707) starts with UNREACHABLE; red on the test-only commit (CI windows job), green on the fix commit"
    intent: "Pointing dirused at a machine name that doesn't exist says UNREACHABLE, not a bare error number."
  - id: E2
    proves: [ "51, 53, 64, 67, 1231 stay UNREACHABLE; 5 stays ACCESS DENIED; 1722 and any other code stay ERROR" ]
    kind: offline
    how: "positive control in the same test: 51, 53, 64, 67, 1231 UNREACHABLE; 5 ACCESS DENIED; 1722 and 2 ERROR"
    intent: "Other errors keep their labels; nothing new is called unreachable without proof."
  - id: E3
    proves: [ "a bare \\\\node whose share enumeration fails with 1707 prints UNREACHABLE: \\\\node (1707)", "the run still exits 3 for an unreachable node", "error 1707 for a target prints ERROR instead of UNREACHABLE" ]
    kind: live
    how: "Claude runs make vm-live on the dirused-dev VM with the fix-commit build: L2 passes (UNREACHABLE: \\\\nosuchhost-xyz (1707), rc=3); L2 failed at febe79d; every other check that passed before still passes"
    intent: "On a real Windows machine, the unreachable-name check that fails today passes, and nothing else breaks."
```
