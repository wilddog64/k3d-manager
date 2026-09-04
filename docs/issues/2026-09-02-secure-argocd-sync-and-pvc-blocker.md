# ArgoCD identity sync: secure credential handling and PVC blocker

## What was attempted

- Retrieved the ArgoCD bootstrap password directly from the Kubernetes Secret into
  a short-lived Python process; it was never written to a file, shell history, or
  command argument, and was never printed.
- Authenticated to the local ArgoCD API and requested a scoped sync of
  `shopping-cart-identity` with `Replace=true`.
- Recovered the ArgoCD application-controller pod after it remained stuck in
  `Terminating`.

## Actual result

The duplicate Keycloak Service merge error was bypassed, but replacement then
failed on the existing `postgres-keycloak-pvc` because its bound
`volumeName`/`storageClassName` fields are immutable. The PVC was not deleted or
modified.

## Follow-up

Use a resource-scoped replacement strategy for the Keycloak Service (or migrate
the PVC deliberately) rather than applying `Replace=true` to the entire identity
application. Keep all password operations in memory-only pipelines.
