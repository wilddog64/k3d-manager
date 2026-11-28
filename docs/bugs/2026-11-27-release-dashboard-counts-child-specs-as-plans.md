# Bug: release tracking dashboard counts child specs as plans and shows no plan dependencies

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** pre-existing (child-spec header conventions drifted from what the parser reads)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** not run (`make find-similar-docs` vector store unavailable: k3d cluster context absent); exact-slug glob found none
**Filed:** 2026-11-27, Claude, from operator question ("why release tracking dashboard look to have more than 5 plans?")
**Operator scope decision:** 2026-11-27 — "plan-level dependencies on the dashboard" (include part 3 below)

## Evidence

- `bin/k3dm-vectordb-metrics:383-386` treats a spec as a child only on `**Release:** vX.Y.Z plan N part` or
  `**Parent plan:**`. v1.46.0 children use other forms, so each is counted as a plan:
  - `**Parent:**` — `cloud-approval-a/b/b1/c/d/e` (6)
  - `**Parents:**` — `model-experiment` (1)
  - Status "SPEC — child of …" with no header — `p2a`–`p2e` (5), `p3a`–`p3d` (4), `tailscale-break-glass-p7a/p7b` (2)
- 18 child specs appear as plans on top of the 5 umbrella plans.
- `**Depends on:**` exists on `p2b`, `p2c`, `p2d`, `p2e`, `p3d`, `travel-bundle-ipad-ssh` but is never read;
  `blocked_by` is published only per release (`k3dm_release_milestone_info`), not per plan. The `cloud-approval-*`,
  `p3a`–`p3c`, `p7a`/`p7b` children record order only in the parent's prose.

## Fix outline (for the spec)

1. Child detection accepts `**Parent plan:**`, `**Parent:**`, `**Parents:**` and a Status containing "child of";
   children roll up under their parent (part count and landed count) instead of counting as plans.
2. One canonical header for new child specs (`**Parent plan:**`); a spec check refuses other spellings
   (contract: writers = specs, reader = `bin/k3dm-vectordb-metrics`).
3. Plan-level dependencies: parse `**Depends on:**` into a per-plan metric (plan → depends-on plan, satisfied or
   not), and show "waiting on <plan>" on the release tracking dashboard.

Tests: fixtures for each header form (red on current code for the three unrecognized forms), a dependency fixture
with one satisfied and one unsatisfied edge, and a positive control that a top-level plan is still counted.
