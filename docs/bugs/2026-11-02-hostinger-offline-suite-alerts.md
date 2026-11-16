# Bug: OfflineSuiteRunIncomplete and OfflineSuiteFailing on ubuntu-hostinger

**Status:** LANDED — fix `2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md` is VERIFIED; live check that the nightly suite is green owed (grooming 2026-11-12, operator); was: ROOT CAUSE FOUND 2026-11-06 — still firing; fix spec `docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md`
**Priority:** P2
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Nightly offline test suite failing on `ubuntu-hostinger` due to missing `pyyaml` (test-only failure, no production outage or data loss)); Claude proposed P2. Claude's higher P2 stands until the operator decides.
**Triage:** status corrected — grooming 2026-11-12, operator. Priority: operator kept Claude's P2 over Argon's P3.
**Waiting on:** live check — since 2026-11-12
**Filed:** 2026-11-02
**Detected by:** operator Gmail Alertmanager screenshot (messages visible Nov 1–2)
**Branch:** k3d-manager-v1.43.14
**Area:** monitoring / alerting / cluster operations

## Observed failure

Correlate both alerts to individual run IDs and timestamps; inspect runner exit codes, test artifacts, suite completeness and last successful run. Determine whether one incomplete run produces both alerts and whether failures are test defects or infrastructure failures.

## Evidence and limitations

The operator screenshot shows a FIRING Alertmanager email for this alert family. This is not live cluster evidence; the underlying cause, exact impacted objects, duration, and current firing state remain unverified. No production remediation was performed.

## Investigation

1. Query Alertmanager for current alerts and full labels, including job_name, namespace, instance and timestamps.
2. Correlate with Prometheus series and the owning component's recent execution logs, events and configuration.
3. Check existing bug documents and recent changes before proposing a fix; link related incidents and avoid duplicate root-cause work.
4. Identify root cause, blast radius, safe mitigation and regression test. Preserve evidence before deleting Jobs or resetting alerts.

## Acceptance

- [ ] Capture actual failing resource/run IDs, timestamps and diagnostic evidence.
- [ ] Reproduce or independently verify the failure mode and root cause.
- [ ] Implement or document safe remediation with regression coverage.
- [ ] Confirm healthy subsequent execution and alert resolution using live evidence.
- [ ] Record human intervention and link any related bug or plan.

**Note:** Initial triage; not a confirmed diagnosis or a claim that remediation has occurred.

## Prior-art / duplication check (2026-11-02)

Related: `docs/bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md` (LIVE-VERIFIED, introduced `OfflineSuiteRunIncomplete`), `docs/bugs/2026-10-15-offline-suite-failing-no-email-after-40m.md` (OPEN, alert delivery failure rather than test failure), `docs/bugs/2026-10-05-offline-tests-rotted-on-v1-41-0.md` (FIXED) and Oct 28 offline-suite verification documents. These explain alert semantics and earlier incidents but **do not yet identify the Nov 1 failing test cases**. Correlate run IDs, latest test output and metrics; if this is a repeat of an existing failing test, update that bug rather than creating parallel remediation work.

## Read-only M5 check, 2026-11-06 about 17:40Z

- The rules run on the Hostinger Prometheus, not the hub's, and route to `platform-warning` on its own Alertmanager. The hub's Alertmanager never lists them.
- `OfflineSuiteFailing` and `OfflineSuiteRunIncomplete` are active from 2026-10-29 12:44Z and `OfflineSuiteStale` from 2026-11-04 23:42Z. They are one failure, not three: the nightly `make test-all` on the M5.
- Last run 2026-11-06 about 12:36Z: 29 of 1995 failed, exit 2, run incomplete. Last pass 2026-10-28 22:42Z.
- The agent's log has 125 `No module named 'yaml'` lines. Not every one of the 29 is proven to be this cause; whatever remains after the fix gets its own bug.
