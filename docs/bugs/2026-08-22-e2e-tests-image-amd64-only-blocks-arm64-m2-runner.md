# E2E Playwright image `shopping-cart-e2e-tests` is amd64-only — blocks the M2 (arm64) remote runner (2026-08-22)

> **RESOLVED 2026-08-24.** Multiarch build shipped: `wilddog64/shopping-cart-e2e-tests`
> **PR #7 MERGED** (`90c13994`) — adds `docker/setup-qemu-action` + `platforms:
> linux/amd64,linux/arm64` + `provenance: false` to `publish-image.yml`. `:latest` rebuilt on
> the main push (run `32725667211`, success) and **verified multiarch**:
> `docker manifest inspect …:latest` → `linux/amd64` + `linux/arm64`. The arm64 pull failure on
> the M2 node is gone. Remaining M2 acceptance-gate blockers are unrelated (hostinger node CPU
> exhaustion; publish-back unconfigured).

**Severity:** high (the v1.27.0 plan #2 M2 remote runner can NEVER complete a passing
Playwright run on Apple Silicon until this is fixed; every dispatch fails identically).
**Component:** the `shopping-cart-e2e-tests` image build (lives in the shopping-cart repo's
CI, not k3d-manager) — consumed by `scripts/plugins/e2e.sh` (`e2e_verify_vcluster` launches
`ghcr.io/wilddog64/shopping-cart-e2e-tests:latest`).
**Found while:** v1.27.0 plan #2 live-acceptance passing run on the M2 OrbStack runner. Every
prior blocker (lock dir, stale repo, kubeconfig, ghcr auth, product-catalog pin) was cleared;
the substrate rolled out fully green, then the Playwright Job failed.

## Symptom

Substrate healthy (postgres/redis/product-catalog/basket/order all rolled out, seed job
complete), then the Playwright Job `e2e-run-<id>` fails. vCluster events:

```
Pulling image "ghcr.io/wilddog64/shopping-cart-e2e-tests:latest"
Warning Failed  Failed to pull image ".../shopping-cart-e2e-tests:latest":
  rpc error: code = NotFound desc = failed to pull and unpack image:
  no match for platform in manifest: not found
Warning Failed  Error: ErrImagePull → ImagePullBackOff
job  DeadlineExceeded  Job was active longer than specified deadline
```

Result JSON: `phase: running-playwright, exit_code: 1, result: fail, passed/total: null`
(harness never gets a Playwright summary because the container never starts).

## Root cause

The image index has no `linux/arm64` entry. Verified against ghcr:

```
mediaType: application/vnd.oci.image.index.v1+json
  platform: {architecture: amd64,   os: linux}
  platform: {architecture: unknown, os: unknown}   # attestation/provenance, not a runnable platform
```

Only `amd64/linux`. The M2 runner's k3d node is `arm64`, so containerd refuses the pull
("no match for platform"). The app images (product-catalog/basket/order) ARE multi-arch and
pulled fine on the same node — only the e2e-tests image is single-arch.

Why it worked before on M4: M4's OrbStack has amd64 emulation (Rosetta/binfmt) enabled, so
its node advertises amd64 and can run the image. The M2 node does not, so the pull fails
outright. Relying on host emulation is not portable — the plan's goal is a substrate-agnostic
runner, so the image must carry the runner's native arch.

## Fix (durable — preferred)

Publish `shopping-cart-e2e-tests` as a multi-arch image including `linux/arm64`. In the
shopping-cart repo's image-build workflow, build with buildx for both platforms:

```yaml
- uses: docker/setup-qemu-action@v3            # pinned tag
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    platforms: linux/amd64,linux/arm64
    push: true
```

(Match the existing multi-arch build used for the product-catalog/basket/order images, which
already work on arm64.) After the rebuild, `docker manifest inspect
ghcr.io/wilddog64/shopping-cart-e2e-tests:latest` must list both `amd64` and `arm64`.

## Fix (stopgap — only if the rebuild is delayed)

Enable amd64 emulation on the M2 k3d node so it can pull/run the amd64 image (binfmt/QEMU in
the k3d node's containerd). This is fragile (per-host setup, slower, not substrate-agnostic)
and violates the plan's portability goal — use only to unblock a single acceptance run, not
as the answer.

## Impact on v1.27.0 plan #2 acceptance

The "one passing run" half of the 2-run live-acceptance gate **cannot pass** on the M2 arm64
runner until the multi-arch rebuild lands. The runner harness itself is proven end-to-end
(dispatch → SSH → OrbStack → k3d host → vCluster → substrate rollout → Playwright launch);
the only remaining failure is this image-arch mismatch, which is external to k3d-manager.
Track the acceptance gate as BLOCKED on the shopping-cart e2e-tests multi-arch build.

## Verification (after fix)

```bash
docker manifest inspect ghcr.io/wilddog64/shopping-cart-e2e-tests:latest \
  | grep -E 'architecture'         # must include amd64 AND arm64
make e2e-remote RUNNER=m2          # substrate green + Playwright runs to a real pass/fail
```

## Related

- `docs/bugs/2026-08-22-e2e-substrate-stale-product-catalog-image-pin.md` (prior substrate blocker).
- `docs/bugs/2026-08-22-e2e-m2-runner-bootstrap-kubeconfig-and-ghcr-gaps.md` (bootstrap/auth/publish-back gaps).
- `docs/plans/v1.27.0-m2-remote-e2e-runner.md` (the acceptance gate this blocks).
