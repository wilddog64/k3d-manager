# Bug: a sandbox `make up` takes over the launchd agents behind Hostinger's public routes

**Filed:** 2026-10-05, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN — operator workaround below; fix spec to follow
**Severity:** high. The public `frontend.3ai-talk.org` returns 502 once the ACG sandbox expires,
although the Hostinger cluster and its frontend pod are healthy.

## Symptom (2026-10-05, about 04:00 UTC)

`make status CLUSTER_PROVIDER=k3s-hostinger`:

```
✗ Frontend: HTTP Error 502: Bad Gateway
✗ Pushgateway: <urlopen error [Errno 61] Connection refused>
Overall: FAIL (2 errors, 0 warnings)
```

ArgoCD, Keycloak, Prometheus (401, as intended) and Grafana were fine.

## Evidence (Claude, read-only)

- **Hostinger is healthy.** `frontend-87f4b57f4-x58gz` is `1/1 Running`, and `endpoints/frontend` is
  `10.42.0.232:8080`. No ingress and no in-cluster `cloudflared` sit in front of it.
- **The public route ends on this Mac.** In `~/.cloudflared/config.yml`, `frontend.3ai-talk.org`
  routes to `http://127.0.0.2:80`. That address is served by the root LaunchDaemon
  `com.k3d-manager.frontend-browser-http`.
- **The daemon now forwards from the sandbox.** Its plist runs
  `~/.local/share/k3d-manager/k3s-aws/bin/frontend-browser-http.sh` (written Oct 3 19:28 by the
  sandbox `make up`), which runs `kubectl --context ubuntu-k3s port-forward --address=127.0.0.2 svc/frontend 80:80`.
  The Hostinger copy of the wrapper (`k3s-hostinger/bin/frontend-browser-http.sh`, Sep 29) still
  exists, but no daemon points at it.
- **The sandbox is gone.** The forward logs show `dial tcp 54.187.188.234:6443: i/o timeout`
  every 30 s.
- **Pushgateway, same pattern.** The user agent `com.k3d-manager.pushgateway-port-forward`
  forwards `svc/prometheus-pushgateway` from `--context ubuntu-k3s` on `9091:9091`. It logs to
  `k3s-aws/logs/pushgateway-pf.log`, which shows the same timeouts. The status check probes
  `localhost:9091` for k3s-hostinger.
- `com.k3d-manager.frontend-port-forward` (`3000:80`) also points at `ubuntu-k3s`.

## Cause

`bin/cluster-up` (sandbox) and `scripts/lib/providers/k3s-hostinger.sh`
(`_hostinger_refresh_access_layer`, around :583–:700) install launchd jobs with **the same labels
and the same local ports**: `com.k3d-manager.frontend-browser-http` on `127.0.0.2:80`, and
`com.k3d-manager.pushgateway-port-forward` on `9091`. The provider that ran last owns them.
A sandbox lives 4–8 hours, so a sandbox `make up` breaks Hostinger's public frontend a few hours
later, and nothing restores it.

## Operator workaround (now)

`make refresh-edge` alone does **not** fix the frontend. `_hostinger_refresh_access_layer` rewrites
the wrapper in `k3s-hostinger/bin/` and restarts the system daemon, but it never rewrites
`/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist`. That plist still runs the
`k3s-aws/` wrapper, so the restart brings back the dead sandbox forward. It does fix Pushgateway,
whose user plist it regenerates.

In Terminal.app:

1. Point the root daemon at the Hostinger wrapper:
   `sudo plutil -replace ProgramArguments.1 -string "$HOME/.local/share/k3d-manager/k3s-hostinger/bin/frontend-browser-http.sh" /Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist`
2. Refresh the edge, which restarts that daemon and rewrites the Pushgateway forward:
   `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`
3. `make status CLUSTER_PROVIDER=k3s-hostinger`

`keycloak-browser-http` points at the `k3s-aws` wrapper too. It does not serve a public route
(`keycloak.3ai-talk.org` goes to `127.0.0.1:8880`), so it is left alone here, but the fix must cover it.

## Second defect: the edge refresh never owns the system plists

The same gap means `make refresh-edge` can never recover from this state on its own. The fix
must make `_hostinger_refresh_access_layer` write (or verify) the `ProgramArguments` of each
system daemon it restarts.

## Fix direction (to spec)

- **Option A: per-provider labels and ports.** Give the sandbox's frontend and Pushgateway
  forwards provider-scoped labels and their own ports, so the two providers never collide. The
  tunnel route `frontend.3ai-talk.org` then belongs to Hostinger alone.
- **Option B: the sandbox does not install public-route daemons.** `127.0.0.2:80` exists for the
  public tunnel. The sandbox needs only its own local forwards.
- **In either case:** `cluster-down` / sandbox expiry must not leave a Hostinger-route label
  pointing at a dead context. `make status` could also flag any `com.k3d-manager.*` plist whose
  `--context` differs from the provider being checked.
