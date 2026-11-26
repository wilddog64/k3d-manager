# Bug: HoverFocus offers no working recovery when its Accessibility grant goes stale

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** pre-existing (M1b app shell, "Grant Accessibility…" item)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone)
**Prior art:** none (exact-slug glob: no `docs/bugs/*hoverfocus*`; `make find-similar-docs` retrieval unavailable)
**Severity:** low — the menu shows a red "Needs Accessibility permission" but the only action is a one-time system prompt, which does nothing when a stale entry exists; recovery needs `tccutil` from a terminal (README:69)
**Filed:** 2026-11-26, operator: "is it possible to allow user to prompt the red highlight and bring system preference to grant the permission?"
**Component:** HoverFocus `Sources/hoverfocus/AppDelegate.swift` (`grantAccessibility`, line 267; status line), `MenuModel.swift:70`

## Symptom

After a reinstall that changed the code signature, System Settings showed HoverFocus enabled (switch would not turn off);
the menu showed "Needs Accessibility permission". "Grant Accessibility…" calls `AXIsProcessTrustedWithOptions(prompt:
true)`, which macOS shows once per app identity, so nothing happened.

## Fix options (for triage)

1. Make the red status line clickable, same action as "Grant Accessibility…".
2. That action also opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and shows a
   short hint: "If HoverFocus is listed and on, remove it with − and add it again."
3. Optionally offer "Reset permission…" that runs `tccutil reset Accessibility com.wilddog64.hoverfocus` (no sudo for
   the user's own app) and then prompts.

Selftest rows for the menu-model text and action routing. Less needed once the signing bug
(`2026-11-26-hoverfocus-bundle-ignores-codesign-failure.md`) is fixed, but a first install and ad-hoc builds still hit it.
