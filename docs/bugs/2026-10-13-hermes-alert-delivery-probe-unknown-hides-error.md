# Bug: Hermes alert_delivery reports UNKNOWN with no diagnostic reason

**Filed:** 2026-10-13, operator screenshot
**Branch:** `k3d-manager-v1.44.0` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — observed in Hermes/Grafana screenshot; exact live probe failure **not yet verified**
**Priority:** P2 — alert delivery monitoring unavailable; manual read-only probe is a workaround
**Release:** v1.44.0 (bug fix carried per docs/roadmap.md) (backlog triage, Claude, 2026-10-22)
**Severity:** Medium — blind spot in monitoring the alert delivery path; **not evidence of an actual alert blackout**
**Component:** `scripts/lib/hermes/sensors.py` (`alert_delivery`); `bin/k3dm-alert-delivery-status`; Hermes dashboard
**Related:** `docs/bugs/2026-09-23-hostinger-alertmanager-discards-every-alert.md`

## Symptom

The Hermes sensor table shows `alert_delivery` with status `unknown`, evidence `alert delivery probe unavailable`, frequency `hour`, source `hermes`. The screenshot does not identify the cause or establish whether Alertmanager is successfully delivering notifications.

Source inspection on `k3d-manager-v1.43.2` confirms `alert_delivery()` runs `bin/k3dm-alert-delivery-status --json` and treats non-zero exit, empty/invalid JSON, `available=false`, or empty/malformed cluster data as errors. Its broad `except Exception` returns the same uninformative evidence for **every** failure, discarding exit status and reason. The Bash probe also emits `{"available":false}` for kubectl/Secret errors and may hide stderr from kubectl. No live command was executed from this cloud session.

## First diagnostic (read-only; operator/local Claude)

1. From the same host/environment where Hermes runs, execute `bin/k3dm-alert-delivery-status --json`; **capture exit status and redacted stderr**. Do not dump raw generated Alertmanager Secret or credentials.
2. Check `kubectl config get-contexts -o name`, hub/app context accessibility and RBAC for `monitoring` Alertmanager CR and generated Secret. The script skips unavailable configured contexts but returns failure if a present context's API/Secret read fails.
3. Verify `python3` and PyYAML are available in the Hermes launchd execution environment. The probe invokes `import yaml` inside a subprocess; `ModuleNotFoundError` would be collapsed to `unknown`.
4. Inspect the generated Alertmanager Secret's **metadata/keys only**, and verify the gzip configuration parsing path without printing secret values.
5. Distinguish a temporarily unreachable cluster, missing generated config, missing dependency, parsing error, and unexpected probe payload. Correlate with launchd logs and prior known-live alerts before classifying delivery itself as broken.

## Required behavior

- Sensor retains `unknown` when probe fails, but emits a **bounded, redacted reason code** (e.g. `probe_exit_nonzero`, `probe_invalid_json`, `probe_missing_clusters`, `probe_dependency_missing`, `cluster_query_failed`) and safe truncated diagnostic detail in local logs. Do not log Secret contents, tokens, generated Alertmanager configuration, or unbounded stderr.
- Probe reports an explicit, machine-readable error reason and affected *context* when possible; partial/inaccessible coverage is not falsely reported as all healthy.
- Sensor and dashboard differentiate `unknown` (can't check) from `degraded` (actual delivery blackout detected), and retain enough evidence to troubleshoot without SSH guesswork.
- Preserve current read-only access and existing alert routing behavior; do not auto-reconfigure Alertmanager.

## Verification

- Reproduce the current failure with the actual probe on the Hermes host and record sanitized reason and exit code; update this bug with observed cause.
- Test real probe parsing using fixture CR/Secret data, with stubbed `kubectl` and missing `yaml` dependency; do not merely stub the `run` callback of the sensor, which previously allowed a probe defect to pass green (documented in `docs/plans/v1.40.0-slack-corpus-qa.md`).
- Verify sensor produces `unknown` with actionable, sanitized reason for each probe failure, `healthy` for valid deliverable route(s), and `degraded` only for a proven null-sink/missing-config blackout.
- Confirm the dashboard displays the reason and returns to healthy/degraded after the underlying condition is corrected.

## What NOT to do

- Do not treat `unknown` as evidence of a real alert outage.
- Do not print or publish the contents of Alertmanager generated Secrets.
- Do not modify alert rules, delivery routes, Kubernetes resources or operator credentials as part of diagnosis.
- No destructive recovery, cluster restart or bypass of Hermes read-only policies.

## Scheduling

Bug doc only; assign a repair release in regular triage. No implementation changes were made.

## Consolidated 2026-10-15 (operator-approved merge)

Two later docs reported the same `alert_delivery` → `unknown` symptom and are now marked DUPLICATE of
this one. Their extra evidence and scope carry over here:

- `2026-10-13-hermes-alert-delivery-unknown-no-diagnostics.md`: the operator ran
  `bin/k3dm-alert-delivery-status --json` by hand on the M4 while Hermes showed `unknown`. It exited 0,
  `available=true`, two clusters (`k3d-k3d-cluster` 6 child routes, `ubuntu-hostinger` 5), both with a
  null root receiver. So the probe can succeed by hand while the Hermes poll fails. Compare the
  launchd environment (PATH, python3, PyYAML, kubeconfig) with the interactive shell. The sensor's
  blanket `except Exception:` is what hides the cause.
- `2026-10-15-hermes-alert-delivery-unknown-masks-probe-errors.md`: seen after an ACG sandbox bring-up
  and teardown. The probe picks contexts by **kubeconfig presence**, not by whether the cluster
  is live, so a torn-down sandbox's leftover context is a likely trigger. Required: per-context
  status (`healthy`, `degraded`, `skipped_expected_offline`, `unknown`), one dead context must not fail
  the whole probe, a required cluster with no evidence stays `unknown`, and docs must say this checks
  routing configuration, not real email/Slack delivery. Tests: an offline sandbox, an unreachable
  persistent cluster, a missing Secret, invalid JSON, no clusters, partial success, and a real
  null-route blackout.

