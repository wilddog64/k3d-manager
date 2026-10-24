# Hermes Status (`hermes-status`)

[← Grafana dashboards index](../grafana-dashboards.md)

Six panels, all from `hermes_*`:

| Panel | Query |
|---|---|
| Active incident | `sum(hermes_incident_active) or vector(0)` |
| Minutes since last poll | `max((time() - hermes_last_poll_timestamp_seconds) / 60)` |
| Degraded sensors | `count(hermes_sensor_status{status="degraded"}) or vector(0)` |
| Unknown sensors | `count(hermes_sensor_status{status="unknown"}) or vector(0)` |
| Current Hermes findings | `hermes_sensor_status` |
| Sensor status history | `hermes_sensor_status` over time |

Hermes runs **off-hub** as a macOS LaunchAgent (`com.k3d-manager.hermes`) and publishes a
redacted snapshot — no tokens, no raw log lines — as a `platform-ops` ConfigMap.
`K3DM_HERMES_PUBLISH_STATUS=0` disables publication, and the dashboard then ages out via
*Minutes since last poll* rather than going blank, which is the point of that panel.

Read *Minutes since last poll* **first**. A stale poll age invalidates every other panel on
the dashboard: sensor states are a snapshot, not a live read. Two sensors reading `unknown`
together (`eso` + `data_layer`) is the webhook-down signature and pages by SMS,
bypassing the correlator — see `docs/guides/hermes.md`.
