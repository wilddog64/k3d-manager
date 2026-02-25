# Jenkins Smoke Test Still Fails on macOS (Istio LB IP Unreachable)

**Date:** 2026-02-25
**Status:** Documented

## Description

After fixing the Jenkins none-auth JCasC flow, `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault` now succeeds end-to-end. However, the built-in smoke test still fails on macOS because it relies on `curl --resolve <host>:443:<IngressIP>` to reach the Istio ingress in the k3d VM.

On OrbStack, `istio-ingressgateway` exposes multiple IPs (e.g., 172.18.0.3–0.6) that are only routable from within the VM. Curl from the macOS host gets `000`/timeouts, so the smoke step always prints `ERROR: Jenkins did not become ready within 60 seconds`, even though the Jenkins pod is Running and accessible via `kubectl port-forward`.

## Impact

- `deploy_jenkins --enable-vault` logs a WARN at the end, making validation noisy even when Jenkins is healthy.
- `./scripts/k3d-manager test_jenkins_smoke` fails in the same way, blocking any attempt to integrate this check into automation on macOS.

## Workaround

- Use `kubectl port-forward -n jenkins svc/jenkins 8443:443` and hit `https://127.0.0.1:8443` for manual smoke validation.
- Alternatively, run the smoke test from inside the k3d node (e.g., `kubectl exec` into the Istio ingress pod) where 172.18.0.x is reachable.

## Fix Ideas

1. Enhance the smoke test to detect when `istio-ingressgateway` exposes only private IPs (172.16/17/18/19) and fall back to `kubectl port-forward` automatically.
2. Allow overriding the smoke-test endpoint via `JENKINS_SMOKE_URL` (default: use ingress IP, but accept a user-supplied host/port like `https://127.0.0.1:8443`).
3. For OrbStack/k3d specifically, query the Docker context to retrieve the load balancer IP published to the host (if any) or skip the ingress check entirely with a warning.

## Verification Needed

- Once the smoke test can reach Jenkins via port-forward or another host-only path, rerun `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault` on macOS and confirm it ends without warnings.
