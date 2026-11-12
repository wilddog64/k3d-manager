# Bug: Hermes "correlated incident resolved" names no sensors, and reads as all-clear while one is still degraded

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (The issue only affects the clarity of the Slack resolution message wording while incident detection, correlation, and state transitions work as intended (and is explicitly noted as P3 in the report)); Claude proposed P3. Agreed.
**Triage:** carry → v1.44.0 (Hermes relay batch) — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** `cd38a7e5` (v1.29.0, Hermes phase 1)
**Should have been caught by:** spec
**Severity:** low — misleading Slack message; workaround: read the earlier incident message and `bin/k3dm-hermes` status
**Approval:** operator, 2026-11-08 ("go ahead to file P3 and dispatch task when time is right")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, Slack, 2026-11-08 10:12 PST (screenshot: "Hermes correlated incident resolved." — "what
incident was resolved? not very clear")
**Affected:** `scripts/lib/hermes/correlator.py`
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)
**Related:** `docs/bugs/2026-11-08-hermes-values-branch-flags-deploy-hub-and-r9-retargets-release-branch.md` (the
incident in question: ci + values_branch; values_branch stayed degraded after "resolved");
`docs/bugs/2026-09-20-hermes-correlator-never-re-pages-after-incident-latches.md` (FIXED, same class)

## Symptom

At 09:51 Hermes opened an incident for `ci + values_branch`. At 10:12 it posted only "Hermes correlated incident
resolved." The ci failure had cleared (`e8ca9af3`); `values_branch` was still degraded. The message named neither.

## Root cause

`Correlator.process` (`scripts/lib/hermes/correlator.py:36-39`) declares an incident over when fewer than 2 distinct
sensors were degraded across the correlation window, and returns a fixed text. It clears `incident_sensors` without
using it, and never looks at the current records. One sensor still degraded, or a sensor whose source went
`unknown`, reads the same as everything healthy.

## Fix

In the resolved branch of `Correlator.process`, before clearing state, build the text from `notified` (the
incident's sensors, `state["incident_sensors"]`) and the current `records`:

`Hermes correlated incident resolved (<notified joined by " + ">). Cleared: <A>. Still degraded: <B>. No data: <C>.`

- Every list is keyed on the **current** `records` only, never on `correlation_history`. With a window above 1 an
  incident resolves while earlier cycles still hold degraded entries; a sensor degraded earlier but `healthy` now is
  Cleared.
- B: every sensor whose current record is `degraded`, in `notified` or not. A sensor in B is never in A or C.
- A: sensors in `notified`, not in B, whose current record is `healthy`.
- C: sensors in `notified`, not in A or B: current record `unknown`, any other status, or no record this cycle.
- Several records for one sensor: it counts once; if any of them is `degraded` it is in B.
- Each list is sorted, de-duplicated and joined by `, `; an empty list reads `none`. Every clause ends with `.`.
- `notified` empty or missing: the header is `Hermes correlated incident resolved (sensors not recorded).`
- Example, literal: `Hermes correlated incident resolved (ci + values_branch). Cleared: ci. Still degraded: values_branch. No data: none.`

The event keeps `kind: "resolved"` and `sensors: []`, the state reset is unchanged, and the resolved text is not
passed to LLM enrichment (as today). `bin/k3dm-hermes:239-241` may append an automatic Kine guard line to any event; that
stays as it is.

## Files

- `scripts/lib/hermes/correlator.py`
- `scripts/tests/hermes/test_correlator_resolved_text.py` (new; do not edit `scripts/tests/hermes/test_hermes.py`,
  which the Hermes values_branch P2 dispatch edits; define your own record helper there, do not import from
  `test_hermes.py`). Run with `python3 -m pytest scripts/tests/hermes/test_correlator_resolved_text.py
  scripts/tests/hermes/test_hermes.py -q`.

## Do not

- Change when an incident opens, escalates or resolves, the correlation window, or the incident and escalation text.
- Change `bin/k3dm-hermes`.

## Acceptance

```yaml
must:
  - id: M1
    text: "the resolved message names the incident's sensors, lists those now healthy under Cleared and every sensor now degraded under Still degraded, including one not in the incident and with correlation_window 3"
  - id: M2
    text: "an incident sensor that now reports unknown, or has no record, is listed under No data; with no recorded incident sensors the header reads '(sensors not recorded)'"
  - id: M3
    text: "incident and escalation events, the resolved kind, sensors [] and the state reset are unchanged (control: green before and after)"
must_not:
  - id: N1
    text: "the Cleared list differs from exactly the incident sensors whose current record is healthy (a degraded, unknown or missing sensor under Cleared, or a healthy one left out; red on pre-fix code, which has no Cleared list; paired with M1)"
  - id: N2
    text: "the resolved message omits a sensor that is still degraded (today's bug: red on pre-fix code)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: "tests open an incident with two checks, then let it resolve several ways: both healthy, one still failing, one whose source went silent, a new check failing alone, a 3-run window, and an incident with no recorded checks. They read the resolved message for the incident's checks and the Cleared, Still degraded and No data lists, and check the incident and escalation messages are unchanged."
  - id: E2
    proves: [M1]
    kind: live
    intent: "the next time a Hermes incident resolves, the Slack message names its checks and says which cleared and which are still failing"
interface:
  - "scripts/lib/hermes/correlator.py Correlator(correlation_window=N).process(records, state) -> event dict with kind and text"
  - "a record is {sensor, status in healthy|degraded|unknown, evidence, sampled_at, data}"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- Intents approved by the operator on 2026-11-08 ("P3 approved"), after the spec review.
- Spec review (Sonnet, 2026-11-08, first-pass trial step 3): no blockers; 4 should-fix and 3 nits, all applied: N1
  rewritten so it is red on pre-fix code, window above 1 and current-record keying, empty incident header, de-dup and
  ordering rules, literal example, test command and helper, E1 cases widened.
- Files do not overlap the open dispatches or the Hermes values_branch P2 (`sensors.py`, `repairs.py`, `argocd.sh`,
  `test_hermes.py`). Dispatch when a WIP slot frees, after the P2 (a P2 that blocks the release goes first).
