# Bug: HoverFocus install — LaunchAgent bootstrap fails over SSH, and the Accessibility grant goes stale per build

**Status:** OPEN
**Priority:** P2 (proposed) — degraded: every install needs manual launchctl/TCC steps (the workaround)
**Introduced by:** `87322d6` (hoverfocus M1b app shell: bundle/install)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Fable)
**Waiting on:** dispatch
**Triage:** carry → hoverfocus v0.0.2 (operator, 2026-11-23: "ship v0.0.1 and fix bugs in v0.0.2")
**Prior art:** none above threshold (no earlier hoverfocus install docs)
**Filed:** 2026-11-23
**Detected by:** operator + Claude, M1 install and E-L1 on m2-air (macOS 26.5.1), 2026-11-23

## Observed (four parts)

1. **Error 37 race.** Re-running install while the old agent is loaded races the unload; `launchctl bootstrap`
   returned error 37 (already loaded / in progress).
2. **No session check.** Over SSH, `launchctl managername` is `Background`; bootstrapping the
   `LimitLoadToSessionType Aqua` plist into `gui/<uid>` fails with `Bootstrap failed: 5: Input/output error`.
   Workaround: `sudo launchctl asuser $(id -u) launchctl bootstrap gui/$(id -u) <plist>`. Install gives no hint.
3. **Grant is noticed only from the menu's Grant item.** `AppDelegate.swift:208-226 grantAccessibility()` polls
   trust every 2 s, 60 times, only after the menu item is clicked. Granting in System Settings directly leaves the
   running app untrusted until it is restarted (`launchctl kickstart -k gui/$(id -u)/com.wilddog64.hoverfocus`).
4. **Ad-hoc signing makes the grant build-specific.** `Signature=adhoc`, no TeamIdentifier: each rebuild changes the
   code hash, so System Settings still shows HoverFocus enabled while the new binary is untrusted. The list offered no
   remove button; `tccutil reset Accessibility com.wilddog64.hoverfocus`, re-grant and kickstart fixed it.

## Expected

- Install unloads and waits before bootstrapping; detects a non-Aqua session and prints the `asuser` command.
- The app watches trust (e.g. poll or `com.apple.accessibility.api` distributed notification) without a menu click.
- Sign with a stable local identity so the grant survives rebuilds, or install prints the `tccutil reset` step.
