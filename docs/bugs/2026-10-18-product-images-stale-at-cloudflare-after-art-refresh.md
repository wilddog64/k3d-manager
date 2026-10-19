# Bug: refreshed product images stay stale at Cloudflare for up to 4 hours

**Filed:** 2026-10-18 (Claude, found while verifying the slug-tag fix)
**Status:** LIVE-VERIFIED — 2026-10-19 01:25Z: the plain `webcam.jpg` URL now returns `cache-control: max-age=300` with `cf-cache-status: REVALIDATED`, after the old 4h edge entry expired
**Priority:** P3 — cosmetic; new art appears on its own once the cache expires, or after a manual purge
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead to file a P3"
**Branch:** `k3d-manager-v1.43.5` (doc); fix in `wilddog64/shopping-cart-frontend` on a feature branch
**Release:** v1.43.5
**Component:** `shopping-cart-frontend`: `nginx.conf` (`location ^~ /minio/product-images/`)
**Fix commit:** `cad50792`
**Fix repo:** shopping-cart-frontend (PR #127, squash of Codex `8c934788`, Claude `a6a951f5`, `866a225`)
**Live evidence:** 2026-10-19 · run curl-plain-url-poll · env ubuntu-hostinger/shopping-cart-apps · scenario plain-image-url-after-edge-expiry · commit cad50792 · proves E2

## Symptom

After shopping-cart-infra #115 re-uploaded every product image (MinIO `last-modified` 2026-10-18
22:51:30Z, `.art-version` = `2`), the storefront still showed the old art on most cards. The plain
image URLs `https://frontend.3ai-talk.org/minio/product-images/<slug>.jpg` returned the July copies with
`cf-cache-status: HIT`, `cache-control: max-age=14400`, `last-modified: Wed, 22 Jul 2026`. The same URLs
with a cache-busting query string returned the new objects.

## Root cause

The `/minio/product-images/` location proxies to MinIO and sets no `Cache-Control`. MinIO sends none
either, so Cloudflare applies its default TTLs. The `max-age=14400` the client sees is Cloudflare's
default Browser Cache TTL, not the origin's. The URLs never change when the art changes, so nothing
tells the edge or the browser to fetch again.

## Fix options considered

- **URL versioning (rejected for now).** The catalog seed (`shopping-cart-product-catalog`
  `seed-job-configmap.yaml`) writes `image_url` once with `ON CONFLICT (sku) DO NOTHING`. A versioned
  URL would need a coordinated change in three repos (uploader keys, seed URLs, an update of existing
  rows), with `ART_VERSION` kept in sync across two of them.
- **Purge from the upload hook (rejected).** That puts a Cloudflare Cache Purge credential into the
  cluster for a cosmetic refresh.
- **Short origin TTL (chosen).** Set an explicit, short `Cache-Control` on the image location. 20 small
  images make the extra revalidation cheap.

## Fix

- **F1.** In `nginx.conf`, inside `location ^~ /minio/product-images/`, add:
  ```nginx
          proxy_hide_header Cache-Control;
          expires 5m;
  ```
  Change nothing else in the location (proxy target and headers stay, per N2). The `^~` prefix keeps
  the regex `expires 1y` / `immutable` static-asset block from applying to these URLs. Keep it that
  way.
- **F2.** A test that renders or parses `nginx.conf` and asserts F1 (see E1).

**Open question for the live check:** Cloudflare's zone-level Browser Cache TTL may override a
`max-age` lower than its setting. If E2 shows the browser-facing header still at 14400, the operator
sets Browser Cache TTL to "Respect Existing Headers" for the zone, or adds a Cache Rule for
`/minio/product-images/*`. That is a dashboard change, not a code change.

## Acceptance

```yaml
must:
  - id: M1
    text: Responses under /minio/product-images/ carry Cache-Control max-age=300 from the origin and keep the server-level security headers.
  - id: M2
    text: After an art refresh, the new image is served at the plain URL within 5 minutes, with no purge.
must_not:
  - id: N1
    text: The image location must not send a max-age above 300 or "immutable" (red on pre-fix, which sends no Cache-Control at all).
  - id: N2
    text: The fix must not change the proxy target, the location path or the image URLs stored by the catalog seed.
evidence:
  - id: E1
    proves: [M1, N1, N2]
    kind: offline
    text: a test on nginx.conf (nginx -t in the frontend image if available, plus a parse of the /minio/product-images/ location) asserting the two directives and the unchanged proxy_pass; N1 red on the pre-fix file.
  - id: E2
    proves: [M1, M2]
    kind: live
    text: after the frontend rolls out, a plain-URL fetch of /minio/product-images/webcam.jpg shows max-age=300 and, once the edge entry expires, the 2026-10-18 last-modified (Claude, read-only curl).
interface:
  - shopping-cart-frontend nginx.conf, location ^~ /minio/product-images/
  - https://frontend.3ai-talk.org/minio/product-images/<slug>.jpg
```

## Definition of Done

- [ ] F1, F2 on a feature branch in `shopping-cart-frontend`; only `nginx.conf`, the test file and
      `CHANGELOG.md` changed.
- [ ] N1 shown red against the pre-fix `nginx.conf`.
- [ ] Commit: `fix(nginx): short cache TTL for product images`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT call the Cloudflare API or change zone settings; that is the operator's.
- Do NOT touch the catalog seed or the MinIO uploader.

## Verification log

- 2026-10-18: Codex `8c934788` implemented F1 as first written (`add_header Cache-Control ... always`).
  Claude found that an `add_header` inside a location stops nginx inheriting the server-level
  `add_header` set, so image responses lost `X-Content-Type-Options`, CSP, `X-Frame-Options`,
  `Referrer-Policy` and `Permissions-Policy`. Confirmed in `nginx:1.31-alpine` with a stub MinIO
  upstream. F1 is now `expires 5m;` (`a6a951f5`). The same container check shows `Cache-Control: max-age=300` plus all
  five headers. The test rejects `add_header` in the block and fails on both the pre-fix conf and
  Codex's conf; vitest 31/31 and lint pass.
- 2026-10-18: PR #127 merged `cad50792` (23:22Z); `866a225` added a node types reference and Prettier formatting after CI lint/type-check reds. Copilot: no issues.
- 2026-10-18: E2 not yet runnable. The image header still reads `max-age=14400` (`cf-cache-status: HIT`), but Hostinger still runs the pre-fix image: `services/shopping-cart-frontend/kustomization.yaml` pins `sha256:1c589d0d…` (deploy last rolled 19:10Z), while the fix image `sha-cad5079…` is `sha256:c6557ecb…` (GHCR, 23:28Z). Same pin-not-bumped class as `2026-10-17-services-digest-pin-not-bumped-by-app-ci.md`. Bumping the pin needs the operator's go.
- 2026-10-18: operator approved the pin bump ("yes, you can"); frontend pin -> `sha256:c6557ecb…` (fix image `sha-cad5079…`).
- 2026-10-19 00:07Z: the frontend rolled out on `sha256:c6557ecb…`. A cache-busted fetch (`cf-cache-status: MISS`) returns `expires` = now + 5 min, so the origin sends the 5 min TTL. Cloudflare rewrites `Cache-Control` to `max-age=14400`, its zone Browser Cache TTL. The security headers are all present. The edge entry follows the origin TTL; the browser TTL needs the operator to set Browser Cache TTL to "Respect Existing Headers" (the open question above). E2 is pending that setting.
- 2026-10-19 01:25Z: E2 passed. `curl -A k3dm-verify/1` on https://frontend.3ai-talk.org/minio/product-images/webcam.jpg returned `cache-control: max-age=300` and `cf-cache-status: REVALIDATED` (last-modified 2026-10-18 22:51:30 GMT). No purge was needed.
