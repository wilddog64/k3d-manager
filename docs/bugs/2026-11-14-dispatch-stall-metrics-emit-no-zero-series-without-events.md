# Bug: dispatch stall metrics emit no zero series for a release without stall events

**Status:** OPEN — captured 2026-11-14 by Claude (stall-D live check E5)
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Introduced by:** 09d12e68
**Should have been caught by:** spec
**Prior art:** exact-slug glob: none; parent `docs/bugs/2026-11-14-dispatch-stall-d-dashboard.md` (read, this is its E5 gap); `make find-similar-docs` not run (vector store unreachable from the M4)

## Symptom

The stall-D spec's E5 expected "the Stall recovery row with zeros for v1.44.0". `_stall_scope_metrics`
(`bin/k3dm-dispatch-metrics:925-931`) builds `by_version` only from stall events, so a release with none gets no
`k3dm_dispatch_stall_*{version=...}` series at all. Live on the hub on 2026-11-14, the four stat panels read 0 only through
`or vector(0)`. "Diagnoses by result", "Operator decisions" and "After resume" show no data, and the Incidents
table is empty. A dashboard with no data looks the same as a broken publisher.

## Fix direction

Seed `by_version` with every version seen in the ledger (or the current release), so the counters render as 0. Offline
test: a ledger with no stall events produces `k3dm_dispatch_stall_incidents{...version="v1.44.0"...} 0`. Do not
dispatch while the dispatch-metrics file is busy.
