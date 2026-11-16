# dirused `/timeout` cannot bound a volume probe that never returns

**Status:** OPEN — captured from the Copilot review of wilddog64/dirused PR #3 (Program.cs:28); approved, not yet dispatched
**Priority:** P3 — a dead SMB server can stall one worker past `/timeout`; other targets still finish (workaround: Ctrl+C after the rest report, or a smaller `/file`)
**Introduced by:** wilddog64/dirused 97a47fc (M1b phase 1b, not yet merged)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (Claude verification)
**Waiting on:** dispatch — since 2026-11-16
**Approved:** operator 2026-11-16 ("approve two P3 bugs and can dispatch to Flash and Luna after /clear"); operator clarified one bug per agent: Luna (`gpt-6-luna`, Codex) implements; spec with Acceptance next
**Prior art:** none above threshold. Exact slug: no match. `make find-similar-docs` was unavailable (vector store context `k3d-k3d-cluster` missing).
**Filed:** 2026-11-16
**Repo / branch:** wilddog64/dirused, `m1b1b-fleet-runner`

## You will see / It failed if

- **You will see:** with `/timeout 30`, a target whose server stops answering mid-probe reports `TIMED OUT after 30s` at about 30 s.
- **It failed if:** that target, and the run, wait as long as Windows' own SMB timeout before reporting.

## Cause

`ScanRunner.Run` (`src/Dirused.Common/ScanRunner.cs`) calls the scan delegate synchronously on its worker and only
checks the timeout after the delegate returns. Full scans check the token between folders, so they stop. The `/summary`
probe is a single blocking Win32 call (`GetDiskFreeSpaceEx` / `GetVolumeInformation`), and no token can interrupt it.
Passing the token through, as the Copilot review suggested, would change nothing observable.

## Fix direction (for a spec, not dispatched)

At the deadline, ScanRunner records `TIMED OUT` for that target and moves the worker on. The stuck call is left to finish
on its own thread and its result is discarded. Bound how many abandoned threads can pile up. Needs a test with a delegate
that ignores its token.
