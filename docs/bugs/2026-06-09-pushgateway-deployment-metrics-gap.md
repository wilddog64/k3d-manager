# Bug: Pushgateway deployment metrics are intermittently missing

**Filed:** 2026-06-09

## Description

`bin/k3dm-webhook` pushes deployment metrics to Prometheus Pushgateway only once,
at job finish. When the Pushgateway port-forward or pod is still warming up, that
single best-effort push can fail and be logged as a non-fatal skip. The Grafana
dashboard then shows no fresh deployment data until a later run succeeds.

This matches the observed behavior where `k3dm_deployment_duration_seconds`,
`k3dm_deployment_success`, and `k3dm_deployment_last_timestamp_seconds` appear
intermittently: the data exists only when the one-shot push lands after
Pushgateway is reachable.

## Why this matters

- Grafana deployment panels look flaky even when the underlying deployment
  completed successfully.
- The last successful metric sample can be stale or missing if Pushgateway was
  briefly unavailable at job completion.
- The current best-effort push path has no retry window, so transient readiness
  gaps turn into lost metrics.

## Proposed follow-up

1. Add a bounded retry window around the Pushgateway metric push.
2. Prefer a healthy/reachable Pushgateway before sending the POST.
3. Keep the push non-fatal, but avoid dropping metrics on short-lived readiness
   gaps.

---

## Update 2026-09-24 — the proposed follow-up above is ALREADY IMPLEMENTED; the real cause is different

Do not re-implement items 1–3. They shipped. `bin/k3dm-webhook:1717-1741` already has a bounded
retry loop (`_PUSHGATEWAY_PUSH_RETRIES`, `_PUSHGATEWAY_PUSH_SLEEP_SECS`) and already prechecks
`${PUSHGATEWAY_URL}/-/healthy` before POSTing, and the push is already non-fatal.

**Measured today:** the symptom is not intermittent, it is total.

- `pushgateway` on `ubuntu-hostinger` is up and being scraped — hostinger Prometheus has
  `pushgateway_build_info` and `pushgateway_http_requests_total`.
- That same Prometheus has **zero** `k3dm_*` series. No push has ever landed.
- The hub (`k3d-k3d-cluster`) has **no pushgateway pod at all**.
- `PUSHGATEWAY_URL` defaults to `http://localhost:9091` (`scripts/lib/webhook/config.py:33`), i.e. a
  launchd port-forward on the laptop (`com.k3d-manager.pushgateway-port-forward`,
  `bin/cluster-up:1873-1890`).
- **That launchd agent is not loaded** (`launchctl list | grep pushgateway` → nothing), and
  `curl http://localhost:9091/-/healthy` returns `000` — connection refused.

So every push retries against a dead local socket, exhausts its retries, and logs a non-fatal skip.
The retry window cannot help: there is nothing listening to retry against.

### Real remaining defects

1. **The sink is absent, not slow.** A bounded retry against a closed port is pure latency. The push
   path needs to distinguish "Pushgateway not reachable at all" from "not ready yet" and say so once,
   loudly, rather than degrading into a silent skip that nobody sees for months.
2. **Silent failure has no operator surface.** `k3dm_deployment_*` being absent for an extended period
   is indistinguishable from "no deployments ran". There is no alert and no `make status` row for
   "deployment metrics have not been published since X".
3. **`_provider_supports_pushgateway` is inconsistent with the push path.**
   `bin/k3dm-webhook:1793` returns `False` for `k3s-hostinger`, so the smoke check skips Pushgateway
   on that provider — but `_push_metrics` (line 1698) gates only on `PUSHGATEWAY_URL` being non-empty
   and attempts the push regardless of provider. One of the two is wrong; decide which and make them
   agree.
4. **Topology is unstated.** The dashboard ships to both the hub and hostinger, but only hostinger has
   a Pushgateway. Which Prometheus is supposed to hold these metrics should be written down before
   any code changes, or the fix will chase the wrong cluster.

### Note on how this was nearly misdiagnosed

An initial producer search used `grep -r --include='*.yaml' --include='*.sh' --include='*.py'` and
concluded **no producer existed**. That was wrong: `bin/k3dm-webhook` has **no file extension**, so
the include filters skipped it. When searching this repo for producers, never restrict by extension —
`bin/` holds extensionless executables.
