# Bug: a rotator whose Slack notice fails says nothing, so a revoked webhook hides every rotation

**Status:** FIXED — `a5ffefb0` (Codex; Claude review, independent verifier PASS; restore trap now disarmed before the notice); live check pending
**Priority:** P3
**Severity:** low — passwords rotate correctly; the operator is not told, and nothing shows the notice failed
**Approval:** operator, 2026-10-31 ("got ahead to file rotator bugs and dispatch to Luna")
**Filed:** 2026-10-31
**Detected by:** Claude, after the operator found the Grafana password changed on the M5 hub
**Affected:** `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml`, `argocd-credential-rotator.yaml`, `keycloak-credential-rotator.yaml`, `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

The monthly rotators ran on the M5 at 2026-11-01T00:00Z. `grafana-credential-rotator-29891520` and
`argocd-credential-rotator-29891520` both completed; Vault `secret/observability/grafana` went to version 2 and
matches the synced Kubernetes secret. Each job's whole log is one line: `curl: (22) The requested URL returned
error: 404`. No Slack message arrived, so the operator learned of the rotation only when the old Grafana password
failed.

Claude probed the webhook URL in `platform-ops/platform-ops-notifications` with an empty JSON body (Slack posts
nothing for that): `http=404 no_service`. The incoming webhook is revoked. Replacing it is an operator action
(new webhook in Slack, update the Keychain record, `make platform-ops`) and is out of scope for this fix.

## Root cause

Every rotator posts with `curl ... >/dev/null || true`. A failed post leaves at most curl's bare error line, which
does not say what failed or that a notice was lost, and the job still succeeds.

## Fix

1. In each rotator, when the Slack post fails, log one line naming the failure, for example
   `WARN slack notice not delivered: HTTP 404 no_service`. Include the HTTP status and Slack's short response body
   (truncated to 64 characters). Never print the webhook URL.
2. When no webhook URL is configured, log `WARN slack notice skipped: no webhook configured`.
3. The job still exits 0 when the rotation succeeded. Do not fail the job on a notice failure: a failed rotator job is
   retried (`backoffLimit: 1`) and would rotate the password a second time.
4. Keep the existing rotation logic and the existing success message text unchanged.

## Files

- `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml`
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml`
- `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml`
- `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`
- `scripts/tests/plugins/platform_ops_rotators.bats`
- `scripts/tests/plugins/ldap_password_rotator.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not print, log or echo the webhook URL, any password, or any token.
- Do not make the job fail or retry on a notice failure.
- Do not touch `acg-expiry-cronjob.yaml` or the plugin scripts in this fix.

## Acceptance

```yaml
must:
  M1: when the Slack post returns a non-2xx status, each rotator logs a line containing "slack notice not delivered" and the HTTP status
  M2: when no webhook URL is configured, each rotator logs "slack notice skipped"
  M3: when the post succeeds, no WARN line about the notice is logged (paired control for M1)
must_not:
  N1: the webhook URL never appears in the rotator's output, including on failure
  N2: a notice failure never makes the rotator exit non-zero after a successful rotation
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see each rotator's notice code run against a curl stub that returns 404 "no_service", one that
      returns 200, and an empty URL; the 404 case logs the WARN line with the status, the 200 case logs none, and
      the stub's URL (a unique marker string) never appears in output. The curl stub's 404 body is the real Slack
      reply captured 2026-10-31 from the M5 hub ("no_service"). M1 and N1 are red against the pre-fix code.
    what: bats scripts/tests/plugins/platform_ops_rotators.bats scripts/tests/plugins/ldap_password_rotator.bats
  E2:
    proves: [M1]
    kind: live
    intent: You will see a manual run of one rotator on the hub log the WARN line while the webhook is still revoked.
    what: operator or Claude, kubectl create job --from=cronjob/<rotator>, then kubectl logs
interface:
  - the notice block inside each rotator's container script (env/secret platform-ops-notifications slack-incoming-webhook-url)
```
