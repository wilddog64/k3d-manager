# Bug: Bug Tracking's Current release row ignores Manual mode

**Status:** OPEN
**Priority:** P3
**Severity:** low — four tiles show the current release while the rest of the dashboard shows the picked one; the numbers are right for what they measure, only the scope is unexpected
**Release:** v1.43.8 (bug; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.8`
**Filed:** 2026-10-25, by Claude, from the operator's Bug Tracking screenshot 346 (Manual, `v1.43.4`)
**Approval:** operator 2026-10-25, "go for that small P3". Not critical (one dashboard ConfigMap); this deliberately reverses v1.43.7's choice to keep the row on the current release
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (row 92 "Current release", panels 1–4), `scripts/tests/plugins/grafana_dashboard_bugs.bats`, `docs/guides/grafana-dashboards.md`, CHANGELOG
**Related:** `docs/plans/v1.43.7-bug-dashboard-auto-release-selection.md` (added `release_mode`; its live note recorded "Current release row stays v1.43.7" under Manual as intended)

## Problem

With **Release mode = Manual** and `v1.43.4` picked, Release plans showed v1.43.4's plans
(5 / 3 implemented-unverified / 2 live-verified), but the **Current release** row still read
`v1.43.8` with 0 filed, 0 open and 0 fixed. The operator reads the whole page as being about the
picked release, so the row looks wrong.

Panels 1–4 filter on `k3dm_bug_current_release_info` only. Every other release-filtered panel
(9–13, 16, 17, 23, 24 and Plans in release) already switches on `vector($release_mode)`.
The test at `grafana_dashboard_bugs.bats` (`for panel_id in (2,3,4,5,6,7,8,14,15)`) pins panels
2–4 as mode-independent.

## Fix

1. Panels 2 (Bugs filed), 3 (Bugs open), 4 (Bugs fixed): use the same two-arm form as panels
   9–13: the Auto arm keeps `and on(release,repo) k3dm_bug_current_release_info{repo="$repo"}`
   gated by `and on() (vector($release_mode) == 1)`; the Manual arm uses
   `release=~"$release"` gated by `and on() (vector($release_mode) == 0)`. Keep `or vector(0)`
   so an empty selection shows 0, not No data. Bugs filed currently has no `or vector(0)`; add it.
2. Panel 1 (Release): Auto shows the current release name as today. Manual shows the picked
   release name(s), taken from series that carry the `release` label for this repo and match
   `release=~"$release"` (both bug and plan inventories, so a release with plans but no bug docs
   still shows). Multiple picks show one value per release. `All` must not list every release:
   show the text `All` (or an equivalent fixed label) instead.
3. Rename the row from `Current release` to `Release`, and update panel 1's description to say it
   follows Release mode.
4. Panels 5 (Open, scheduled later) and 6 (Open, untriaged) are repository-wide today and stay
   unchanged in both modes. Their descriptions must say so.
5. Update the mode test: move 2, 3, 4 out of the "no `$release_mode`" list into the mode-aware
   checks. This is the one intended assertion change.
6. `docs/guides/grafana-dashboards.md`: the Auto/Manual paragraph names the Release row as
   following the mode, and names panels 5 and 6 as repository-wide.

## Acceptance

```yaml
must:
  - id: M1
    text: In Manual mode with one release picked, Bugs filed, Bugs open and Bugs fixed show that release's values; in Auto they show the current release's values, unchanged from today.
  - id: M2
    text: The Release tile shows the current release name in Auto and the picked release name in Manual, including a picked release that has plans but no bug docs; Manual with All shows a fixed All label, not a list of every release.
  - id: M3
    text: The row is titled Release, and the guide and panel descriptions state which tiles follow Release mode and which are repository-wide.
must_not:
  - id: N1
    text: Auto mode output for panels 1-4 must not change, and the Auto arm must not contain a hard-coded release version.
  - id: N2
    text: Open, scheduled later and Open, untriaged must not change their queries.
  - id: N3
    text: Manual mode with an empty or non-matching selection must not show No data on Bugs filed, Bugs open or Bugs fixed (0 instead).
  - id: N4
    text: Switching modes must not change the repo or Verified fixes filters, and no other panel's query changes.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3, N4]
    text: grafana_dashboard_bugs.bats evaluates panels 1-4 with $release_mode expanded to 1 and 0 against fixture series (current v1.43.8 with no bug docs; v1.43.4 with bugs and plans; v1.43.5 with plans only), and shows the new mode tests red on the pre-fix dashboard.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: Operator screenshot of Bug Tracking in Manual with v1.43.4 shows Release v1.43.4 and v1.43.4's filed/open/fixed counts; back in Auto it shows v1.43.8 and 0/0/0. Claude reads it.
interface:
  - the k3dm-bugs.json ConfigMap in scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (panel ids 1-6, variables release_mode and release)
  - series k3dm_bug_current_release_info, k3dm_bug_release_docs, k3dm_bug_status_docs, k3dm_bug_fixed_in_release_docs, k3dm_plan_release_docs
  - bats scripts/tests/plugins/grafana_dashboard_bugs.bats
```

## Definition of Done

- [ ] Fix items 1–6 on `k3d-manager-v1.43.8`.
- [ ] New mode tests red against the pre-fix dashboard (temp copy), green after.
- [ ] `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` and every other suite that reads `grafana-dashboard-bugs.yaml` green.
- [ ] Guide and CHANGELOG updated.
- [ ] E2 read by Claude from an operator screenshot.

## What NOT to Do

- Do not change panels 5 or 6, the Bugs table, Release plans or Release forecast.
- Do not hard-code a release version anywhere in an Auto arm.
- Do not create a PR, commit to `main`, or skip pre-commit hooks.
