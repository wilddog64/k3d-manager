# Bug: `make test-all` on a dev machine overwrites the nightly offline-suite metrics

**Status:** LANDED — `64a8de5c` (Flash, v1.45.0; plan `docs/plans/test-all-metrics-explicit-pushgateway.md`); captured 2026-11-14 by Claude (alert investigation)
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** live check — since 2026-11-18 (E2 on the M4 by Claude; E3 after promote: operator re-runs `make install-test-metrics` on the hub)
**Triage:** carry → v1.45.0, batched with install-test-metrics (same files) — operator grooming 2026-11-15 ("Accept as shown")
**Release:** v1.44.1 (operator approved Claude's recommendation, 2026-11-14)
**Introduced by:** unknown
**Should have been caught by:** review
**Prior art:** exact-slug glob: none; related `docs/bugs/2026-11-02-hostinger-offline-suite-alerts.md`, `docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md` (read, different root cause); `make find-similar-docs` not run (vector store unreachable from the M4)

## Symptom

OfflineSuiteRunIncomplete is firing on ubuntu-hostinger, but the series it reads comes from a test run on a dev machine,
not from the nightly suite. `make test-all` always publishes to `K3DM_PUSHGATEWAY_URL`, default `localhost:9091`
(`Makefile:1646`, `bin/k3dm-test-metrics:17`). On the M4, 9091 is a kubectl port-forward to the hostinger Pushgateway
(pid 48769, 2026-11-14), so any test-all run there replaces the nightly group.

## Evidence (alert investigation agent, read-only, 2026-11-14; spot-checked by Claude)

- 00:11:52Z push: from the makefile_test_all.bats fixture of an early Part B revision (pass1, pass2, pass_py; log
  `/private/tmp/k3dm-test-all-1794615110.log`). It set `k3dm_test_last_success_timestamp_seconds=1794615110` from a fake
  3-case "complete" run, giving OfflineSuiteStale a false success. (The current Part B revision sets `127.0.0.1:9`.)
- 18:51:42Z push (total 460, failed 0, incomplete): likely the Part B worktree's own test-all run (10:34–10:40 PST log),
  not proven. It cleared OfflineSuiteFailing and OfflineSuiteVacuous, so the RunIncomplete firing now describes that run.

## Fix direction

Publish only when the URL is set explicitly (the nightly LaunchAgent sets it), or put the host in the Pushgateway group
so a dev run cannot replace the nightly group. Needs a spec with Contract readers (the nightly plist template, the
`k3dm_test_*` rules and dashboards).

## Decision (operator, 2026-11-14: "approve")

P2 confirmed. Option (a): `make test-all` and `bin/k3dm-test-metrics` publish only when `K3DM_PUSHGATEWAY_URL` is set
explicitly. The nightly LaunchAgent sets it; a dev run prints "metrics not published (K3DM_PUSHGATEWAY_URL unset)" and
writes only the local log. Rejected (b), a per-host Pushgateway grouping key, because it changes every `k3dm_test_*` series
and the rules and dashboards that read them. Target v1.44.1. Needs a spec with Acceptance and Contract readers (plist
template, `Makefile:1646`, `bin/k3dm-test-metrics:17`, the rules-acg file, the dashboard). Dispatch after Part B frees the
Makefile.
