# Bug: product images show a cut-off slug label in the bottom-left corner of each storefront card

**Filed:** 2026-10-18 (Claude, from the operator's storefront screenshot)
**Status:** DISPATCHED — Codex, 2026-10-18
**Priority:** P3 — cosmetic; images load and products are usable
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "file a P3 for that cosmetic issue"
**Branch:** `k3d-manager-v1.43.5` (doc); fix in `wilddog64/shopping-cart-infra` on a feature branch
**Release:** v1.43.5
**Component:** `shopping-cart-infra`: `data-layer/minio/image-upload-configmap.yaml` (`generate_image`)

## Symptom

On the Products page each image tile shows a fragment of text at its bottom-left edge: "cam" (webcam),
"pad" (desk mat), "ltor-24" (monitor-24), "op" (laptop), "desk" (desktop hub). The fragment is the end
of the product slug.

## Root cause

- `generate_image` draws 800×600 (4:3) images: a centred label, plus a 24px "bottom tag" with the slug
  at `x = margin + 10 = 50`.
- The frontend shows them in `aspect-square` boxes with `object-cover` (`src/pages/ProductsPage.tsx:97-99`,
  `src/pages/ProductDetailPage.tsx:64-66` in `shopping-cart-frontend`). A 4:3 image filling a square box
  loses 100px on each side, so everything left of x=100 is cut. The slug tag starts at x=50 and is
  clipped. The centred label (at most ~400px wide) survives.

## Fix

Decision (operator, 2026-10-18: "just do wha proposed fix"): drop the tag, add a version marker.

- **F1.** In `generate_image`, delete the "Subtle bottom tag" block (the `tag_font` line and the
  `draw.text(... slug ...)` line). Keep `WIDTH`, `HEIGHT`, the colours, the inner rectangle, the centred
  label and the object keys unchanged.
- **F2.** Version marker, so changed art reaches images that already exist:
  - add `ART_VERSION = "2"` next to `WIDTH, HEIGHT`;
  - add `stored_art_version()`, which returns the stripped output of `mc cat <ALIAS>/<BUCKET>/.art-version`,
    or `""` when that fails;
  - in `main()`, after `wait_for_minio()`, set `refresh = stored_art_version() != ART_VERSION`. Skip an
    existing image only when `not refresh`. After the loop, when `refresh` is true, write `ART_VERSION`
    to a temp file and `mc cp` it to `<ALIAS>/<BUCKET>/.art-version`.
  - Later art changes bump `ART_VERSION`.
- **F3.** A comment above `ART_VERSION`: bump it whenever `generate_image` output changes.

## Acceptance

```yaml
must:
  - id: M1
    text: A generated image has no text outside the centred square region (x 100..700 for 800x600).
  - id: M2
    text: After the fix reaches MinIO, no storefront card shows a clipped text fragment.
must_not:
  - id: N1
    text: generate_image must not draw text left of x=100 or right of x=700 (red on pre-fix, which draws the slug at x=50).
  - id: N2
    text: The fix must not change object keys (<slug>.jpg), the bucket, or the MinIO endpoint.
  - id: N3
    text: When the stored marker equals ART_VERSION, existing images must not be regenerated or re-uploaded.
  - id: N4
    text: When the marker is missing or older, existing images must not be skipped (red on pre-fix, which skips every existing image).
evidence:
  - id: E1
    proves: [M1, N1, N2, N3, N4]
    kind: offline
    text: render each image locally with the ConfigMap script and assert no non-background pixels of the text colour outside x 100..700; with a stubbed mc on PATH, assert refresh/skip behaviour for a missing, older and current marker; N1 and N4 red on pre-fix.
  - id: E2
    proves: [M2]
    kind: live
    text: operator screenshot of the Products page after the sync and image refresh.
interface:
  - data-layer/minio/image-upload-configmap.yaml (generate_image)
  - MinIO bucket product-images
```

## What NOT to Do

- Do NOT change the frontend's `object-cover` or `aspect-square`; the product grid layout is correct.
- Do NOT create a PR or commit to `main`; no `--no-verify`.
