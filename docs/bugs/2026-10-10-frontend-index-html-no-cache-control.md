# Bug: the frontend serves `index.html` with no Cache-Control header, so a deploy can leave browsers on the old app

**Filed:** 2026-10-10
**Branch:** k3d-manager `k3d-manager-v1.43.3` (this spec; moved from v1.43.2 2026-10-12); work repo `shopping-cart-frontend`, branch `fix/index-html-no-cache`, cut from `origin/main`
**Status:** IMPLEMENTED — shopping-cart-frontend PR #121 (`636514d2`), awaiting CI/Copilot and merge; live check after the image deploys
**Priority:** P2 — after a deploy, a returning browser can keep running the previous build; the workaround is a hard refresh
**Severity:** medium

## Symptom

`shopping-cart-frontend/nginx.conf` caches hashed assets for a year, but sets nothing on the SPA
document. Measured on 2026-10-10 against the current `nginx.conf` in `nginx:1.31-alpine` (the
Dockerfile's image):

| Path | Cache-Control today |
|---|---|
| `/`, `/index.html`, `/orders/123` (SPA fallback) | none |
| `/assets/*.js` | `max-age=31536000` + `public, immutable` |

With no Cache-Control and a `Last-Modified` header, browsers cache `index.html` heuristically
(commonly 10% of the time since it was last modified). Until that expires, a returning user gets the
old `index.html`, which references the previous build's hashed bundles. The new build does not ship
those bundles, so they 404 and the page renders blank or keeps running old code. The 2026-10-09
login-callback fix (`docs/bugs/2026-10-09-frontend-login-callback-hangs-when-keycloak-db-restarts.md`)
reaches users only once their cached copy expires.

## Cause

No `location` sets a cache policy for the document. The asset rule (`location ~* \.(js|css|...)$`)
does not match `index.html`.

## Fix

Add one line to the SPA location, and nothing else:

```nginx
    # SPA fallback - serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
        expires -1;
    }
```

`expires -1` sends `Cache-Control: no-cache` plus a past `Expires`. The browser keeps its copy but
revalidates it on every load, so it costs one conditional request.

**Do not use `add_header Cache-Control ...` here.** nginx drops every inherited server-level
`add_header` in any location that declares its own. That would silently remove the
Content-Security-Policy, X-Frame-Options and the other security headers from the document. The
`expires` directive does not trigger that. Verified on 2026-10-10: with the line above, `/`,
`/index.html` and `/orders/123` return `Cache-Control: no-cache` **and** still carry the CSP and
X-Frame-Options; `/assets/*.js` is unchanged.

## Tests

The repo has no nginx config test. Add `scripts/check-nginx-cache.sh` (`set -euo pipefail`). It:
1. starts `nginx:1.31-alpine` with `nginx.conf` mounted at `/etc/nginx/conf.d/default.conf`, a tiny
   `index.html`, and an `assets/a.js`. Pass `--add-host <name>:127.0.0.1` for each `proxy_pass`
   upstream host, or nginx refuses to start;
2. asserts `Cache-Control: no-cache` and a `Content-Security-Policy` header on `/`, `/index.html`
   and `/some/route`;
3. asserts `immutable` on `/assets/a.js`;
4. removes the container on exit (trap).

Wire it into `.github/workflows/ci.yml` as its own step. Pin action versions to tags; keep
`permissions: contents: read`.

Mutation checks:
- Remove `expires -1;`: step 2 fails.
- Replace it with `add_header Cache-Control "no-cache";`: the CSP assertion fails.

## Live check (operator, after the image deploys)

`curl -sI https://<frontend host>/ | grep -i -e cache-control -e content-security-policy` shows both
headers. Without a public host, port-forward the Hostinger Deployment and check `/` and an SPA route:

```bash
kubectl --context ubuntu-hostinger -n shopping-cart-apps port-forward deploy/frontend 18091:<containerPort> &
curl -sI http://127.0.0.1:18091/ | grep -i -e cache-control -e content-security-policy
curl -sI http://127.0.0.1:18091/some/spa/route | grep -i cache-control
```

State 2026-10-16 ~21:50Z: PR #121 merged (`b874b3d8`) but the image publish job "Build, Scan, Push &
Deploy" hung for ~5h in its build-and-push step; the Hostinger pod still runs the 2026-10-09 image
(CSP present, no Cache-Control). Next: operator cancels and re-runs the job, merges the manifest PR it
opens, then the check above.

## Files (shopping-cart-frontend)

- `nginx.conf`
- `scripts/check-nginx-cache.sh`
- `.github/workflows/ci.yml`
- `CHANGELOG.md`

Commit message: `fix(nginx): revalidate index.html on every load so a deploy reaches returning browsers`

## Not in scope

The static-asset location's own `add_header Cache-Control` already drops the security headers on
`.js`/`.css` responses. CSP has no effect on a script response, so this is harmless; leave it.
