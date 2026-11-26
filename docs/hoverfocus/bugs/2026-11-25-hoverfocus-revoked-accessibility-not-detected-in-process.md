# Bug: HoverFocus keeps showing Running after its Accessibility permission is revoked

**Status:** OPEN — capture
**Priority:** P2 — the U1 error state never appears for a revoked grant; hover focus silently stops; workaround: quit and reopen HoverFocus (the start check then shows the red line)
**Introduced by:** `4e66919` (U1 trust-loss detection relies on `AXIsProcessTrustedWithOptions` flipping in-process)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (both)
**Waiting on:** investigation — since 2026-11-25
**Classified:** P2 — Argon (`gemini-4-argon-medium`, blind), 2026-11-25: running-process trust loss not surfaced; quit and reopen restores detection.
**Prior art:** exact-slug glob over `docs/hoverfocus/bugs/` (no trust/permission/stale match); `make find-similar-docs` not run (vector store unavailable earlier today)
**Filed:** 2026-11-25
**Detected by:** operator, U1-EL step 2 on m2-air (macOS 26.5.1 25F80), HoverFocus pid 51792 built from `7b42f63`

## Observed

1. Switching HoverFocus off in System Settings > Privacy & Security > Accessibility crashed the panel ("Extension
   process `Privacy & Security(57353)` exited"); the switch stayed on. Not counted.
2. `tccutil reset Accessibility com.wilddog64.hoverfocus` (~19:47 PST) → "Successfully reset". The menu stayed on
   **Running** (no red line, no notification).

HoverFocus log (`log stream`, subsystem `com.wilddog64.hoverfocus`, Claude over SSH, 19:44–19:49):

```
19:47:09.454 E [focus] focus failed for window 254003
19:47:20.548 I [focus] ax-enable pid 57887 rc -25211
```

`-25211` is `kAXErrorAPIDisabled`: after the reset the running process's AX calls are refused. No `[health] trust lost`
line was logged, so `AppCoordinator.trustTick` (`Sources/HoverFocusCore/AppCoordinator.swift:43`) saw
`isTrusted()` return true while the AX API was disabled for the same process.

Follow-up the same evening (operator, ~20:00 PST) weakens the capture: after the reset, hover focus still typed into
TextEdit, and a quit-and-reopen of HoverFocus came up **Running** (a fresh process reported trusted). So the grant was
either absent only briefly (the -25211 window) or restored (the Settings panel crash had re-enabled the switch once
already). Open: did the operator re-grant, and is HoverFocus listed and on in Accessibility now. Do not triage as
confirmed until a clean revoke (stays revoked for a fresh process) is shown.

## Suspected cause (to prove before a fix)

`AXIsProcessTrustedWithOptions` appears to keep returning the value cached at launch for the running process on
macOS 26.5.1, while real AX calls fail with `kAXErrorAPIDisabled`. U1's spec (`docs/plans/hoverfocus-v0.0.3-u1-visible-errors.md`,
U1-EL) anticipated "AXIsProcessTrusted did not flip in-process" as a possible outcome.

Still to confirm at m2: hover focus stopped working after the reset (expected from rc -25211), and a quit-and-reopen
shows the red start error (the start path calls the same function in a fresh process).

## Fix direction (for triage)

Treat `kAXErrorAPIDisabled` from the controller's own AX calls (hit-test, `AXManualAccessibility`, focused-window read)
as trust lost and feed it into the same health path, instead of, or in addition to, polling
`AXIsProcessTrustedWithOptions`. Needs a probe first: does a fresh `AXIsProcessTrustedWithOptions` call in a
long-running process ever flip after `tccutil reset` on 26.5.1?
