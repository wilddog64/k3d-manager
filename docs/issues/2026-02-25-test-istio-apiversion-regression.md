# test_istio Deployment apiVersion Regression

**Date:** 2026-02-25
**Status:** Fixed

## Description

During the namespace-isolation refactor in `scripts/lib/test.sh`, the Deployment
resource inside `test_istio()` was accidentally changed from `apiVersion: apps/v1`
to `apiVersion: v1`. `kind: Deployment` lives in the `apps` API group; using the core
`v1` version makes `kubectl apply` fail with `no matches for kind "Deployment" in
version "v1"`, so the test aborts immediately.

## Impact

- `./scripts/k3d-manager test_istio` and any future Stage 2 workflow would fail before
  creating the test Deployment, blocking CI work.

## Fix

- Restored `apiVersion: apps/v1` on the Deployment block within `test_istio()` and
  left the Namespace/Service manifests untouched (`scripts/lib/test.sh`).
- Re-ran `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test lib` to ensure no
  regressions in the unit suite; `test_jenkins` trap test still passes (53/53).

## Follow-up

- None. Namespace isolation + Istio manifest are now correct, so Stage 2 CI work can
  proceed.
