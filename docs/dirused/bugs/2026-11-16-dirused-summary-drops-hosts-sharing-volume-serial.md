# dirused `/summary` silently drops remote hosts whose volume has the same serial number as another host's

**Status:** LANDED — fix ef6c0d1 merged in 784e1a6 (wilddog64/dirused#10, 2026-11-17T01:08Z), released in v0.0.2 (pre-release, win-x64 + win-arm64 zips, run 43993540322); was OPEN, fix in #10 not yet on main; verified by Claude offline (red at 6a99c36, CI green at ef6c0d1) and on the dirused-dev VM (`docs/dirused/evidence/2026-11-16-m1c-a-live-vm.txt`)
**Priority:** P2 (proposed; Argon classification pending) — the summary leaves out hosts with no error and no warning, so the report looks complete when it is not; workaround: run without `/summary`, or one host per run
**Introduced by:** wilddog64/dirused d302f65 (M1b phase 1b fleet runner: `/file`, `/summary`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-16 (operator, from the office, 2026-11-17: `dirused /summary /file servers.list` shows all four hosts)
**Prior art:** `docs/dirused/bugs/` exact-slug glob, no match; `make find-similar-docs` not run (vector store context `k3d-k3d-cluster` missing) — none above threshold
**Filed:** 2026-11-16 (operator report, screenshot)

## What the operator saw

`servers.list` holds four targets: `\\us03l12agt01\d$`, `\\us03l12agt02\d$`, `\\us03l11agt11\d$`, `\\us03l11agt12\d$`.
`dirused /summary /file servers.list` printed two lines (agt01 and agt11) and nothing at all for agt02 or agt12, not even an error line.

## Cause (read from source, main 1926d2e)

`SummaryRenderer.Prepare` (src/Dirused.Common/Renderers/SummaryRenderer.cs:27-37) removes duplicate volumes using the key
`serial:{Volume.SerialNumber}` (or `drive:{Volume.Drive}` when the serial number is 0). The key leaves out the host. Machines built from
the same image (the agt01/02 and agt11/12 pairs are clones) carry the same D: volume serial number. Every host after the first is dropped as a
"duplicate", and only complete results go through this path, so nothing reports the drop. The 1.0% and 0.8% rows match one host per pair.

The duplicate check exists so that two local drive letters (or a drive plus a mount point) on one machine count once. That reasoning applies within one
machine, not across machines.

## You will see / It failed if

- **You will see:** one summary line per reachable target in `servers.list` (four lines for the file above), even when two hosts share a volume serial number.
- **It failed if:** a reachable host is missing from the summary and no error line names it.

## Fix direction (for the spec, not decided)

Add the target's host (its UNC server, or the local machine) to the duplicate key, so duplicates are removed only within one host. JSON and CSV output with `/summary`
run through `Prepare` as well; check whether they drop hosts in the same way.

## Evidence: single-host runs (operator, 2026-11-16)

- `dirused /summary \\us03l12agt02\d$` on its own: `used 9.1 GB, free 190.7 GB, total 199.9 GB, 4.6% used`. So agt02 is reachable and its usage differs from agt01 (1.0%),
  yet the `/file` run left it out. The combined run printed no error line at all, so no failing node hid it. This matches the duplicate check on serial number only.
- `dirused /summary \\us03l12agt11\d$` returned `UNREACHABLE (53)`. That name is l**12**agt11; the list holds l**11**agt11, which the combined run did show, so this result does not bear on the bug.
