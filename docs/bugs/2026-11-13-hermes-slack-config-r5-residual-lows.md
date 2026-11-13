# Hermes Slack config sensor: residual low findings after round 5 (manifest polling, flag source, guard test coverage)

**Status:** OPEN — captured 2026-11-13 from the round-5 cross-model review of plan 5 (Claude)
**Priority:** P3 (proposed: no secret leak, no rotation storm, every flag state recovers when the operator writes a new pair; the items are extra API calls, edge-case flag labelling and test coverage)
**Classified:** pending second-agent classification
**Introduced by:** plan 5 `hermes-slack-config-sensors` (rounds 3–5 corrections)
**Should have been caught by:** offline test (items 1, 6); review (items 2–5)
**Prior art:** exact-slug glob, none; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing)
**Waiting on:** operator decision

## Symptom

From the round-5 review (Fable, 2026-11-13). Fable ran each item in a scratch copy, with logging stubs for `ssh`, `security` and `curl` and a scratch HOME. No item reaches a secret, a real external call, more than one rotation per hour, or a healthy result on an exception.

1. Test gap: the guard teardown test (`scripts/tests/hermes/conftest.py` ~180-189) exercises only the `ssh` PATH stub. A mutant that drops the `security` and `curl` stubs stays green.
2. A manifest auth failure right after a successful rotate is flagged as rotate-sourced (`scripts/lib/hermes/sensors.py` ~122, ~235-245). Suppose the same pair later becomes valid without a Keychain write, for example after a Slack-side fix. The flag never clears, so Hermes keeps saying "regenerate" until the operator writes a new pair. Writing a new pair does recover it.
3. In failure states while the rotation guard is active, the manifest is called on every poll, 12 times an hour (~108-115). It should be throttled by `regenerate_checked_at`.
4. Inferred: `rotate_attempted_at` and the flag are saved only at the end of the cycle (`bin/k3dm-hermes` ~249-255, ~974-978, ~1042). If the same poll crashes later, the throttle is lost and the next poll can attempt again.
5. Nit: the flag is popped before the Keychain-writable check (~137-141). When the Keychain is not writable, the regenerate action is lost and `writable()` runs on every poll.
6. Test gaps (surviving mutants, 16 of 86):
   - M1d: the `security` and `curl` stubs are dropped (item 1).
   - L2b: the flag branch ignores only the attempted-rotation guard.
   - 1f: post-rotate `regenerate_checked_at` and `regenerate_checked_refresh` are not set.
   - Five poll-test stub removals, all unreached at `now=1000`.
   - 2n: the scratch-HOME fixture is removed.
   - 5b: no `regenerate_checked_refresh` is stored.
   - 9c′ and 9c″: the rotation code allows a dash, or a dot.
   - G2, G3, G6, and the minimum-interval clamp (G10).

   The rate and recovery simulations cover L2b, 1f and G10.
7. Nits: lines ~72-79 are outside the `try`, so a non-numeric `rotated_at` in state would raise. `_slack_rotation_unknown` (~345-348) echoes any alphanumeric Slack code of up to 48 characters into evidence.

## Evidence

Fable's scratch results, including the full mutant table, are in the session scratchpad (`fable-p5r5/mut5.out`). Rotation counts over 12 h at 300 s polls are the same at interval 3600 and at 60:

| Case | Rotates | Max in any hour |
|---|---|---|
| Success, 12 h tokens | 2 | 1 |
| Success, expiry 10 min ahead or missing | 12 | 1 |
| Ratelimited / exception / Keychain-write failure | 12 each | 1 |
| Rejected pair | 1, then flag | 1 |
| Rotate ok, then manifest auth failure | 1, then flag | 1 |

Recovery: once the operator writes a new valid pair, the next poll is healthy in all 12 flag states (7 rotate-sourced, 5 manifest-sourced).
