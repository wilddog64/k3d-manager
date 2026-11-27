# Bug: HoverFocus uses ~55% CPU while idle — the menu-bar icon's appearance observer and its redraw feed each other

**Status:** LANDED — hoverfocus `6bd845c` (C1, Claude-verified offline); live idle-budget check owed on m4
**Priority:** P1 (proposed after control; reviews Fable + Neon: release blocker — degraded battery/heat; no workaround except quitting HoverFocus — `focusIndicator` off and a relaunch do not help)
**Introduced by:** hoverfocus `87322d6` (M1b app shell, 2026-11-22: `effectiveAppearance` observer → `updateIcon`), shipped in v0.0.1 and v0.0.2; secondary cost from the M1a 50 ms tick `4cbd377`
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report (macOS battery menu lists HoverFocus under "Using Significant Energy")
**Component:** `hoverfocus` `Sources/HoverFocusPlatform/Controller.swift` `onTick` (:100), `FocusIndicatorPanel.swift`
`show` (:59 `setFrame(..., display: true)`, :65 `order(.above, relativeTo:)`)

## Evidence (m4, 2026-11-27 ~19:00, v0.0.3 branch `a4244b6`, pid 2455, operator idle)

`ps`: 53.7% CPU, 3:27 CPU time; `top -stats pid,cpu,idlew,power`: 57.4% CPU, 4887 idle wakeups per sample, power 57.9.

## Root cause (control + profile, Claude, 2026-11-27 03:22Z, m4 macOS 26.5.2, pid 2455)

**Control:** `focusIndicator: false` (Claude wrote `~/.config/hoverfocus/config.json`; operator clicked Reload Config).
`top -l 7 -s 5 -c d`: CPU 51.1, 54.0, 52.6, 55.6, 54.0, 54.2% — unchanged. The border is not the cause.

**Profile** (`sample 2455 5`, 1 ms, border off, `scratchpad/hf-sample-off.txt`), main thread ~3500 samples:

- ~1830 (≈52%) in `__NSFireDelayedPerform` → `-[NSStatusItem _updateReplicants]` → `_redrawReplicantSnapshot` →
  `CALayer renderInContext:` — AppKit re-rendering the menu-bar icon's replicant snapshots.
- 186 in the KVO closure `AppDelegate.swift:51` (`button.observe(\.effectiveAppearance)`) → `updateIcon()` →
  `button.image = image` (`:234`), reached from `NSKeyValueDidChange`.
- ~316 (≈9%) in `onTick` → `systemState()` (the window-list copies and AX call below).

Loop: setting `button.image` makes AppKit rebuild the status item's replicants; that re-resolves the button's
`effectiveAppearance`, which fires the observer, which builds a new image and sets it again. `updateIcon` never checks
whether anything changed. The earlier border-on sample at 3.9% CPU (03:14Z) had only the 2 s trust-timer path
(`AppDelegate.swift:42` → `updateUI` `:187` → `updateIcon`, 47 samples) and no KVO frames, so the loop is intermittent:
once started it persists. That explains the 57 / 26 / 3.9 / steady-54% readings.

**Relaunch (operator, 19:44 PST):** new pid 36809, `top -c d` 56.0 / 58.6 / 56.4% within a minute of launch; `sample 3`:
1777 samples in `_updateReplicants`, 125 in the `AppDelegate.swift:51` observer. The loop starts at launch on m4; the
3.9% reading was a lull, not a loop-free state.

**m2 comparison (Claude over SSH, 2026-11-27 ~03:50Z, macOS 26.5.1, same v0.0.3 build, pid 74669 up since 12:45 PST):**
`top -c d` 5.6 / 5.7% CPU, 0–1 idle wakeups; 33:45 CPU time over ~7 h (≈8% average); `sample 3`: main thread 317 in
`onTick` and **no** `_updateReplicants` or `AppDelegate.swift:51` frames. So m2 has only the tick cost (Part B), not the
icon loop. Both Macs have one display, so a multi-display menu bar is not the trigger; m4 runs macOS 26.5.2, m2 26.5.1
(not proven to be the trigger). The Part A fix (never re-assign an unchanged icon) does not depend on what triggers
the appearance churn.

Fix direction: `updateIcon` computes the `(style, darkBar, dimmed)` key and returns early when it equals the last one it
applied (never re-assign `button.image` for an unchanged key); the 2 s `updateUI` must not touch the icon unless that
key changed. Secondary (separate child or same spec): one window-list snapshot per tick and a slower idle tick (Fable).

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

## Live evidence (after C1 `6bd845c`, m4, operator installed 2026-11-26 20:09 PST, pid 15541)

- `top -l 7 -s 10 -c d` (04:17Z, operator active, not hands-off): 2.9, 3.7, 5.7, 1.9, 1.1, 3.7% CPU (before: 51–58%).
- `sample 15541 5`: **no** `_updateReplicants` or appearance-observer frames; the remaining main-thread time is in
  `handle()` (`Controller.swift:156`, `lookup` on pointer events) — active-use cost, not idle.
- macOS battery menu (operator screenshot, ~20:20 PST): "No Apps Using Significant Energy" (before: HoverFocus listed).
- Owed: a hands-off 60 s measurement against the C-M3 budget, and the operator behaviour checks (C-E3).
- Side note: the m4 build is ad-hoc signed (no "HoverFocus Local Signing" identity on m4; Makefile falls back by design).
