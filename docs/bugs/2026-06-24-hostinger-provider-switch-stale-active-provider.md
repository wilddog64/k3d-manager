# Bug: `make status` can resolve the wrong provider after switching between ACG and Hostinger

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Files:** `scripts/lib/provider.sh`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

## Problem

`make status` is meant to report the currently active cluster provider, whether that is the ACG
sandbox (`k3s-aws`, `k3s-az`, `k3s-gcp`) or the permanent Hostinger app cluster (`k3s-hostinger`).

When both `ubuntu-k3s` and `ubuntu-hostinger` contexts are present, the current provider resolution
can still drift to the previous cluster if the shared active-provider marker is stale or missing.
That makes status switching unreliable and can send the health probe to the wrong cluster.

This is not a `/etc/hosts` problem. The failure is in provider state selection.

## Root Cause

Two gaps combine:

1. `scripts/lib/provider.sh::_acg_resolve_provider()` trusts the active-provider file without
   checking whether it still points at a live context.
2. `scripts/lib/providers/k3s-hostinger.sh` does not record Hostinger as the active provider after
   deploy/refresh, and the destroy path does not clear the shared marker.

As a result, the last provider to write the file wins, even if the user has switched to the other
cluster since then.

## Fix

- Make `_acg_resolve_provider()` validate the active-provider file before returning it.
- Record `k3s-hostinger` as active at the end of a successful Hostinger deploy/refresh.
- Clear the active-provider file when Hostinger is destroyed.
- Add provider-contract coverage for the active-provider resolution and Hostinger state hooks.

## Expected Result

- `make status` reports the current provider after switching between ACG and Hostinger.
- A stale provider file no longer forces status onto an unreachable or previous cluster.
- Hostinger refresh/deploy keeps the active-provider state current.
