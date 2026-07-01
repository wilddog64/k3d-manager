# Issue: Alertmanager public hostname still returns 404 at the Cloudflare edge

## What I tested

- Ran `make status CLUSTER_PROVIDER=k3s-hostinger`
- Probed the public hostname directly with a forced Cloudflare edge IP
- Probed the local authenticated proxy on `127.0.0.1:9093`

## Actual output

```text
curl -sS -o /dev/null -w '"'"'%{http_code}\n'"'"' -u "$ALERTMANAGER_BASIC_AUTH_USER:$ALERTMANAGER_BASIC_AUTH_PASSWORD" http://127.0.0.1:9093/api/v2/status
200
```

```text
curl -sk --resolve alertmanager.3ai-talk.org:443:104.21.61.169 -u "$ALERTMANAGER_BASIC_AUTH_USER:$ALERTMANAGER_BASIC_AUTH_PASSWORD" -o /dev/null -w '"'"'%{http_code}\n'"'"' https://alertmanager.3ai-talk.org/api/v2/status
404
```

```text
make status CLUSTER_PROVIDER=k3s-hostinger
...
=== Service Health ===
  ✅ Alertmanager: HTTP 200
  ✅ ArgoCD: HTTP 200
  ✅ Frontend: HTTP 200
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ✅ Grafana: HTTP 200
  ✅ Product images: 20/20 have image_url
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 17/17 synced
  ✅ Data layer: 4/4 ready
```

## Root cause

The local Alertmanager login proxy is healthy, but old `cloudflared` connectors were still running with the stale ingress config that lacked the Alertmanager hostname. Cloudflare was load-balancing requests across those stale connectors, which made the public hostname return `404` even after the repo config and the current connector were correct.

## Recommended follow-up

- Rebuild or stop the stale `cloudflared` connectors before judging public hostname health
- Keep `~/.cloudflared/config.yml` synced with `scripts/etc/cloudflared/config.yml`
- Re-verify the public URL after any tunnel restart or config refresh
