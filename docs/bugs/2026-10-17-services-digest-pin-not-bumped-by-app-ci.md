# App CI bumps the image in shopping-cart-infra, never the digest k3d-manager deploys

**Status:** LIVE-VERIFIED — 2026-10-18; FIXED (`dcf8f58a`) — drift is now reported by `make image-pin-drift`; pins stay manual
**Live evidence:** 2026-10-18 · run image-pin-drift-0600-pdt · env ghcr.io · scenario image-pin-drift/reports-real-drift · commit 8d7994ff · proves fix
Claude ran make image-pin-drift against GHCR: frontend, order, payment and product-catalog reported DRIFT (pinned digest differs from :latest), basket and namespace unpinned, exit 1 as specified. No token appeared in the output.
**Priority:** P2
**Severity:** Medium — a merged, published service fix silently never reaches the sandbox or Hostinger;
the e2e run then reports the old defect as if it were still unfixed
**Found by:** Claude, live run `1792235987-31168` (2026-10-17), branch `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-17 "go for those" (operator), to file; option 4 approved 2026-10-17 "go for that" (operator)
**Related:** `docs/bugs/2026-10-17-stripe-placeholder-key-sticks-in-vault.md` (the fix that sat undeployed)

## Symptom

The Stripe fix (`shopping-cart-payment` PR #89, `b60c4bf7`; then #87, `19079d5f`) merged, CI built and
pushed `sha-19079d5f`, and CI committed `ci: update shopping-cart-payment to sha-19079d5f…` to
`shopping-cart-infra`. The next Tier 2 run (`1792235987-31168`) still got the same Stripe 402. Both
`ubuntu-k3s-shopping-cart-payment` and `ubuntu-hostinger-shopping-cart-payment` were `Synced Healthy` —
on the old image.

## Cause

The payment Applications on both clusters render `services/shopping-cart-payment/` from **this** repo
at the release branch. Its `kustomization.yaml` pins the image by digest under `images:`. The
service's CI (`shopping-cart-infra`'s reusable `build-push-deploy.yml`) only updates the tag in
`shopping-cart-infra`, which these Applications do not read. Nothing updates the k3d-manager pin, so
it stays on whatever digest was last committed by hand.

It was fixed by hand in `11a9c0c8` (`sha256:2d930a93…` → `sha256:b3fb4b07…`, the index of
`sha-19079d5f`).

`make e2e-sandbox DIGEST=…` does not help: on Tier 2 it only records `candidate_digest` in the
summary. Only the Tier 1 vCluster path runs `kubectl set image` (`scripts/plugins/e2e.sh:623`).

The same gap likely applies to every `services/*/kustomization.yaml` that pins a digest; this run
only proved it for payment.

## Options (not yet decided)

1. **Bump in this repo from app CI.** Have `build-push-deploy.yml` also open a PR (or push to the
   current release branch) that rewrites the digest in `services/<app>/kustomization.yaml`. Needs a
   cross-repo credential (a GitHub App, per
   `reference_github_actions_bot_no_ruleset_bypass_personal_repo`).
2. **Point the Applications at shopping-cart-infra's manifests** (which CI already bumps). This is a
   larger change to the AppSets and to what "the release branch pins the platform" means.
3. **Argo CD Image Updater** write-back to this repo. It is already installed with
   `applications=0` on purpose (`reference_image_updater_zero_applications`), so this reverses a
   decision.
4. **Make it loud, not automatic.** Add a check (Hermes sensor or a `make` target) that compares each
   `services/*` digest with the newest `sha-*` digest in GHCR and reports drift. Cheapest; keeps
   pins deliberate.

Claude's lean: option 4 now (pins stay a reviewed decision; drift becomes visible), option 1 later if
the manual bump keeps being forgotten.

## Recurrence note

Until a fix lands: after any service merge that must reach the sandbox or Hostinger, bump its digest in
`services/<app>/kustomization.yaml` on the release branch. That push deploys to **both** clusters, so it
needs the operator's go.

## Decision (2026-10-17)

Option 4. Pins stay a deliberate, reviewed commit; a read-only check makes drift visible.

Claude prototyped the comparison against GHCR before writing this spec (read-only, `gh auth token` with
`read:packages`). It works, and found a real drift:

| Service | Pinned | `:latest` | |
|---|---|---|---|
| shopping-cart-frontend | `1c589d0dfe0a` | `1c589d0dfe0a` | current |
| shopping-cart-order | `6412b131c193` | `590832de525f` | **drift** |
| shopping-cart-payment | `b3fb4b071520` | `b3fb4b071520` | current |
| shopping-cart-product-catalog | `b4b699519a79` | `b4b699519a79` | current |
| shopping-cart-basket, -namespace | — | — | no `images:` pin |

App CI (`shopping-cart-infra` `build-push-deploy.yml`) pushes `sha-<commit>` and `latest` on `main`, so
`:latest` is the newest published build. The pins are **index** digests (see `11a9c0c8`), so the check
asks for the index media types first, as `app-cve-scan.sh` `_resolve_tag_digest` does.

Whether to bump the order pin is a separate decision for the operator (it deploys to both clusters).

## Fix — `bin/k3dm-image-pin-drift`

**F1. New script `bin/k3dm-image-pin-drift`** (executable, `#!/usr/bin/env bash`, `set -euo pipefail`,
plain bash like `bin/k3dm-hostnet-drift`; no lib sourcing).

- Option `--services-dir DIR` (default: `<repo root>/services`, repo root resolved from the script's own
  location). Any other argument: `ERROR: unknown option: <arg>` to stderr, exit 2.
- For each `DIR/*/kustomization.yaml`, sorted: read the first `images:` entry's `name:` and `digest:`.
  - No `images:` block, or no `digest:` → print `<service> unpinned` and continue.
  - Only `ghcr.io/` names are checked; anything else → `<service> unknown (not ghcr.io)`.
- Resolve `:latest` for `ghcr.io/<path>`:
  1. Credential: `gh auth token`. If it fails or is empty → print
     `ERROR: no gh token; run: gh auth refresh -h github.com -s read:packages` to stderr, exit 2.
  2. Registry token: `curl -s --netrc-file <tmp>` to
     `https://ghcr.io/token?service=ghcr.io&scope=repository:<path>:pull`, where `<tmp>` is a `mktemp`
     file, mode 0600, holding `machine ghcr.io login wilddog64 password <gh token>`. Take `.token` with
     `jq -r '.token // empty'`.
  3. Digest: `curl -sI` to `https://ghcr.io/v2/<path>/manifests/latest`, with headers from a second
     0600 `mktemp` file (`-H @<file>`) holding `Authorization: Bearer <token>`, plus
     `-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'`.
     Take the `Docker-Content-Digest` header (case-insensitive, strip `\r`).
  4. Tokens must never appear in argv, stdout, stderr or `set -x` output. Remove both temp files on exit
     (`trap ... EXIT`).
- Output, one line per service:
  - `<service> current pinned=<12 hex> latest=<12 hex>`
  - `<service> DRIFT pinned=<12 hex> latest=<12 hex>`
  - `<service> unknown (could not resolve latest)` when step 2 or 3 yields nothing
  - (`<12 hex>` = the first 12 hex characters after `sha256:`)
- Exit 1 if any line is `DRIFT`; otherwise 2 if any is `unknown`; otherwise 0.

**F2. Make target**, next to `find-similar-docs`, and add `image-pin-drift` to the `.PHONY` line on line 34:

```make
## Compare services/*/kustomization.yaml image digests with :latest in GHCR (read-only; needs gh read:packages)
image-pin-drift:
	@./bin/k3dm-image-pin-drift
```

**F3. BATS `scripts/tests/bin/image_pin_drift.bats`**, offline only. Stub `gh` and `curl` in a fake
`PATH` (as `cleanup_stale_sandbox.bats` does) and use a fixture `--services-dir` under
`$BATS_TEST_TMPDIR`. The `curl` stub answers the token URL with `{"token":"t"}` and the manifests URL
with a `docker-content-digest: sha256:<fixture>` header line (lower case, with `\r`). Tests:
1. pinned == latest → `current`, exit 0;
2. pinned != latest → `DRIFT`, exit 1;
3. a service with no `images:` → `unpinned`, exit 0;
4. manifests stub returns no digest header → `unknown`, exit 2;
5. `gh` stub fails → exit 2, stderr names `read:packages`;
6. the `gh` token value (`gho_FAKE_SECRET`) appears in neither output nor the recorded `curl` argv;
7. unknown option → exit 2.

Assert tokens (`DRIFT`, `pinned=`, …), not whole lines.

**F4. Doc `docs/howto/check-service-image-pins.md`**: what the pins are, why app CI doesn't bump them
(link this bug), `make image-pin-drift`, how to read each status and exit code, and how to bump a pin
(edit `digest:` in `services/<app>/kustomization.yaml` on the release branch; deploys to **both**
clusters, so it needs the operator's go). Add it to the README How-To list under the shopping-cart group.

**Mutation checks** (temp copy): make the comparison always say `current` → test 2 fails; put the gh
token in the `curl` argv → test 6 fails.

## Files

- `bin/k3dm-image-pin-drift` (new)
- `Makefile`
- `scripts/tests/bin/image_pin_drift.bats` (new)
- `docs/howto/check-service-image-pins.md` (new)
- `README.md`

## Rules

`shellcheck -S warning bin/k3dm-image-pin-drift` clean; `bats scripts/tests/bin/image_pin_drift.bats`
fully green; `make check-doc-links` clean. No network calls in tests.

## Definition of Done

- [ ] F1–F4 applied; gates green (paste output); both mutation checks reported.
- [ ] Commit message: `feat(bin): report services image pins that lag :latest in GHCR`.

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks. Do NOT touch files outside `## Files`.
- Do NOT change any `services/*/kustomization.yaml` pin.
- Do NOT call GHCR or any network endpoint, and do NOT run `gh auth token` for real.

## Landed (2026-10-17)

`dcf8f58a` on `k3d-manager-v1.43.4`, via `bin/k3dm-codex-dispatch` (task `image-pin-drift`). Claude's review
found three defects in Codex's version and fixed them before landing:

1. It compared only the first 12 hex characters of each digest. It now compares the full digest.
2. The token-leak test ended in `! grep`, which never fails a BATS test. It now uses `run grep` and asserts
   status 1.
3. Nothing covered digests that share the displayed prefix. Test 3 now does.

Gates: `shellcheck -S warning` clean; `bats scripts/tests/bin/image_pin_drift.bats` passes 8/8;
`make check-doc-links` clean. Mutations, on temporary copies: always `current` fails tests 2 and 3; a
12-character compare fails test 3; the gh token in `curl` argv fails test 7.

Live (read-only, against GHCR): the output matches the prototype table above, with `shopping-cart-order`
reported as `DRIFT`, exit 1. The order pin is the operator's call.

## Order drift — checked, not bumped (2026-10-17)

The operator asked for a check before any bump. Findings:

- Pinned `6412b131…` = `sha-61568ccc` (built 2026-09-22). `:latest` `590832de…` = `sha-fc3fae5a`
  (built 2026-10-06).
- `61568ccc...fc3fae5a` is 4 commits, all CI or Dependabot (`dependabot.yml`, `ci.yml`, a coverage
  workflow and script, a CHANGELOG line, the CI tag bump). No application code, Dockerfile or build file changed.
- The images differ because the base images in `go/Dockerfile` (`golang:1.25-alpine`, `alpine:3.19`) are floating tags, so a
  rebuild picks up a newer base.
- `trivy image --severity HIGH,CRITICAL` on both images: identical, 0 CRITICAL and the same 9 HIGH (musl
  CVE-2026-40200, and Go `stdlib`/`golang.org/x/*` findings in `/app/order-service`).

Bumping would redeploy order on both clusters for no change in behaviour or vulnerabilities, so it was not
bumped. The check will keep reporting this drift until order's next real release is pinned. Base-image-only
rebuilds therefore show up as `DRIFT` too, and a `DRIFT` line is a prompt to look, not a defect on its own.

**Correction (same day).** Order is the Go rewrite, not Java: CI builds `go/Dockerfile` with context `go`
(`ci.yml` → `build-push-deploy.yml`, `dockerfile: go/Dockerfile`). The root `Dockerfile` (Java/temurin) is
legacy and not built by CI. `/app/order-service` is the service itself. Where the 9 HIGH findings get fixed:

| Findings | Fixed by |
|---|---|
| musl CVE-2026-40200 (2) | `alpine:3.19` → `3.24`: Dependabot PR #90 (`go/Dockerfile`), #89 (`go/Dockerfile.local`) |
| Go `stdlib` (3) | Go 1.25.14 → 1.27-alpine builder: Dependabot PR #92 |
| `golang.org/x/crypto`, `x/net` (2), `x/text` | indirect deps in `go/go.mod`; no Dependabot PR, needs a `go get` bump |

All three PRs are green but `BEHIND` main. #95 (golang `1.21` → `1.25` in `go/Dockerfile.local`) duplicates #92's purpose.
