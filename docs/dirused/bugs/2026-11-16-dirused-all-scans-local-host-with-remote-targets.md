# dirused `/all` adds the local machine's drives even when remote targets are given

**Status:** OPEN — captured, not triaged
**Priority:** P3 (proposed; Argon classification pending) — extra rows for the machine running dirused mixed into a fleet report; nothing is missing; workaround: leave out `/all` when targets are listed
**Introduced by:** wilddog64/dirused d86655b (M1b phase 0; `/all` = all fixed local drives in `TargetResolver`)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-16
**Prior art:** `docs/dirused/bugs/` exact-slug glob, no match; `make find-similar-docs` not run (vector store context `k3d-k3d-cluster` missing) — none above threshold
**Filed:** 2026-11-16 (operator report)

## What the operator wants

"/all should not include the host that runs the binary, only the targets when targets are specified."

## Current behaviour (read from source, main 1926d2e)

`TargetResolver` (src/Dirused.Core/Targets/TargetResolver.cs:19) turns `/all` into every fixed, ready local drive (`DriveInfo.GetDrives()`),
whatever other targets are given. With `/file` or with `\\node` targets, the local machine's C:, D:, ... show up next to the remote hosts.
The help text says "All fixed local drives", so this matches the documented behaviour; the meaning of `/all` itself has to change.

## You will see / It failed if

- **You will see:** with one or more targets (positional or from `/file`), `/all` adds no local drives. On its own, `dirused /all` still scans the local fixed drives.
- **It failed if:** a run with remote targets plus `/all` prints a row for a local drive letter of the machine running dirused.

## Open question for the operator

With targets given, should `/all` mean "all admin shares on each target host" (what `\\node` already does for a bare host), or simply be ignored?
