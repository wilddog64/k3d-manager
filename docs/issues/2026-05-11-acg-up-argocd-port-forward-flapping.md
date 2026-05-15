# ACG up Argo CD port-forward flaps after sandbox rebuild

## Status

Fixed in `bin/acg-up` by replacing the one-shot Argo CD port-forward launchd command with a self-healing wrapper that restarts the listener when `localhost:8080/healthz` stops responding.

## What was observed

After a fresh `make up` on a rebuilt sandbox, Safari still reported:

```text
Safari can't open the page "localhost:8080/auth/login?return_url=http%3A%2F%2Flocalhost%3A8080%2Fapplications%2Fcicd%2Fshopping-cart-identity%3Fresource%3D%26orphaned%3Dfalse"
because Safari can't connect to the server "localhost".
```

The local host listener did exist at the time of inspection:

```text
LISTEN
COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
kubectl 95253 cliang    8u  IPv4 0xf974af852d419c0a      0t0  TCP 127.0.0.1:8080 (LISTEN)
kubectl 95253 cliang    9u  IPv6 0x154603e4469ca9bb      0t0  TCP [::1]:8080 (LISTEN)
```

The Argo CD port-forward log also showed repeated backend loss events:

```text
E0511 15:45:17.642731   72763 portforward.go:522] "Unhandled Error" err="an error occurred forwarding 8080 -> 8080: error forwarding port 8080 to pod 696a826ff607c7ec8bac0c5beb34ddbe319aca36014c1baa12769357acef88f7, uid : failed to find sandbox \"696a826ff607c7ec8bac0c5beb34ddbe319aca36014c1baa12769357acef88f7\" in store: not found"
error: lost connection to pod
```

## Why this appears to happen

`bin/acg-up` now waits for `localhost:8080/healthz` when the launchd agent first comes up, but the port-forward process can still lose its backing pod later when the sandbox is rebuilt or the pod sandbox is recycled. Launchd keeps the process alive, so the host socket can remain bound even though the backend connection is effectively flapping.

## Recommended follow-up

- Re-test after a sandbox rebuild to confirm Safari can reach the login page consistently.
- If the wrapper still misses a flapping backend, consider moving the launchd agent to the explicit managed port-forward state pattern used by `bin/acg-sync-apps`.
