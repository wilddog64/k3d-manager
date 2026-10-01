# Bug: `make fix-sync` cannot connect to ArgoCD

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** FIXED (`ffe501fa`)
**Severity:** medium — the documented repair target fails with an opaque EOF when the local
ArgoCD port-forward is not already running.

## Evidence

```text
argocd app sync "acg-kube-prometheus-stack" --timeout 120 --server localhost:8080 --insecure
{"level":"fatal","msg":"Failed to establish connection to localhost:8080: error creating connection: EOF"}
make: *** [fix-sync] Error 1
```

## Root cause

The `fix-sync` and `fix-force-sync` recipes assumed that `localhost:8080` was already served by
the ArgoCD port-forward. They also omitted `--grpc-web`, although the repository's ArgoCD login
path uses the port-forward with gRPC-web.

## Fix

The targets now create a short-lived `k3d-k3d-cluster` port-forward when the default local
endpoint is unavailable, wait for `/healthz`, use `--grpc-web`, and clean up the process and log.
`ARGOCD_SERVER=host:port` remains available for an already reachable non-local endpoint.

## Follow-up evidence

After the first fix established the tunnel, ArgoCD returned:

```text
rpc error: code = Unknown desc = Post "https://localhost:8080/application.ApplicationService/Get": EOF
```

The repository's working login path uses `--plaintext` for this local port-forward. The sync
targets now pass that flag as well.

Follow-up commit: `14dab218`.
