# Issue: Keycloak admin token fetch fails after remote cluster rebuild, blocking Argo CD client reconciliation

## Status
OPEN

## Reported Symptom
After a remote cluster rebuild, Argo CD SSO still fails with:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

## Verification
The live cluster still has Keycloak running in `identity`:

```text
$ kubectl get pods -n identity --context k3d-k3d-cluster -o wide
NAME                                        READY   STATUS      RESTARTS      AGE   IP           NODE                       NOMINATED NODE   READINESS GATES
kc-importer-1778418836                      0/1     Completed   0             35h   10.42.0.12   k3d-k3d-cluster-server-0   <none>           <none>
keycloak-6cf9c8f5b5-ddvb5                   1/1     Running     0             23h   10.42.2.11   k3d-k3d-cluster-agent-0    <none>           <none>
ldap-56997b96d-hqw5m                        1/1     Running     0             37h   10.42.3.11   k3d-k3d-cluster-agent-1    <none>           <none>
openldap-openldap-bitnami-c9bdbf8c5-npmk5   1/1     Running     0             37h   10.42.0.7    k3d-k3d-cluster-server-0   <none>           <none>
postgres-keycloak-df48bf96-hfd4b            1/1     Running     1 (31h ago)   31h   10.42.0.14   k3d-k3d-cluster-server-0   <none>           <none>
```

The live `keycloak-secrets` secret still exposes an admin password key:

```text
$ kubectl get secrets -n identity --context k3d-k3d-cluster
NAME                             TYPE                 DATA   AGE
keycloak-client-secrets          Opaque               4      37h
keycloak-secrets                 Opaque               5      37h
ldap-secrets                     Opaque               2      37h
openldap-admin                   Opaque               7      37h
openldap-bitnami-ldif-import     Opaque               1      37h
sh.helm.release.v1.openldap.v1   helm.sh/release.v1   1      37h
```

But the Keycloak token endpoint rejects that secret-backed credential:

```text
$ curl -sS -w '\nHTTP:%{http_code}\n' -X POST 'http://localhost:18080/realms/master/protocol/openid-connect/token' -d "client_id=admin-cli&grant_type=password&username=admin&password=${admin_pass}"
{"error":"invalid_grant","error_description":"Invalid user credentials"}
HTTP:401
```

Keycloak logs also show repeated `invalid_user_credentials` attempts for `admin-cli`.

## Root Cause Hypothesis
`bin/acg-up` can only reconcile the live `argocd` client if it can obtain a valid Keycloak admin token. On the rebuilt cluster, the admin token request using the current `keycloak-secrets` password returns `401 invalid_grant`, so the reconciliation step cannot be trusted to run.

That leaves the live `argocd` client vulnerable to stale redirect URIs even though the repo JSON already includes both:

- `https://argocd.shopping-cart.local/*`
- `http://localhost:8080/*`

## Follow-up
- Verify which component owns the live Keycloak admin password after rebuild.
- Make the bootstrap path reconcile or re-seed the admin credentials before attempting client redirect updates.
- Re-check the `argocd` client after a rebuild once admin login works again.
