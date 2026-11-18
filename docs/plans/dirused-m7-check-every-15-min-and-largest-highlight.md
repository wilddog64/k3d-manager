# dirused M7: update lookup every 15 minutes and always on `/help`; highlight the largest files in HTML

**Filed:** 2026-11-18
**Status:** LIVE-VERIFIED (E2 highlight part: operator screenshot 2026-11-18 on v0.0.17: 116.7 GB row red with full bar, 9.8 GB and 7.2 GB amber, dates on one line). Merged PR wilddog64/dirused#30 (19e66d0), v0.0.17. Notice part of E2 waits for v0.0.18.
**Repo / branch:** wilddog64/dirused / `m7-check-highlight` (from main 8ccf307)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (lookup timing and HTML styling only; scan results, exit codes and text/JSON/CSV output unchanged)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

1. Operator, 2026-11-18: updated 0.0.15 → 0.0.16 with `/update` and "didn't see the notice". The lookup is throttled to once
   per 24 h (`src/Dirused.Common/Update/UpdateCheck.cs:19`), and the last lookup ran before v0.0.16 was published, so the
   cached `Latest` was still 0.0.15.
2. Operator, 2026-11-18, looking at the M5 HTML report (a 116.7 GB log at the top of the ffm01 D$ list): "can we highlight
   largest files?" Today every row in the `Largest candidate files` table looks the same
   (`src/Dirused.Common/Renderers/HtmlRenderer.cs`, the `largestGroups` block), and the Modified date wraps onto two lines.

## Operator decision (2026-11-18)

- Lookup: "how about every 15 mins and whenever /help".
- Highlight: "Color by size + bar": rows of 10 GB or more use the critical color, rows of 1 GB or more the warning color; each
  row gets a size bar scaled to the largest file in its group; the Modified column does not wrap.

## Change

- **`UpdateCheck.cs`:** replace `TimeSpan.FromHours(24)` at `:19` with a 15-minute window (`TimeSpan.FromMinutes(15)`, one
  `internal static readonly TimeSpan LookupInterval`). Add `CheckAsync(bool force = false)`: when `force` is true, skip the
  throttle test and always look up (still writes `AttemptedUtc`; opt-outs at `:16` still return first). Everything else in
  `CheckAsync`, `WaitAfterReport` and `PrintNotice` is unchanged.
- **`src/Dirused.Cli/Program.cs`:** `StartUpdateCheck` gains a `bool force` parameter passed to `CheckAsync(force)`. The
  `parsed.Usage` path (`/help`, `-h`, `/?`, `:45`) passes `true`; the bare-run path (`:37`) and the scan path (`:75`) pass
  `false`. `/noupdatecheck` and `DIRUSED_NO_UPDATE_CHECK=1` still suppress everything.
- **`HtmlRenderer.cs`, `largestGroups` block only:**
  - Each file row gets `class="crit"` when `LogicalBytes >= 10L * 1024 * 1024 * 1024`, `class="warn"` when
    `>= 1L * 1024 * 1024 * 1024`, no class otherwise (1024 base, the same as `Format.Size`, so the row reading "10.0 GB" is
    the first critical one). These are the existing `.crit` / `.warn` row colors (light and dark CSS already defined).
  - The Size cell becomes `{size}<span class="bar"><span style="width:{pct}%"></span></span>` with
    `pct = LogicalBytes * 100.0 / max(LogicalBytes in that group)`, formatted `0.##` with InvariantCulture, the same markup
    as the volume table bar (`:47-48`). When the group maximum is 0 or the row is 0 bytes, `pct = 0` and the inner `<span>`
    is omitted (as `:48` does), so `NaN` never appears. The existing `.crit .bar>span` / `.warn .bar>span` colors apply; a plain row uses the
    default blue.
  - The Modified cell gets `class="date"`; add `td.date{white-space:nowrap}` to the stylesheet at `:16`.
  - Group header rows, the table header and every other table are unchanged.
- **`README.md`:** line 137 (match the text, verified on 8ccf307) "at most once a day" becomes "at most every 15 minutes (always on `/help`)". In the `/largest`
  section add one sentence: "In the HTML report, files of 10 GB or more are red, 1 GB or more amber, and each row has a bar
  scaled to the largest file in its group."
- **`CHANGELOG.md` `[Unreleased]`:** "Update lookup every 15 minutes (was daily) and always on `/help`. HTML largest-files
  rows are colored by size and show a size bar."

## Tests

Portable:
- **U2 (`UpdateTests.cs:23`):** the "1 h later, FindCalls unchanged, notice from cache" step becomes 10 minutes later
  (`now.AddMinutes(10)`); adjust only the `FindCalls` counts that change because of the new window, and say which in the report.
- U22 and U23 save `DIRUSED_NO_UPDATE_CHECK`, clear it at the start, and restore the saved value in `finally` (as W1 does,
  `UpdateWiringTests.cs:17,23`).
- **U22 `LookupWindowIs15Minutes`:** after a lookup, a check 14 min 59 s later makes no lookup (`FindCalls` unchanged) and a
  check 15 min 1 s after the first makes one (`FindCalls + 1`).
- **U23 `ForceLooksUpInsideTheWindow`:** right after a lookup, `CheckAsync(force: true)` makes another lookup and, when the
  fake now returns 0.0.12, `WaitAfterReport` prints `dirused 0.0.12 is available`. Positive control: `CheckAsync()` at the
  same instant makes no lookup. With `DIRUSED_NO_UPDATE_CHECK=1` (saved and restored), `force: true` makes no lookup.
- **L8 (`LargestTests.cs`) `HtmlLargestRowsColoredAndBarred`:** one group with files of `10L<<30`, `(10L<<30) - 1`, `1L<<30`,
  `(1L<<30) - 1` bytes renders, in order, rows with `class="crit"`, `class="warn"`, `class="warn"`, and no class; the first row's
  bar is `width:100%`, the `1L<<30` row's bar is `width:10%`; every file row's Modified cell has `class="date"`; the
  stylesheet contains `td.date{white-space:nowrap}`. A second group's bar is scaled to its own maximum (its largest row is
  `width:100%`). A group whose files are all 0 bytes renders no `NaN` and no `style="width:` inside its rows.

Windows (`tests/Dirused.Tests/UpdateWiringTests.cs`, scratch state, env saved/restored as W1):
- **W7_HelpAlwaysLooksUpBareRunHonoursWindow:** a bare run (lookup 1), then a bare run at once (no new lookup, `FindCalls == 1`),
  then `["/help"]` at once (`FindCalls == 2`).

Red on main 8ccf307: U22, U23, L8 and W7 fail there (U23 does not compile: paste the build error); paste the failing lines
(W7 from Windows CI on the PR if it cannot run locally).

## Files

- `src/Dirused.Common/Update/UpdateCheck.cs`
- `src/Dirused.Cli/Program.cs`
- `src/Dirused.Common/Renderers/HtmlRenderer.cs`
- `tests/Dirused.Tests.Portable/UpdateTests.cs`
- `tests/Dirused.Tests.Portable/LargestTests.cs`
- `tests/Dirused.Tests/UpdateWiringTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `CheckAsync()`: callers `Program.cs:125` (via `StartUpdateCheck`, called at `:37`, `:45`, `:75`) and tests (grep
  `CheckAsync(` in `tests/`). The new parameter is optional, so existing calls compile unchanged.
- Throttle window: read by `UpdateTests.cs` time steps (`:23-25`, `:67`) and README.md:137. Only U2's 1 h step needs a change.
- HTML largest table: read by people and `LargestTests.cs` (`<h2>Largest candidate files</h2>`, `<tr class="group">` count,
  `a&amp;b.log`). The `<tr class="group">` count must stay one per group: file rows use `class="crit"`/`"warn"`, never `group`.

## What NOT to Do

- Do not change the notice text, the 1 s grace, `/update`, `/version`, exit codes, or the text/JSON/CSV/summary renderers.
- Do not restyle the volume table or the group header rows.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: a newer release is looked up at most 15 minutes after the previous lookup, on any scan or bare run
  - id: M2
    text: "`/help` always looks up (unless opted out) and shows the notice when a newer release exists"
  - id: M3
    text: in the HTML largest-files table, rows >= 10 GB are critical-colored, >= 1 GB warning-colored, each row has a bar scaled to its group's largest file, and the Modified date does not wrap
must_not:
  - id: N1
    text: "a check 15 min 1 s after a lookup makes no new lookup — red today (U22)"
  - id: N2
    text: "/help inside the window makes no lookup — red today (U23, W7)"
  - id: N3
    text: "largest-file rows all look the same, with no size class or bar — red today (L8)"
  - id: N4
    text: "an opted-out run (DIRUSED_NO_UPDATE_CHECK=1) looks up because of force (U23)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3, N4]
    kind: offline
    command: portable suite (U2, U22, U23, L8) locally and on PR CI; Windows CI for W7; U22, U23, L8, W7 red on 8ccf307
    intent: dirused notices a new version within 15 minutes, or right away on /help, and the HTML report makes the huge files stand out.
  - id: E2
    kind: live
    proves: [M2, M3]
    command: "operator, work laptop, on the release with this change: `dirused /file server-list.txt /summary /warn 30 /largest /html` shows the 116.7 GB log row red with a full bar; after Claude publishes the next release, `dirused /help` shows the three-line notice straight away"
    intent: On your laptop, the big log stands out in red, and /help tells you about a new version at once.
interface:
  - "HTML largest row: <tr class=\"crit|warn\">...<td class=\"num\">SIZE<span class=\"bar\"><span style=\"width:P%\"></span></span></td><td class=\"date\">yyyy-MM-dd</td>..."
```

## Amendment 1 (Claude, 2026-11-18, blind Argon review)

1. Zero-byte rows and groups: `pct = 0` with no inner bar span, never `NaN`; L8 asserts it.
2. U22/U23 save, clear and restore `DIRUSED_NO_UPDATE_CHECK`.
3. README edit matched by text (line 137 verified on 8ccf307).

**Intent approved:** operator, 2026-11-18
**Intent approval note:** answers to Claude's questions: "how about every 15 mins and whenever /help" and "Color by size + bar (Recommended)"
