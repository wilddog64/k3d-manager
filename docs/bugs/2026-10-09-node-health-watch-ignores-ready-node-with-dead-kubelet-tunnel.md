# node-health-watch never recovers a Ready node whose kubelet tunnel is dead (ArgoCD public 502)

**Filed:** 2026-10-09, Claude (operator received a `PublicEndpointDown` SMS for argocd)
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** OPEN — specified; not started
**Priority:** P1 — a public endpoint stays down until a human restarts the agent
**Severity:** High
**Component:** `bin/k3dm-node-health-watch` (`_healthy`, `_tick`)
**Related:**
- `docs/issues/2026-08-19-agent0-kubelet-proxy-instability.md`: the same failure, which is why the watchdog was built.
- `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`: made `_healthy` advisory, which created this gap.
- `docs/bugs/2026-09-13-node-health-watch-restarts-on-host-api-unreachable.md`

## Symptom (2026-10-09)

1. At about 11:05 UTC, `PublicEndpointDown` fired for `https://argocd.3ai-talk.org/`.
   - Probe status 502. The other six public endpoints were at 1.
   - It was sent by SMS.
2. The argocd port-forward supervisor (`argocd-pf.log`) loops: 250+ restarts with this error:
   ```
   error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.4:10250, code 502: 502 Bad Gateway
   ```
3. On the hub nodes:
   - `kubectl get --raw /api/v1/nodes/k3d-k3d-cluster-agent-0/proxy/healthz` gives the same fast 502.
   - agent-1, agent-2 and server-0 return `ok`.
   - All four nodes are `Ready`.
   - argocd-server (`2/2 Running`) and 12 other pods are on agent-0.
4. `node-health-watch.log` noticed the failure and did nothing. Every 30s it logged:
   ```
   k3d-k3d-cluster-agent-0 Ready but /healthz slow/unreachable (advisory, no restart)
   ```
   Just before that, it logged "API server unreachable from host" lines up to 04:00 PDT. This is consistent with a host sleep or wake, after which agent-0's k3s tunnel to the server did not come back.

## Root cause

The 2026-08-28 fix correctly stopped the watchdog from restarting a node that is merely **slow**
(a healthz timeout under CPU pressure). It did that by making every `_healthy` failure advisory
while the node is Ready.

That also swallows a different failure:
- In this one, the k3s **agent tunnel** (the egress path the API server uses to reach the
  kubelet) is dead.
- It fails fast, in milliseconds, with `proxy error ... while dialing <node>:10250, code 502`.
- The node stays `Ready`, because the kubelet still heartbeats outward.
- It never heals by itself: there are 30 occurrences in the log since 2026-10-05.
- `kubectl logs`, `exec` and `port-forward` to every pod on that node fail. That is why the
  public endpoint goes down.

`_healthy` discards stderr, so it cannot tell a dead tunnel from a slow node.

## Fix (spec for Codex)

In `bin/k3dm-node-health-watch`:

1. Make `_healthy` classify its result instead of returning only true or false:
   - `ok`: the body is `ok`.
   - `tunnel`: stderr matches `proxy error from .* while dialing .*:10250, code 502`.
   - `slow`: anything else, such as a timeout or a TLS error.
2. In `_tick`, when `_ready` is true:
   - Keep `slow` advisory, unchanged (the 2026-08-28 behaviour).
   - On `tunnel`, increment a separate counter, `tunnel_failures`. Reset it on `ok` or `slow`.
   - When it reaches `K3DM_NODE_TUNNEL_THRESHOLD` (default **6**, which is 3 minutes at the 30s
     tick), call the existing `_recover`.
   - Reuse `_recover` unchanged. It already handles the cooldown, the state file,
     `docker restart`, the readiness and healthz wait, and drift reconciliation.
   - Log `"${node} Ready but kubelet tunnel dead (n/threshold)"`.
3. Keep the existing NotReady path and the API-unreachable path unchanged.

## Tests

Add BATS tests in the existing node-health-watch suite, with `kubectl` and `docker` stubbed:
- A tunnel 502 for 6 ticks leads to exactly one `docker restart`.
- A tunnel 502 for 5 ticks followed by `ok` leads to no restart.
- A `slow` healthz (timeout) for 20 ticks leads to no restart. This is the regression guard for
  2026-08-28.
- A tunnel 502 during the cooldown leads to no second restart.
- **RED:** the 6-tick tunnel test must fail on the current script. Paste the failure.

## Docs

- Add the dead-tunnel case to the watchdog's how-to or guide entry.
- CHANGELOG.

## Immediate recovery (operator, 2026-10-09)

```
docker restart k3d-k3d-cluster-agent-0
```

Then verify (Claude can run these read-only):
- agent-0 `/proxy/healthz` returns `ok`.
- The argocd port-forward log shows healthz reachable.
- `probe_success{instance="https://argocd.3ai-talk.org/"}` is 1, and the alert resolves.
  `sms-critical` has `send_resolved: false`, so no "resolved" text arrives.

## What NOT to do

- Do not make `slow` recoverable again.
- Do not lower the cooldown.
- Do not restart server-0 from this path.
