# Bug: ACG sandbox expiry is reported as generic tunnel loss

**Date:** 2026-07-08  
**Branch:** `k3d-manager-v1.14.0`  
**Files:** `bin/cluster-status`, `bin/k3dm-webhook`, `scripts/tests/bin/cluster_status_observability.bats`, `scripts/tests/lib/webhook.bats`

## Problem

Today the operator-facing status surfaces collapse several different states into the same message:

- local SSH tunnel down
- remote app cluster temporarily unreachable
- AWS credentials expired
- the ACG AWS sandbox itself no longer exists

For the ACG-backed environment, that last state is not just "the tunnel is down." The sandbox can
legitimately expire or be torn down underneath the laptop. When that happens, `/cluster-status`,
`bin/cluster-status`, and `/cluster-refresh` currently imply that a simple refresh can restore
access, which is misleading.

This repo should treat ACG as part of the ecosystem, but not as a permanent substrate. Operator
feedback must say explicitly when the sandbox-backed cluster is absent so the next action is clear.

## Root Cause

`bin/cluster-status` only probes:

- localhost `:6443` reachability
- `kubectl get nodes` on the app context
- `aws sts get-caller-identity`

`bin/k3dm-webhook` does the same, then reports:

> cluster may be rebuilding or unavailable

Neither path checks the ACG AWS source of truth used by the real provider flow:
CloudFormation stack status for `${_ACG_CF_STACK_NAME}`.

## Required Fix

### Change 1 — `bin/cluster-status`: add an explicit ACG sandbox section

For provider `k3s-aws` only, add an `=== ACG Sandbox ===` section that probes:

- AWS identity (`aws sts get-caller-identity`)
- CloudFormation stack status for `k3d-manager-acg`

Classify the result into operator-facing states:

- credentials invalid / unavailable
- stack present and healthy
- stack present but unhealthy / deleting
- stack absent (most likely sandbox expired or was torn down)

When the app cluster is unreachable, stop printing a generic "run bin/cluster-refresh" hint with no
qualification. The status output should point operators at the ACG sandbox classification so they
can distinguish access-layer drift from an actually missing sandbox.

### Change 2 — `bin/k3dm-webhook`: classify ACG reachability before reporting cluster status

Add a narrow helper that probes AWS identity plus CloudFormation stack status for the ACG AWS
provider, then use it in `_run_cluster_status`:

- log an `*ACG sandbox:* ...` line for `k3s-aws`
- if the app cluster is unreachable and the stack is absent, say explicitly that the sandbox is
  likely expired or torn down and that `/cluster-refresh` will not recreate it
- if the stack is still present, keep the current "cluster rebuilding or unavailable" framing

The goal is to make Slack status output actionable without requiring the operator to infer expiry
from a dead tunnel.

### Change 3 — `bin/k3dm-webhook`: stop promising that refresh always restores the tunnel

`_run_cluster_refresh` currently reports:

> Refresh complete — tunnel and credentials restored

That is only true when the ACG stack still exists. After this fix:

- if refresh succeeds and the ACG stack is healthy, say the access layer / credentials were refreshed
- if refresh succeeds but the stack is absent, say refresh completed but the ACG sandbox is still
  absent and must be reprovisioned

No auto-recreate belongs in this bugfix. This is visibility and operator guidance only.

## Tests

- `shellcheck -S warning bin/cluster-status`
- `python3 -m py_compile bin/k3dm-webhook`
- `bats scripts/tests/bin/cluster_status_observability.bats`
- `bats scripts/tests/lib/webhook.bats`
- `./scripts/k3d-manager _agent_audit`

## Out of Scope

- auto-extending or auto-recreating the ACG sandbox
- changing tunnel plugin behavior
- changing any Hostinger code path
- de-ACG work or provider migration
