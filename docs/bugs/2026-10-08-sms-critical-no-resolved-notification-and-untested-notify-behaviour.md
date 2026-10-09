# SMS pages never say "resolved", and nothing tests deduplication, repeats or recovery

**Filed:** 2026-10-08, Claude (operator: "let's do that at v1.44.0. text is free so that's fine")
**Branch:** target **v1.44.0**. Bug docs are exempt from the 5-plan cap; v1.44.0 already has 5 plan files.
**Status:** OPEN — specified; not started
**Priority:** P2 — a page with no "all clear" means checking a dashboard to learn a problem ended
**Severity:** Medium
**Component:** `scripts/etc/prometheus/alertmanager.yaml.tmpl`, new behaviour test, `scripts/plugins/observability.sh` (apply path)
**Related:** `docs/bugs/2026-09-20-sms-alert-body-is-unidentifiable.md` (made the SMS body legible; iterates `.Alerts.Firing`), `docs/plans/v1.42.0-host-disk-space-sensor.md` (the SMS proof)

## Symptom

The 2026-10-08 SMS proof (fake `host="smstest"` disk) showed what is and is not covered:

| Behaviour | Today |
|---|---|
| Deduplication | Works live. Prometheus re-sent the firing alert every evaluation; exactly one text went out (`alertmanager_notifications_total{integration="email"}` 21 → 22). There is no automated test for it. |
| Repeat | Configured as a 24h `repeat_interval` on the root route, which `sms-critical` inherits. It was never observed until the week-long `smstest` run (until 2026-10-15). Not tested. |
| Recovery | **Off.** `sms-critical` has `send_resolved: false` (`alertmanager.yaml.tmpl:42`, since v1.5.0 `faa00331`, with no recorded reason). `platform-warning` emails have `send_resolved: true`. Not tested. |

The existing BATS (`alertmanager_config_secret.bats`, `e2e_observability.bats`) only checks the
rendered configuration and its routing. Nothing exercises Alertmanager's actual behaviour.

## Root cause

1. `send_resolved: false` on `sms-critical`. The likely reason was text cost, but texts are free on
   the operator's plan (operator, 2026-10-08).
2. **A latent second bug that appears as soon as (1) is flipped.** The SMS `text:` body only ranges
   over `.Alerts.Firing`. That was correct for the 2026-09-20 legibility fix, but in a resolved
   notification `.Alerts.Firing` is empty. So the "all clear" text would carry only the subject,
   `[RESOLVED] … (0)`, with an empty body that names nothing. The `platform-warning` email has the
   same template shape, so its resolved emails are blank today too.

## Fix (spec for Codex)

### 1. Turn on SMS recovery

In `alertmanager.yaml.tmpl`, under `sms-critical`, change `send_resolved: false` to `send_resolved: true`.

### 2. Make resolved notifications name what recovered (both receivers)

Keep the firing block exactly as it is. After it, append a resolved block to both `text:` bodies:

```
{{ range .Alerts.Resolved }}RESOLVED {{ .Labels.alertname }}{{ if .Labels.severity }} [{{ .Labels.severity }}]{{ end }} on {{ if .Labels.cluster }}{{ .Labels.cluster }}{{ else }}unknown-cluster{{ end }}
where:{{ if .Labels.namespace }} ns={{ .Labels.namespace }}{{ end }}{{ if .Labels.instance }} instance={{ .Labels.instance }}{{ end }}{{ if .Labels.job }} job={{ .Labels.job }}{{ end }}
since: {{ .StartsAt.UTC.Format "2006-01-02 15:04 UTC" }} ended: {{ .EndsAt.UTC.Format "2006-01-02 15:04 UTC" }}
{{ end }}
```

Keep the SMS body short: no description line in the resolved block, because the firing text already
carried it. Follow the inline-template constraints in
`reference_alertmanager_inline_templates_no_sprig`: no Sprig functions such as `default`.

### 3. Behaviour test: real Alertmanager, fake receiver

Add a new test `scripts/tests/observability/test_alertmanager_notify_behaviour.py` (pytest).

**Setup:**
- Run the pinned image `quay.io/prometheus/alertmanager:v0.27.0`, the same one the hub runs.
  Keep the tag in one variable.
- Render the **real** template with dummy envsubst values.
- Rewrite only the delivery and the timers in Python:
  - Each receiver's `email_configs` becomes `webhook_configs` pointing at a local HTTP sink, keeping
    that receiver's `send_resolved` value.
  - Scale the timers down: `group_wait` 1s, `group_interval` 2s, `repeat_interval` 6s.
- Leave the route tree, the matchers and `inhibit_rules` untouched. Those are what the test is
  checking.
- Post alerts through `POST /api/v2/alerts`.

**Assertions:**

| Test | Steps | Expect |
|---|---|---|
| dedup | Post the same `severity=critical, cluster=hub` alert 5 times within 1s | exactly **1** firing notification at the `sms-critical` sink |
| repeat | Keep re-posting it (as Prometheus does) for about 15s | a **second** firing notification after `repeat_interval`, and no more than `ceil(15/6)+1` in total |
| recovery (SMS) | Post it with `endsAt` in the past | a notification with `status: resolved` at the `sms-critical` sink |
| recovery (email) | Same steps with a `severity=warning` alert | `status: resolved` at the `platform-warning` sink |
| routing guard | A critical alert with `cluster=acg` | goes to `platform-warning`, **not** `sms-critical` (sandbox alerts stay email-only, per `feedback_sandbox_alerts_email_only`) |
| Trivy guard | `alertname=TrivyCriticalVulnerabilityDetected, severity=critical` | no notification at any sink (`null`) |

Separately, add a template test: render both receivers' `text:` with a resolved-only alert using
`amtool template render` (available in Alertmanager v0.27.0 and later). The output must contain
`RESOLVED` and the alert name. **RED:** this must fail against the pre-fix template, where the body
renders empty.

**Running it:**
- The test needs Docker, so it is skipped when Docker is unavailable. The skip names the reason.
- Add `make test-alertmanager-behaviour` and a CI job on `ubuntu-latest`, which has Docker. Pin the
  actions, and set the workflow to `permissions: contents: read`.
- **RED:** the recovery (SMS) test and the template test must fail on the pre-fix template. Paste
  the failure names.

### 4. A lightweight apply path (optional, same release)

Today the template only reaches the hub through `make observability`, which is the full stack
redeploy, or through its ACG twin. Add `make alertmanager-config`, mirroring
`make prometheus-rules`. It re-renders the template with the same `envsubst` variable list and
applies the `alertmanager-smtp-secret` Secret, reusing the code at `observability.sh:81` by
extracting a helper rather than copying it.
- The operator runs it, because it reads credentials.
- It must never echo the rendered config, which contains the Gmail app password.

### 5. Docs

- `docs/guides/` (the Alertmanager or observability guide): SMS now sends a resolved text; how to
  run the behaviour test.
- CHANGELOG.

## Live verification (operator)

1. Run `make alertmanager-config`, or `make observability`.
2. Confirm the live config reads back `send_resolved: true` for `sms-critical`, using
   `amtool config show` filtered to `send_resolved`. Don't print anything else.
3. Fire a test alert, using the `k3dm-disk-smstest` Pushgateway job method from the disk-sensor plan.
   Expect a firing text.
4. Delete the job. Expect a `[RESOLVED]` text naming `HostDiskSpaceCritical` and `smstest`.

## Timing note

The `smstest` series pushed on 2026-10-08 is kept firing until **2026-10-15** on purpose. If
v1.44.0 is not live by then, deleting it on 10/15 resolves **silently**: no text, as today. If
recovery should be demonstrated on that delete, ship item 1 and item 2 first, as a bug fix.

## What NOT to do

- Do not lower `repeat_interval` or `group_wait` in the real config. The scaled timers exist only
  in the test copy.
- Do not send real email or SMS from any test.
- Do not print, log or commit the rendered config with real credentials.
- Do not change the route tree or matchers in this fix.
