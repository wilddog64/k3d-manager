# Bug: k3s-aws local kubeconfig uses a public IP outside the API certificate SANs

**Filed:** 2026-08-20
**Source:** live `make up` failure

## Observed output

```text
INFO: [acg-up] using PAT from Vault for ghcr-pull-secret
error: error validating "STDIN": error validating data: failed to download openapi: Get "https://44.248.252.152:6443/openapi/v2?timeout=32s": tls: failed to verify certificate: x509: certificate is valid for 10.0.1.61, 10.43.0.1, 127.0.0.1, ::1, not 44.248.252.152; if you choose to ignore these errors, turn validation off with --validate=false
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

## Root cause

The k3s kubeconfig export replaces `127.0.0.1` with the EC2 public address. Local
`kubectl` traffic is actually sent through the SSH/SSM port-forward on
`127.0.0.1:6443`, but the API certificate does not contain the public address as a
TLS SAN. Kubernetes OpenAPI validation therefore fails before the GHCR secret can
be applied.

## Fix implemented

Keep the local kubeconfig server at `https://127.0.0.1:6443` whenever the local
tunnel is used. Keep the separately registered ArgoCD cluster endpoint on the Hub
host alias (`host.k3d.internal`) and its configured CA/insecure policy; do not disable
TLS validation globally or use `--validate=false` as a workaround.

Both SSH and SSM kubeconfig paths now retain the loopback API endpoint for local
tunneled kubectl traffic. The SSH path also normalizes `https://localhost` to
`https://127.0.0.1`. A source regression test prevents reintroducing the public-IP
replacement. No live sandbox was deployed for this source-only fix.
