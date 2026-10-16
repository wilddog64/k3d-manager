# Bug: Bug Tracking's Release filter opens on All instead of the current release

**Status:** OPEN — not started
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** human (operator)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, variable `release`
**Branch:** `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-16 "is it possible default to current release … can do this in next
release" (operator)

## Problem

The k3dm Bug Tracking dashboard opens with **Release (filed in) = All**. The operator usually wants
the release in progress. Today the variable is a multi-select query
`label_values(k3dm_bug_info{repo="$repo"}, release_order)` with a saved `current` of `$__all`.

## Constraint

Grafana cannot set a variable's default from a query result; `current` in the JSON is static. A
hard-coded release would go stale every release.

## Proposed approach (to confirm in the spec)

- Source: `k3dm_bug_current_release_info{repo,release}`, already published for k3d-manager
  (`bin/k3dm-vectordb-metrics`), never for lib-foundation.
- Make the current release the **first** option and save a `current` that matches no option, so
  Grafana falls back to the first option on load. Keep **All** selectable.
- lib-foundation, or k3d-manager with no `current_release_info`: fall back to All, not an empty
  dashboard.
- Alternative if the fallback proves unreliable in our Grafana version: a dashboard link /
  Hermes link that passes `var-release=<current>` in the URL, keeping All as the JSON default.

## Proof

Open the dashboard with no URL parameters while on `k3d-manager-v1.43.4`: Release shows v1.43.4;
switching Repo to lib-foundation shows All with data. A BATS test asserts the variable wiring with
`jq`, not whole lines.
