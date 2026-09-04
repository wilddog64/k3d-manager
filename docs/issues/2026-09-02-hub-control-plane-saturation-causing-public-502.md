# Hub control-plane saturation causes false-green status and public 502s

## Symptoms

On 2026-09-02, Cloudflare returned HTTP 502 for `grafana.3ai-talk.org` and the
ArgoCD OAuth flow failed with an invalid redirect error. `make status` reported
healthy because its point-in-time probes succeeded while the dependent tunnels
were flapping.

## Evidence

The local Grafana forwarder repeatedly logged `health check failed — restarting
stale port-forward`. Kubernetes `/readyz` reported `etcd` and
`etcd-readiness` failures. The hub k3s server reached approximately 650–880%
CPU, with agents also elevated. Server logs contained repeated API handler
timeouts, slow kine SQL, and failed lease updates.

The live ArgoCD ConfigMap advertised `https://argocd.shopping-cart.local`
while the public browser URL is `https://argocd.3ai-talk.org`; this caused the
Keycloak redirect mismatch. The URL was patched live, but API instability
prevented durable verification.

## Recovery attempted

The frontend listener was confirmed healthy intermittently (public HTTP 200).
The two highest-load agents and the k3s server were restarted. The API remained
unready and Grafana continued returning HTTP 502.

## Follow-up

Identify and stop the controller/event workload driving the API storm once the
API is responsive; then persist the ArgoCD public URL in Git, restart the
affected port-forward agents, and add sustained (not single-sample) public
endpoint checks to `make status`.
