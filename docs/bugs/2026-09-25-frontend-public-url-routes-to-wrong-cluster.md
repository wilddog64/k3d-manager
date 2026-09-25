# Bug: `frontend.3ai-talk.org` returns 404 — the tunnel routes it to the hub cluster, which does not run the frontend

**Filed:** 2026-09-25
**Severity:** the public storefront has been unreachable while every health signal stayed green
**Reported by:** the operator, via `make status CLUSTER_PROVIDER=k3s-hostinger`

---

## Symptom

```
$ make status CLUSTER_PROVIDER=k3s-hostinger
  ✓ ArgoCD: HTTP 200
  ✗ Frontend: HTTP Error 404: Not Found
  ✓ Keycloak: HTTP 200
  ! Prometheus: HTTP 401 (authentication required)
  ✓ Grafana: HTTP 200
  ✓ Pushgateway: HTTP 200
Overall: FAIL (1 errors, 1 warnings)
```

No alert fired. See the separate coverage finding below.

## Root cause — the request never reaches the hostinger cluster

The tunnel config is correct and the tunnel is healthy. `~/.cloudflared/config.yml` maps:

```yaml
  - hostname: frontend.3ai-talk.org
    service: http://127.0.0.1:8000
```

`127.0.0.1:8000` is bound by **OrbStack** (`*:8000`), which publishes into the local **k3d hub**
cluster's Istio ingress. Probing it locally shows who actually answers:

```
$ curl -sS -o /dev/null -D - http://127.0.0.1:8000/
HTTP/1.1 404 Not Found
server: istio-envoy
content-length: 0
```

The hub's gateway has routes for exactly two hosts, and the storefront is not one of them:

```
$ kubectl --context k3d-k3d-cluster get virtualservice -A
monitoring   grafana      ["grafana.3ai-talk.org"]
monitoring   prometheus   ["prometheus.3ai-talk.org"]

$ kubectl --context k3d-k3d-cluster get pods -n shopping-cart-apps
No resources found in shopping-cart-apps namespace.
```

So the chain is: edge → tunnel → `:8000` → OrbStack → **hub** Istio → no matching host → 404.
The hub does not run the frontend at all.

Meanwhile the frontend that *is* running — on hostinger — has no path in:

```
$ kubectl --context ubuntu-hostinger get pods -n shopping-cart-apps
frontend-86cdb6969d-4sgsh   1/1   Running   0   32h

$ kubectl --context ubuntu-hostinger get ingress -A
No resources found

$ kubectl --context ubuntu-hostinger get svc -n shopping-cart-apps
frontend                   ClusterIP   10.43.27.156    <none>   80/TCP
order-service-nodeport     NodePort    10.43.161.215   <none>   80:30081/TCP
product-catalog-nodeport   NodePort    10.43.139.220   <none>   80:30082/TCP
```

`frontend` is **ClusterIP-only with no Ingress and no NodePort**, while its two sibling services
both have NodePorts. Nothing publishes it off-cluster.

### Why the other hostnames are fine

| host | path | works |
|---|---|---|
| `argocd` | tunnel → `:8080` → kubectl port-forward | yes |
| `keycloak` | tunnel → `:8880` → kubectl port-forward | yes |
| `grafana`, `prometheus` | tunnel → `:8000` → hub Istio, and the hub **has** those VirtualServices | yes |
| `frontend` | tunnel → `:8000` → hub Istio, **no route, no workload** | **404** |

`frontend` is the only host routed through `:8000` without a corresponding hub VirtualService.

### A second, independent fault

`com.k3d-manager.frontend-port-forward` is the only frontend port-forward agent, and it is aimed at
the wrong cluster and the wrong port:

```
ProgramArguments: kubectl port-forward svc/frontend --namespace shopping-cart-apps \
                  --context ubuntu-k3s 3000:80
```

Context `ubuntu-k3s` is the ACG cluster, not hostinger, and the port is 3000, which no tunnel rule
references. `launchctl list` reports it running with last exit status 1, and it answers nothing on
either stack:

```
$ curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/   → 000
$ curl -s -o /dev/null -w '%{http_code}' 'http://[::1]:3000/'     → 000
```

So even the agent that looks like it should be serving this is dead and pointed elsewhere.

## Why no alert fired — a monitoring coverage gap, not a delivery failure

Delivery is fine: `alertmanager.yaml.tmpl` routes `severity = critical` to `sms-critical`. The
problem is that **nothing produces a signal for this failure**:

1. `make status` writes no metrics. There is no Pushgateway writer anywhere in `scripts/` or
   `bin/` — no `push_to_gateway`, no `metrics/job/`, no curl to Pushgateway. Its results exist
   only in the operator's terminal. (The "Pushgateway" line in its output is Pushgateway being
   *checked*, not written to.)
2. Nothing probes the public hostnames. **There is no blackbox exporter anywhere in the repo** —
   zero matches for `blackbox`. Prometheus sees in-cluster targets only.
3. The rule that would otherwise cover the frontend is correctly silent, because the workload is
   healthy:
   ```
   ServiceDown: sum by (namespace) (
     kube_pod_status_ready{condition="true", namespace=~"shopping-cart.*"}
   ) == 0
   ```
   All four `shopping-cart-apps` pods are Running 1/1. The pod is up; only the public path is
   broken, and no rule observes the public path.

This is the second silent failure from this gap — the first was the `_acg_up_cleanup` tunnel
bootout that took all 7 hostnames down. The fix is specified in
`docs/plans/v1.38.0-public-endpoint-blackbox-probes.md`.

## Fix — not yet decided, needs the operator

Two candidate shapes, and the choice is an architecture decision rather than a patch:

- **Point the tunnel at hostinger.** Give `frontend` a NodePort like its siblings already have, and
  repoint `frontend.3ai-talk.org` at a port-forward or node port that reaches `ubuntu-hostinger`.
  Consistent with how `order-service` and `product-catalog` are already exposed there.
- **Route it on the hub.** Add a `frontend` VirtualService to `observability-gateway` and have it
  forward to hostinger. Keeps one ingress path but makes the hub a proxy for an app it does not run.

The first is the smaller change and matches existing precedent. Either way, fix
`com.k3d-manager.frontend-port-forward` in the same pass — a port-forward agent naming the wrong
context and a port nothing references is a trap for the next person, whichever route is chosen.

## What NOT to do

- Do NOT change `~/.cloudflared/config.yml` and restart the tunnel casually. It currently serves 7
  public hostnames; a bad edit takes all of them down, which has already happened once.
- Do NOT assume the frontend pod is broken. It is healthy and has been for 32h.
