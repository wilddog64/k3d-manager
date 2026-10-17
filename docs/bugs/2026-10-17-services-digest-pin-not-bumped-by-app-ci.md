# App CI bumps the image in shopping-cart-infra, never the digest k3d-manager deploys

**Status:** OPEN — needs a design decision; no fix spec yet
**Priority:** P2
**Severity:** Medium — a merged, published service fix silently never reaches the sandbox or Hostinger;
the e2e run then reports the old defect as if it were still unfixed
**Found by:** Claude, live run `1792235987-31168` (2026-10-17), branch `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-17 "go for those" (operator), to file; the fix needs its own approval
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
