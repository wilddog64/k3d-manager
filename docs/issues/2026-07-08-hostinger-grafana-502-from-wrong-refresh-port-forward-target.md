# Issue: Hostinger Grafana 502 after refresh because the local port-forward plist was regenerated with the wrong target

## What was tested

User-reported failure on `2026-07-08`:

- Public Grafana URL returned Cloudflare `502 Bad gateway`
- `make status CLUSTER_PROVIDER=k3s-hostinger` reported:

```text
=== Service Health ===
  ✅ Alertmanager: HTTP 200
  ❌ Frontend: HTTP Error 502: Bad Gateway
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ❌ Grafana: HTTP Error 502: Bad Gateway
  ❌ Product images: HTTP Error 502: Bad Gateway
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 18/18 synced
  ❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

Grafana-specific live checks before the fix:

```text
$ plutil -p ~/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist
{
  "ProgramArguments" => [
    0 => "/opt/homebrew/bin/kubectl"
    1 => "port-forward"
    2 => "svc/kube-prometheus-stack-grafana"
    3 => "--namespace"
    4 => "monitoring"
    5 => "--context"
    6 => "k3d-k3d-cluster"
    7 => "3001:80"
  ]
}
```

Live cluster state at the same time:

```text
$ kubectl --context ubuntu-hostinger -n monitoring get pods,svc | rg 'grafana|NAME|acg-kube-prometheus-stack-grafana'
NAME                                                                READY   STATUS    RESTARTS   AGE
pod/acg-kube-prometheus-stack-grafana-b5d5dd97-mlhf2                3/3     Running   0          16d
NAME                                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)      AGE
service/acg-kube-prometheus-stack-grafana                    NodePort    10.43.192.223   <none>        80:30030/TCP 12d
```

Grafana port-forward log before the fix:

```text
Unable to connect to the server: dial tcp 52.37.60.119:6443: i/o timeout
```

## Root cause

`scripts/lib/providers/k3s-hostinger.sh` regenerated the local Grafana launch agent with stale values during Hostinger refresh:

- service name: `svc/kube-prometheus-stack-grafana`
- context: `k3d-k3d-cluster`

That did not match the live Hostinger monitoring stack:

- service name: `svc/acg-kube-prometheus-stack-grafana`
- context: `ubuntu-hostinger`

Result: the local `kubectl port-forward` agent behind `grafana.3ai-talk.org` pointed at the wrong cluster/service, so the Cloudflare tunnel had no healthy backend and returned `502`.

## Fix

Code fix landed in `scripts/lib/providers/k3s-hostinger.sh`:

- regenerate the Grafana port-forward plist against `svc/acg-kube-prometheus-stack-grafana`
- use `${_HOSTINGER_KUBE_CONTEXT}` instead of `k3d-k3d-cluster`

Regression coverage updated in `scripts/tests/lib/provider_contract.bats`.

## Live verification after refresh

After `make refresh CLUSTER_PROVIDER=k3s-hostinger`:

```text
$ plutil -p ~/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist
{
  "ProgramArguments" => [
    0 => "/opt/homebrew/bin/kubectl"
    1 => "port-forward"
    2 => "svc/acg-kube-prometheus-stack-grafana"
    3 => "--namespace"
    4 => "monitoring"
    5 => "--context"
    6 => "ubuntu-hostinger"
    7 => "3001:80"
  ]
}
```

```text
$ tail -40 ~/.local/share/k3d-manager/logs/grafana-pf.log
Forwarding from 127.0.0.1:3001 -> 3000
Forwarding from [::1]:3001 -> 3000
```

```text
$ make status CLUSTER_PROVIDER=k3s-hostinger
=== Service Health ===
  ✅ Alertmanager: HTTP 200
  ✅ ArgoCD: HTTP 200
  ✅ Frontend: HTTP 200
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ✅ Grafana: HTTP 200
  ✅ Product images: 20/20 have image_url
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 18/18 synced
  ✅ Data layer: 4/4 ready
```
