# Bug: the webhook access log cannot tell the operator's own probes from an outsider

**Status:** OPEN
**Priority:** P3
**Severity:** low. Every request described here was refused; there is no sign of a breach. The gap is that a suspicious request cannot be attributed from this log.
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"; "go ahead to investigate webhook GET / 401 traffic. file bug if necessary and dispatch to Luna"
**Filed:** 2026-11-06
**Detected by:** Claude, tracing `GET / 401` on the M5
**Branch:** `k3d-manager-v1.43.14`
**Depends on:** `2026-11-06-webhook-analyze-reports-success-when-slack-post-fails` (same file; land it first)
**Related:** `docs/bugs/2026-11-06-webhook-analyze-rejects-alert-batches-over-4096-bytes.md`

## Investigation: the `GET / 401` traffic is the platform's own probing

`~/Library/Logs/k3dm-webhook.log` on `m5-air.local`, read 2026-11-06 about 15:48Z, from 2026-10-31T01:44Z: 16,981 `GET / 401`. No change is needed for them; 401 is the expected answer.

| Requests | Source | Evidence |
|---|---|---|
| about 9,460 (one a minute, at `:14`) | Blackbox `Probe/public-endpoints-authenticated`, 60s, target `https://webhook.3ai-talk.org/` | Prometheus `lastScrape` for that target `15:48:14.04Z`; module `http_authenticated` accepts 200 and 401 |
| about 6,580 (1,330 chains of about 5, 3 to 4 seconds apart) | Hermes `bin/public-endpoint-probe`, 5 samples each cycle | `scripts/lib/hermes/sensors.py:192`; 1,352 Hermes cycles over the same period |
| about 700 in the same second as the blackbox request, 761 of the in-slot repeats on 10-31 | Not proven. Likely the old M4 Prometheus before its cluster stopped on 10-31 | Timing only |
| about 240 others, 100 of them on 10-31 | Mixed; includes `bin/hub-cutover` verification (14:54:11Z) | The rest cannot be attributed from this log |

## The gap

Requests no code in this repo makes, all refused, with no client recorded:

    2026-10-31T06:58:06Z GET /api/v1/argocd-upgrade/v1/models 401, then 06:58:07Z GET /api/v1/status/{job_id} 401
    2026-11-01T00:49:11Z, 2026-11-01T17:10:24Z, 2026-11-02T09:16:39Z, 2026-11-03T11:19:38Z, 2026-11-04T14:37:13Z: the same pair
    2026-11-04T04:05:06Z GET /api/v1/analyze/v1/models 401
    2026-11-06T11:08:57Z HEAD / 501, twice

The prefix uses real route names, which are public in this repo. The client could be a scanner or a misconfigured tool. The log line in `log_message` (`bin/k3dm-webhook:2824`) has method, route, status, role and duration, so it cannot say which. Attributing even the known traffic took a socket sample and timing analysis.

## Files

- `bin/k3dm-webhook`
- `scripts/tests/bin/test_webhook_access_log.py` (new)
- `CHANGELOG.md`

## Fix

Append two fields to the end of the request line in `log_message`, leaving the existing fields and their order unchanged:

- `client=`: the `CF-Connecting-IP` header if `ipaddress.ip_address` accepts it, `local` if the header is absent, otherwise `invalid`. The listener binds `127.0.0.1` and Cloudflare sets this header on tunnel traffic. A local process could forge it, which is acceptable for this purpose.
- `ua=`: `User-Agent`, truncated to 80 characters, with anything outside `[A-Za-z0-9 ._/()+;:,-]` replaced by `_`, and the whole value quoted. `-` if absent.

Check for other parsers of this line (Loki queries, dashboards, tests) with `git grep`, and keep them working.

## Acceptance

```yaml
must:
  - id: M1
    text: "A request with a valid CF-Connecting-IP logs client=<that address>; a request with no such header logs client=local."
  - id: M2
    text: "A request with a User-Agent logs it in ua=, truncated to 80 characters."
  - id: M3
    text: "The existing fields method, path, status, role and duration_ms keep their order and values."
must_not:
  - id: N1
    text: "An Authorization header, token, query string or request body never appears in the log line (paired with M1)."
  - id: N2
    text: "A CF-Connecting-IP or User-Agent holding newlines, control characters or quotes cannot add a log line or forge a field (paired with M2)."
  - id: N3
    text: "GET / without credentials still returns 401; bin/hub-cutover and the blackbox probe rely on it."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2, N3], kind: offline, text: "pytest against a local server instance with a scratch K3DM_JOB_DIR, K3DM_RUN_DIR and HOME; M1 and M2 red on the pre-fix commit; N1 and N2 red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "After a webhook restart on the M5, the log shows the blackbox User-Agent k3dm-blackbox/1.0 with a client address, and a local health check with client=local."}
interface:
  - "GET / on the webhook server"
  - "Log line: INFO webhook request method= path= status= role= duration_ms= client= ua="
  - "env: K3DM_JOB_DIR, K3DM_RUN_DIR, HOME"
```
