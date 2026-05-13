# Keycloak intermittently never reaches `Available` before `make up` times out

## What happened
`make up` occasionally fails at the Keycloak readiness gate even with the longer wait window:

```text
ERROR: [acg-up] Keycloak API not Ready after 900s — realm import is required for SSO and cannot be skipped
make: *** [up] Error 1
```

## What I checked
Current live status during the investigation:

```text
NAME       READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                           SELECTOR
keycloak   0/1     1            0           87s   keycloak     quay.io/keycloak/keycloak:24.0   app.kubernetes.io/name=keycloak
```

```text
NAME                        READY   STATUS              RESTARTS   AGE   IP       NODE                       NOMINATED NODE   READINESS GATES
keycloak-745b995454-h859q   0/1     ContainerCreating   0          87s   <none>   k3d-k3d-cluster-server-0   <none>           <none>
```

The deployed Keycloak manifest currently has:

```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
startupProbe:
  httpGet:
    path: /health/started
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30
```

## Likely cause
The intermittent failure is not the wait loop itself. The live Keycloak deployment sometimes never converges to `Available` in time, which means one of these is happening:
- the pod is still pulling or creating the container when the timeout hits
- the startup probe is too aggressive for a cold rebuild and causes the pod to restart before it settles
- the identity stack is still waiting on an upstream dependency and never reaches ready state

## Recommendation
- Inspect the live Keycloak pod events and logs when this happens again.
- If the pod is repeatedly restarting or staying in `ContainerCreating`, adjust the Keycloak startup budget in `shopping-cart-infra` rather than only increasing the `make up` timeout.
- Keep the `make up` failure, because it is correctly surfacing a real identity-stack startup problem.
