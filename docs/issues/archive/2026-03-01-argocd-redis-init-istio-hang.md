# Issue: ArgoCD `redis-secret-init` job hangs due to Istio sidecar

**Date:** 2026-03-01
**Component:** `scripts/plugins/argocd.sh`

## Description

The ArgoCD Helm chart deploys a `redis-secret-init` Job. When Istio injection is enabled in the namespace (like `cicd`), this Job gets an Istio sidecar. The sidecar doesn't exit when the main container finishes, causing the Job to stay in "Running" (but NotReady) status indefinitely, which blocks `helm upgrade --install --wait`.

## Root Cause

Istio sidecars do not automatically exit when the main container of a Job finishes.

## Fix

Disable Istio sidecar injection specifically for the `redis-secret-init` Job pods using Helm values.
