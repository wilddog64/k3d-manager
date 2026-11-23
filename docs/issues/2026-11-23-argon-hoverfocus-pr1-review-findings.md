# Argon blind review of hoverfocus PR #1 (M1 prototype, v0.0.1)

**Date:** 2026-11-23
**PR:** wilddog64/hoverfocus#1 (`m1-base` → `main`, head a4d9abb)
**Reviewer:** Argon (agy, `gemini-4-argon-medium`), role review, spec `docs/plans/review-hoverfocus-pr1-v0.0.1.md`
**Verified by:** Claude, against the code at a4d9abb
**Disposition:** none block v0.0.1 (operator, 2026-11-23: "ship v0.0.1 and fix bugs in v0.0.2"); confirmed ones carry to v0.0.2

| # | Finding (Argon severity) | Claude verdict |
|---|---|---|
| 1 | `AppDelegate.swift:229-236` `reloadConfig()`: an invalid `config.json` sets `config = Config()` (defaults, `enabled: true`) with `configError` set, then `controller.apply(config)` runs anyway, so a running controller keeps focusing with defaults while the menu shows the config error (medium) | **Confirmed** (fails open). The `enabled: false` half is wrong: a valid `enabled: false` reaches `Engine.permitted` (`Engine.swift:21`) and stops focus. Carry → v0.0.2. |
| 2 | `Controller.swift:157` `elements[windowID] = element` never evicts closed windows; grows for the life of the process (low) | **Confirmed**, low: slow memory growth in a login item. Carry → v0.0.2. |
| 3 | `Makefile:37` `sed 's|__PROGRAM__|$(APPDIR)/...|g'` breaks if `APPDIR`/`HOME` contains `|` or `&`; also not XML-escaped (low) | **Confirmed**, low: needs an unusual home path. Carry → v0.0.2. |
| 4 | `Controller.swift:118-125` `buttonsDown` comes from the event type only, so a `.mouseMoved` while a button is held (second pointer device) could fire focus (low) | **Speculative.** macOS delivers `*MouseDragged`, not `.mouseMoved`, while a button is held; after a mouse-down `candidate` is nil so `tick` cannot fire. Possible only with mixed devices; checking `CGEventSource.buttonState` would close it. Noted, no bug. |
| 5 | `ConfigLoader.swift:50-51` checks `number.intValue` in range, so `dwellMs: 1e30` might wrap into `0...5000` (low) | **Speculative.** On arm64 the double→Int conversion saturates to `Int.max`, which the range check rejects. Range-checking `doubleValue` is the cleaner form. Noted, no bug. |

## Process note

Argon's report lands only in the run's `agy.log`; the operator approved reading it for this run (2026-11-23).
