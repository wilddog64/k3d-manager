# dirused: RootSharedOpenDoesNotBlockConfirmDelete cleanup races the FileSystemWatcher handle on Windows

**Status:** OPEN
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-24
**Prior art:** docs/bugs/2026-11-18-dirused-e3-timeout-flake.md (n/a, find-similar-docs unavailable: vector store down) — read, different root cause (FleetRunner timing, not a directory handle)
**Tracked:** dirused (OOB repo), not a k3d-manager release.

## Symptom

wilddog64/dirused Actions run 45455761460 (push, `cf07ace` on `m10b-scheduled-purge`, 2026-11-24), job `windows`, attempt 1:
`Dirused.Tests.ProgramPurgeTests.RootSharedOpenDoesNotBlockConfirmDelete` failed with
`System.IO.IOException: The process cannot access the file '\\?\C:\Users\runneradmin\AppData\Local\Temp\dirused-purge-<guid>'
because it is being used by another process` from `Directory.Delete` at `ProgramPurgeTests.cs:131` (the `finally`). The test's
assertions had passed; only cleanup failed. Attempt 2 of the same run passed. `cf07ace` adds only `TaskXml.cs` and its Portable
tests. No failure of this test in the previous 30 runs.

## Likely cause

The test opens `using var watcher = new FileSystemWatcher(dir) { EnableRaisingEvents = true }` inside `try`. The watcher is
disposed when the `try` block ends, but on Windows the directory handle is released only after its pending overlapped read
completes, which can be after `finally` starts `Directory.Delete(dir, true)`.

## Fix (proposed)

Test-only: in that test's `finally`, retry `Directory.Delete(dir, true)` on `IOException` a few times with a short sleep (for
example 5 × 100 ms), or use the suite's scratch-cleanup helper if one exists with retry. No product change.
