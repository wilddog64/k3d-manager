# e2e Playwright test-runner image is amd64-only → ErrImagePull on arm64 substrate

**Filed:** 2026-08-16
**Component:** `ghcr.io/wilddog64/shopping-cart-e2e-tests:latest` (published by the
`shopping-cart-e2e-tests` repo, `.github/workflows/publish-image.yml`); consumed by the k3d-manager
Tier 1 harness `scripts/plugins/e2e.sh` (`E2E_IMAGE`, `_e2e_job_manifest`).
**Severity:** high (final blocker for a green live e2e smoke on an Apple-Silicon / arm64 substrate)
**Found by:** live smoke run #7 — the harness ran clean through vCluster create → readiness → all 5
substrate rollouts → seed job → Playwright Job launch, then the Job pod stuck in `ImagePullBackOff`.

## Problem

The Playwright Job pod (`e2e-run-...`) never starts on the arm64 k3d node:

```
Failed to pull image "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest":
rpc error: code = NotFound desc = failed to pull and unpack image ...:
no match for platform in manifest: not found
```

This is **not** an auth failure — the `ghcr-pull-secret` (dockerconfigjson) is present, wired onto the
`default` SA and the Job's `imagePullSecrets`, and authentication to GHCR succeeds (the manifest list is
fetched). The failure is platform selection.

## Root cause

`docker manifest inspect ghcr.io/wilddog64/shopping-cart-e2e-tests:latest` publishes **only**:

```
platform: linux / amd64
platform: unknown / unknown   # SBOM/attestation manifest, not runnable
```

The k3d/OrbStack node on this host is **arm64** (`uname -m` → `arm64`). There is no `linux/arm64`
variant in the manifest list, so containerd cannot select a runnable image → `no match for platform`.

The e2e-tests Dockerfile bases on `mcr.microsoft.com/playwright:v1.57.0-jammy`, which **is** published
multi-arch (amd64 + arm64), so an arm64 build is fully feasible — the image just isn't being built/pushed
for arm64. The repo's `publish-image.yml` sets up `docker/setup-buildx-action` but does not pass a
multi-platform `platforms:` list (defaults to the runner's single arch, amd64).

## Fix

**Durable (correct, substrate-agnostic) — publish the image multi-arch.** In
`shopping-cart-e2e-tests/.github/workflows/publish-image.yml`, add QEMU + a multi-platform buildx push:

```yaml
- uses: docker/setup-qemu-action@v3          # emulate arm64 on the amd64 runner
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    platforms: linux/amd64,linux/arm64        # <-- the fix
    push: true
    tags: ghcr.io/wilddog64/shopping-cart-e2e-tests:latest
```

(Or build arm64 natively on an arm64 runner if emulation is too slow for `npm ci` + browser layers.)
This makes the harness truly substrate-agnostic — it will run on both the arm64 laptop and amd64
CI/cloud substrates. **This is a `shopping-cart-e2e-tests` repo change** — do NOT edit that repo from
k3d-manager; spec it there / hand to the shopping-cart flow (branch + PR, never direct main push).

**Local workaround (this session, no publish) — build arm64 locally + import into k3d.** The harness Job
uses `imagePullPolicy: IfNotPresent` (`scripts/plugins/e2e.sh` `_e2e_job_manifest`), so a locally-present
image is used without any GHCR pull:

```bash
cd ~/src/gitrepo/personal/shopping-carts/shopping-cart-e2e-tests
docker build --platform linux/arm64 -t ghcr.io/wilddog64/shopping-cart-e2e-tests:latest .
k3d image import ghcr.io/wilddog64/shopping-cart-e2e-tests:latest -c k3d-cluster
# then re-run: ./scripts/k3d-manager e2e_verify_vcluster
```

This proves the harness green on arm64 now; it does **not** replace the durable multi-arch publish (a
fresh machine or CI arm64 node would still fail until the image is multi-arch).

## Harness follow-ups surfaced by this run (track, decide from evidence)

1. **Background-task max-runtime vs. cold-run wall time.** Smoke #7 was externally killed (~12 min) while
   waiting on the Playwright Job. The full cold path (vCluster create + readiness + 5 rollouts + seed +
   Playwright) can exceed a short background budget. When re-running, allow enough wall time or run
   detached; the harness itself was healthy.
2. **Optional preflight arch check.** The harness could `docker manifest inspect` (or a lighter check)
   the `E2E_IMAGE` for the node arch before launching the Job and fail fast with a clear message instead
   of a 6-minute `ImagePullBackOff`. Nice-to-have, not required.
3. **Teardown EXIT trap** still leaves orphan vClusters on interruption/failure (tracked in
   `docs/bugs/2026-08-16-e2e-substrate-db-env-var-mismatch.md`).

## Verification

1. `docker manifest inspect ghcr.io/wilddog64/shopping-cart-e2e-tests:latest` lists `linux/arm64`
   (after the durable fix) — or the local arm64 image is present on the k3d node (workaround).
2. Live re-run: the `e2e-run-...` Job pod reaches `Running` then `Completed`, and the harness writes a
   pass/fail JSON summary to `~/.k3dm/e2e/<run_id>.json`. This is the run that must go green.

## What NOT to do

- Do NOT add `--platform` overrides or `insecure`/`skip-tls` flags to paper over the pull.
- Do NOT edit the `shopping-cart-e2e-tests` repo directly from k3d-manager — spec the multi-arch publish
  in that repo's own flow.
- Do NOT create a PR; do NOT commit to `main`. k3d-manager changes go on `k3d-manager-v1.25.0`.
