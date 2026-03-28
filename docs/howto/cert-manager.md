# How-To: cert-manager

cert-manager handles TLS certificate issuance and renewal. k3d-manager deploys cert-manager and configures two ClusterIssuers: one backed by Vault PKI (internal cluster TLS) and one backed by Let's Encrypt ACME (public-facing endpoints).

## Prerequisites

- Infra cluster running (`deploy_cluster`)
- Vault deployed and PKI configured (`deploy_vault`) — required for the Vault issuer
- A valid email address for Let's Encrypt registration

## Deploy cert-manager

```bash
ACME_EMAIL=you@example.com \
  ./scripts/k3d-manager deploy_cert_manager --confirm
```

Installs cert-manager via Helm and creates:
- `vault-issuer` ClusterIssuer — signs certs via Vault PKI intermediate CA
- `letsencrypt-prod` ClusterIssuer — signs certs via Let's Encrypt ACME HTTP-01 challenge

## Issue a Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myservice-tls
  namespace: myservice
spec:
  secretName: myservice-tls
  issuerRef:
    name: vault-issuer        # or letsencrypt-prod for public endpoints
    kind: ClusterIssuer
  dnsNames:
    - myservice.example.com
```

```bash
kubectl apply -f myservice-cert.yaml
kubectl describe certificate myservice-tls -n myservice
```

## Common Operations

```bash
# List all certificates and their status
kubectl get certificates -A

# Check a certificate's renewal schedule
kubectl describe certificate <name> -n <namespace>

# Force renewal
kubectl delete secret <tls-secret-name> -n <namespace>
# cert-manager re-issues automatically within ~1 minute

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager -f
```

## Notes

- Vault issuer cert TTL is capped at 720h (`VAULT_PKI_ROLE_TTL`) — cert-manager renews at 2/3 of TTL
- Let's Encrypt rate limits apply in production — use `letsencrypt-staging` for testing
- `--insecure` and `insecureSkipVerify: true` are dev-only flags — never use against production endpoints
