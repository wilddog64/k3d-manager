# Bug: `bin/acg-sync-apps` should reuse its own ArgoCD port-forward and replace foreign listeners

**Date:** 2026-04-24
**Status:** OPEN
**Branch:** `k3d-manager-v1.1.0`

## Problem

`bin/acg-sync-apps` now fails clearly when local port 8080 is already bound, but the script
needs to distinguish two cases:

- if the existing listener is the script's own managed ArgoCD port-forward, reuse it
- if the listener is unrelated or stale, stop it and start the correct ArgoCD port-forward

Without that distinction, the sync target either restarts unnecessary port-forwards or forces
the user to manage the listener manually.

## Root Cause

The previous implementation only checked whether port 8080 was in use. It had no durable
ownership marker for the port-forward it created, so it could not tell whether a bound listener
was safe to reuse.

## Expected Fix

Persist the script-owned port-forward metadata in a state file. On subsequent runs:

- if the state file matches the requested ArgoCD context/namespace and the PID is alive, reuse it
- otherwise kill any listener on 8080, clear stale state, and start a fresh port-forward

## Impact

Medium. This improves operator UX and avoids unnecessary port-forward churn while keeping stale
or foreign listeners from blocking sync-apps.
