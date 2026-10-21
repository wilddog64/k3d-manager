# k3dm Alertmanager Delivery (`k3dm-alertmanager-delivery`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

Shows whether alerts are actually being delivered. Stats at the top cover notifications sent and failed
per integration over 24h, actionable alerts by severity, and an `Alerting pipeline` health count. The
actionable selector is `ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor|Trivy.*",job!~".*smstest.*"}`:
it excludes the two always-on meta-alerts, Trivy security findings, and deliberate synthetic tests.
The **Actionable alerts** table uses the same selector and lists `severity`, `alertname`, `cluster`,
`namespace`, and any image/remediation labels. The **Security findings by image** table uses
`alertname=~"Trivy.*"`; `tier="upstream"` is a third-party image we only consume, while other tiers
have a remediation path through the CVE loop. The **Synthetic / test alerts** table uses
`job=~".*smstest.*"`; these route like real alerts and can send texts, so delete the test job when it
is no longer needed.

The **Alerting pipeline** stat counts kube-prometheus-stack rules that watch delivery and evaluation
health, including Alertmanager send failures, Prometheus connectivity, a full notification queue, and
rule failures or missed evaluations. Zero means none are firing; inspect the alert names in Prometheus
when it is red.

Severity mostly decides the route: `critical` texts (`sms-critical`), `warning` emails
(`platform-warning`). The exception is `TrivyCriticalVulnerabilityDetected`, which goes to the CVE
auto-patch webhook and the analysis receiver, not SMS. Synthetic tests route like real alerts, so a
`critical` test does send a text.

The **Noisiest alerts (3d)** table uses the hub Prometheus retention window. `firing series-hours` is
time spent firing summed over series, assuming the 60-second rule evaluation interval. `trips` counts
starts of pending or firing states, including alerts that cleared before firing; a high trips count with
no firing hours indicates flapping. Alertmanager does not label notification counts or latency by alert
name, so this table cannot show notifications per alert. The dashboard's 41-warning example was 39
Trivy findings, plus one actionable `TargetDown` and one deliberate `HostDiskSpaceLow` synthetic alert.
