# Bug: k3dm Tests "Last run" panel is always red, even after a passing run

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.42.0`
**Status:** FIXED — the panel uses a fixed neutral colour (`color.mode: fixed`, `fixedColor: text`)
**Priority:** P3 — cosmetic, but a red value reads as a failure signal
**Severity:** low

## Symptom

On hub Grafana "k3dm Tests", after `make test-all` passed (2026-10-09 20:01:33Z, 0 failed, exit 0),
the "Last run" stat showed `2026-10-09 13:01:33` in red. "Time since last successful run" beside it
was green.

## Cause

`scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` panel 1 sets only
`"unit": "dateTimeAsIso"`. With no thresholds of its own, a stat panel uses Grafana's defaults,
green below 80 and red from 80. The value is `max(k3dm_test_last_timestamp_seconds) * 1000`, an
epoch in milliseconds, so it is always above 80 and always red. The colour never carried pass or fail.

## Fix

- The panel gets `"color": { "mode": "fixed", "fixedColor": "text" }`. Its description says the
  colour is neutral on purpose, and that pass or fail is shown by "Latest run classification" and
  "Time since last successful run".
- `scripts/tests/plugins/grafana_dashboard_appsets.bats` asserts the fixed colour. The assertion
  was checked against the pre-fix dashboard, where `jq -e` exits 4.

## Rollout

ArgoCD app `hub-grafana-dashboards` tracks `k3d-manager-v1.42.0` with auto-sync. The ConfigMap
`monitoring/k3dm-test-metrics` updates after the push, and Grafana reloads it with no restart.
