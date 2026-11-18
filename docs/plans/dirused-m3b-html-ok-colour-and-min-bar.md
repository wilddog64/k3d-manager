# dirused M3b — `/html` report: green OK level and a visible bar for small usage

**Filed:** 2026-11-18
**Status:** ready for dispatch (after intent approval)
**Repo / branch:** wilddog64/dirused / `m3b-html-ok-colour` (from main cbf37ac)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (HTML report styling only; console, JSON and CSV output unchanged)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live look by the operator at the office.

## Problem

Operator, 2026-11-18, v0.0.10 report of `\\us03l12agt01\d$` at 1.0% used with `/warn 3 /crit 5`: "I still don't see
color". By design only WARN and CRIT rows are styled (`HtmlRenderer.cs:42-44`), so a healthy volume shows no level and
its blue bar fill is 1% of 90px, under one pixel, so the bar reads as empty grey.

## Operator decisions (2026-11-18)

"go for these two":
1. **Green OK:** a volume whose level is OK gets a green bar fill and a green `OK` label in the Level column.
2. **Visible small fill:** the bar fill has a minimum visible width of about 3px, so 1% does not look empty.

## Change (`src/Dirused.Common/Renderers/HtmlRenderer.cs` only)

- Volumes table: map `FullnessLevel.Ok` to level text `OK` and row class `ok`, alongside the existing `CRIT`/`WARN`.
  A row whose `Fullness.For` is `null` (incomplete scan, zero total) keeps no class and an empty Level cell.
- CSS: `.ok .bar>span` green fill (light `#1e8e3e`, dark `#81c995`); `.ok .lvl` green label (light: white on `#1e8e3e`;
  dark: `#202124` on `#81c995`). **No row background for `ok`** (only crit and warn rows are tinted, so problems still
  stand out). Add the matching rules inside the existing `@media(prefers-color-scheme:dark)` block.
- CSS: `.bar>span{min-width:3px}` so any rendered fill is at least 3px wide. The inline `width:N%` stays as today.
- Nodes table unchanged (no `ok` class on node rows).

## Tests (portable, `tests/Dirused.Tests.Portable/HtmlRendererTests.cs`)

- **H17_OkVolumesAreGreen:** warn 85 / crit 90 with volumes at 95, 87, 10 → the 10% row starts `<tr class="ok">` and
  contains `<span class="lvl">OK</span>`; the CSS contains `.ok .bar>span{background:` and `.ok .lvl{`; the 95% row
  is still `crit` and 87% still `warn` (positive control); the nodes table contains `<tr><td>srv3</td>` (unchanged);
  no CSS rule sets a `background` on `.ok` alone (assert `.ok{` absent).
- **H18_IncompleteVolumeHasNoLevel:** an incomplete result (or zero total) renders no `class="ok"` and an empty Level
  cell for that row.
- **H19_SmallFillHasMinimumWidth:** the CSS contains `.bar>span{` with `min-width:3px`.
- Update H16 only if needed for the new `ok` class on the 10% volume row (its node-row assertion is unchanged).
- Red on main cbf37ac: H17 and H19 fail there; paste the failing lines.

## Files

- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `tests/Dirused.Tests.Portable/HtmlRendererTests.cs`
- `CHANGELOG.md` (`[Unreleased]`: "`/html` report: OK volumes show a green bar and OK label; small usage stays visible")

## Contract readers

- HTML report markup is read only by people and by `HtmlRendererTests.cs` (H6-H16). `tools/live-check.ps1`: grep for
  `class=\"` / `lvl` before editing; if it asserts on report markup, list it here and keep it passing.
- Console text, `/json` (`FullnessLevelJsonConverter`) and `/csv`: not touched.

## What NOT to Do

- Do not change console colours, JSON or CSV output, thresholds, or exit codes.
- Do not tint OK row backgrounds.
- Do not touch the nodes table.

## Acceptance

```yaml
must:
  - id: M1
    text: in the /html report a complete volume below /warn has a green bar fill and an OK label in the Level column
  - id: M2
    text: every bar fill renders at least 3px wide (CSS min-width:3px on .bar>span)
  - id: M3
    text: CRIT and WARN rows, the nodes table, and console/JSON/CSV output are unchanged
must_not:
  - id: N1
    text: "a 10% volume at warn 85 renders with no level and no row class — red today (H17)"
  - id: N2
    text: "the bar fill has no minimum width, so 1% renders under one pixel — red today (H19)"
  - id: N3
    text: "an incomplete or zero-size volume is labelled OK (H18)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: portable tests H16-H19 (H17, H19 red on main cbf37ac) plus the full portable suite; Windows CI on the PR
    intent: A healthy disk now shows a green bar and an OK label, a nearly empty disk still shows a sliver of bar, and warning and critical disks look exactly as before.
  - id: E2
    proves: [M1, M2]
    kind: live
    command: "operator, office: run the next release on \\\\us03l12agt01\\d$ with /html; the row shows a green bar sliver and a green OK label"
    intent: The report you looked at today shows colour on a healthy disk.
interface:
  - "/html report Level column: OK (green), WARN (yellow), CRIT (red)"
```

**Intent approved:** pending (operator)
