# dirused `/all` adds the local machine's drives even when remote targets are given

**Status:** OPEN — fix in wilddog64/dirused#10 (ef6c0d1), not yet on main; verified by Claude offline (red at 6a99c36, CI green at ef6c0d1) and on the dirused-dev VM (`docs/dirused/evidence/2026-11-16-m1c-a-live-vm.txt`)
**Priority:** P3 (proposed; Argon classification pending) — extra rows for the machine running dirused mixed into a fleet report; nothing is missing; workaround: leave out `/all` when targets are listed
**Introduced by:** wilddog64/dirused d86655b (M1b phase 0; `/all` = all fixed local drives in `TargetResolver`)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-16 (operator, from the office, 2026-11-17: `dirused /summary /file servers.list` shows all four hosts)
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

## Decision (operator, 2026-11-16)

"all drive for each target but excluded the host that runs binary. if dirused /all /summary . then show host all drive."

- **`/all` with no targets** (`dirused /all /summary`): every fixed drive on the machine running dirused, as today.
- **`/all` with targets** (positional or from `/file`): every drive (admin share) on each target host, and nothing from the machine running dirused.
  A share target such as `\\host\d$` widens to all admin shares on `host`; a bare `\\host` already means that.
- Help text changes to match: "/all  all drives: local when no targets, else every drive on each target".

## You will see / It failed if (updated)

- **You will see:** `dirused /all /summary /file servers.list` lists every drive of each listed host and no local drive; `dirused /all /summary` lists the local drives.
- **It failed if:** a run with targets plus `/all` prints a local drive of the machine running dirused, or leaves out a drive of a target host.
