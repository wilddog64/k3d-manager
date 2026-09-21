# SMS alert bodies cannot identify what broke, and the hub lost its Alertmanager config entirely

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High — alerts are delivered but unactionable, and SMS delivery is currently dead.

## Symptom

The operator received a text message whose entire body was:

```
target disappeared from prometheus target discovery
```

No alert name, no severity, no cluster, no namespace, no component, no timestamp. The reported
reaction — "I am not sure anyone can understand it" — is correct: the message is not merely terse,
it is **ambiguous in principle**.

## Root cause 1 — the body carries the least informative field available

`scripts/etc/prometheus/alertmanager.yaml.tmpl:29` (before this fix):

```yaml
text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

The SMS body is `summary` and nothing else. Discarded: `alertname`, `description`, `severity`,
`cluster`, `namespace`, `pod`, `instance`, `job`, and `StartsAt`. Alerts in the group are
concatenated with no separator, so two firing alerts produce one run-on sentence.

## Root cause 2 — that summary is a shared constant across two unrelated rules

Measured against the live rule set (`/api/v1/rules`, 134 alerting rules):

| Rule | `summary` | `description` |
|---|---|---|
| `KubeAPIDown` | `Target disappeared from Prometheus target discovery.` | `KubeAPI has disappeared…` |
| `KubeletDown` | `Target disappeared from Prometheus target discovery.` | `Kubelet has disappeared…` |

Both are `absent(up{job=…} == 1)` with `for: 15m` and `severity: critical`. Only the
`description` distinguishes them, and the `description` was never sent. So the body could not name
the failing component even in principle.

A full sweep for shared summaries found eight other collisions, but all eight are the *same* rule
emitted at two severities (`KubePersistentVolumeFillingUp`, `KubeCPUOvercommit`,
`KubeClientCertificateExpiration`, …), where a shared summary is correct. `KubeAPIDown`/
`KubeletDown` is the only genuine cross-rule ambiguity.

## Root cause 3 — the Subject was empty, not merely dropped

```yaml
Subject: '[ALERT] {{ .GroupLabels.alertname }}'
```

The root route declared no `group_by`. With `group_by` unset, Alertmanager groups **all** alerts
into a single group whose `GroupLabels` is empty — so `.GroupLabels.alertname` rendered as the
empty string. The Subject was `[ALERT] ` regardless of gateway behaviour. Email-to-SMS gateways
also routinely drop subjects, so the identifying half was lost twice over.

## Root cause 4 — hub alerts carry no `cluster` label

`scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml:65` sets
`externalLabels: {cluster: ubuntu-k3s}`. The **hub** values file set no `externalLabels` at all.
Our own PrometheusRules hardcode `cluster: hub` in their rule labels, so they were attributable;
every upstream rule — including the two above — was not. An SMS about `KubeAPIDown` could not say
which cluster it came from.

## Separate, larger finding — SMS delivery is dead on the hub right now

The Alertmanager CR references the config:

```
$ kubectl -n monitoring get alertmanager kube-prometheus-stack-alertmanager -o jsonpath='{.spec.configSecret}'
alertmanager-smtp-secret
$ kubectl -n monitoring get secret alertmanager-smtp-secret
Error from server (NotFound): secrets "alertmanager-smtp-secret" not found
```

The secret was lost in the 2026-09-20 hub rebuild and nothing recreated it. The operator silently
fell back to a generated default config: the live root receiver is `"null"`, and
`sms-critical`/`smtp_smarthost` are **absent** from the running configuration. Three `critical`
alerts are firing and none can page.

This is the same disease as the ApplicationSet values-branch freeze and the inert `45s`
apiserver `scrapeTimeout`: **committed, wired, and not running.** The text the operator received
therefore predates the rebuild — the current Prometheus/Alertmanager pair started
`2026-09-20T23:55Z` with an empty notify log, and hostinger's long-lived stack never fired either
rule in 48h.

## Fix

**1 — Make the body self-identifying.** Identity first, so a truncating gateway keeps the useful
part: `alertname`, `severity`, `cluster`, then `description` (falling back to `summary`), then the
locating labels, then `StartsAt`. Iterate `.Alerts.Firing` so resolved entries cannot pad the
message.

**2 — Give the root route an explicit `group_by`** (`alertname`, `cluster`, `namespace`) so
`GroupLabels` is populated and the Subject is meaningful, and so one SMS covers one alert type on
one cluster rather than every critical alert at once.

**3 — Replace the two ambiguous upstream rules.** `defaultRules.disabled` (supported by chart
67.9.0 — its own commented example is literally `KubeAPIDown: true`) switches them off, and
`scripts/etc/prometheus/rules/kubernetes-control-plane.yaml` re-adds them with the same `expr`,
`for` and `severity`, plus summaries that name the component and descriptions that state the real
failure mode — a scrape slower than `scrape_timeout` is indistinguishable from an absent target,
which is exactly what misled triage on 2026-09-19.

Hub-only: `deploy_observability` applies `scripts/etc/prometheus/rules/` to the hub context only,
so disabling the rules in the ACG values would remove them with no replacement. Left untouched
there.

**4 — Add `externalLabels: {cluster: hub}`** to the hub values so every alert, ours or upstream, is
attributable. Prometheus does not overwrite a label an alert already carries, so rules that
federate `cluster: ubuntu-hostinger` keep their true origin.

## Verification performed

- `amtool check-config` on the rendered config: SUCCESS, 2 receivers, 1 inhibit rule.
- Inline templates compiled and executed against real live alert labels with a standalone Go
  harness, because `amtool check-config` validates only *file*-based templates and would not
  have caught an inline syntax error before send time. Rendered output for three cases —
  `KubeAPIDown`, `ServiceDown`, and an alert with no annotations at all.

## Definition of Done

- [x] SMS body names alertname, severity and cluster before any prose
- [x] `description` preferred over `summary`; graceful when both are absent
- [x] Root route has an explicit `group_by`
- [x] `KubeAPIDown`/`KubeletDown` summaries name their component
- [x] Hub Prometheus sets `cluster: hub` in `externalLabels`
- [x] Templates proven to compile and render, not merely parse as YAML
- [ ] `alertmanager-smtp-secret` recreated on the live hub and `sms-critical` present in
      `/api/v2/status`
- [ ] One real SMS received and legible

## What NOT to Do

- Do NOT use `default` in Alertmanager templates. Alertmanager does not ship sprig; only
  `toUpper`, `toLower`, `title`, `join`, `match`, `reReplaceAll`, `safeHtml` and friends exist.
  Use explicit `{{ if }}`.
- Do NOT rely on the Subject line reaching the phone. Email-to-SMS gateways drop it.
- Do NOT disable `KubeAPIDown`/`KubeletDown` without shipping a replacement — `absent()` rules are
  the only signal that a target vanished entirely.
- Do NOT treat a quiet Alertmanager as a healthy one. Confirm the receiver is in the **running**
  config, not just in git.
