# 2e E9 reconciliation evidence, 2026-11-21

Hub m5-air, Argo CD v3.5.5 (`quay.io/argoproj/argocd:v3.5.5`), deploy/hub 74ff9a6f, app cluster context `ubuntu-hostinger`.
Read-only reads by Claude over ssh from m4; the one GitHub write (controlled pin) on the operator's go. Spec:
`docs/plans/v1.45.0-remote-promote-2e-cve-pin-branch.md` E9 (M1, M2, M3, M11).

## Before the pin (15:08:58Z)
- ApplicationSet `cicd/services-git`: no `ignoreApplicationDifferences`; ErrorOccurred False (ApplicationSetUpToDate),
  ParametersGenerated True, ResourcesUpToDate True; generators `[matrix]` with a files generator `revision cve-pins/hub`,
  `files: [pins.json]`.
- Applications owned by services-git: 6 (basket, frontend, namespace, order, payment, product-catalog), all Synced/Healthy, none
  with `kustomize.images`. Same 6 as the `services/*` directories minus shopping-cart-identity, and the 6 that stayed Synced/Healthy
  through the cutover (watched 14:26–14:30Z).
- `origin/cve-pins/hub` = 010fba8d (k3dm-cve-promoter, 2026-11-21T14:26:24Z, seed), `pins.json` `{"v":1,"cvePins":{}}`. An empty
  map does not pass E9, so the controlled same-digest pin was used.

## Controlled same-digest pin (operator go)
- Candidate: shopping-cart-frontend. Base on deploy/hub `services/shopping-cart-frontend/kustomization.yaml` = running Deployment
  image = `sha256:97d0b172db3bfeaaabb8e4d75b6183369be87d080b2f3d564779b38b2f7fe18c`; Deployment generation 64 before.
- Commit bac62527 on `cve-pins/hub` (fast-forward from 010fba8d, author chengkai liang, 15:12:55Z):
  `cvePins["shopping-cart-frontend"] = {digest: <above>, base: <above>, at: 2026-11-21T15:12:45Z}`; validated with
  `_pin_valid` from `scripts/etc/argocd/platform-ops/app-cve-scan.sh` before the commit.

## After the pin
- 15:15:07Z (about 2m after the push, ApplicationSet requeue): frontend Application
  `spec.source.kustomize.images = ["ghcr.io/wilddog64/shopping-cart-frontend@sha256:97d0b172…"]`, Synced/Healthy, sync revision
  74ff9a6f (the pin changes the Application spec, not the source revision).
- 15:15:36Z Deployment `shopping-cart-apps/frontend`: image `ghcr.io/wilddog64/shopping-cart-frontend@sha256:97d0b172…` = the pin;
  generation 64, observedGeneration 64 (no rollout); pod `frontend-6cb766d98f-6whgt` created 2026-11-11T23:54:57Z, imageID the same
  digest.
- Unpinned: order, basket, payment, product-catalog Applications show no `kustomize.images`, Synced/Healthy.
- Application count 6; ApplicationSet conditions unchanged and healthy.
- `git log --author=k3dm-cve-promoter --since=2026-11-21T14:26:00Z origin/deploy/hub`: empty.

Result: E9 PASS (positive case included). The pin stays; the startup prune removes it when the frontend base on deploy/hub changes.
