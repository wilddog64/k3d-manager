# Bug: HoverFocus uses ~57% CPU while idle — the focus border re-frames and re-orders four panels every 50 ms

**Status:** OPEN — captured, not triaged
**Priority:** P2 (proposed: degraded battery/heat; workaround: `focusIndicator` off or pause)
**Introduced by:** hoverfocus `4cbd377` (M1a 50 ms tick, per profile); `4a3940f` (U2 border) contribution unconfirmed
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report (macOS battery menu lists HoverFocus under "Using Significant Energy")
**Component:** `hoverfocus` `Sources/HoverFocusPlatform/Controller.swift` `onTick` (:100), `FocusIndicatorPanel.swift`
`show` (:59 `setFrame(..., display: true)`, :65 `order(.above, relativeTo:)`)

## Evidence (m4, 2026-11-27 ~19:00, v0.0.3 branch `a4244b6`, pid 2455, operator idle)

`ps`: 53.7% CPU, 3:27 CPU time; `top -stats pid,cpu,idlew,power`: 57.4% CPU, 4887 idle wakeups per sample, power 57.9.

**Correction (Fable review + Claude re-measure, 2026-11-27 03:14Z, m4 macOS 26.5.2, same pid):** the "4887 idle
wakeups" figure was `top`'s cumulative count (default `-c n`). Per-sample deltas (`top -l 4 -s 5 -c d`): CPU 57.5%,
26.0%, 3.9%; idle wakeups 6, 15, 6 per 5 s sample. So this is expensive work per tick, not a wakeup storm, and the cost
varies (pointer activity, window count). `sample 2455 5` (1 ms interval, `scratchpad/hf-sample.txt`): of 300 onTick
samples, 297 were in `systemState()` (`Controller.swift:108`): `menuWindowIsAt` `:292` 166 (two full
`SLWindowListCopyWindowInfo` per tick), `frontmostWindowID` AX IPC `:236` 68, Mission Control `windowAtLevel` `:242` 61.
**No samples in `FocusIndicatorPanel.show` or `windowBounds`.** The measured cost is mainly from M1a `4cbd377`, so
"Introduced by" and the `focusIndicator`-off workaround are unconfirmed until the indicator-off control is run.
Also: `setFrame` is already guarded by `lastFrame` (`FocusIndicatorPanel.swift:49-50`); only the four `order` calls run
every tick.

## Cause (from code; superseded in part by the correction above)

A repeating 50 ms timer (`Controller.swift:85`) runs `onTick` whether or not the pointer moved. Each tick:

1. `systemState()` — an AX IPC call into the frontmost app (`frontmostWindowID`, :252) and `CGWindowListCopyWindowInfo`
   for the menu / Mission Control checks (:302).
2. `indicator.frame` → `windowBounds` — another `CGWindowListCopyWindowInfo` (:126).
3. While a window is tracked, `indicatorPanel.show` — `setFrame(display: true)` and `order(.above, relativeTo:)` on four
   edge panels: about 80 WindowServer re-frame/re-order/redraw operations per second even when nothing changed.

Because the border stays up for as long as the focused window is tracked
([stale-border bug](2026-11-27-hoverfocus-universal-control-border-without-keyboard-and-stale-border.md)), step 3 runs
continuously.

## Directions (for triage)

- Only call `show` when the frame or the window above changed; skip `display: true` when only ordering.
- Run the tick only after pointer events (or slow it to ~4 Hz when the pointer has not moved).
- Acceptance should include an idle CPU/wakeup budget measured with `top -stats cpu,idlew` (before/after), with
  `focusIndicator` on and off as the control.
