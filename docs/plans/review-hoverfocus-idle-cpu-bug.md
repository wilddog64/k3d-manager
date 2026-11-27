# Review: HoverFocus idle CPU bug (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `wilddog64/hoverfocus` / `v0.0.3` (head `a4244b6`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.

## Task

Review the bug report below against the code in this repository. You get the report and the repository, nothing else.
Do not edit any file; write your review as your final answer. No network calls.

Answer:

- **Cause:** trace `Controller.swift` `onTick` and every call it makes per tick, and `FocusIndicatorPanel.swift` `show`.
  Which work is done every 50 ms when the pointer has not moved? Rank by likely cost (WindowServer re-order/redraw,
  `CGWindowListCopyWindowInfo`, AX IPC). Is anything else waking the process (event tap, other timers, observers)?
- **Fix:** what is the smallest change that brings idle cost near zero without breaking hover focus, the border
  following a moved/resized window, Mission Control/menu detection, pause, or the tap re-enable path? Is "tick only
  after pointer events" safe, given the border must also follow a window that moves while the pointer is still?
- **Acceptance:** how should an offline test prove "no redundant show/setFrame/order when nothing changed" (the core is
  pure Swift in `HoverFocusCore`; the selftest is `swift run hoverfocus-selftest`)? What live budget (CPU %, idle
  wakeups via `top -stats cpu,idlew`) is realistic, with `focusIndicator` off as the control?
- **Priority:** is P2 right? v0.0.3 is unreleased.

## Bug report under review

# Bug: HoverFocus uses ~57% CPU while idle — the focus border re-frames and re-orders four panels every 50 ms

**Status:** OPEN — captured, not triaged
**Priority:** P2 (proposed: degraded battery/heat; workaround: `focusIndicator` off or pause)
**Introduced by:** hoverfocus `4a3940f` (v0.0.3 U2 focus border), on top of the 50 ms tick from `4cbd377` (M1a)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report (macOS battery menu lists HoverFocus under "Using Significant Energy")
**Component:** `hoverfocus` `Sources/HoverFocusPlatform/Controller.swift` `onTick` (:100), `FocusIndicatorPanel.swift`
`show` (:59 `setFrame(..., display: true)`, :65 `order(.above, relativeTo:)`)

## Evidence (m4, 2026-11-27 ~19:00, v0.0.3 branch `a4244b6`, pid 2455, operator idle)

`ps`: 53.7% CPU, 3:27 CPU time; `top -stats pid,cpu,idlew,power`: 57.4% CPU, 4887 idle wakeups per sample, power 57.9.

## Cause (from code; not yet profiled)

A repeating 50 ms timer (`Controller.swift:85`) runs `onTick` whether or not the pointer moved. Each tick:

1. `systemState()` — an AX IPC call into the frontmost app (`frontmostWindowID`, :252) and `CGWindowListCopyWindowInfo`
   for the menu / Mission Control checks (:302).
2. `indicator.frame` → `windowBounds` — another `CGWindowListCopyWindowInfo` (:126).
3. While a window is tracked, `indicatorPanel.show` — `setFrame(display: true)` and `order(.above, relativeTo:)` on four
   edge panels: about 80 WindowServer re-frame/re-order/redraw operations per second even when nothing changed.

Because the border stays up for as long as the focused window is tracked
([stale-border bug](../bugs/2026-11-27-hoverfocus-universal-control-border-without-keyboard-and-stale-border.md)), step 3 runs
continuously.

## Directions (for triage)

- Only call `show` when the frame or the window above changed; skip `display: true` when only ordering.
- Run the tick only after pointer events (or slow it to ~4 Hz when the pointer has not moved).
- Acceptance should include an idle CPU/wakeup budget measured with `top -stats cpu,idlew` (before/after), with
  `focusIndicator` on and off as the control.

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusPlatform/Controller.swift` | read only (start here) |
| `Sources/HoverFocusPlatform/FocusIndicatorPanel.swift` | read only |
| `Sources/HoverFocusCore/FocusIndicator.swift` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not run the app or install anything.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix, then a
verdict: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the review ends with a verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and a verdict
    intent: A second model checks the HoverFocus battery-drain diagnosis against the code before Luna fixes it, so the fix targets the real cost.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "can you have fable, neon review P2 bug then dispatch to Luna"
