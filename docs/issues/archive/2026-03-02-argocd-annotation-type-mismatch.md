# Issue: ArgoCD redis-init annotation requires string type

**Date:** 2026-03-02
**Component:** `scripts/plugins/argocd.sh`

## Description

The Istio sidecar injection annotation `sidecar.istio.io/inject` must be a string value `"false"`. Using Helm's `--set` flag without quotes causes the value to be interpreted as a YAML boolean (`false`), which may be ignored by the Istio admission webhook or causes validation errors in Kubernetes annotations (which must be strings).

## Reproducer

```bash
# Using --set causes boolean type in manifest
--set "redisSecretInit.podAnnotations.sidecar\.istio\.io/inject=false"
```

## Root Cause

Helm `--set` defaults to type-guessing. Unquoted `false` becomes a boolean.

## Fix

Use `--set-string` to force the value to be rendered as a quoted string in the final manifest.

```bash
--set-string "redisSecretInit.podAnnotations.sidecar\.istio\.io/inject=false"
```
