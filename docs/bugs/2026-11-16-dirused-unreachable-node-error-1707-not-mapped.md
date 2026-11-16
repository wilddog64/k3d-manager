# dirused `\\node` for a host that does not resolve prints `ERROR (1707)` instead of `UNREACHABLE`

**Status:** OPEN — found by `make vm-live` check L2 on the dirused-dev VM, 2026-11-16, at main febe79d; not dispatched
**Priority:** P3 — wrong label only: the run still exits 3 and other targets still scan; the operator sees a raw code instead of "UNREACHABLE"
**Introduced by:** wilddog64/dirused ab27363 (M1b phase 1a `\\node` expansion; merged in 245bedd)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Claude verification)
**Waiting on:** operator decision — since 2026-11-16
**Prior art:** `docs/bugs/2026-11-16-dirused-unreachable-host-error-64-not-mapped.md` (exact-slug neighbour; `make find-similar-docs` unavailable, vector store context `k3d-k3d-cluster` missing) — read, different code path: that fix mapped share-path codes 51/64 from the volume probe; this code comes from `NetShareEnum` while expanding a bare node.
**Filed:** 2026-11-16
**Repo:** wilddog64/dirused, `main` at febe79d

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

## Fix direction (for a spec, not dispatched)

Add 1707 (and 1722 once seen in a capture) to the unreachable set in `TargetResolver.ErrorMessage`, with a portable test.
`make vm-live` L2 is the live red check (red at febe79d).
