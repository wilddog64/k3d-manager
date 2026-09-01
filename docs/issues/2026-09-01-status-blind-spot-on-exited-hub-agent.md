# `make status` hides exited hub-agent diagnosis when webhook is unavailable

## Observed behavior

The hub node `k3d-k3d-cluster-agent-0` exited. The local Keycloak port-forward
and public login path failed, while `make status` reported only:

```text
Overall: UNKNOWN
  ! status source: webhook unavailable
  hint: make restart-webhook
make: *** [status] Error 2
```

The webhook health endpoint was unavailable because the Kubernetes API was
returning backend 502 errors for the exited node. The node itself was not
shown in the status output.

After restarting the exited container and the managed port-forwards, all nodes
became Ready and `make status` returned `Overall: HEALTHY`.

## Root cause

`bin/cluster-status-summary` obtains all checks through the local webhook
`/api/v1/health` endpoint. If that endpoint is unreachable, it emits the
generic `status source: webhook unavailable` result and exits 2. There is no
local fallback probe for hub container/node state.

## Recommended fix

Add a bounded, read-only fallback when the webhook cannot be reached. It should
report the webhook failure plus available local hub evidence (for example,
Docker state for `k3d-k3d-cluster-*` and a concise remediation hint), without
claiming service health or attempting a restart automatically.

## Evidence

The hub server log contained repeated errors of the form:

```text
error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.4:10250, code 502: 502 Bad Gateway
```

Container inspection showed:

```text
k3d-k3d-cluster-agent-0   Exited (143) 4 minutes ago
```

