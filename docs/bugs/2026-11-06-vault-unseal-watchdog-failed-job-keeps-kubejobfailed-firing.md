# Bug: one failed vault-unseal-watchdog Job has kept KubeJobFailed firing since the cutover

**Status:** OPEN — observed 2026-11-06 on the M5
**Priority:** P3
**Approval:** pending
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md`; `docs/bugs/2026-10-24-platform-ops-notifications-slack-url-lost-on-hub-rebuild.md` (noted it as "Separate, not filed")

## Symptom

`KubeJobFailed` for `secrets/vault-unseal-watchdog-29889925` has fired since 2026-10-30T21:44Z. The Job's condition is `DeadlineExceeded: Job was active longer than specified deadline`. Later runs succeed, such as `vault-unseal-watchdog-29899625`, Complete 1/1 in 3s.

## Cause

The failed Job ran during the M5 cutover, around 2026-10-30 21:25Z, when Vault was coming up. A failed Job from history stays until it is deleted or aged out, so one old run holds the alert for days. Why this CronJob keeps it so long has not been read.

## Files

- `scripts/etc/vault/unseal-watchdog.yaml.tmpl`
- `scripts/tests/lib/hostinger_vault_watchdog_acceptance.bats`

## Fix direction

Confirm the CronJob's history settings. Either let a later success clear the old failure, or give the Job a TTL. The immediate clear is deleting that one Job, which the operator should approve.

## Acceptance

```yaml
must:
  - id: M1
    text: "A failed watchdog Job followed by a successful run no longer keeps KubeJobFailed firing beyond the configured TTL."
must_not:
  - id: N1
    text: "A watchdog that keeps failing still alerts (paired with M1)."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, text: "Manifest test of the TTL setting, red on the pre-fix commit; N1 by a test that the alert rule stays unchanged."}
  - {id: E2, proves: [M1], kind: live, text: "After deploy, no KubeJobFailed for this CronJob once the TTL has passed."}
interface:
  - "namespace: secrets"
  - "CronJob: vault-unseal-watchdog"
```
