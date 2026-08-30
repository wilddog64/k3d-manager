# Stage D Audit finding — Kyverno verifyImages can't authenticate to private ghcr.io

**Date:** 2026-08-29
**Found on:** `k3d-manager-v1.27.0`, live on the hostinger app cluster (`ubuntu-hostinger`)
**Severity:** High — blocks the Audit→Enforce boundary (D2). Enforce is unsafe until fixed.
**Status:** RESOLVED 2026-08-30 (`8d8b2251`). Root cause was NOT registry auth — it is Kyverno's
cosign verifier resolving creds against the admitted object's (empty) `metadata.namespace` on
`generateName` Pods; the cosign path ignores `--imagePullSecrets` and a mounted `DOCKER_CONFIG`.
Fixed by gating at workload controllers instead of `Pod`. Full diagnosis, decision tree, and the
separate product-catalog unsigned-digest follow-up: `docs/bugs/2026-08-30-kyverno-verify-401-private-ghcr.md`.
**Context:** Stage D Audit slice (`deploy_image_signing --audit --app-cluster`, `bbbacfe0`)

## What Audit surfaced

With the `verify-first-party-images` ClusterPolicy live in **Audit** on hostinger, a
server-side dry-run admission of a first-party image returns:

```
policy verify-first-party-images.verify-cosign-signature:
  failed to verify image ghcr.io/wilddog64/shopping-cart-basket:sha-...:
  .attestors[0].entries[0].keys:
  GET https://ghcr.io/token?scope=repository:wilddog64/shopping-cart-basket:pull&service=ghcr.io:
  UNAUTHORIZED: authentication required
unverified image ghcr.io/wilddog64/shopping-cart-basket:sha-...
```

The failure is **registry authentication (401)**, NOT a signature mismatch. Kyverno cannot
pull the manifest + cosign signature for the **private** `ghcr.io/wilddog64/*` images, so
it reports every first-party image as `unverified`. Referencing the workload's
`ghcr-pull-secret` in the pod spec did NOT help — Kyverno's admission controller does not
use the resource's imagePullSecrets for verifyImages registry auth by default.

Under **Enforce** this would block **every** first-party pod (basket, frontend, order,
product-catalog, payment). That is precisely the would-be-block D2's Audit phase exists to
catch before flipping.

The signatures themselves are known-good: Stage C's `cosign verify` passed on all 5 images
independently. The only gap for Kyverno-based Enforce is registry credentials.

## Fix direction (before Enforce)

Give the Kyverno admission controller ghcr.io pull credentials:
1. Provision a `kubernetes.io/dockerconfigjson` secret in the `kyverno` namespace (ESO from
   the same Vault ghcr creds the app namespaces already use, or a copied secret).
2. Configure Kyverno to use it for image verification — admission controller
   `--imagePullSecrets=<name>` (Helm `admissionController.container.extraArgs` /
   `imagePullSecrets`), secret resolved from the Kyverno namespace.
3. Re-run the Audit dry-run; expect `verified` / a `pass` PolicyReport for each first-party
   image. Only then is Audit clean and Enforce safe.

Related prior art: `reference_trivy_operator_node_cred_private_image_skip` — same class of
"private registry, no creds → silent/again-visible verification gap".

## UPDATE 2026-08-29 — registry creds wired, but Kyverno's cosign path ignores them

Wired the standard fix and it did **not** resolve the 401:
- Created ExternalSecret `ghcr-pull-secret` in the `kyverno` ns (mirrors the app one:
  Vault `secret/data/github/pat` → dockerconfigjson for `ghcr.io`, user `wilddog64`).
  `SecretSynced=True`, type `kubernetes.io/dockerconfigjson`.
- helm-upgraded Kyverno with `existingImagePullSecrets[0]=ghcr-pull-secret` →
  admission controller now runs `--imagePullSecrets=ghcr-pull-secret` (verified in the
  Deployment args), rolled out 1/1, SA can `get` the secret.

**The credential is valid:** decoding the secret and calling
`GET https://ghcr.io/token?scope=repository:wilddog64/shopping-cart-basket:pull` with
`Authorization: Basic <auth>` returns **HTTP 200**. The token is a 40-char `gho_` OAuth
token.

**But Kyverno still 401s** on the SAME token endpoint (fresh, uncached image too — logs show
`cache entry not found` then the 401). The cosign verifier
(`pkg/image/verifiers/cpol/cosign/verifier.go`) sends **no auth** to the token endpoint,
i.e. it is NOT using the `--imagePullSecrets` credential for the sigstore/cosign registry
access. This looks like the cosign path using an ambient/default keychain rather than
Kyverno's configured registry credentials.

**Candidate fixes to try next (own investigation):**
1. Bump the Kyverno chart to a version where verifyImages consumes `--imagePullSecrets` for
   the cosign registry client (possible 1.19.0-specific regression).
2. Mount the dockerconfigjson at `/root/.docker/config.json` (or `$DOCKER_CONFIG`) in the
   admission controller so cosign's DefaultKeychain finds it (helm volume/volumeMount).
3. Check for a Kyverno registry-credentials ConfigMap / `imageVerify` registry option in
   3.9.0 that the cosign verifier actually reads.

**DefaultKeychain mount also FAILED (2026-08-29).** Patched the admission-controller
Deployment: mounted `ghcr-pull-secret`'s `.dockerconfigjson` as `config.json` at
`/kyverno-docker` + set `DOCKER_CONFIG=/kyverno-docker` (both confirmed in the Deployment
spec; the container is distroless so no in-pod shell to cat it). A fresh order-service
dry-run STILL 401s. So BOTH documented mechanisms — `--imagePullSecrets` and cosign's
`DOCKER_CONFIG`/DefaultKeychain — are ignored. This pins the cause on Kyverno 1.19.0's
cosign verifier (`pkg/image/verifiers/cpol/cosign/verifier.go`) constructing its own
credential-less registry client for the ghcr token request, bypassing both. **This is an
upstream/version matter — not resolvable at the config or pod level.** Next avenue = a
Kyverno chart version bump (or upstream issue), tracked as a separate task.

Live state left in place: Kyverno healthy, policy in **Audit** (fail-open — no workload
impact), `ghcr-pull-secret` present in kyverno ns, flag set, admission-controller Deployment
carries the experimental docker-config mount (harmless; removed by the next helm upgrade).
Rollback = `helm uninstall kyverno -n kyverno` + delete the ClusterPolicy.

## Why not fixed in this slice

Stopping before Enforce per the release plan (D2) and the operator's instruction. Wiring
registry creds into Kyverno is a distinct provisioning + reconfigure step (still Audit,
fail-open — no posture change), queued as the next Stage D increment.
