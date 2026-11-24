# Bug: console TOTP (v1.45.1 A1): decay drops one level per request after the first day; rotate keeps `lock_level`

**Status:** OPEN — captured 2026-11-23; both defects reproduced or confirmed by Claude on `k3d-manager-v1.45.1`
**Priority:** P2 (proposed)
**Introduced by:** `f1dca6e8` (v1.45.1 totp-a1, escalating lock; unreleased, on the open release branch)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23 (confirm priority; fix in v1.45.1 before the release PR is proposed, since A1 is part of this release)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: m4 kube context missing); parent [`2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md) is the spec these violate, not a duplicate
**Detected by:** independent verifier of totp-c-guides (2026-11-23), reading the landed code to check the guide; Claude reproduced defect 1 and confirmed defect 2 against the code and the A1 spec
**Parent:** [`2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md`](2026-11-23-console-totp-gate-silent-lockout-and-socket-dos.md); spec [`docs/plans/v1.45.1-totp-a-lock-and-recovery.md`](../plans/v1.45.1-totp-a-lock-and-recovery.md)

## Defect 1 — decay collapses after one day

Spec (A1 `:36`, `:161`): with no active lock and `lock_level > 0`, the level drops by one per full 86400 s since the
last lock expired.

Code (`scripts/libexec/k3dm-console-totpd.py` `decay_state`, `:497-512`): `elapsed_levels = (now - until) // 86400`
with `until = locked_until`. The reduced level is committed, but `locked_until` is left at the old expiry unless the
new level is 0. The next request recomputes the same `elapsed_levels` from the same `until` and subtracts again.

Reproduced (Claude, 2026-11-23, m4-air, scratch copy of `scripts/tests/bin/test_web_console_totp.py` fixtures,
sandbox-exec denying sudo/launchctl): `lock_level=4`, `locked_until = wall - 1`, `wall += 86400`, start, then three
`VERIFY 000000` requests: levels `[3, 2, 1, 0]`; spec expects 3 throughout that day.

Effect: one quiet day after a level-4 lock, the first few attempts reset the escalation to level 0, so the next lock is
5 min instead of 24 h. The escalating lock (parent B1, operator Q3/Q4) is weaker than specified.

Why tests missed it: `test_decay_after_full_days` (`test_web_console_totp.py:1778`) restarts the daemon once per
simulated day and never sends a second request within the same day.

## Defect 2 — rotate keeps `lock_level`

Spec (A1 `:49`): enrol and rotate also reset `failures`, `locked_until` and `lock_level` to 0.

Code (`totpd.py` rotate commit, `:929-935`): `nstate = dict(cur_state)` then sets `secret`, `last_counter`,
`failures = 0`, `locked_until = 0`, `enrolled`; `lock_level` is carried over and `state_for_commit` writes it.
Enrol (`:860-866`) builds a fresh dict and is correct.

Effect: after a rotate the state can hold `locked_until = 0` with `lock_level > 0`. `decay_state` returns early when
`until <= 0`, so that level never decays; the operator's next five typos jump straight to the next level (up to 24 h).
A rollback to v1.45.0 after such a rotate hits the 6-key `load_state` refusal ("console login unavailable").

## Fix shape (for the spec)

- Decay: when the level drops but stays above 0, advance the reference point by the days consumed
  (`locked_until += elapsed_levels * 86400`, or keep a separate decay anchor) so each day is counted once; keep the
  monotonic-deadline guard.
- Rotate: set `nstate["lock_level"] = 0` (or build the dict as enrol does).
- Tests: a same-day multi-request decay case (red today: `[3, 2, 1, 0]`), and a rotate-at-level-N case asserting the
  5-key state.

## Related doc corrections (totp-c-guides, not code)

The same verifier found guide errors that follow the code as landed; they are corrected in totp-c, not here: rollback
snippet must also zero `failures` and `locked_until`; `totp-recovery-regen` is not logged; `totp-recovery-failure` and
`totp-recovery-damaged` are unstructured lines; `seconds=none` never emitted.
