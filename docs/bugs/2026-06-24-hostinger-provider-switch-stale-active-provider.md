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

---

## Recurrence — 2026-09-27: `cluster-down` clears the scalar but leaks the set entry

**Branch:** `k3d-manager-v1.40.0`
**Files:** `bin/cluster-down`, `scripts/lib/provider.sh`, `bin/k3dm-webhook`, `Makefile`, `bin/cluster-status-summary`

The 2026-06-24 fix replaced the single scalar marker with a **set** —
`_ACG_ACTIVE_PROVIDERS_DIR` (`active-providers/`, one file per live provider) — keeping
`_ACG_ACTIVE_PROVIDER_FILE` (`active-provider`) as a legacy tie-break. `provider_active_set.bats:74`
still records the intent: *"prove the SET, not the scalar, drives it."*

The teardown path never joined that migration.

`bin/cluster-down:127` hardcodes the scalar path and nothing else:

```bash
_dry_guard "remove active-provider marker" rm -f "${HOME}/.local/share/k3d-manager/active-provider"
```

It never calls `_acg_unrecord_provider` and never touches `active-providers/`. So every teardown
**clears the tie-break and leaks the set entry** — the exact inverse of what the resolver needs.

Live state on 2026-09-27 confirms it:

| Path | State |
|---|---|
| `active-providers/k3s-aws` | present, **dated Sep 4 14:04** |
| `active-providers/k3s-hostinger` | present |
| `active-provider` | **absent** |

An ACG sandbox lives 4 hours. The `k3s-aws` entry had outlived its cluster by 23 days.

### Why that breaks resolution

`_resolve_provider` (`scripts/lib/provider.sh:258-266`) shortcuts only when the set holds exactly
one entry; with two it falls back to the scalar — which teardown deleted. Every consumer that reads
the scalar alone then lands on its hardcoded default, and **the two layers do not agree on what that
default is**:

| Consumer | Default when the scalar is absent |
|---|---|
| `scripts/lib/provider.sh:266` | `k3s-hostinger` |
| `bin/k3dm-webhook:149` | `k3s-aws` → context `ubuntu-k3s` |
| `Makefile:153` (`make status`) | `k3s-hostinger` |
| `bin/cluster-status-summary:7-8` | falls through to its own default |

`ubuntu-k3s` is not in the live kubeconfig. That is the upstream trigger for the D1 symptom in
`2026-09-27-hermes-eso-sensor-unknown-kubeconfig-error-as-absence.md`: the ESO smoke probe was
pointed at a context that had not existed for three weeks. That fix correctly stopped reporting the
resulting kubeconfig error as resource absence; it deliberately did **not** address why the wrong
context was chosen. This is why.

### Fix direction (not implemented — operator decision)

1. `bin/cluster-down` must call `_acg_unrecord_provider "${_cluster_provider}"` instead of the
   hardcoded `rm -f`. That removes the set entry and clears the scalar only when it names the
   provider being torn down — which is already the correct, tested behaviour.
2. Reconcile the two `_resolve_provider` defaults. They disagree today, so the same absent-marker
   state resolves to different clusters depending on which layer asks.
3. Consider a startup reconcile that drops set entries whose context is absent from the kubeconfig,
   so a leak self-heals rather than persisting for weeks.

Item 1 is the narrow fix and matches the existing tested helper. Items 2 and 3 are wider than this
defect.

### Lesson

The 2026-06-24 fix added the set and updated the *write* and *read* paths, but the teardown path
reached around the abstraction with a literal path. A migration that leaves one consumer hardcoding
the old location does not fail loudly — it degrades into stale state that reads as a plausible
answer. When replacing a state file with a state directory, grep for the **literal path**, not just
the variable name: `bin/cluster-down` referenced neither `_ACG_ACTIVE_PROVIDER_FILE` nor
`_ACG_ACTIVE_PROVIDERS_DIR`, so every variable-name search missed it.
