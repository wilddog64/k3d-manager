# Dispatch `--parent` limit is shorter than the slugs it must name

**Status:** LANDED — fixed on `k3d-manager-v1.43.15`, 2026-11-08
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** offline test
**Severity:** low — a review child could not be linked to a long-named task; no data affected
**Approval:** operator, 2026-11-08 ("go ahead for A": Claude patches directly, not dispatched)
**Prior art:** none found by grep for the error text or the limit. `find-similar-docs` not run: the store is reached
through kube context `k3d-k3d-cluster`, which m4-air does not have.
**Filed:** 2026-11-08
**Detected by:** Claude, starting the Hermes P2 review child, 2026-11-08
**Affected:** `bin/k3dm-codex-dispatch`, `bin/k3dm-dispatch-metrics`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

`start --parent <slug> --role review` failed with `--parent and --role must be valid and used together` for
`2026-11-08-hermes-values-branch-flags-deploy-hub-and-r9-retargets-release-branch` (80 characters), a slug `start` had
accepted when it created that task.

## Root cause

A parent is limited to 64 characters. Slugs are not held to that limit: `start` has no length bound and `verify` allows
120.

## Fix

Raise the parent limit to 120, matching `verify`, in all three copies of the pattern.

## Contract readers

| Reader | Changes? |
|---|---|
| `bin/k3dm-codex-dispatch:326` `PARENT` (`link`, `combine`) | yes |
| `bin/k3dm-codex-dispatch:857` `start` | yes |
| `bin/k3dm-dispatch-metrics:49` `PARENT_RE` | yes: otherwise a long parent counts as invalid |
| `scripts/tests/bin/test_dispatch_metrics.py:2936` | no: reads `PARENT_RE` |

## Evidence (m4-air, 2026-11-08)

- New tests red against the 64 limit: the bats case failed with the error above, and
  `test_parent_limit_matches_dispatcher_slug_limit` failed.
- After the fix: `scripts/tests/bin/codex_dispatch.bats` 114 ok, rc 0; `scripts/tests/bin/test_dispatch_metrics.py` 199 passed.
- The bats case also shows a 121-character parent is still refused and writes no `start` event.

## Notes

- The metrics exporter deployed on the hub keeps the old limit until the next `make hub-promote`.
