# Bug: MinIO image-upload PostSync hook installs Pillow from PyPI on every run and can hang for a day

**Filed:** 2026-10-18 (Claude, from the operator's Oct 17 KubeJobFailed alert email on ubuntu-hostinger)
**Status:** LIVE-VERIFIED — fix `83e8880d6dba22ebe3ffda36f052d7ce870887d7` is deployed; PostSync jobs succeeded, the application is Synced/Healthy, the data-layer health sensor reports 4/4 ready, and storefront product images loaded. The specific historical KubeJobFailed notification could not be located, so its resolved notification is not independently evidenced.
**Fix commit:** 83e8880d
**Priority:** P3 — a failed seed hook leaves the data-layer app OutOfSync and a KubeJobFailed alert firing; product images already in MinIO keep serving
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "you can open a P3 bug base on what you discovered"
**Branch:** `k3d-manager-v1.43.5` (doc); fix in `wilddog64/shopping-cart-infra` on a feature branch
**Release:** v1.43.5
**Component:** `shopping-cart-infra`: `data-layer/minio/image-upload-job.yaml`, `data-layer/minio/uploader/Dockerfile` (new), `.github/workflows/minio-uploader-image.yml` (new)

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

Decision (operator, 2026-10-18): a pinned uploader image built in `shopping-cart-infra`.

Hostinger facts that shape it (read-only, 2026-10-18):
- Kyverno `verify-first-party-images` **enforces** a cosign signature on `ghcr.io/wilddog64/*`, so the image
  must be signed. `shopping-cart-infra` has only `PACKAGES_TOKEN`; no `COSIGN_KEY` / `COSIGN_PASSWORD`.
- Nodes are `amd64`; namespace `shopping-cart-data`'s default ServiceAccount already uses `ghcr-pull-secret`.
- The shared `build-push-deploy.yml` promotes into `k8s/base/kustomization.yaml`, which this repo lacks,
  so the uploader gets its own workflow.

### Step 1 — Codex, branch `fix/minio-uploader-image` in `shopping-cart-infra`

- **F1.** `data-layer/minio/uploader/Dockerfile`:
  `FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1`,
  `pip install --no-cache-dir Pillow==13.0.0`, a non-root `USER`. The upload script stays in the
  ConfigMap (unchanged), so script edits need no rebuild.
- **F2.** `.github/workflows/minio-uploader-image.yml`: on push to `main` with paths
  `data-layer/minio/uploader/**` and on `workflow_dispatch`; `permissions: contents: read, packages: write`;
  actions pinned to version tags (`@v3`, `@v5`, as in `build-push-deploy.yml`); build `linux/amd64`, push
  `ghcr.io/wilddog64/minio-image-uploader:sha-<sha>` and `:1.0.0`; cosign sign by digest with
  `secrets.COSIGN_KEY` / `COSIGN_PASSWORD`. The job **fails** when `COSIGN_KEY` is empty (an unsigned
  image is rejected by Kyverno, so a silent skip would publish an unusable image). No `latest` tag.
- **F3.** In `image-upload-job.yaml`: `activeDeadlineSeconds: 600`.
- **F4.** `hook-delete-policy: BeforeHookCreation,HookSucceeded`.

Step 1 does not change the uploader image or the `pip install` line yet; the image does not exist until
step 1 merges and the workflow runs.

### Operator prerequisites (before step 1 merges)

- **DONE 2026-10-18** (operator; verified with `gh secret list`). Add `COSIGN_KEY` and `COSIGN_PASSWORD` to `wilddog64/shopping-cart-infra` (same key the app repos sign
  with; Kyverno trusts its public key).
- After the first publish, confirm the package `minio-image-uploader` is pullable with `ghcr-pull-secret`
  (link it to the repo or grant the token's account read access).

**Step 1 landed 2026-10-18:** shopping-cart-infra PR #113, squash `1be75f5f` (Codex `fb572b8`, Claude `387cabf` guard-before-build, `0c7e630` CHANGELOG). Workflow run `39167798042` succeeded: `minio-image-uploader:1.0.0` = `sha256:f152ceb0e3293888372fc43fe0e8a87bbcea3d1fb1e1dba7bcc599596b72657d`, cosign `.sig` published. The package is **public** and linked to the repo, so the pull-access prerequisite needs no action.

### Step 2 — after the first signed publish

- **F5.** In `image-upload-job.yaml`: uploader image
  `ghcr.io/wilddog64/minio-image-uploader:1.0.0@sha256:<published digest>`, command
  `python3 /scripts/generate-and-upload.py` (no `pip install`). Pin the `copy-mc` init image by digest too.

Recovery: the operator syncs `ubuntu-hostinger-data-layer` after step 2 lands. Claude reads the new pod's
log before the TTL removes it.

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

- [x] Step 1 (F1–F4) on `fix/minio-uploader-image` in `shopping-cart-infra`; only
      `data-layer/minio/uploader/Dockerfile`, `.github/workflows/minio-uploader-image.yml`,
      `data-layer/minio/image-upload-job.yaml` and a test file changed.
- [x] Step 1 tests: M3, M4 and N2 green, N2 red on the pre-fix manifest; the workflow passes `actionlint`
      if available, otherwise a YAML parse plus the assertions in F2.
- [x] Step 2 (F5) after the first signed publish: M1, M2, N1 green, N1 red on the pre-fix manifest.
- [x] Each step pushed; fix landed on `shopping-cart-infra` main at `83e8880d6dba22ebe3ffda36f052d7ce870887d7`.

## What NOT to Do

- Do NOT create a PR or commit to `main` in any repo.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT sync or delete anything on the cluster; the operator runs the recovery sync.
- Do NOT change the bucket contents layout or the MinIO credentials wiring.

**Live sync 2026-10-18 15:14 PDT** (after the data-layer Application was recovered, see
`2026-10-18-data-layer-app-cascade-deleted-by-registration-label-window.md`): synced `83e8880d`;
PostSync `minio-bucket-init` and `minio-image-upload` both Succeeded. Events: pod
`minio-image-upload-76g6t` pulled `minio-image-uploader:1.0.0@sha256:f152ceb0…` (Kyverno admitted it),
container ran ~6s; the 10-16 Failed Job was replaced. The pod log was not captured
(HookSucceeded deleted the pod within seconds). Remaining for E2: product images load on the storefront
and KubeJobFailed resolved.
- 2026-10-18 (operator screenshot): the storefront Products page shows the generated product images
  (coloured tiles with the product name) for all 8 visible products. Remaining for E2: the
  KubeJobFailed RESOLVED email.

**Offline verification 2026-10-21:** `bats scripts/tests/bin/minio-image-upload-job.bats` passed 8/8 against the landed `shopping-cart-infra` fix. The manifest pins the uploader and init images by tag and digest, removes runtime package installation, and bounds the Job with `activeDeadlineSeconds: 600`.

**Live evidence:** 2026-10-21 · run operator-ArgoCD-and-Hermes-screenshots · env ubuntu-hostinger/shopping-cart-data · scenario pinned-MinIO-PostSync-and-current-data-layer-health · commit 83e8880d · proves E2

The operator could not find the historical resolved-alert notification. A supplied notification screenshot was for `ubuntu-k3s/trivy-system` and is not counted as MinIO evidence. LIVE-VERIFIED is based on the successful pinned-hook run and storefront evidence recorded above, plus the supplied Argo CD Synced/Healthy and Hermes `data_layer 4/4 ready` / `no superseded failed Jobs` screenshots; the absent notification is explicitly retained as an evidence limitation.
