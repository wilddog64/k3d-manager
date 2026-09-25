# Incident: `make up` cleanup unloaded the Cloudflare tunnel — 9.5h public outage, no alert fired

**Date:** 2026-09-25
**Reported by:** the operator, with a Cloudflare **Error 1033** page for `grafana.3ai-talk.org`
(Ray `a409ea59ed406afb`, 12:08:38 UTC) and the observation *"I didn't get any text notification"*
**Status:** service RESTORED 12:16:51Z. Two follow-ups open (see below).

## Timeline

| Time (UTC) | Event |
|---|---|
| 02:44:58 | `cloudflared` logs `no more connections active and exiting`; `Tunnel server stopped` |
| 02:44:58 → 12:16:51 | All 7 public hostnames return Cloudflare 1033 (9h 32m) |
| 12:08:38 | Operator hits the 1033 page on `grafana.3ai-talk.org` |
| 12:16:51 | `launchctl bootstrap` of `com.k3d-manager.cloudflare-tunnel`; QUIC + TCP prechecks pass |
| 12:16:56 | `[cve-remediate] triggered … job=cve-auto-1790338616` — the webhook pipeline resumes **5s later** |

## What broke

`com.k3d-manager.cluster-up`'s failure path ends with:

```
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
```

The third `make up CLUSTER_PROVIDER=k3s-aws` attempt failed at Step 10b/14 at 02:44, and that
cleanup unloaded the `com.k3d-manager.cloudflare-tunnel` LaunchAgent. The plist stayed present
and `launchctl print-disabled` still reported it **enabled** — it was simply not bootstrapped,
so nothing retried it and nothing reported it.

The tunnel is the single ingress for **all seven** public hostnames, not just Grafana:

```
argocd / frontend / keycloak / prometheus / alertmanager / grafana / webhook  .3ai-talk.org
```

Every local backend stayed healthy throughout — after the restore the public status codes match
the loopback ones exactly (grafana 302, argocd 200, keycloak 302, alertmanager 401,
prometheus 401, webhook 401). Nothing was wrong behind the tunnel; only the tunnel was gone.

### Blast radius beyond the web UIs

Both Alertmanager webhook receivers post to `https://webhook.3ai-talk.org`:

| Receiver | Path |
|---|---|
| `k3dm-analyze` | `/api/v1/analyze` |
| `k3dm-cve-remediate` | `/api/v1/cve-remediate` |

So CVE auto-remediation and alert analysis were down for the same 9.5 hours. This is visible as
`alertmanager_notifications_failed_total{integration="webhook",reason="serverError"} = 95` out of
142 attempts. The counter **froze at 95** the moment the tunnel returned, and the next
remediation job fired 5 seconds later — that pairing is what identifies the tunnel as the cause
rather than a webhook fault.

## Why no notification arrived

Two independent facts, and neither is a delivery failure:

1. **Nothing watches the tunnel.** There is no blackbox exporter in `monitoring`, and no
   PrometheusRule anywhere references a public hostname, `probe_*`, `cloudflare` or `tunnel`.
   The outage was therefore never an alert in the first place.
2. **The text path is healthy.** `sms-critical` matches `severity="critical"` and is an
   `email_configs` receiver — `alertmanager_notifications_total{integration="email"} = 19` with
   **zero** failures. It would have delivered had anything fired.

Prometheus was evaluating normally the whole time (53 alerts firing, including `TargetDown`,
`KubeJobFailed`, `E2EVerificationFailing`, `ArgoCDAppOutOfSync`). The monitoring stack was up and
blind, which is the worst of the three possible states and the one least visible from a dashboard
— especially as the dashboard itself was behind the dead tunnel.

Also worth recording: the Alertmanager root route's receiver is `null`, so any alert not matched
by a child route is dropped silently. A future tunnel alert must be given an explicit route; adding
the rule alone would not notify.

## Recovery

```
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist
```

No sudo required (user GUI domain). Verified by 17 `Registered tunnel connection` entries and the
seven public probes above.

## Follow-ups (NOT started — need the owner's go)

1. **Detect it.** Add a blackbox probe over the seven public hostnames plus a
   `CloudflareTunnelDown` rule, routed explicitly to `sms-critical` (the root receiver is `null`).
   Until this exists, every tunnel outage is operator-discovered.
2. **Don't kill it.** `cluster-up`'s failure cleanup should not unload the public-ingress tunnel;
   a failed ACG provision has no reason to take the hub's public edge down with it.
3. **Unhandled 500 in the webhook.** `bin/k3dm-webhook` `_create_cve_scan_job` raises
   `RuntimeError: error: failed to create job: jobs.batch "cve-auto-1790038164" already exists`
   out of `do_POST`, which Alertmanager records as a `serverError`. An already-existing job is a
   normal race with the cooldown path and should be treated as idempotent, not a 500. This is
   independent of the tunnel outage.

## Lesson

A LaunchAgent that is *enabled* but *not bootstrapped* is indistinguishable from a healthy one in
`launchctl print-disabled`, and absent from `launchctl list` in a way that reads as "no such job"
rather than "job down". Check membership in `launchctl list`, not the disabled map. More broadly:
the tunnel had no monitor because it is infrastructure *for* monitoring — the path that would
report its death runs through it.

---

## Resolution — 2026-09-25

**Reproduced three times** (2026-09-24 once, 2026-09-25 twice). Each occurrence was a `cluster-up`
failure at **Step 10b**, and each took all 7 public hostnames down (`bin/public-endpoint-probe`
verdict `edge-down`, every host `530`) until the agent was manually re-bootstrapped.

**Root cause.** `_acg_up_cleanup` (`bin/cluster-up`) ran an *unconditional*
`launchctl bootout` of `com.k3d-manager.cloudflare-tunnel` on any non-zero exit. But `cluster-up`
does not install or bootstrap that tunnel until roughly line 1809 — far past Step 10b at line 811.
So on every one of these failures the cleanup tore down a long-lived service **the run had never
started**, and which it had no business owning: the plist lives in `~/Library/LaunchAgents` with
`RunAtLoad` and `KeepAlive=true`, survives reboots, and serves the hub's public ingress
independently of any ACG sandbox.

**Fix.** The bootout is now gated on `_ACG_TUNNEL_PLIST_CREATED`, set only where the run installs
the plist and no plist existed beforehand. A failure that never reached the tunnel step now logs:

```
INFO: [acg-up] leaving the cloudflare tunnel up — it is the hub's public ingress and predates this run
```

"Clean up what you created" is preserved: a run that genuinely created the agent from scratch still
removes it on failure.

**Coverage.** Four BATS cases in `scripts/tests/bin/cluster_up.bats` — pre-existing tunnel is left
alone, a self-created one is removed, the marker is set exactly once, and the cleanup body no
longer boots out unconditionally. Mutation-proven: restoring the unconditional bootout fails three
of the four.

**Not fixed by this change.** There is still no alert on the outage — no blackbox probe over the 7
public hostnames and no `CloudflareTunnelDown` rule, and the Alertmanager root receiver is `null`,
so a future outage is still silent. Hermes `reachability()` (`scripts/lib/hermes/sensors.py:107`)
already has an `edge-down` verdict and would have caught all three, but its LaunchAgent
(`com.k3d-manager.hermes`) is installed and never bootstrapped. Those two remain open.
