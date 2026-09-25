# Alertmanager's `null` root route silently drops every warning-severity alert

**Filed:** 2026-09-23
**Status:** FIXED 2026-09-23 in `a7135966` — Changes 1-3 implemented, unit-verified and
mutation-proven. **Not yet deployed**; the route tree in the live cluster is unchanged until
the operator re-renders the Alertmanager secret (see "Verification after deploy" below).
**Found while:** explaining why the CVE Auto-Patch Grafana dashboard is blank. The
`cve-remediation-verify` CronJob had failed 15 consecutive times and nothing notified the
operator.

## Summary

`cve-remediation-verify` (`*/15 * * * *`, namespace `platform-ops`) has been failing since the
hub rebuild on 2026-09-20. The detection chain is intact right up to the last hop:

| Hop | State | Evidence |
|---|---|---|
| Job fails | ✅ working | 3 `Failed` Jobs retained in `platform-ops` |
| kube-state-metrics exports it | ✅ working | `kube_job_failed{namespace="platform-ops"} 1` |
| `KubeJobFailed` rule exists | ✅ working | `kube-prometheus-stack-kubernetes-apps` group |
| Rule fires | ✅ working | `ALERTS{alertname="KubeJobFailed"} ... alertstate="firing"` |
| Alertmanager receives it | ✅ working | active, `silencedBy: []`, `inhibitedBy: []` |
| **Alertmanager routes it** | ❌ **dropped** | matches no child route → root receiver `'null'` |

So this is not a missing rule and not a missing metric. **It is a routing defect.**

## Root cause

`scripts/etc/prometheus/alertmanager.yaml.tmpl:8-20` makes the root route a default-deny:

```yaml
route:
  receiver: 'null'          # <-- everything unmatched is discarded
  routes:
    - matchers:
        - alertname = TrivyCriticalVulnerabilityDetected
      receiver: 'null'
    - matchers:
        - severity = critical
      receiver: sms-critical
```

There are exactly two ways for an alert to reach a human:

1. `severity = critical` → `sms-critical`, or
2. an alertname on the 5-name allowlist in the `AlertmanagerConfig` CR that adds the
   `cicd/k3dm-analyze/*` webhook routes (`ArgoCDAppDegraded`, `ArgoCDAppOutOfSync`,
   `ArgoCDImageUpdaterFlapping`, `TrivyOperatorScanJobFailures`,
   `TrivyCriticalVulnerabilityDetected`).

`KubeJobFailed` ships from kube-prometheus-stack with `severity: warning` and is on neither
list. It therefore lands on the root `'null'` receiver and is thrown away. **Every**
kube-prometheus-stack default rule is in the same position.

This is not specific to the CronJob. Measured against the live hub, these alerts are firing
right now and all of them are being discarded:

```
 43  analyze-webhook  sev=warning   TrivyCriticalVulnerabilityDetected
  3  NULL (dropped)   sev=warning   KubeJobFailed
  2  NULL (dropped)   sev=warning   KubeHpaMaxedOut
  2  analyze-webhook  sev=critical  TrivyCriticalVulnerabilityDetected
  2  NULL (dropped)   sev=warning   E2EVerificationFailing
  1  NULL (dropped)   sev=warning   PrometheusDuplicateTimestamps
  1  analyze-webhook  sev=warning   ArgoCDAppOutOfSync
  1  NULL (dropped)   sev=none      Watchdog
```

`E2EVerificationFailing` being on that list matters: the repo's own e2e alert has never been
deliverable either.

## Why no test catches it

`scripts/tests/plugins/alertmanager_config_secret.bats:26`
(`Alertmanager routes Trivy critical CVE alerts to null before SMS`) asserts that one alert
*is* routed to null. Nothing asserts that any alert is routed to a **real** receiver, so a
template in which every route ends at `'null'` would pass the suite.

## Fix plan

### Change 1 — a `platform-warning` receiver

Operational warnings need a destination that is not SMS (SMS is reserved for `critical`, and
43 firing Trivy alerts would make it useless). Send them to the operator's own mailbox, which
is already configured as `${ALERTMANAGER_GMAIL_FROM}`.

Add to `receivers:` in `scripts/etc/prometheus/alertmanager.yaml.tmpl`, after the
`sms-critical` entry:

```yaml
  - name: platform-warning
    email_configs:
      - to: '${ALERTMANAGER_GMAIL_FROM}'
        send_resolved: true
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} on {{ if .GroupLabels.cluster }}{{ .GroupLabels.cluster }}{{ else }}unknown-cluster{{ end }} ({{ .Alerts.Firing | len }})'
        text: |-
          {{ range .Alerts.Firing }}{{ .Labels.alertname }}{{ if .Labels.severity }} [{{ .Labels.severity }}]{{ end }} on {{ if .Labels.cluster }}{{ .Labels.cluster }}{{ else }}unknown-cluster{{ end }}
          {{ if .Annotations.description }}{{ .Annotations.description }}{{ else if .Annotations.summary }}{{ .Annotations.summary }}{{ else }}(rule carries no description){{ end }}
          where:{{ if .Labels.namespace }} ns={{ .Labels.namespace }}{{ end }}{{ if .Labels.job_name }} job_name={{ .Labels.job_name }}{{ end }}{{ if .Labels.pod }} pod={{ .Labels.pod }}{{ end }}{{ if .Labels.instance }} instance={{ .Labels.instance }}{{ end }}
          since: {{ .StartsAt.UTC.Format "2006-01-02 15:04 UTC" }}
          {{ end }}
```

Deliberately **no new environment variable**: `${ALERTMANAGER_GMAIL_FROM}` is already in the
`envsubst` allowlist at `scripts/plugins/observability.sh:78` and `:634`. Introducing a new
placeholder would require editing both call sites and would render as an empty `to:` on any
host where it is unset.

### Change 2 — route the alerts to it

Add a third child route, **after** the `severity = critical` route so a critical alert still
wins SMS. Routes are first-match; order is load-bearing.

```yaml
    - matchers:
        - alertname =~ "KubeJobFailed|KubeJobNotCompleted|E2EVerificationFailing|E2EVerificationStale|PrometheusDuplicateTimestamps"
      receiver: platform-warning
      group_wait: 5m
      group_interval: 2h
      repeat_interval: 24h
```

Scope of the allowlist, and why each is on it:

- `KubeJobFailed` — the reported gap.
- `KubeJobNotCompleted` — its sibling; a Job wedged past 12h is the same class of silence.
- `E2EVerificationFailing`, `E2EVerificationStale` — this repo's own alerts, currently dropped.
- `PrometheusDuplicateTimestamps` — firing now, and it explains the duplicated
  `kube_job_failed` series (6 per Job) seen while diagnosing this.

`KubeHpaMaxedOut` is deliberately **excluded**: it is firing steadily in `istio-system` on this
hardware and would deliver as immediate recurring noise. Adding it is the operator's call.

An allowlist is used rather than flipping the root receiver to `platform-warning`
(default-allow), because default-allow would immediately deliver `Watchdog` and every other
default rule, and would need a new explicit `'null'` route per unwanted alert — a larger blast
radius than this bug justifies.

### Change 3 — documentation

There is no alerting guide in `docs/guides/`. Create `docs/guides/alerting.md` covering:

- the three receivers (`null`, `sms-critical`, `platform-warning`) and what reaches each;
- that the root route is **default-deny**, so a new PrometheusRule is not delivered until it
  is either `severity: critical` or added to a route matcher — the trap this bug is;
- the first-match ordering constraint on the child routes;
- a triage table: alert fires in Prometheus but no notification → check the route, not the rule;
- the verification commands from "Testing requirements" below.

Link it from `README.md` under the guides list.

### Testing requirements

In `scripts/tests/plugins/alertmanager_config_secret.bats`. Follow the existing idiom in that
file: the template is valid YAML (every `${...}` sits inside quotes), so assert with `yq -r`
against the template path directly — do not shell out to `envsubst` except where a test
specifically needs the substituted value. The new route must be `.route.routes[2]` so that the
existing assertions on `routes[0]` and `routes[1]` keep passing unchanged.

- **A test that `KubeJobFailed` reaches a non-`null` receiver.** This is the guard that was
  missing. Asserting the matcher line exists is not sufficient — assert the rendered template
  routes the alertname to `platform-warning`.
- **A test that `platform-warning` has a non-empty `to:`** after `envsubst` with
  `ALERTMANAGER_GMAIL_FROM` set — this is what catches a future rename of the variable.
- **A test that the `severity = critical` route still precedes the new route**, so criticals
  keep going to SMS. Assert relative order in the rendered output, not just presence.
- Mutation-prove each new guard: reintroduce the defect (delete the new route; blank the `to:`;
  swap the two routes) and confirm the corresponding test goes red. A new test passing is not
  evidence it can fail.
- `make test` must stay green (~15 min — not a hang).

### Verification after deploy (operator, not Codex)

Codex must not touch the live cluster. Once merged, the operator re-renders the secret and
confirms:

```bash
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager \
  -- wget -qO- 'http://localhost:9093/api/v2/status'   # route tree contains platform-warning
```

and that a `KubeJobFailed` email arrives while `cve-remediation-verify` is still failing —
which it will be until the hostinger registration is restored.

### Implemented

Changes 1, 2 and 3 landed as written in `a7135966`. The route tree is now:

```
route.receiver          null
route.routes[0]         null              alertname = TrivyCriticalVulnerabilityDetected
route.routes[1]         sms-critical      severity = critical
route.routes[2]         platform-warning  alertname =~ "KubeJobFailed|..."
```

Verification: 7/7 in `alertmanager_config_secret.bats` (3 new guards), `make test` green,
`make check-doc-links` OK. All three mutations reproduced independently — deleting the new
route reds tests 3 and 5, blanking the `to:` reds test 4, swapping the two routes reds tests
2, 3 and 5; the template was restored byte-identical after each.

## Not in this change

- **The `cve-remediation-verify` failure itself.** Its cause is the lost
  `cluster-ubuntu-hostinger` registration, tracked in
  `docs/bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`
  (RECURRED 2026-09-23). This spec only makes the failure audible. Both are needed.
- **`E2EVerificationStale` cannot fire yet.** `e2e_last_success_timestamp_seconds` has zero
  series, because no e2e run has yet reached the test phase. Routing it now is correct and
  costs nothing; it becomes live once a run succeeds.
- **`Watchdog` still routes to `'null'`.** A dead-man's switch that terminates inside the
  cluster it monitors proves nothing. Wiring it to an external endpoint is separate work.
- **`KubeHpaMaxedOut`** — excluded as noise, see above.
- **A 502 from the `cve-remediate` webhook** on 2026-09-22T00:49Z
  (`webhook.3ai-talk.org/api/v1/cve-remediate`), single occurrence, not retried since. Noted
  for the record; not diagnosed here.
