# ArgoCD Keycloak OIDC values were rendered with literal placeholders

## Problem

Signing in to ArgoCD through Keycloak failed with a provider-query error. The live
`cicd/argocd-cm` contained these literal values:

```yaml
issuer: ${ARGOCD_KEYCLOAK_REALM_URL}
clientID: ${ARGOCD_KEYCLOAK_CLIENT_ID}
```

ArgoCD therefore attempted to discover the provider at the encoded literal value
and logged:

```text
failed to query provider "${ARGOCD_KEYCLOAK_REALM_URL}": Get "$%7BARGOCD_KEYCLOAK_REALM_URL%7D/.well-known/openid-configuration": unsupported protocol scheme ""
```

The public Keycloak discovery endpoint was healthy. This was a local render defect,
not an identity-provider outage.

## Root cause

`scripts/etc/argocd/vars.sh` exports both OIDC variables, and
`scripts/etc/argocd/values.yaml.tmpl` references them. However,
`_argocd_helm_deploy_release` used an explicit `envsubst` allowlist that omitted
both variables. Any Helm reconciliation using that values file overwrote the prior
bootstrap patch with literal placeholders.

## Fix

- Add `ARGOCD_KEYCLOAK_REALM_URL` and `ARGOCD_KEYCLOAK_CLIENT_ID` to the Helm
  values render allowlist.
- Add a BATS regression test that verifies the deployed allowlist and rendered
  values contain resolved issuer and client ID values, never the two placeholders.
- Restore the affected live ConfigMap with the existing public ArgoCD/Keycloak
  settings and restart `argocd-server`.

## Verification

```text
bats scripts/tests/plugins/argocd.bats
shellcheck scripts/plugins/argocd.sh
```
