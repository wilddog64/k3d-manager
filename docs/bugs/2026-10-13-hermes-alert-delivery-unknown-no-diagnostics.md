# Bug: Hermes alert_delivery reports opaque unknown despite healthy manual probe (2026-10-13)

**Status:** DUPLICATE 2026-10-15 — merged into `docs/bugs/2026-10-13-hermes-alert-delivery-probe-unknown-hides-error.md` (operator-approved); track and fix there
**Branch:** `k3d-manager-v1.44.0` (follows the canonical doc)
**Priority:** P2 — observability diagnostic blind spot
**Filed:** 2026-10-13 at operator request
**Release:** v1.44.0 (follows the canonical doc)
**Approval:** explicit operator 2026-10-13 "can you file a bug for this"
**Component:** `scripts/lib/hermes/sensors.py` alert_delivery sensor, `bin/k3dm-alert-delivery-status`, Hermes findings exporter/Grafana
**Type:** Confirmed diagnostic deficiency; underlying availability fault not confirmed

## Evidence

The Hermes Status Grafana findings table reported:

```
Sensor          Finding                          Status    Target namespace
alert_delivery  alert delivery probe unavailable unknown   hermes
```

Operator then ran `bin/k3dm-alert-delivery-status --json` manually on M4. It exited 0 and returned `available=true` with two clusters:

- `k3d-k3d-cluster`: `config_ref_missing=false`, root receiver `null`, `root_receiver_is_null=true`, `child_routes=6`.
- `ubuntu-hostinger`: `config_ref_missing=false`, root receiver `null`, `root_receiver_is_null=true`, `child_routes=5`.

Both `kubectl --context ... -n monitoring get alertmanager` commands displayed ready/reconciled/available Alertmanager CRs. These findings support a *successful manual configuration probe*, not proof of notification delivery or successful historical Hermes polling.

## Confirmed code problem

`scripts/lib/hermes/sensors.py` `alert_delivery()` invokes `bin/k3dm-alert-delivery-status --json` then parses a nonempty `clusters` array. Its blanket `except Exception:` returns `record("alert_delivery", "unknown", "alert delivery probe unavailable")` with **no reason, exit status, or affected cluster**.

The helper `bin/k3dm-alert-delivery-status` uses fail-fast behavior: failures reading any included cluster's Alertmanager CR/generated Secret can return `{"available":false}` and discard otherwise successful cluster results. Therefore Grafana cannot distinguish transient API failure, launchd environment differences, a missing generated configuration, invalid JSON, or an unavailable target.

**Do not classify the live Alertmanager pipeline as broken from the `unknown` row alone.** A manual probe later succeeded, but that does not identify the original failure.

## Investigation

1. Confirm the exact Hermes scheduled invocation and launchd environment (PATH, Python/YAML, kubeconfig, credentials) without printing secrets.
2. Inspect the Hermes sensor poll record/time, exit code and sanitized probe diagnostics; distinguish an old/stale finding from a continuously recurring `unknown`.
3. Determine whether unavailable context, kube API timeout, missing generated Secret, malformed payload or transient error caused the failed invocation. The probe should avoid reporting a successful cluster as failed because another cluster could not be read.
4. Check existing Hermes/Python sensor and Alertmanager-delivery tests and bug history before implementation.

## Expected behavior

- Preserve per-cluster probe results; an inaccessible cluster reports an explicit `unknown` reason while reachable clusters retain valid status.
- Provide **bounded redacted diagnostic categories** (e.g. `probe_nonzero`, `invalid_payload`, `cluster_api_unreachable`, `generated_config_missing`, `yaml_decode_failed`). Avoid dumping secret contents, tokens, full subprocess output or connection strings.
- Distinguish `unknown` (cannot evaluate) from `degraded` (confirmed routing blackout) and `healthy` (route configuration passes). Do not equate `root_receiver=null` with blackout when child routes provide delivery paths.
- Include probe timestamp/freshness so old unknown findings do not appear to describe current live conditions indefinitely.
- Maintain read-only checks and deterministic behavior. Do not initiate repairs/restarts or delivery notifications just because a probe is unknown.

## Acceptance

- [ ] Offline tests cover exit-nonzero, malformed JSON, missing/empty clusters, missing generated config, unavailable kube context, and successful multi-cluster response.
- [ ] Partial failure in one cluster preserves the other cluster's supported healthy/degraded evidence, and the overall rollup communicates partial uncertainty.
- [ ] A failed poll contains a safe actionable reason; no credential material or raw config is included in Grafana/logs.
- [ ] A later healthy poll can supersede a transient unknown with correct timestamps.
- [ ] Existing null-root-with-child-routes cases remain classified correctly.
- [ ] Run relevant Hermes unit tests, shellcheck/BATS for probe, exporter and dashboard regression checks.
- [ ] Live acceptance under the actual Hermes launchd execution path confirms reason/freshness and no leaked secrets; manually succeeding in an interactive shell is not sufficient.

## Files

- `scripts/lib/hermes/sensors.py`
- `bin/k3dm-alert-delivery-status`
- `scripts/tests/hermes/test_alert_delivery.py`
- Relevant Hermes exporter/dashboard tests and `CHANGELOG.md` as identified by implementation audit.

No runtime code or cluster resources changed by filing this bug.
