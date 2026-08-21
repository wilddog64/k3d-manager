# Bug: deploy_eso returns before validating webhook has endpoints

**Date:** 2026-04-24
**Branch:** `k3d-manager-v1.1.0`
**Status:** READY FOR IMPLEMENTATION

## Problem

Fresh Hub bootstrap can fail during LDAP deployment after Vault installs External Secrets Operator:

```text
Error from server (InternalError): error when creating "/var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T/ldap-eso.XXXXXX.yaml.AM99qPrt1X": Internal error occurred: failed calling webhook "validate.externalsecret.external-secrets.io": failed to call webhook: Post "https://external-secrets-webhook.secrets.svc:443/validate-external-secrets-io-v1-externalsecret?timeout=5s": no endpoints available for service "external-secrets-webhook"
kubectl command failed (1): kubectl apply -f /var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T/ldap-eso.XXXXXX.yaml.AM99qPrt1X
ERROR: failed to execute kubectl apply -f /var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T/ldap-eso.XXXXXX.yaml.AM99qPrt1X: 1
make: *** [up] Error 1
```

## RCA

`bin/acg-up` fresh-Hub Step 3.6 runs:

```bash
"${REPO_ROOT}/scripts/k3d-manager" deploy_vault --confirm
"${REPO_ROOT}/scripts/k3d-manager" deploy_ldap --confirm
"${REPO_ROOT}/scripts/k3d-manager" deploy_argocd --confirm
```

`deploy_vault` calls `deploy_eso`, but `deploy_eso` currently waits only for the main controller deployment:

```bash
_kubectl -n "$ns" rollout status deploy/external-secrets --timeout=120s
```

It does not wait for `deploy/external-secrets-webhook` or for `svc/external-secrets-webhook` to have a ready endpoint.

`deploy_ldap` then applies ExternalSecret resources via `_ldap_apply_eso_resources`. Kubernetes admission calls the ESO validating webhook, but the webhook service can exist before it has endpoints, so admission fails.

Observed webhook startup evidence:

```text
invalid certs. retrying... stat /tmp/certs/tls.crt: no such file or directory
...
Registering a validating webhook
Serving webhook server ... port:10250
```

Current cluster eventually recovered:

```text
deployment.apps/external-secrets-webhook   1/1
endpoints/external-secrets-webhook         10.42.1.4:10250
```

## Required Fix

Update `scripts/plugins/eso.sh`.

Centralize ESO readiness in `deploy_eso` so every caller is protected:

1. After Helm install and CRD establishment checks, wait for:
   - `deploy/external-secrets`
   - `deploy/external-secrets-webhook`
   - `deploy/external-secrets-cert-controller`
2. Wait until `endpoints/external-secrets-webhook` has at least one address.
3. Fail with a clear `_err` if the webhook endpoint never appears within a bounded timeout.

Do not add a one-off sleep. Do not duplicate the wait in `bin/acg-up` unless unavoidable.

## Validation

Run:

```bash
shellcheck -x scripts/plugins/eso.sh
bats scripts/tests/plugins/eso.bats
./scripts/k3d-manager _agent_lint
./scripts/k3d-manager _agent_audit
```

If broader suites still show unrelated ArgoCD help/shellcheck failures, keep them documented in the existing verification issue rather than expanding this fix.
