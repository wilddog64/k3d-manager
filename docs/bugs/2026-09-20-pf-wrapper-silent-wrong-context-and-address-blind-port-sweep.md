# Port-forward wrapper resolves its context once, fails over silently, and sweeps a port address-blind

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Template:** `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`
**Severity:** High — one wrapper has been port-forwarding against the **wrong cluster** for 16
days while silently killing a second, healthy listener every 31 seconds.

## Symptom

`make status CLUSTER_PROVIDER=k3d` reports Keycloak as the last remaining error:

```
✗ Keycloak: <urlopen error [Errno 61] Connection refused>
```

The `com.k3d-manager.keycloak-browser-http` LaunchDaemon is *running* — `launchctl print`
shows `state = running`, `pid = 30083`, `last exit code = (never exited)` — yet its log is a
90 MB loop of:

```
[argocd-pf] starting port-forward: svc/istio-ingressgateway -> localhost:80
Error from server (NotFound): services "istio-ingressgateway" not found
[argocd-pf] port-forward exited before healthz became reachable — restarting
[argocd-pf] port 80 still in use — clearing stale listener(s) before retry
```

The service it cannot find **exists**:

```
$ kubectl --context k3d-k3d-cluster -n istio-system get svc istio-ingressgateway
istio-ingressgateway   LoadBalancer   10.43.71.71   ...   80:31901/TCP   74m
```

## Root cause — proven, not inferred

Caught the daemon's own short-lived child by polling `ps` for 75 s:

```
$ ps -o pid=,ppid=,command= -ax | grep port-forward
82444 30083 /opt/homebrew/bin/kubectl --context ubuntu-hostinger port-forward \
            svc/istio-ingressgateway -n istio-system 80:80
```

`--context ubuntu-hostinger`. The wrapper was configured with `CONTEXT=k3d-k3d-cluster` and is
running against the remote cluster instead. `ubuntu-hostinger`'s `istio-system` holds `istiod`
only — no ingressgateway — which is exactly the reported `NotFound`.

Three defects in the template combine to produce this.

### D1 — context resolution happens once, outside the loop

`port-forward-wrapper.sh.tmpl:26-35` resolves `_kubectl_context_arg` at **process start**, then
`while true` (line 110) reuses that string forever. The daemon has `KeepAlive` and never exits:

```
runs = 1
last exit code = (never exited)
$ ps -o lstart= -p 30083
Fri Sep  4 08:41:28 2026        # 16 days
```

So whatever the context landscape looked like at 08:41 on Sep 4 is frozen in for the process's
entire life. A `k3d cluster delete` / `create` cycle — which removes and re-adds the
`k3d-k3d-cluster` context — cannot be picked up. The wrapper resolved during a window when the
k3d context was absent, fell back, and stayed fallen back.

### D2 — the fallback is silent

Of the three branches at lines 26-35, only the *third* logs anything:

```bash
if [[ -n "${CONTEXT}" ]] && kubectl config get-contexts "${CONTEXT}" ...; then
   _kubectl_context_arg="--context ${CONTEXT}"          # intended
else
   _current_context="$(kubectl config current-context ...)"
   if [[ -n "${_current_context}" ]] && ...; then
      _kubectl_context_arg="--context ${_current_context}"   # <-- SILENT wrong-cluster
   elif [[ -n "${CONTEXT}" ]]; then
      printf ... "WARNING: kubectl context '${CONTEXT}' not found — falling back"   # logs
   fi
fi
```

The branch that actually causes harm — substituting a *different real cluster* — prints nothing.
Confirmed: `grep -c WARNING` over the whole 90 MB log returns **0**. This is what made the
failure undiagnosable from its own log; the log accuses the cluster of missing a service that is
plainly present.

### D3 — `_clear_stale_listeners` is address-blind, and kills a healthy neighbour

Lines 76 and 93 enumerate listeners by **port only**:

```bash
lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN -t
```

Two daemons legitimately share port 80 on different addresses:

| Daemon | Bind |
|---|---|
| `com.k3d-manager.keycloak-browser-http` | `localhost:80` |
| `com.k3d-manager.frontend-browser-http` | `127.0.0.2:80` |

So the keycloak wrapper's sweep matches the **frontend's** forward and `kill`s it. Because D1/D2
put the wrapper in a permanent retry loop, the sweep runs every cycle. Measured causation — the
keycloak log grew and the frontend died in the *same second*, repeatedly:

```
keycloak log 18:01:36 size=90100181
keycloak log 18:01:51 size=90100334      # +153 B
frontend log: [Sun Sep 20 18:01:51 PDT 2026] starting frontend port-forward   # killed & restarted
```

Frontend `Terminated: 15` at 17:59:27 → 17:59:58 → 18:00:31 → 18:01:51, a clean ~31 s beat
(`sleep 30` + teardown). `forks = 23015` on the keycloak daemon. The frontend log is 69 MB of
the same churn. **A broken wrapper is silently degrading an unrelated, healthy service.**

## Deployed wrapper is also stale

The on-disk wrapper is an older generation than the template. Template has
`RESTART_DELAY=2`, `HEALTH_FAILURE_THRESHOLD=6`, `--max-time 5`, `--address=127.0.0.1`; the
deployed copy has hardcoded `sleep 30`, no failure threshold, `--max-time 1`, and **no
`--address`**. `bin/cluster-up:1246-1249` only writes the wrapper when the *plist* is missing,
and `_hostinger_refresh_access_layer` regenerates the argocd, keycloak-pf and frontend wrappers
but **never** `keycloak-browser-http.sh`. So a fixed template does not reach this daemon.

Note the missing `--address` is why the deployed copy binds `localhost` rather than `127.0.0.1`
explicitly — it does not change the collision, since the sweep ignores address either way.

## Fix

Three changes to `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`, plus one to the installer.

**1 — scope the sweep to the address actually being bound.** Add an `ADDRESS` knob (default
`127.0.0.1`, matching the existing `--address` literal) and filter on it:

```bash
lsof -nP -iTCP@"${ADDRESS}":"${LOCAL_PORT}" -sTCP:LISTEN -t
```

Apply to both `_port_in_use` (line 76) and `_clear_stale_listeners` (line 93). A wrapper must
never be able to kill a listener it does not own.

**2 — re-resolve the context every iteration.** Move lines 26-35 into a function and call it at
the top of the `while true` body, so a cluster rebuild is picked up on the next cycle.

**3 — log the silent fallback.** The `_current_context` branch must print which context it
substituted and which it wanted:

```bash
printf '%s\n' "[${LOG_TAG}] WARNING: context '${CONTEXT}' not found — using current-context '${_current_context}' instead" >> "${LOG_FILE}"
```

**4 — regenerate the wrapper unconditionally.** `bin/cluster-up` must call
`_argocd_write_port_forward_wrapper` for `keycloak-browser-http.sh` regardless of whether the
plist exists, the way the other wrappers are refreshed.

Also worth doing while in here: the log tag is hardcoded `[argocd-pf]` in a template used by at
least three different services, which is why a Keycloak listener logs as argocd. Parameterise it
as `LOG_TAG`. This is cosmetic but it actively misleads during triage.

## Out of scope — do NOT bundle

- Log rotation for the two runaway logs (90 MB + 69 MB). Real, but a separate concern.
- The `frontend-browser-http.sh` `--context ubuntu-hostinger` target, which is why
  `make status` shows a **false green** `Frontend: HTTP 200` served by the remote cluster rather
  than the hub. Separate defect, separate spec.
- `_hostinger_refresh_access_layer`'s broader wrapper-coverage gaps beyond item 4.

## Tests

`scripts/tests/` — assert on the template text, which is static and cannot flake:

- sweep and in-use probe both use the `-iTCP@` address-scoped form; assert the bare
  `-iTCP:"${LOCAL_PORT}"` form has **disappeared** (count → 0)
- context resolution appears *after* the `while true` line (ordering assertion)
- the `_current_context` branch contains a `WARNING` printf
- generated wrapper for keycloak-browser-http contains `--address`

## Definition of Done

- [ ] Sweep cannot match a different bind address on the same port
- [ ] Context re-resolved per iteration
- [ ] Silent fallback now logs a WARNING naming both contexts
- [ ] `keycloak-browser-http.sh` regenerated on every `cluster-up`
- [ ] BATS green; `make test` green or failures shown pre-existing
- [ ] `shellcheck` — zero new warnings
- [ ] CHANGELOG `[Unreleased] → ### Fixed`
- [ ] Live: daemon restarted, `--context k3d-k3d-cluster` confirmed in its argv, frontend forward
      survives ≥5 minutes without a `Terminated: 15`

## What NOT to Do

- Do NOT "fix" this by hardcoding `--context k3d-k3d-cluster`. The freeze and the silence are the
  bugs; a hardcoded context repeats
  [`2026-06-06-prometheus-port-forward-wrong-kubectl-context`](2026-06-06-prometheus-port-forward-wrong-kubectl-context.md).
- Do NOT delete `_clear_stale_listeners`. It exists for the zombie-port-forward failure mode
  (`reference_single_service_502_zombie_port_forward`). Scope it, don't remove it.
- Do NOT remove the current-context fallback — make it loud, not absent.
