# Alerting Guide

Alertmanager uses a default-deny route tree. The root route sends unmatched alerts to
`null`, so a new PrometheusRule is not delivered until it is either `severity: critical`
or added to an explicit child-route matcher.

## Receivers

- `null` discards alerts. It is the root default and also intentionally receives
  `TrivyCriticalVulnerabilityDetected` before the critical route.
- `sms-critical` sends `severity = critical` alerts to the configured SMS gateway.
- `sms-critical` sends a resolved text naming the alert and where it recovered, as well as the
  initial firing text. The `platform-warning` email receiver also names resolved alerts.
- `platform-warning` emails the operator's `ALERTMANAGER_GMAIL_FROM` mailbox for the
  explicitly allowlisted warning alerts: `KubeJobFailed`, `KubeJobNotCompleted`,
  `E2EVerificationFailing`, `E2EVerificationStale`, and
  `PrometheusDuplicateTimestamps`.
- ACG sandbox criticals email through `platform-warning`; only hub criticals text through
  `sms-critical`.

Child routes are first-match. The ACG sandbox critical route must remain before the
general `severity = critical` SMS route.

## Triage

| Symptom | Check |
|---|---|
| Alert fires in Prometheus but no notification arrives | Check the Alertmanager route matcher and receiver, not the Prometheus rule. An unmatched warning alert falls through to the root `null` receiver. |
| A critical alert is not sent by SMS | Check that the `severity = critical` route remains before later child routes. |
| A platform warning has no email recipient | Check `ALERTMANAGER_GMAIL_FROM` and the rendered `platform-warning` receiver. |

## Verification

From the repository root, verify the focused configuration suite and documentation links:

```bash
bats scripts/tests/plugins/alertmanager_config_secret.bats
make test
make check-doc-links
make test-alertmanager-behaviour
```

To re-render and apply only the hub Alertmanager Secret after changing the template, use
`make alertmanager-config`; it reads the Alertmanager credentials from Vault and never prints the
rendered configuration.

The operator verifies the deployed route tree and a delivered `KubeJobFailed` email after
deployment; this guide covers the repository-side checks only. The behaviour test renders the
real template with dummy recipients, rewrites email delivery to a local HTTP sink, scales only
the test timers, and runs Alertmanager v0.27.0 in Docker. It never sends real email or SMS.
