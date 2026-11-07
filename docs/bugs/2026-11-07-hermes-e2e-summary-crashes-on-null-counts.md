# Bug: Hermes crashes formatting an e2e summary whose counts are null, so failed runs are never reported

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** VERIFIED 2026-11-07 — d619fcbd (Luna; reviewed by Claude); independent verifier PASS (fix 8 passed, pre-fix 5 red); live E2 pending
**Fix commit:** d619fcbd
**Priority:** P2 — every e2e run that fails before tests start is silent: no Slack post, no slot record, and the slot is rerun
**Waiting on:** live check — since 2026-11-07
**Approval:** explicit 2026-11-07 "can you investigate this issue, file bug if necessary and dispatch to Luna" (operator)
**Severity:** medium
**Related:** `docs/bugs/2026-11-07-e2e-results-never-reach-m5-hub.md`

## Symptom

`~/Library/Logs/k3dm-hermes-e2e.log` on the M5 (2026-11-07) holds 10 copies of:

`File "bin/k3dm-hermes", line 348, in _e2e_text ... TypeError: unsupported operand type(s) for -: 'NoneType' and 'NoneType'`

## Root cause

When an e2e run fails before tests start, the runner writes a summary with the count keys present and null. Real file from the M5, `~/.k3dm/e2e/dispatch/m2-20261107T113949Z.summary.json`, 2026-11-07 (captured by Claude; keys unchanged, values as written):

`{"candidate_digest": null, "commit": "4f46a677...", "duration_seconds": null, "exit_code": 1, "failed": null, "failure_details": [], "failure_groups": [], "passed": null, "phase": "deploying-substrate", "project": "api+flows", "result": "fail", "run_id": "1794051590-16732", "runner": "m2", "service": "product-catalog", "tier": "vcluster", "timestamp": "2026-11-07T11:40:39.629001+00:00", "total": null}`

`_e2e_text` (`bin/k3dm-hermes:346`) reads the counts with `summary.get(key, 0)`, which returns `None` for a key that is present with a null value, then computes `total - passed - failed`. `_run_e2e` (`bin/k3dm-hermes:386`) calls it before writing the slot record (`_e2e_write(... f"{slot}.json" ...)`), so the crash also skips that record and the slot stays claimed. The same `.get(key, 0)` pattern builds the record's `counts`.

## Fix

1. `bin/k3dm-hermes`: read `passed`, `failed` and `total` as integers with null or missing treated as 0, in both `_e2e_text` and the `counts` written by `_run_e2e`. Use one small helper for both.
2. When all three counts are 0 and the result is not `pass`, the Slack head line names the phase instead of counts: `FAIL — before tests (phase <phase>)`, with `phase` from the summary, or `unknown` when absent.
3. New `scripts/tests/bin/test_hermes_e2e_text.py`, loading `bin/k3dm-hermes` the way `scripts/tests/bin/test_hermes_checkout_lag.py` does. Use the captured summary above as the fixture, with its source and date in a comment.
4. `CHANGELOG.md`: one bullet at the end of `[Unreleased]`.

## Files

- `bin/k3dm-hermes`
- `scripts/tests/bin/test_hermes_e2e_text.py`
- `CHANGELOG.md`

## Gates

`pytest scripts/tests/bin/test_hermes_e2e_text.py scripts/tests/bin/test_hermes_checkout_lag.py` with `PATH` including a Python that has PyYAML. Paste the output, including failures.

## What NOT to Do

- Do NOT change the runner, `e2e_remote.sh`, or the summary format.
- Do NOT change how passing runs or runs with real counts are worded.
- Do NOT post to Slack or call the network in tests; stub `post_summary` and `_keychain_secret`.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/` or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "bin/k3dm-hermes: _e2e_text(slot, run, summary, filed, changes)"
  - "bin/k3dm-hermes: _run_e2e(slot, runner=..., now=...) with K3DM_HERMES_E2E_DIR and K3DM_E2E_DISPATCH_DIR pointed at temp dirs"
must:
  - id: M1
    text: "_e2e_text with the captured null-count summary returns text whose head line contains 'FAIL — before tests (phase deploying-substrate)'."
  - id: M2
    text: "_run_e2e with a stub runner (preflight rc 0, dispatch rc 1) and the captured summary in the dispatch dir writes <slot>.json with outcome fail and counts {passed: 0, failed: 0, total: 0}, and calls post_summary once."
must_not:
  - id: N1
    text: "Neither function raises on a summary whose passed, failed or total is null or missing. Shown red against the pre-fix code."
  - id: N2
    text: "Real counts are unchanged: a summary with passed 3, failed 1, total 5 and result fail still gives 'FAIL — 3 passed, 1 failed, 1 skipped'; passed 5, total 5, result pass gives 'PASS 5/5'."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    what: "Independent verifier, tests from this block only; N1 shown red against the pre-fix code."
  - id: E2
    proves: [M1]
    kind: live
    what: "Claude: the next scheduled slot on the M5 writes its <slot>.json, and the operator sees the Slack post."
```
