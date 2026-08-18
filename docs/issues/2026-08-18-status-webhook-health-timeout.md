# `make status` falsely reported an unavailable webhook

## Symptom

`make status` returned `Overall: UNKNOWN` and suggested restarting the webhook even though the webhook
process was running and authenticated requests succeeded.

## Root cause

`bin/cluster-status-summary` limited the authenticated `/api/v1/health` request to 15 seconds. The health
sweep performs bounded endpoint, Kubernetes, and credential probes. During hub degradation, the sweep
needed approximately 57 seconds to return its structured result, so the client timed out and discarded
the real service failures.

## Fix

The summary client now allows 90 seconds, matching the full-status path's budget. It reports the actual
service failures and warnings instead of collapsing them into `status source: webhook unavailable`.

## Live verification

After the timeout fix, `make status` returned actual results including Grafana HTTP 200, while also
showing ArgoCD/Keycloak failures and expected missing optional resources. Public Grafana remained HTTP
502 because the hub control plane was timing out; that separate incident is tracked in
`docs/issues/2026-08-18-grafana-502-hub-control-plane-degradation.md`.
