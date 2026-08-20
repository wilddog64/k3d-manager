# Status falsely reported product-image and frontend-login failures during tunnel recovery

## Observed output

```text
✗ Product images: HTTP Error 502: Bad Gateway
✓ ESO ClusterSecretStore: Ready=True
✓ ESO ExternalSecrets: 18/18 synced
✓ Data layer: 4/4 ready
✓ Keycloak login: token minted (realm=shopping-cart)
✗ Frontend login: HTTP 502 on /api/cart
```

The same checks passed after the forwards converged: `make status` reported
`Product images: 20/20 have image_url`, `Frontend login: HTTP 200 on /api/cart`,
and `Overall: HEALTHY`. Local upstreams and public hostnames were healthy on
the second check.

## Root cause

The general service probes retried transient tunnel failures, but the product
catalog request and authenticated frontend request did not. A single Cloudflare
502 during node/forward recovery was therefore reported as a data or login
failure.

## Fix

Both requests now use the same bounded smoke retry policy. The health status
still fails when all attempts fail, but transient 502s no longer create false
red checks.

Hostinger `/cluster-status` also uses the normal three-attempt service probe
window instead of a single attempt, so a node restart has time to rebuild its
port-forwards before the command reports an outage.
