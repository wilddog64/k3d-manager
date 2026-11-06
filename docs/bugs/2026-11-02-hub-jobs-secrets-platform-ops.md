# Bug: KubeJobFailed in secrets and platform-ops

**Status:** OPEN — narrowed 2026-11-06: one stale Job still fires, and `acg-expiry-check` failure bursts have no logs left
**Priority:** P2
**Filed:** 2026-11-02
**Detected by:** operator Gmail Alertmanager screenshot (messages visible Nov 1–2)
**Branch:** k3d-manager-v1.43.14
**Area:** monitoring / alerting / cluster operations

## Observed failure

Multiple alerts on Nov 1 in secrets and platform-ops. Enumerate distinct failed Job names, owners, creation/finish times, exit codes, events and pod logs; separate recurring failures from retained historical Job objects. Check whether these failures block Vault/secrets or scheduled platform automation.

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

Earlier `KubeJobFailed` bugs include `docs/bugs/2026-10-02-ldap-password-rotator-never-succeeds.md` (identity namespace), `docs/bugs/2026-10-05-argocd-cve-scan-exits-nonzero-when-no-newer-chart.md` (platform-ops), and `docs/bugs/2026-10-21-hermes-minio-upload-status-not-visible.md` (notification visibility). **Same alert name does not establish same Job/root cause**. Screenshot provides namespaces `secrets` and `platform-ops` but not Job names. Compare owning Jobs to these records and Hermes R10 superseded-job handling before implementing any fix; merge back to prior bug if matched.

## Read-only M5 check, 2026-11-06 about 17:40Z

- Only `secrets/vault-unseal-watchdog-29889925` still fires, from 2026-10-30. It is a retained Job object; its fix is `dd248543`. Deleting it needs the operator's approval.
- `platform-ops/acg-expiry-check` failed in bursts, its Job names decoding to about 2026-11-01 23:00Z to 2026-11-02 00:00Z and 2026-11-04 08:30Z to 12:30Z. It is not firing now and the latest three runs complete in 3s.
- Those Jobs and their logs are gone, so the cause of the bursts is not established. Check the next burst while its pods exist.
