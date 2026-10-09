# Hostinger status reported transient ESO and data-layer failures

**Observed:** 2026-10-07, Slack status at approximately 18:06 local time
**Provider:** `k3s-hostinger`
**Status:** Not reproduced on immediate read-only recheck

## Reported output

The status message reported:

```text
Cluster status: FAIL — k3s-hostinger (7 ok / 9 warn / 5 fail)
ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
ESO ExternalSecrets: Expecting value: line 1 column 1 (char 0)
Hub ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
Hub ESO ExternalSecrets: Expecting value: line 1 column 1 (char 0)
Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

The same message also contained credential-unavailable warnings for optional Keycloak,
ArgoCD, Prometheus, Grafana, and smoke-token login checks.

## Recheck

The local status command immediately returned:

```text
make status CLUSTER_PROVIDER=k3s-hostinger
  ✓ ArgoCD: HTTP 200
  ✓ Frontend: HTTP 200
  ✓ Keycloak: HTTP 200
  ✓ Prometheus: HTTP 401 (auth enforced)
  ✓ Grafana: HTTP 200
  ✓ Pushgateway: HTTP 200
Overall: HEALTHY
```

Direct read-only Kubernetes checks also returned:

```text
ClusterSecretStore:
True store validated
ExternalSecrets:
all synced
Data layer:
postgresql-orders=1/1
postgresql-payment=1/1
postgresql-products=1/1
minio=1/1
```

## Assessment

The screenshot represents a transient or stale status response. The JSON parse errors indicate
that the status worker received empty `kubectl -o json` output at that moment; the current
resources are healthy. The credential warnings are separate optional login probes and are not
evidence that the service endpoints or ESO resources are currently failing.

## Follow-up

If the failure recurs, capture the status job ID and rerun the ESO checks with the same Kubernetes
context. The status formatter should preserve the distinction between empty command output,
context/authentication failure, and invalid JSON rather than exposing a raw `JSONDecodeError`.
