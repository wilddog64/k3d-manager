# Public Endpoint Alerts

The hub blackbox exporter probes the seven public hostnames listed in
`~/.cloudflared/config.yml` every 60 seconds. The Probe targets use the `${CF_DOMAIN}`
domain variable so the hostname suffix is supplied by the deployment environment rather
than copied into monitoring manifests.

The default `CF_DOMAIN` comes from `scripts/etc/vars.sh`; exporting `CF_DOMAIN` overrides it.
`deploy_observability` renders `scripts/etc/prometheus/rules/*.yaml` through `envsubst`, so a new
rule file may use `${CF_DOMAIN}`, but any other new placeholder must be added to the allowlist in
`scripts/plugins/observability.sh`.

The exporter must be running and selected by the hub Prometheus before `probe_success`,
`probe_http_status_code`, or these alerts can exist. Each Probe carries the
`release: kube-prometheus-stack` label because the stack's `probeSelector` matches that
label.

## Alerts

`PublicEndpointDown` means one public hostname has failed its expected HTTP status for five
minutes. `CloudflareTunnelDown` means every public probe is failing; that points toward the
Cloudflare edge or tunnel and fires alongside the per-endpoint alert. `PublicEndpointProbeAbsent`
means no `probe_success` series has reported for 15 minutes, so the exporter, Probe resource,
or scrape itself is broken and public availability is unmonitored.

The UI module accepts 200, 301, and 302. The authenticated module accepts 200 and 401. The
401 allowance is intentional and credential-free: an auth proxy that returns 401 even while its
backend is unavailable will look healthy. A green probe therefore does not prove that Prometheus,
Alertmanager, or the webhook backend is serving data.

The absent alert cannot detect the hub being down, because the probes run inside the hub. The
operator must also reapply the hub ApplicationSets after a release so ArgoCD reads the new chart,
Probe resources, and rules.
