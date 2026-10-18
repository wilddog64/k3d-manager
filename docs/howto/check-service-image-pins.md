# Check service image pins

The shopping-cart manifests in `services/<app>/kustomization.yaml` pin each deployed image by
an immutable `sha256:` digest. This keeps the release branch deliberate and reproducible, but
the shopping-cart app CI publishes new images in `shopping-cart-infra`; it does not update the
digest pins in this repository. See [the incident bug](../bugs/2026-10-17-services-digest-pin-not-bumped-by-app-ci.md)
for the failure mode and decision to make drift visible.

## Run the check

Authenticate GitHub CLI with package-read access, then run:

```bash
gh auth refresh -h github.com -s read:packages
make image-pin-drift
```

The check reads every `services/*/kustomization.yaml`, compares its first GHCR image pin with
the digest advertised by that image's `:latest` manifest, and makes no changes.

Each service reports one of these statuses:

- `current` means the pinned and latest digests match.
- `DRIFT` means the pin differs from `:latest`; review the image and decide whether to update it.
- `unpinned` means the service has no digest pin and is not checked.
- `unknown` means the image is not in GHCR or its latest digest could not be resolved.

The exit codes are `0` when all checked pins are current, `1` when any pin is `DRIFT`, and `2`
when there is no drift but at least one service is `unknown` (including a missing GitHub package
token).

## Bump a pin

After reviewing the published image, edit the `digest:` value in
`services/<app>/kustomization.yaml` on the release branch. That branch deploys the service to
both the sandbox and Hostinger, so changing a pin requires the operator's go.
