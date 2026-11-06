# Bug: TargetDown for ubuntu-k3s pushgateway

**Status:** CLOSED 2026-11-06 — not recurring in the history available; the Nov 1-2 cause cannot be recovered
**Priority:** P2
**Filed:** 2026-11-02
**Detected by:** operator Gmail Alertmanager screenshot (messages visible Nov 1–2)
**Branch:** k3d-manager-v1.43.14
**Area:** monitoring / alerting / cluster operations

## Observed failure

Check target discovery and scrape errors, pushgateway service/pod/endpoints, remote connectivity, firewall/tunnel, and whether ubuntu-k3s sandbox is intentionally stopped. Avoid treating expected ephemeral shutdown as production outage.

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

Related: `docs/bugs/2026-10-08-cleanup-stale-sandbox-kills-hostinger-pushgateway-forward.md` (FIXED, concerns Hostinger Pushgateway port-forward), plus `docs/bugs/2026-10-15-acg-up-prometheus-forward-missing-after-success.md`. Screenshot's target is `ubuntu-k3s` with `job=pushgateway`, **not explicitly Hostinger**. Do not assume an identical regression. Verify actual target endpoint, expected sandbox lifecycle and service ownership; consolidate with older bug only if matching cause is proven.

## Read-only M5 check, 2026-11-06 about 17:40Z

- The hub Prometheus keeps 3 days, so its history starts 2026-11-03 12:00Z and does not reach the screenshot.
- Since then `TargetDown` has fired only for `job=federate-acg cluster=acg`, not for a pushgateway. Both pushgateway targets report `up 1`.
- The `federate-acg` alert is a separate matter: `host.internal:19190` refuses connections, active since 2026-11-04 10:00Z, and nothing listens on 19190 on the M5. Whether a sandbox should be up then was not checked.
