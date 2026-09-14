# Bug: Alertmanager never uses `alertmanager-smtp-secret` — `configSecret` is at the wrong values path

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** OPEN — awaiting user go (enabling it sends real SMS)
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`, `scripts/tests/plugins/` (new BATS), `CHANGELOG.md`

## Problem

On 2026-09-14 the user ran `make alertmanager-secret`, then `make observability`, which created `monitoring/alertmanager-smtp-secret`. The live Alertmanager is unaffected:

```
kube-prometheus-stack-alertmanager configSecret=
```

Both values files put the key directly under `alertmanager:`:

```yaml
alertmanager:
  alertmanagerSpec:
    ...
  configSecret: alertmanager-smtp-secret
```

kube-prometheus-stack `67.9.0` only reads `alertmanager.alertmanagerSpec.configSecret`, together with `alertmanager.alertmanagerSpec.useExistingSecret: true`. The top-level key is silently ignored, so the chart keeps its generated default config (null receiver).

The line has been in place since `faa00331` (v1.5.0, 2026-05-31). SMS alerting for critical alerts has never worked.

## Impact of fixing

At filing time, 4 `severity=critical` alerts are firing (`TrivyCriticalVulnerabilityDetected`, namespace `platform-ops`). With `repeat_interval: 24h`, the fix sends SMS for these right away and then once a day. The alerts are real, but the noise is upstream-image driven; see `reference_trivy_critical_upstream_image_noise`. Decide with the user whether to route Trivy criticals to `null` first.

## Fix

### S1 — both values files

Old:

```yaml
  configSecret: alertmanager-smtp-secret
```

New (move under `alertmanagerSpec`, alongside its other keys):

```yaml
    useExistingSecret: true
    configSecret: alertmanager-smtp-secret
```

### S2 — guard for a missing secret

With `useExistingSecret: true` and no secret, the operator has no config to load. `deploy_observability` already skips secret creation when the Vault credentials are absent. Before landing S1, confirm the operator's behaviour when the secret is missing (the prometheus-operator falls back to an empty config, and Alertmanager stays up). If it does not fall back, have the no-credentials path create a null-receiver `alertmanager-smtp-secret`.

### S3 — tests

`yq` against both values files:
- `.alertmanager.alertmanagerSpec.configSecret == "alertmanager-smtp-secret"`
- `.alertmanager.alertmanagerSpec.useExistingSecret == true`
- `.alertmanager.configSecret == null`

## Definition of Done

- [ ] S1–S3 applied; `bats` on the new test passes.
- [ ] Live, after the observability app syncs: `kubectl get alertmanager -n monitoring -o jsonpath='{.items[0].spec.configSecret}'` = `alertmanager-smtp-secret`; the Alertmanager `/api/v2/status` config shows the `sms-critical` receiver.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT print or log the secret contents.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
