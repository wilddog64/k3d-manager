# Order image promotion blocked by GHCR blob upload failure

## What was tested

After order PR #64 merged as `914039ad665aded1571d0409b0b6c7bd5acc3ebf`, the
post-merge workflow `31135401214` was checked end-to-end. The corrected Go
Dockerfile was selected and the image build and Trivy scan completed, but the
push to GHCR failed. ArgoCD and the live Hostinger deployment were then checked.

## Actual output

```text
Build, Scan & Push / build-push 2026-08-07T00:50:15.0727390Z #35 ERROR: failed to push ghcr.io/wilddog64/shopping-cart-order:sha-d4a3082400ab3b850326ad3f9359ecac8df61e98: unknown: blob upload unknown to registry
Build, Scan & Push / build-push 2026-08-07T00:50:15.1060359Z ERROR: failed to build: failed to solve: failed to push ghcr.io/wilddog64/shopping-cart-order:sha-d4a3082400ab3b850326ad3f9359ecac8df61e98: unknown: blob upload unknown to registry
Build, Scan & Push / build-push 2026-08-07T00:50:15.1160621Z ##[error]buildx failed with: ERROR: failed to build: failed to solve: failed to push ghcr.io/wilddog64/shopping-cart-order:sha-d4a3082400ab3b850326ad3f9359ecac8df61e98: unknown: blob upload unknown to registry
```

```text
Unknown Degraded Succeeded k3d-manager-v1.22.0
k3d-manager-v1.22.0
ghcr.io/wilddog64/shopping-cart-order:sha-05ce65b96a5fe2f77cd0168580f6b7b6b5b56b6f@sha256:a8813e7505a9db62ecc599b58fab139bef74851ef438f005942778b01a7d3a01
No resources found in shopping-cart-apps namespace.
```

## Root cause

The corrected workflow path is proven, but the registry rejected a layer upload
with `blob upload unknown`. This is an external/transient GHCR registry failure;
it is not a Dockerfile selection or application build failure. The promotion did
not create a new image tag, so Argo has no new revision to deploy.

## Recommended follow-up

Retry the publish workflow after confirming GHCR health. Do not mark the order
runtime fix deployed until the image exists in GHCR, Argo reports `Synced Healthy`,
and the live Deployment references the new tag/digest.
