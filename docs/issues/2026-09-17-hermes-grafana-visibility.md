# Hermes findings visibility design

**Date:** 2026-09-17
**Status:** Implemented in the Hermes observability dashboard slice

## Finding

Hermes was polling successfully, but its findings were visible only in the
local `~/Library/Logs/k3dm-hermes.log` and `~/.k3dm/hermes/state.json`. A
persistent finding could therefore remain open without a durable Grafana view.

## Scope

Publish a redacted Hermes status snapshot as a labeled `platform-ops`
ConfigMap. The existing vulnerability exporter reads that snapshot and emits
bounded Prometheus gauges. A dedicated Grafana dashboard displays current
sensor states, active incident state, finding age, and the detailed checks.
No credentials, bearer tokens, or raw local log lines are published.

The v1.34.0 milestone already contains its five permitted plan documents, so
this issue record is the design and acceptance record rather than a sixth plan.

## Acceptance

- Hermes publishes the latest status record when the scheduled status sensor runs.
- Prometheus exposes sensor status, incident state, last-poll age, and check details.
- Grafana has a `Hermes Status` dashboard with current findings and history-friendly panels.
- Existing Hermes and exporter tests remain green.
