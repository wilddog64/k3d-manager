# Bug: Agent Activity "All Codex activity" panels float up, so API prices sits under Untracked by repo instead of beside Unpriced

**Status:** LIVE-VERIFIED — E2 PASS 2026-11-21 on deploy/hub 4217648 (ArgoCD sync 18:34:51Z; live ConfigMap equals 42176488, compaction simulation no moves; operator screenshot): [`docs/captures/2026-11-21-codex-row-float-up-e2/`](../captures/2026-11-21-codex-row-float-up-e2/README.md). Previously VERIFIED — landed 83344176; E1 offline PASS, independent Sonnet verifier PASS
**Fix commit:** 83344176
**Live evidence:** 2026-11-21 · run grafana-screenshot-1834Z · env hub-grafana · scenario agent-activity-codex-row-no-float-up · commit 83344176 · proves E2
**Priority:** P3 (cosmetic: every panel shows its data; the layout differs from the stored and tested one)
**Introduced by:** bd5e4828 (plan-quotas-beside-fable rev 1 removed panels 50–52 and 113–115 from the Codex row's top band)
**Should have been caught by:** offline test
**Introducing change reviewed:** no (independent Sonnet verifier from Acceptance only; no Argon or Fable review recorded in the spec)
**Prior art:** exact-slug glob none; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing on the M4, 2026-11-21); `ls docs/bugs | grep -iE 'float|codex-row|activity.*layout|gridpos|compact'` found only kine-compaction and image-tag docs — read titles, different root cause
**Approval:** operator, 2026-11-21: "go with you suggestion" — file as a P3 bug and fix inside v1.45.0 (it corrects a layout this release broke), no triage wait; dispatch to Codex. The daily-bar feature asked at the same time went to `docs/ideas.md`.
**Intent approved:** operator, 2026-11-21
**Intent note:** "Approved, dispatch" (E1-E3 as listed)
**Branch:** `k3d-manager-v1.45.0`

## Symptom

On 2026-11-21 at about 15:25Z the operator's screenshot of Grafana `/d/k3dm-agent-activity`, row "All Codex activity"
(`docs/captures/2026-11-21-plan-quotas-e2/agent-activity-codex-row.png`), showed Sessions by mode, Tokens by repo and
Codex active hours level with Untracked Codex sessions, Unpriced Codex sessions under Sessions by mode, and "Codex at API
prices, all sessions" alone at the bottom left under Untracked by repo. The operator asked for API prices "in the same row
as Unpriced Codex sessions but in front of it".

## Cause

The stored layout (deploy/hub 74ff9a6f, live ConfigMap identical) is:

| id | title | x | y | w | h |
|---|---|---|---|---|---|
| 53 | Untracked Codex sessions | 0 | 20 | 6 | 6 |
| 54 | Untracked by repo | 0 | 26 | 6 | 12 |
| 55 | Sessions by mode | 6 | 26 | 6 | 12 |
| 56 | Tokens by repo | 12 | 26 | 6 | 12 |
| 57 | Codex active hours | 18 | 26 | 6 | 12 |
| 58 | Codex at API prices, all sessions | 0 | 38 | 6 | 6 |
| 83 | Unpriced Codex sessions | 6 | 38 | 6 | 6 |

So 58 is already directly left of 83, and `scripts/tests/plugins/agent_dispatch_dashboard.bats:249` asserts it. Grafana
compacts panels vertically: a panel moves up while the space above it is empty. bd5e4828 removed the quota stats that
filled x6–24, y20–26, and left that band empty. 55, 56 and 57 rise to y20, and 83 rises to y32 under 55, while 58 stays
at y38 under 54. A compaction simulation of the live ConfigMap (Claude, 2026-11-21) reproduces the screenshot exactly:
55, 56, 57 26→20 and 83 38→32. Agent Cost has no moves.

The tests check stored `gridPos` only (overlaps, adjacency, "no empty band" in rev 1's M3 read from stored values), never
the layout Grafana renders, so the gap passed offline and was seen only live.

## Workaround

None needed for the data; the panels are all there, in a different place.

## Fix

1. `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`, row 49:
   - y=20, h=6, w=8: 53 x0, 58 x8, 83 x16.
   - y=26, h=12, w=6: 54 x0, 55 x6, 56 x12, 57 x18 (unchanged).
   - Panels below row 49's band shift up by the freed height (6) so no row gains a gap; no other field changes.
2. `scripts/tests/plugins/agent_dispatch_dashboard.bats`: a new test with a vertical-compaction simulation (sort panels by
   y then x; move each up while no already-placed panel overlaps its x range at y-1; rows are panels too) asserts that no
   panel on Agent Cost or Agent Activity moves. Agent dispatch is out of scope (it has 16 one- or two-unit moves today).
3. `docs/guides/grafana-dashboards/k3dm-agent-activity.md`: the Codex row's top band reads sessions, API prices, unpriced.
4. `CHANGELOG.md`, open v1.45.0 Fixed section: one line.

## Contract readers

Panel ids and titles are unchanged; only gridPos moves. Found by grep 2026-11-21:

- `agent_dispatch_dashboard.bats:219` and `:447` overlap and unique-id tests: unedited, must pass.
- `:238-252` Codex API cost (58 left-adjacent to 83, same y): unedited, must pass.
- `:359-378` id sets and count 117: unedited (no id added or removed).
- `:415-446` Activity 54–57 one y, h=12, protected exprs: unedited, must pass.
- `:503` Claude row on Activity fills the width: unedited, must pass after the shift.
- No `viewPanel=` link to 53–58 or 83 in `scripts/`, `bin/` or `docs/` (re-grep before dispatch).

## What NOT to Do

- No change to Agent Cost, Agent dispatch, the exporter, metrics or alerts.
- Do not change any panel field except gridPos; do not renumber panels; do not edit the pre-split fixture.

## Acceptance

```yaml
interface:
  - "Agent Activity row 'All Codex activity': y20 53|58|83 (w8, h6); y26 54|55|56|57 (w6, h12)"
must:
  - id: M1
    text: "Agent Activity panels 53, 58, 83 sit at y=20, h=6, w=8, x=0/8/16, and 54-57 keep x=0/6/12/18, y=26, h=12; no overlap"
  - id: M2
    text: "on Agent Cost and Agent Activity every panel's stored y equals its y after vertical compaction"
  - id: M3
    text: "the Agent Activity guide and CHANGELOG describe the Codex row's top band"
must_not:
  - id: N1
    text: "a panel on Agent Activity floats up under compaction (paired: the compaction helper reports 55, 56, 57 and 83 moving on the base commit)"
  - id: N2
    text: "any panel field other than gridPos changes on Agent Activity (paired: targets, fieldConfig and options of 53-58 and 83 compare equal to the base commit)"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    command: "bats scripts/tests/plugins/agent_dispatch_dashboard.bats; Claude also runs make test outside the sandbox. The new compaction test is red on the base commit listing 55, 56, 57, 83. Mutants, each red: put 58 back at x0 y38 (M1/N1); move 54-57 to y=27, leaving a one-unit gap under the top band (M2); change 58's unit (N2)."
    intent: "You will see tests proving Grafana keeps the Codex row exactly as stored, with API prices directly in front of Unpriced Codex sessions."
  - id: E2
    proves: [M1, M2]
    kind: live
    command: "after make hub-deploy, the operator screenshots /d/k3dm-agent-activity row 'All Codex activity'"
    intent: "You will see Untracked sessions, API prices and Unpriced side by side on top, and the four bar panels beneath, with nothing out of place."
  - id: E3
    proves: [M3]
    kind: offline
    command: "reviewer reads the guide paragraph and the CHANGELOG line"
    intent: "You will see the guide describe the new Codex row."
```

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md`
- `CHANGELOG.md`

## Worker definition of done

- `bats scripts/tests/plugins/agent_dispatch_dashboard.bats` green; `git diff --check` clean.
- Commit on the task branch, push, report the SHA.

## Verification (Claude, 2026-11-21)

- Worker (Codex) could not commit from its sandbox; Claude committed da1f2922 on the task branch, landed as 83344176 (land test: dashboard suite + affected gates PASS).
- Pre-fix: the new compaction test is red on the base Activity file with moves (55,26,20), (56,26,20), (57,26,20), (83,38,32); tests 43, 48, 54 also red.
- Mutants, each red: 58 back to x0 y38 (overlap and Codex API cost tests, 54); 54-57 at y27 (53, 54, overlap); 58 unit changed (17, 54). Round-trip control green.
- Independent Sonnet verifier from Acceptance only: M1, M2, M3, N1 (positive control reproduced), N2 PASS; Agent Cost unchanged; rows below shifted by exactly 6.
- Nit (not blocking): test 54 pins a SHA-256 of all Activity panel content, so any future legitimate Activity edit must update that hash.
- E2 PASS 2026-11-21: `make hub-deploy REF=42176488` (f06bddd3's CI had one test job cancelled by a later push); live ConfigMap equals the repo, no compaction moves, operator screenshot matches. A pre-existing "Value" bar in Sessions by mode was filed separately (`docs/bugs/2026-11-21-sessions-by-mode-value-bar-from-category-series.md`).
