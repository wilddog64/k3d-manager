# keycloak-0 restart loop — Bitnami chart's tight probes on a CPU-starved hub

**Filed:** 2026-08-27
**Severity:** Medium — recurring restarts + credentialed-login false-red on `make status`.
**Status:** IMPLEMENTED + LIVE (values override committed 2026-08-27; live-patched onto the
StatefulSet the same day — keycloak-0 now `1/1 Running`, 0 restarts). Rolling the pod exposed a
**second, cluster-wide casualty of the same disease — CoreDNS crashlooping** (see "CoreDNS
collateral" below); also fixed live.

## Symptom

`keycloak-0` (ns `identity`) has **67 restarts** (last kill 2026-08-27 17:31). `make status`
reports `✓ Keycloak: HTTP 200` (health route up) but `✗ Keycloak login: read operation timed
out` — the credentialed token POST can't complete inside its 8s cap.

## Root cause — NOT a crash, NOT OOM

Every termination is **exit 143 (SIGTERM)** — the kubelet is *killing* the container — or exit
0 (graceful, from a `NodeNotReady` blip). No `137`/`OOMKilled` anywhere: the 768Mi memory limit
is not the driver.

The kill trigger is the **Bitnami `keycloak-25.2.0` chart's default probes**, which
`scripts/etc/keycloak/values.yaml.tmpl` does not override, colliding with a CPU-starved hub:

| Probe | Live default | Failure mode |
|---|---|---|
| Liveness | `tcpSocket periodSeconds=1 timeoutSeconds=5 failureThreshold=3` | Probes **every 1s**; 3 consecutive misses = **3s unresponsive → SIGTERM**. A single JVM GC pause or hub CPU-contention burst (container throttled at the 750m CPU limit) hits it trivially. |
| Readiness | `httpGet /realms/master timeoutSeconds=1` | **1s** timeout on a JVM+DB endpoint; failing **×36 over 80m** (`context deadline exceeded … awaiting headers`). This is *also* the exact cause of the `make status` login-smoke timeout. |

Secondary driver: a `NodeNotReady` event during the CPU storm gracefully stops the pod (the
exit-0 terminations). CPU pressure hits Keycloak twice — directly (probe misses) and via node
flaps.

The restarts clustered during the hub CPU overcommit (Steps 1/2, see
`2026-08-27-hub-cpu-overcommit-resource-governance.md` and
`2026-08-27-hub-load-shed-observability-footprint.md`). Recovery froze the counter, but the
zero-tolerance probes leave Keycloak fragile to any future CPU spike.

## The slow-boot amplifier (why loosening liveness alone was not enough)

Rolling the pod revealed a **third factor**: Keycloak runs Bitnami's `start-dev` profile, which
**re-runs Quarkus augmentation on every boot**. On the CPU-starved hub the live logs measured
`Quarkus augmentation completed in 172742ms` + `Keycloak … started in 154.023s` = a **~326s
cold start**. The chart ships **no startupProbe**, so liveness (`initialDelaySeconds:120` +
`5×10s` = ~170s) fired *mid-augmentation* and killed the JVM before it ever opened `:8080`
(`Liveness probe failed: connect: connection refused` → SIGTERM → SIGKILL 137). Loosening
liveness periods is necessary but insufficient — a **startupProbe** that gates liveness for the
full boot is required.

## Fix

Add startupProbe + probe + resource overrides to `scripts/etc/keycloak/values.yaml.tmpl`
(currently sets none). All levers are durable and CPU-independent:

```yaml
startupProbe:            # NEW — gates liveness for ~430s so the ~326s cold start completes
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 40
  successThreshold: 1
livenessProbe:
  enabled: true
  initialDelaySeconds: 120
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5
  successThreshold: 1
readinessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

- Liveness `periodSeconds 1→10` + `failureThreshold 3→5` → tolerates ~50s of transient
  unresponsiveness before a kill, instead of 3s.
- Readiness `timeoutSeconds 1→5` → survives a slow-but-alive realm endpoint; also greens the
  `make status` login smoke.
- CPU limit `750m→1000m`, mem `768Mi→1Gi` → JVM headroom so GC pauses are rarer/shorter.

Applying the Step 2 observability load-shed further reduces probe misses by freeing hub CPU at
the source (complementary, not a substitute).

## CoreDNS collateral (same disease, cluster-wide) — ⚠ live-patch NOT in git

Rolling keycloak-0 forced a cold start that could not resolve `keycloak-postgresql`
(`i/o timeout` to CoreDNS `10.43.0.10:53`). Cause: **CoreDNS was in CrashLoopBackOff (155
restarts, deployment `0/1 AVAILABLE`)** — the single replica was being killed by its own
liveness probe for the *identical* reason: `plugin/health: Local health request … took more
than 1s: 1.93s` under CPU starvation, and CoreDNS liveness has `timeoutSeconds:1
failureThreshold:3`. DNS was effectively down cluster-wide; only pods that never re-resolve
(cached connections) kept working — which is why the old long-lived keycloak-0 survived on the
probe kills alone and the outage stayed hidden until the roll.

Live fix applied: `kubectl -n kube-system patch deploy coredns` → liveness `timeoutSeconds
1→5`, `failureThreshold 3→5`; readiness `timeoutSeconds 1→3`. CoreDNS went `1/1` and stable;
DNS restored; keycloak then resolved postgres and booted.

**⚠ This CoreDNS patch is NOT captured in this repo.** CoreDNS is **k3s-managed**
(`objectset.rio.cattle.io/owner-gvk: k3s.cattle.io/v1`), reconciled from the on-node manifest
`/var/lib/rancher/k3s/server/manifests/coredns.yaml`. The live patch held this time, but k3s's
addon controller can revert it. **Follow-up:** persist the loosened CoreDNS probe durably — via
a k3s manifest override / HelmChartConfig, or by treating it as one more reason to land the hub
CPU load-shed (Step 2) so 1s probes stop failing at the source. Filed as a lead here rather than
a second doc.

## Rollout

Keycloak is deployed by the plugin's `helm upgrade --install`
(`scripts/plugins/keycloak.sh:147`), **not ArgoCD** — no ApplicationSet `$values` reapply trap
here. Roll via the keycloak deploy path (`./scripts/k3d-manager deploy_keycloak`), which renders
the template through `envsubst` and runs the Helm upgrade.

## Verification (acceptance)

- `kubectl -n identity get pod keycloak-0 -o jsonpath='{.spec.containers[0].livenessProbe}'` →
  `periodSeconds:10 failureThreshold:5`.
- Restart count stops climbing across a sustained window; no new exit-143 in
  `kubectl -n identity describe pod keycloak-0`.
- `make status` → `✓ Keycloak login` (token minted), and `Frontend login` no longer skipped.

## Evidence

`kubectl -n identity describe pod keycloak-0` 2026-08-27: `Exit Code: 143`; 36× readiness
`context deadline exceeded`; `Liveness: tcp-socket :http delay=120s timeout=5s period=1s
failureThreshold=3`; chart `keycloak-25.2.0`; `values.yaml.tmpl` sets no probe/resource block.
