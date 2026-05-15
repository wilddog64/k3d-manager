# Issue: Keycloak readiness gate fails immediately when the Deployment is not created yet

## What happened
`make up` can fail at the Keycloak readiness gate with:

```text
WARN: [acg-up] Keycloak deployment did not become Available after 900s
Error from server (NotFound): deployments.apps "keycloak" not found
No resources found in identity namespace.
ERROR: [acg-up] Keycloak API not Ready after 900s — realm import is required for SSO and cannot be skipped
make: *** [up] Error 1
```

The current gate uses a single `kubectl wait --for=condition=Available deployment/keycloak` check. When Argo CD has not created the `Deployment` yet, `kubectl wait` returns `NotFound` immediately instead of continuing to poll.

## Root cause
The bootstrap assumes the Keycloak `Deployment` already exists by the time the readiness wait starts. That is not always true on slower or colder rebuilds, so the readiness gate conflates:

- "Keycloak deployment has not been created yet"
- "Keycloak deployment exists but is not Available"

## Fix
Poll for the deployment to exist first, then wait for it to become `Available`. If it still never appears or becomes ready, dump the Keycloak deployment, pod, and Argo CD Application status before failing.

## Follow-up
Verify `make up` succeeds when Argo CD takes longer to materialize `identity/keycloak`, and that the timeout path now reports whether the deployment never appeared or just never became `Available`.
