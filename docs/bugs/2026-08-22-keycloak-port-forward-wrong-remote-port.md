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

## Recurrence 2026-10-03 — hub Keycloak now exposes port 80; the wrapper pins 8080 (Claude)

**Status:** OPEN — spec below, for Codex. A live stopgap is for the operator to run.

After the hub rebuild, `deploy/keycloak` is `1/1` and `shopping-cart-identity` is `Synced/Healthy`.
Even so, `https://keycloak.3ai-talk.org/realms/master` returns **502** and `localhost:8880` returns
`000`. `~/.local/share/k3d-manager/k3s-aws/logs/keycloak-pf.log` loops:

```
error: Service keycloak does not have a service port 8080
[keycloak-pf] port-forward exited before healthz became reachable — restarting
```

**Why it came back.** The fix above changed `80` to `8080` because the Bitnami chart's `svc/keycloak`
exposes `http:8080`. The hub's Keycloak now comes from `shopping-cart-infra`
`identity/keycloak/deployment.yaml`, whose `svc/keycloak` exposes `http:80 → targetPort http`. A
pinned port number is right for only one of the two sources.

The reconcile's smoke seed then fails too: it mints its admin token through the public URL
(`curl ... https://keycloak.3ai-talk.org/... : 56`, `could not mint master admin token`).

### Fix — forward to the named port, not a number

`kubectl port-forward svc/keycloak 8880:http` resolves the Service port named `http` (80 on the
infra manifest, 8080 on the chart), so the same wrapper works for both.

1. `bin/cluster-up` (the `_argocd_write_port_forward_wrapper` call for `svc/keycloak`): REMOTE_PORT
   `"8080"` → `"http"`.
2. `scripts/lib/providers/k3s-hostinger.sh` (the `SERVICE="svc/keycloak"` envsubst block):
   `REMOTE_PORT="8080"` → `REMOTE_PORT="http"`.
3. Confirm that `_argocd_write_port_forward_wrapper` (`scripts/plugins/argocd.sh`) and the hostinger
   template only interpolate REMOTE_PORT into `${LOCAL_PORT}:${REMOTE_PORT}`, and never do
   arithmetic or numeric validation on it. If they do, allow `[a-z][a-z0-9-]*`.

**Gates (offline):** BATS asserts that each generated wrapper contains `8880:http` and no `8880:8080`.
Mutation: restoring `8080` turns the test red. shellcheck is clean.

### Live stopgap (operator)

Edit `~/.local/share/k3d-manager/k3s-aws/bin/keycloak-port-forward.sh`:
`REMOTE_PORT=8080` → `REMOTE_PORT=http` and `"8880:8080"` → `"8880:http"`. Then
`launchctl kickstart -k gui/$(id -u)/com.k3d-manager.keycloak-port-forward`. The next `cluster-up`
regenerates the file, so the source fix is still required.

### Related defect found in the same run — the Keychain write fails silently

`_hub_recovery_sync_vault_root_token` (`scripts/plugins/hub_recovery.sh`) pipes
`add-generic-password` into `security -i`. When it ran without a GUI Keychain session, the log
showed `SecKeychainItemModifyContent: User interaction is not allowed` / `-25308`, yet the reconcile
went on as if the step had passed. That leaves the Keychain copy of the **rebuilt** Vault's root
token stale, which is a DR gap: the next recovery would push the old token back. Fix: verify the
write by reading the item back and comparing it, without printing it. On a mismatch, `_err` and
return 1. Re-run the reconcile in the foreground in Terminal.app.
