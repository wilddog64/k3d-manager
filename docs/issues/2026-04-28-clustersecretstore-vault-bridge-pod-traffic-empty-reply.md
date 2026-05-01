# Issue: ClusterSecretStore remains InvalidProviderConfig because pod-origin traffic to vault-bridge returns empty reply

**Date:** 2026-04-28
**Status:** Open
**Severity:** High

## What Was Attempted

After fixing local Vault sealed-state recovery and splitting the local Vault port-forward from the remote reverse tunnel, `make up` was rerun.

The run passed the original Step 4 failure:

```text
INFO: [acg-up] Step 4/12 — Starting Vault port-forward (k3d → localhost:18200)...
INFO: [acg-up] Vault port-forward PID: 33939 (log: /Users/cliang/.local/share/k3d-manager/vault-pf.log)
INFO: [acg-up] Vault is unsealed and reachable.
```

The run then completed:

```text
INFO: [acg-up] ClusterSecretStore not Ready after 180s — check vault-bridge connectivity
INFO: [acg-up] Step 12/12 — Installing sandbox TTL watcher (launchd)...
INFO: [acg-up] Cluster is up.
NAME            STATUS   ROLES           AGE   VERSION
ip-10-0-1-135   Ready    control-plane   30m   v1.35.4+k3s1
ip-10-0-1-154   Ready    <none>          30m   v1.35.4+k3s1
ip-10-0-1-238   Ready    <none>          30m   v1.35.4+k3s1
```

## Actual Behavior

The app-cluster `ClusterSecretStore` remains invalid:

```text
$ kubectl --context ubuntu-k3s get clustersecretstore vault-backend -o yaml | sed -n '/status:/,$p'
status:
  capabilities: ReadWrite
  conditions:
  - lastTransitionTime: "2026-04-29T00:00:51Z"
    message: unable to validate store
    reason: InvalidProviderConfig
    status: "False"
    type: Ready
```

ESO reports:

```text
invalid vault credentials: Get "http://vault-bridge.secrets.svc.cluster.local:8201/v1/auth/token/lookup-self": EOF
```

The EC2 host can reach the Vault bridge path:

```text
$ ssh ubuntu 'curl -sS -i --max-time 5 http://127.0.0.1:8200/v1/sys/health; echo; curl -sS -i --max-time 5 http://127.0.0.1:8201/v1/sys/health'
HTTP/1.1 200 OK
...
{"initialized":true,"sealed":false,...}

HTTP/1.1 200 OK
...
{"initialized":true,"sealed":false,...}
```

The local port-forward is stable:

```text
$ lsof -nP -iTCP:18200 -sTCP:LISTEN
COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
kubectl 33939 cliang    8u  IPv4 ... TCP 127.0.0.1:18200 (LISTEN)
kubectl 33939 cliang    9u  IPv6 ... TCP [::1]:18200 (LISTEN)
```

But pod-origin traffic through the Kubernetes service fails:

```text
$ kubectl --context ubuntu-k3s -n secrets run vault-bridge-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- curl -sS -i --max-time 10 http://vault-bridge.secrets.svc.cluster.local:8201/v1/sys/health
curl: (52) Empty reply from server
```

Direct pod-to-node tests show the same pattern:

```text
$ kubectl --context ubuntu-k3s -n secrets run vault-node-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- sh -c 'curl -sS -i --max-time 5 http://10.0.1.135:8200/v1/sys/health; echo; curl -sS -i --max-time 5 http://10.0.1.135:8201/v1/sys/health'
curl: (7) Failed to connect to 10.0.1.135 port 8200 after 0 ms: Could not connect to server

curl: (52) Empty reply from server
```

## Root Cause

Known:

- The local Hub-side Vault is unsealed and reachable.
- The local `kubectl port-forward` on `18200` is reachable from the Mac.
- The SSH reverse tunnel from EC2 host loopback to Mac `18200` works from the EC2 host.
- The EC2 host's `vault-bridge` socat service works for host-origin traffic.
- Pod-origin traffic to the same `vault-bridge` endpoint gets an empty response.

Unknown:

- Whether k3s pod-to-node traffic is interacting badly with the host `socat` process.
- Whether `vault-bridge` should be replaced with a different exposure pattern, such as a hostNetwork bridge pod, NodePort, or another tunnel model.
- Whether EC2 host firewall / CNI hairpin behavior is closing pod-origin TCP streams.

## Recommended Follow-Up

Replace the host-level `socat` bridge with an app-cluster-native bridge that can be reached reliably from pods.

Candidates:

1. A `hostNetwork: true` Deployment/DaemonSet on the control-plane node that proxies to remote loopback `8200`.
2. A NodePort/hostPort bridge controlled by Kubernetes instead of a systemd unit.
3. A different tunnel design that binds an address reachable by pods without relying on pod-to-host hairpin through `socat`.

Also change Step 11 to fail hard once this connectivity is expected to be stable; today `make up` logs the Not Ready state but still exits 0.
