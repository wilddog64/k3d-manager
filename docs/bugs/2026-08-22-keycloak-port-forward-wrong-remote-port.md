# Keycloak :8880 port-forward targets wrong remote port → public 502 (2026-08-22)

**Severity:** high (Keycloak public URL 502 even when the pod is healthy).
**Cluster:** hub `k3d-k3d-cluster`, ns `identity`.
**Related:** `docs/bugs/2026-08-22-keycloak-not-deployed-on-hub-sso-down.md` (surfaced
while restoring Keycloak after the hub deploy).

## Observed state

After `deploy_keycloak` brought `keycloak-0` to 1/1 Running, both
`http://127.0.0.1:8880/realms/master` and `https://keycloak.3ai-talk.org/realms/master`
returned 000 / 502. The managed port-forward log
(`~/.local/share/k3d-manager/logs/keycloak-pf.log`) looped:

```
error: Service keycloak does not have a service port 80
[argocd-pf] port-forward exited before healthz became reachable — restarting
```

## Root cause

`bin/cluster-up:1544` installs the keycloak port-forward wrapper via
`_argocd_write_port_forward_wrapper` with the wrong **REMOTE_PORT** and an
unreachable **HEALTHZ_URL**:

```
... "svc/keycloak" "8880" "80" "http://localhost:8880/health/live"
                            ^^^^ REMOTE_PORT   ^^^^^^^^^^^^^^^^^^^^^^ HEALTHZ
```

- `svc/keycloak` exposes only `http:8080` (`targetPort http`). There is **no port
  80** → `kubectl port-forward svc/keycloak 8880:80` fails immediately on every
  wrapper restart, so nothing ever listens on :8880.
- The chart does not enable the Keycloak health endpoints on the HTTP port
  (`/health/live` → 404 on 8080; the Quarkus 9000 management port is not exposed),
  so even with the port corrected the wrapper's healthz probe would never pass and
  it would keep tearing the forward down. `/realms/master` returns 200 and is a
  valid liveness proxy.

(The sibling argocd call at `bin/cluster-up:488` uses `8080 80`, which is correct —
`svc/argocd-server` genuinely exposes port 80. Only the keycloak call is wrong.)

## Fix

`bin/cluster-up:1544` — change the REMOTE_PORT arg `"80"` → `"8080"` and the
HEALTHZ_URL `"http://localhost:8880/health/live"` → `"http://localhost:8880/realms/master"`:

```
  _argocd_write_port_forward_wrapper "${_kc_pf_wrapper}" "${_kc_pf_log}" \
    "$(command -v kubectl)" "$(command -v curl)" "identity" "k3d-k3d-cluster" \
    "svc/keycloak" "8880" "8080" "http://localhost:8880/realms/master"
```

## Live stopgap already applied (2026-08-22)

The installed wrapper `~/.local/share/k3d-manager/bin/keycloak-port-forward.sh`
(generated output, regenerated on next cluster-up) was hand-corrected
(`8880:80`→`8880:8080`, `/health/live`→`/realms/master`) and
`launchctl kickstart -k ...keycloak-port-forward` restarted it. Result: local
:8880 and public `keycloak.3ai-talk.org/realms/master` both 200. The source fix
above makes this survive the next `cluster-up`.

## Verification

- `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8880/realms/master` → 200
- `curl -s -o /dev/null -w '%{http_code}' https://keycloak.3ai-talk.org/realms/master` → 200
- `keycloak-pf.log` shows `healthz reachable — monitoring backend availability`
  (no restart loop).
