# Monitoring port-forward supervisor kills a healthy forward on one slow probe

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Medium — self-inflicted Grafana/Prometheus flapping; intermittent Cloudflare 502.
**Status:** observed live on the rebuilt hub 2026-09-20 ~16:57 PDT. Fix below NOT yet in git.

## Symptom

Found while completing the hub rebuild that cleared the kine compaction stall
(`docs/bugs/2026-09-09-hub-kine-compaction-stall.md`). After the rebuild the apiserver is
healthy — `kubectl get nodes` answers in 0.05s, down from 5.5s — and
`kubectl port-forward` establishes on the first try every time. Grafana is `3/3 Running`.

The forward nevertheless still restarts roughly every 45 s:

```
[Sun Sep 20 16:57:51 PDT 2026] health check failed — restarting stale port-forward
[Sun Sep 20 16:57:53 PDT 2026] starting svc/kube-prometheus-stack-grafana port-forward
[Sun Sep 20 16:58:41 PDT 2026] health check failed — restarting stale port-forward
```

Five restarts in two minutes. Between them the forward serves traffic normally —
`Handling connection for 3001` repeatedly, and an external `curl` gets `200`.

Measured `/api/health` through the forward, 12 samples 4 s apart:

```
code=200 total=0.595   code=200 total=1.941   code=200 total=0.512
code=200 total=0.240   code=200 total=0.046   code=200 total=0.067
code=200 total=0.152   code=200 total=0.190   code=000 total=3.315
```

and in an earlier window, one outright `code=503 total=0.254` from Grafana itself.

The distribution is the point: median ~0.2 s, but a tail past 3 s, plus occasional 503 while
Grafana reloads provisioned dashboards.

## Root cause — one bad probe is treated as a dead forward

`scripts/lib/providers/k3s-hostinger.sh:412-441`,
`_hostinger_write_monitoring_port_forward_wrapper`, generates the supervisor:

```bash
  while kill -0 "${_pf_pid}" 2>/dev/null; do
    sleep 5
    ((_elapsed += 5))
    if ((_elapsed >= 30)) && ! curl -fsS --max-time 3 "${_health_url}" >/dev/null 2>&1; then
      printf '%s\n' "[$(date)] health check failed — restarting stale port-forward" >> "${_log}"
      kill "${_pf_pid}" 2>/dev/null || true
      break
    fi
  done
```

Two independent defects:

1. **No consecutive-failure tolerance.** A *single* failed probe kills the forward. There is no
   counter — one 3.3 s response, or one 503 during dashboard provisioning, and a working forward
   is destroyed. Compare `bin/k3dm-node-health-watch`, which requires
   `K3DM_NODE_RECOVERY_FAILURE_THRESHOLD` consecutive failures precisely to avoid this.
2. **`--max-time 3` is tighter than the target's own tail latency.** Grafana's `/api/health`
   touches its database and is measurably slower than 3 s under dashboard load. `curl -f` also
   fails the probe on any HTTP ≥ 400, so a transient 503 counts as "forward is dead" when it is
   in fact proof the forward is alive and reaching Grafana.

The restart is not merely useless, it is harmful: each cycle drops the listener for ~2 s, which
is exactly the window cloudflared reports upstream as a **502**. The supervisor manufactures the
outage it exists to prevent.

This is the **host-side port-forward instance of a disease family already documented in this
repo**:

| Doc | Target | Probe that misfired |
|---|---|---|
| `2026-08-27-keycloak-restart-loop-tight-probes.md` | pod | k8s liveness probe |
| `2026-08-28-node-health-watch-restart-loop-slow-node.md` | node | `/healthz` proxy, 5 s |
| `2026-07-06-grafana-repeatedly-killed-by-liveness-probe-under-argocd-image-updater-dashboard-load.md` | Grafana pod | k8s liveness under dashboard load |
| **this doc** | host port-forward | supervisor `curl`, 3 s |

The 2026-07-06 doc is the same target and the same trigger — dashboard-load latency — one layer
down. The lesson did not propagate to the host-side supervisor.

## Why it was invisible before

Pre-rebuild, this supervisor was restarting for a genuine reason: the kine stall made
`kubectl port-forward` fail outright with `net/http: TLS handshake timeout`, and only 121 of 263
attempts in one window even reached `Forwarding from`. The real fault masked this one. Clearing
the datastore removed the loud cause and left the quiet one.

## Fix

Give the probe a failure threshold and a timeout matched to the target, both env-overridable,
following the `k3dm-node-health-watch` precedent. In
`_hostinger_write_monitoring_port_forward_wrapper`, replace the inner loop:

```bash
  _pf_pid=\$!
  _elapsed=0
  _fails=0
  while kill -0 "\${_pf_pid}" 2>/dev/null; do
    sleep 5
    ((_elapsed += 5))
    if ((_elapsed >= 30)); then
      if curl -fsS --max-time "\${_health_timeout}" "\${_health_url}" >/dev/null 2>&1; then
        _fails=0
      else
        ((_fails += 1))
        if ((_fails >= _health_threshold)); then
          printf '%s\\n' "[\$(date)] health check failed \${_fails}x — restarting stale port-forward" >> "\${_log}"
          kill "\${_pf_pid}" 2>/dev/null || true
          break
        fi
      fi
    fi
  done
```

with these declared above the outer `while true`:

```bash
_health_timeout="\${K3DM_PF_HEALTH_TIMEOUT:-8}"
_health_threshold="\${K3DM_PF_HEALTH_THRESHOLD:-3}"
```

Defaults: timeout `3 → 8` s, threshold `1 → 3`. Three consecutive failures at 5 s apart means a
forward is declared dead after ~15 s of sustained unreachability, which still catches a genuinely
broken SPDY stream promptly while tolerating a single slow or 503 response.

`_fails=0` on success is required — the counter must measure *consecutive* failures, not
cumulative ones over the forward's lifetime.

Note the wrapper runs under `set -u` (not `set -e`), so the `((...))` arithmetic is safe: an
expression evaluating to 0 returns exit status 1 but cannot abort the script.

## Scope

`_hostinger_write_monitoring_port_forward_wrapper` is shared — it is parameterized by
`context_name` and generates the supervisor for **both** the hostinger cluster and the local k3d
hub (the live hub wrapper targets `--context "k3d-k3d-cluster"`). One fix covers Grafana,
Prometheus, Alertmanager and Pushgateway on both clusters. The generated
`health_path` stays `/metrics` for everything except Grafana, which uses `/api/health`.

Do **not** change the frontend wrapper (`_hostinger_write_frontend_port_forward_wrapper`) — it
has no health probe at all and is out of scope.

## Tests

`scripts/tests/lib/provider_contract.bats` already asserts on the generated wrapper (see the
`com.k3d-manager.grafana-port-forward.sh` assertions). Add assertions there that the generated
wrapper contains:

1. `K3DM_PF_HEALTH_THRESHOLD` and `K3DM_PF_HEALTH_TIMEOUT` with their defaults.
2. `_fails=0` reset on a successful probe.
3. `--max-time "${_health_timeout}"` rather than a hardcoded `--max-time 3`.

Assert on meaningful tokens — no whole-line `grep -F` of a full source line, and no bare `!`.
A disappearance gate for the old form (`--max-time 3` → 0 occurrences) is preferable to a count.

## Definition of Done

- [ ] Threshold + timeout env-overridable, defaults 3 and 8
- [ ] `_fails` resets to 0 on a successful probe
- [ ] BATS assertions above pass; `make test` green or failures shown pre-existing
- [ ] `shellcheck scripts/lib/providers/k3s-hostinger.sh` — zero new warnings
- [ ] Live hub wrapper regenerated and the launchd agent restarted; restart rate drops to 0
      over a 10-minute observation window
- [ ] CHANGELOG `[Unreleased] → ### Fixed`
- [ ] `memory-bank/activeContext.md` + `progress.md` updated

## What NOT to Do

- Do NOT remove the health check. A stale forward whose SPDY stream has broken while the process
  lives is a real failure mode this supervisor exists to catch.
- Do NOT raise the timeout so far that a dead forward goes unnoticed for minutes.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- Do NOT edit the frontend port-forward wrapper.
