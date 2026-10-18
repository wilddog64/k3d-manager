# Bug: MinIO image-upload PostSync hook installs Pillow from PyPI on every run and can hang for a day

**Filed:** 2026-10-18 (Claude, from the operator's Oct 17 KubeJobFailed alert email on ubuntu-hostinger)
**Status:** OPEN
**Priority:** P3 — a failed seed hook leaves the data-layer app OutOfSync and a KubeJobFailed alert firing; product images already in MinIO keep serving
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "you can open a P3 bug base on what you discovered"
**Branch:** `k3d-manager-v1.43.5` (doc); fix in `wilddog64/shopping-cart-infra` on a feature branch
**Release:** v1.43.5
**Component:** `shopping-cart-infra`: `data-layer/minio/image-upload-job.yaml`, `data-layer/minio/image-upload-configmap.yaml`

## Symptom

- Oct 17: `[FIRING] KubeJobFailed on ubuntu-hostinger (1)` for `shopping-cart-data`, with no RESOLVED
  email after it. As of 2026-10-18 13:5x PDT it is still firing.
- ArgoCD `ubuntu-hostinger-data-layer`: last operation `Failed` at 2026-10-17T18:17:38Z, "one or more
  synchronization tasks completed unsuccessfully (retried 5 times)"; the app stays OutOfSync.
- Live Job `shopping-cart-data/minio-image-upload` (read-only, 2026-10-18):
  `created=2026-10-16T16:59:04Z`, `FailureTarget@2026-10-17T18:21:11Z`, `Failed@2026-10-17T18:21:43Z`,
  reason `BackoffLimitExceeded`, `ttlSecondsAfterFinished=300`, still present more than 24h after Failed.
  Its pods and events are gone, so the failing container's log is lost.

## Root cause (what is known)

`image-upload-job.yaml` (shopping-cart-infra `main`, last changed `f909906`, 2026-09-29):

1. The uploader container is `python:3.12-slim` and its command starts with `pip install --quiet Pillow`.
   Every run needs outbound access to PyPI. Any DNS, egress or PyPI failure fails the hook, and a sync
   is the only retry.
2. `restartPolicy: OnFailure`, `backoffLimit: 3`, and no `activeDeadlineSeconds`. The Job ran for about
   25 hours (10-16 16:59Z to 10-17 18:21Z) before it was marked Failed, so a hung or slow-failing run blocks the
   PostSync phase for a day.
3. `python:3.12-slim` is a moving tag. The repo's supply-chain rule asks for pinned image tags.

**Not established:** why this particular run failed. The window overlaps Hostinger's pod-IP and network
trouble and the 10-17 reboot (`docs/bugs/2026-10-17-hostinger-vault-sealed-after-reboot-no-unseal-watchdog.md`).
That is a timing match, not log evidence. Also unexplained: the TTL controller did not delete the Job
300s after it Failed. Record both if the logs of a rerun show them.

## Fix

In `shopping-cart-infra`, on a feature branch, never `main`:

- **F1.** Remove the runtime `pip install`. Either build a small pinned uploader image with Pillow
  (published to GHCR with the repo's existing image pipeline), or generate the images without Pillow.
  The hook must make no PyPI or other package-index call at run time.
- **F2.** Pin the uploader image by tag and digest.
- **F3.** Add `activeDeadlineSeconds: 600` to the Job spec.
- **F4.** Keep `hook-delete-policy: HookSucceeded`, so a failed Job stays for diagnosis. Add
  `BeforeHookCreation` so the next sync replaces it rather than colliding with the leftover.

Recovery for the current state is an operator-run sync of `ubuntu-hostinger-data-layer` after F1–F4 land.
Claude reads the new pod's log before the TTL removes it.

## Acceptance

```yaml
must:
  - id: M1
    text: The image-upload Job's containers make no pip/apt/package-index call at run time.
  - id: M2
    text: Every image in image-upload-job.yaml is pinned by tag and digest.
  - id: M3
    text: The Job has activeDeadlineSeconds <= 600.
  - id: M4
    text: hook-delete-policy includes BeforeHookCreation and HookSucceeded.
must_not:
  - id: N1
    text: The hook must not depend on outbound internet beyond pulling its pinned images (red on pre-fix, which runs pip install).
  - id: N2
    text: A hung uploader must not hold the PostSync phase longer than activeDeadlineSeconds (red on pre-fix, which has no deadline).
  - id: N3
    text: The fix must not change the bucket name, the object keys or the MinIO endpoint the hook writes to.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    text: a static test on the rendered manifest asserting no pip/apt in command/args, digest-pinned images, the deadline and the delete policy; N1/N2 red on the pre-fix manifest.
  - id: E2
    proves: [N1, N3]
    kind: live
    text: the operator syncs ubuntu-hostinger-data-layer; the hook succeeds, the app returns to Synced/Healthy, the KubeJobFailed alert resolves, and product images still load on the storefront.
interface:
  - data-layer/minio/image-upload-job.yaml (rendered Job manifest)
  - ArgoCD application ubuntu-hostinger-data-layer (sync, PostSync hook)
  - MinIO bucket product-images
```

## Definition of Done

- [ ] F1–F4 on a `shopping-cart-infra` feature branch; only the Component files (plus an uploader image
      definition if F1 builds one) changed.
- [ ] E1 passes; N1 and N2 shown red on the pre-fix manifest.
- [ ] Pushed; report the SHA.

## What NOT to Do

- Do NOT create a PR or commit to `main` in any repo.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT sync or delete anything on the cluster; the operator runs the recovery sync.
- Do NOT change the bucket contents layout or the MinIO credentials wiring.
