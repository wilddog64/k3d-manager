# Stage D Audit finding — Kyverno verifyImages can't authenticate to private ghcr.io

**Date:** 2026-08-29
**Found on:** `k3d-manager-v1.27.0`, live on the hostinger app cluster (`ubuntu-hostinger`)
**Severity:** High — blocks the Audit→Enforce boundary (D2). Enforce is unsafe until fixed.
**Status:** OPEN
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

## Why not fixed in this slice

Stopping before Enforce per the release plan (D2) and the operator's instruction. Wiring
registry creds into Kyverno is a distinct provisioning + reconfigure step (still Audit,
fail-open — no posture change), queued as the next Stage D increment.
