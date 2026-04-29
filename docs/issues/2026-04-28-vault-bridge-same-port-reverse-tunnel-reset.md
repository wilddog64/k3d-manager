# Issue: vault-bridge reverse tunnel resets when remote and local Vault ports both use 8200

**Date:** 2026-04-28
**Status:** Partial fix; pod-origin bridge path still unstable
**Severity:** High

## What Was Attempted

After `make up` passed the local Vault sealed-state recovery, it reached Step 11 and waited for `ClusterSecretStore` readiness.

Observed output:

```text
INFO: [acg-up] Step 11/12 — Verifying ClusterSecretStore...
INFO: [acg-up] ClusterSecretStore not Ready yet (attempt 1/18) — waiting 10s...
...
INFO: [acg-up] ClusterSecretStore not Ready after 180s — check vault-bridge connectivity
INFO: [acg-up] Step 12/12 — Installing sandbox TTL watcher (launchd)...
INFO: [acg-up] Cluster is up.
```

The flow exited 0, but ESO later reported the store was invalid:

```text
$ kubectl --context ubuntu-k3s describe clustersecretstore vault-backend
Warning  InvalidProviderConfig  invalid vault credentials: Get "http://vault-bridge.secrets.svc.cluster.local:8201/v1/auth/token/lookup-self": EOF
```

## Actual Behavior

Local Vault health was valid when accessed directly through a fresh local port-forward, but the remote bridge path failed.

Broken path:

```text
$ ssh ubuntu 'curl -sS -i --max-time 5 http://127.0.0.1:8200/v1/sys/health; echo; curl -sS -i --max-time 5 http://127.0.0.1:8201/v1/sys/health'
curl: (56) Recv failure: Connection reset by peer

curl: (52) Empty reply from server
```

The remote listeners existed:

```text
LISTEN 0      5            0.0.0.0:8201       0.0.0.0:*    users:(("socat",pid=4135,fd=5))
LISTEN 0      128        127.0.0.1:8200       0.0.0.0:*    users:(("sshd",pid=13733,fd=9))
LISTEN 0      128            [::1]:8200          [::]:*    users:(("sshd",pid=13733,fd=7))
```

The failing topology was:

```text
remote 8200 -> SSH -R -> local localhost:8200 -> kubectl port-forward -> Vault 8200
remote 8201 -> socat -> remote localhost:8200
```

Remote access through that path caused the local `kubectl port-forward` on 8200 to exit.

## Root Cause

The tunnel used the same port number on both sides:

```text
-R 8200:localhost:8200
```

That made the remote Vault path fragile: a remote request through the reverse tunnel reset the connection and killed the local `kubectl port-forward` listening on 8200.

## Partial Fix

Split the local and remote Vault ports:

```text
remote 8200 -> SSH -R -> local 127.0.0.1:18200 -> kubectl port-forward -> Vault 8200
remote 8201 -> socat -> remote localhost:8200
```

Code changes:

- `scripts/plugins/tunnel.sh` now supports `TUNNEL_VAULT_REMOTE_PORT` and `TUNNEL_VAULT_LOCAL_PORT`.
- Default remote Vault reverse port remains `8200`.
- Default local Vault port-forward port is now `18200`.
- `bin/acg-up` starts the Vault port-forward on `${TUNNEL_VAULT_LOCAL_PORT:-18200}`.
- Local Vault seeding uses the same local port-forward port.
- `bin/acg-up` annotates `ClusterSecretStore/vault-backend` after applying it to force ESO to revalidate when the bridge path recovers but the manifest is otherwise unchanged.
- `bin/acg-up` fixes the Step 11 JSONPath filter from escaped `\"Ready\"` to `"` inside the single-quoted JSONPath expression.

## Live Proof

Manual test of the fixed topology:

```text
$ ./scripts/k3d-manager tunnel_stop
running under bash version 5.3.9(1)-release
[tunnel] stopped
```

```text
$ kubectl --context k3d-k3d-cluster -n secrets port-forward svc/vault 18200:8200 >/tmp/vault-18200-pf.log 2>&1 &
```

```text
$ ssh -f -N -o ExitOnForwardFailure=yes -R 8200:127.0.0.1:18200 ubuntu
```

```text
$ ssh ubuntu 'curl -sS -i --max-time 5 http://127.0.0.1:8200/v1/sys/health; echo; curl -sS -i --max-time 5 http://127.0.0.1:8201/v1/sys/health'
HTTP/1.1 200 OK
...
{"initialized":true,"sealed":false,...}

HTTP/1.1 200 OK
...
{"initialized":true,"sealed":false,...}
```

The local port-forward remained alive:

```text
$ ps -p "$(cat /tmp/vault-18200-pf.pid)" -o pid,ppid,stat,command
  PID  PPID STAT COMMAND
28578 28501 SN   kubectl --context k3d-k3d-cluster -n secrets port-forward svc/vault 18200:8200
```

## Follow-Up

`make up` was rerun after the code patch. The run exits 0 and reaches Step 12, but `ClusterSecretStore/vault-backend` still becomes `Ready=False` from inside the app cluster. The remaining issue is tracked separately in `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
