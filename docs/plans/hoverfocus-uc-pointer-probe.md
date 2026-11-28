# hoverfocus — Universal Control pointer probe (read-only diagnostic for capture 2)

**Status:** LANDED 2026-11-28 on hoverfocus v0.0.3 (Flash `hf-uc-probe`; Claude verified P-E1 offline); P-E2 (live run by the operator on m4) pending
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent bug:** [`2026-11-27-hoverfocus-universal-control-border-without-keyboard-and-stale-border.md`](../bugs/2026-11-27-hoverfocus-universal-control-border-without-keyboard-and-stale-border.md) (P3, operator approved 2026-11-28)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` (head `4a9bb6e`)
**Risk:** low (a standalone script; the app, its build and its install are not touched)
**Implementer:** Flash (agy, `gemini-3.8-flash-medium`).
**Verifier:** Claude, from `## Acceptance` only; the live capture is run by the operator.
**Filed:** 2026-11-28
**Intent approved:** operator, 2026-11-28
**Approval:** operator 2026-11-28 "can you dispatch it to flash?", then chose "HoverFocus probe" ("Dispatch the small read-only diagnostic for capture 2 (what m4 sees when the pointer leaves for m2) to Flash now. No fix yet; it gives you the tool to run at the desk.")

## Context (you cannot read the bug doc; this is what it established)

Two Macs (m2, m4) share one keyboard and pointer through Apple Universal Control. HoverFocus (a focus-follows-mouse
menu-bar app in this repo) draws a blue border around the window it focused. When the pointer moves from m4 to m2,
m4's border stays, because HoverFocus has no way to know the pointer left this Mac. Two reviewers agreed that before
any fix we must **measure** what macOS reports on m4 while the pointer is on the other Mac. Unknown today:

1. Does `CGEvent(source: nil)?.location` (or `NSEvent.mouseLocation`) move outside every local display, or stay
   **clamped** at the shared edge?
2. How long since the last `mouseMoved` (`CGEventSource.secondsSinceLastEventType(.combinedSessionState, .mouseMoved)`)
   while the pointer is away, compared with a pointer resting still on this Mac?
3. Does `CGCursorIsVisible()` change when the pointer leaves? (Reviewers warn it also changes while typing, so record it
   but do not rely on it.)

## Build

A standalone Swift script `tools/uc-probe.swift`, run with `swift tools/uc-probe.swift [--seconds N] [--interval-ms M]`
(defaults 60 s, 100 ms). It is **not** part of `Package.swift` and not linked into the app.

- Every interval it samples: monotonic ms since start; `CGEvent(source: nil)?.location` (x, y, Quartz top-left);
  `NSEvent.mouseLocation` (x, y, AppKit bottom-left); the local display containing the CG point
  (`CGGetDisplaysWithPoint`, `none` when no local display contains it); whether the CG point is within 2 px of an
  **outer** edge of the union of active local displays (`CGGetActiveDisplayList` + `CGDisplayBounds`; an edge shared
  by two local displays is not outer); seconds since the last `mouseMoved`; `CGCursorIsVisible()`; the frontmost app's
  bundle id (`NSWorkspace.shared.frontmostApplication?.bundleIdentifier`; no window titles).
- It prints a header line first (`uc-probe v1 macOS <version> displays=<count> <id:WxH@x,y ...>`), then **one line
  per sample only when a field other than time and idle seconds changed, or at least every 5 s** (so a 60 s run is
  readable). Lines are tab-separated with a fixed field order documented in the script's top comment.
- Output goes to **stdout only**. It writes no file, needs no Accessibility or Input Monitoring permission, creates no
  event tap, posts no event, and changes no setting.
- A short usage note in `tools/README.md`: how to run it on m4 during the crossing (start it, wait 5 s with the pointer
  still on m4, cross to m2, wait 10 s, cross back, wait 5 s), and that the operator pastes the output into the bug doc.

## Files

| File | Change |
|---|---|
| `tools/uc-probe.swift` | new |
| `tools/README.md` | new |
| `tests/uc_probe_test.sh` | new |

## What NOT to Do

- Do not edit `Package.swift`, anything under `Sources/`, `Makefile`, `packaging/` or the existing tests.
- No event taps (`CGEvent.tapCreate`), no posting (`CGEvent.post`, `CGEventPost`, `postToPid`), no
  `AXUIElement` calls, no file writes, no network.
- Do not commit; leave the files for Claude to verify.

## Acceptance

```yaml
must:
  - id: P-M1
    text: "swift tools/uc-probe.swift --seconds 2 --interval-ms 100 exits 0, prints the header line first, then at least one sample line with every documented field"
  - id: P-M2
    text: "a sample line names the local display containing the pointer, or 'none'; an outer-edge flag; seconds since the last mouseMoved; cursor visibility; the frontmost bundle id"
  - id: P-M3
    text: "change-only output: with the pointer untouched, a 12 s run prints at most 4 sample lines"
must_not:
  - id: P-N1
    text: "the script creates an event tap, posts an event, calls AXUIElement APIs, writes a file or opens a network connection"
    red_on_current: "red today: tests/uc_probe_test.sh does not exist and tools/uc-probe.swift does not exist, so the test fails"
  - id: P-N2
    text: "the app target, Package.swift or anything under Sources/ changes"
    red_on_current: "green on current and after: positive control kept in the test (git diff --quiet on those paths)"
evidence:
  - id: P-E1
    proves: [P-M1, P-M2, P-M3, P-N1, P-N2]
    kind: offline
    command: "bash tests/uc_probe_test.sh: (a) swiftc -typecheck tools/uc-probe.swift rc 0; (b) grep finds none of tapCreate, CGEventPost, '.post(', postToPid, AXUIElement, FileManager, write(to, URLSession, Network in the script; (c) a 2 s run exits 0, its first line starts 'uc-probe v1', and a sample line has the documented field count; (d) a 12 s run prints at most 4 sample lines; (e) git diff --quiet -- Package.swift Sources Makefile packaging. Red control: add a CGEventPost call to a copy of the script; (b) fails"
    intent: "The probe only watches: it cannot click, type, move anything or save a file, and it does not touch the HoverFocus app."
  - id: P-E2
    proves: [P-M2]
    kind: live
    command: "operator on m4 with m2 linked by Universal Control: swift tools/uc-probe.swift --seconds 30, pointer still on m4 for 5 s, cross to m2 for 10 s, back to m4; output pasted into the bug doc"
    intent: "One 30-second run at your desk shows whether a Mac can tell that the pointer went to the other Mac, which decides how the stale blue border gets fixed."
interface:
  - "CLI: swift tools/uc-probe.swift [--seconds N] [--interval-ms M]"
```

## Worker definition of done

`bash tests/uc_probe_test.sh` passes; the red control (an added `CGEventPost` in a copy) fails check (b) and is removed;
`swift build` still passes (app untouched); `git status` shows only the three files in `## Files`. Report each command,
its exit code and the proving lines.
