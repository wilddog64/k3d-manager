# Expired ACG sandbox leaves stale status resources

## Symptoms

After the AWS sandbox expired, `make status` reported either `UNKNOWN` or failures for
the frontend, Pushgateway, and sandbox login checks even though the local hub,
Prometheus, and Grafana were healthy. `make restart-webhook` restarted the webhook but
did not remove the stale sandbox access layer.

## Evidence

```text
aws: [ERROR]: ... InvalidClientTokenId ... security token ... invalid
error: context ubuntu-k3s not found
ubuntu-k3s.yaml=present
```

The frontend and Pushgateway launchd agents continued retrying an expired sandbox.
Their logs showed connection timeouts to the old sandbox API endpoint. The local
Grafana/ArgoCD/Keycloak agents are hub services and must not be removed by this fix.

## Root cause

The status default is `k3s-aws` when no active-provider marker exists. An expired
sandbox therefore remains the assumed target, while generated kubeconfig and
app-only port-forward launchd state survive teardown.

## Fix

`bin/cleanup-stale-sandbox` and `make cleanup-stale-sandbox` now provide a bounded,
AWS-only cleanup workflow. It is dry-run by default and, with `CONFIRM=1` or
`--confirm`, stops only the frontend/Pushgateway agents and removes the
`ubuntu-k3s` context. The local hub agents and cluster are intentionally untouched.

The authenticated admin Slack command `/cleanup-stale-sandbox` uses the same script;
without `confirm` it performs a dry-run, and `cleanup-stale-sandbox confirm` applies it.

## Follow-up

Status provider autodetection should be addressed separately so an absent sandbox is
reported as an explicit warning rather than an unknown source. This cleanup command
is the safe operational path until that status UX work lands.
