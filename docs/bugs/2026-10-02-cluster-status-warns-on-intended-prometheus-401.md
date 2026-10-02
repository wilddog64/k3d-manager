# `/cluster-status` warns on the Prometheus 401 that proves auth is working

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low, with a security inversion.
- Every k3s-hostinger `/cluster-status` ends `Overall: WARN (1 warnings)` on a healthy stack, so
  the operator learns to ignore WARN.
- The same check would report a **green** Prometheus if the auth proxy were bypassed and the public
  endpoint answered 200 again — the exact regression fixed on 2026-09-15.

**Status:** OPEN
**Related:** `docs/issues/2026-09-15-prometheus-public-endpoint-unauthenticated.md` (added
`bin/prometheus-auth-proxy` on 19090 in front of the port-forward on 19091)

## Observed (operator, 2026-10-02)

```
  ✓ ArgoCD: HTTP 200
  ✓ Frontend: HTTP 200
  ✓ Keycloak: HTTP 200
  ! Prometheus: HTTP 401 (authentication required)
  ✓ Grafana: HTTP 200
  ✓ Pushgateway: HTTP 200
Overall: WARN (1 warnings)
```

## Cause

In `scripts/lib/webhook/smoke.py`, the endpoint probe (`_probe_endpoint`, around lines 590–618) hits
`https://prometheus.3ai-talk.org/-/ready` without credentials and expects `[200]`. A 401 returns
`(name, None, "HTTP 401 (authentication required)")`, and `None` renders as a warning.

Since 2026-09-15, that public URL is fronted by `bin/prometheus-auth-proxy`. A 401 is the intended
answer to an unauthenticated request. A 200 means the proxy is bypassed.

The credentialed check already exists: the full sweep's `Prometheus login` result (around line 434,
`_smoke_basic_auth` with Vault `k3d-manager/prometheus-basic-auth`, `True` = expect auth enforced).
So the quick probe needs to answer only "is the protected front door up and protected".

## Fix

Only `scripts/lib/webhook/smoke.py` and its tests change. Do not touch `bin/k3dm-webhook`,
`bin/prometheus-auth-proxy`, the LaunchAgents, or the `Prometheus login` check. Do not touch
`CHANGELOG.md`; Claude adds the bullet.

1. **Public Prometheus URL** (`provider == "k3s-hostinger"`, `https://prometheus.3ai-talk.org/-/ready`):
   - 401 → **pass**, detail `HTTP 401 (auth enforced)`.
   - 200 → **fail**, detail `HTTP 200 without credentials — auth proxy bypassed`.
   - Anything else → unchanged: retry, then fail with the existing detail.
   - Express this as data, not another `name == "Prometheus"` branch. For example, give the endpoint
     tuple an expected-auth flag or per-endpoint ok/fail code sets, and drop the two hardcoded
     `name == "Prometheus" and code == 401` branches (both the `resp.status` and the `HTTPError`
     path).
2. **Local Prometheus URL** (other providers, `http://localhost:19190/-/ready`): unchanged, 200
   passes. That port-forward has no proxy.
3. The monitoring-paused downgrade (around line 640, `_n in ("Prometheus", "Grafana")`) keeps
   working: with the hub monitoring paused, its expected 502 is still a skip.
4. No other endpoint's behaviour changes.

## Tests

Use the existing smoke test file for `smoke.py` (find it with
`grep -l "_probe_endpoint\|smoke_endpoints\|def run_smoke" scripts/tests -r`). If none covers the
endpoint probe, add `scripts/tests/bin/test_smoke_prometheus_auth.py`. Stub `urllib.request.urlopen`;
no network.

- hostinger, Prometheus returns 401 (as an `HTTPError`) → passed `True`, detail contains
  `auth enforced`, and overall is not WARN when every other endpoint passes.
- hostinger, Prometheus 401 returned as a response status (not an exception) → same.
- hostinger, Prometheus 200 → passed `False`, detail contains `auth proxy bypassed`.
- hostinger, Prometheus 502 → fail as today.
- k3d (local URL), Prometheus 200 → pass; 401 → not a pass.
- The monitoring-paused case still downgrades the Prometheus 502 to a skip.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) treat 200 as pass on the public URL → the bypass test is red;
(b) restore 401 → `None` → the auth-enforced test is red;
(c) apply the public rules to the local URL → the k3d test is red.

## Rules

- `pytest` on the touched test file plus `scripts/tests/bin/test_webhook_ask_delivery.py` is green.
- `python3 -m py_compile scripts/lib/webhook/smoke.py` passes.
- No network, no live webhook restart.
- Leave changes uncommitted. Update this doc: Status FIXED and a short Resolution section.

## Operator step after the fix

Run `make restart-webhook`, then `/cluster-status`. Prometheus should read `✓ Prometheus: HTTP 401
(auth enforced)` and the overall status should be OK.
