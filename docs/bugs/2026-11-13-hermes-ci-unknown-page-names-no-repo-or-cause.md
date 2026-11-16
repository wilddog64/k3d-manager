# Bug: Hermes "ci check unknown 30+ min" page names no repo, workflow or cause

**Status:** OPEN — captured 2026-11-13
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-14 (The `ci` sensor's broad exception handler masks the failing repository, workflow, and underlying error in both Slack pages and logs, degrading alert diagnostics while leaving manual GitHub Actions inspection as a workaround.)
**Triage:** patch → v1.44.1 — triage 2026-11-14, operator
**Waiting on:** fix running — since 2026-11-16 (Flash)
**Branch:** k3d-manager-v1.44.1
**Introduced by:** pre-existing
**Should have been caught by:** review
**Prior art:** exact-slug glob: none; `make find-similar-docs` returned nothing — none above threshold
**Approval:** none yet (capture only)

## Symptom

The operator got this Slack page and could not tell which CI check it meant (operator screenshot, 2026-11-13: "this message is unclear for which ci check is unknown for 30+ mins ... as we have many ci"):

- 02:38 PST `Hermes: ci check unknown 30+ min: CI status source unavailable`
- 02:47 PST `Hermes: ci check recovered`

The hub Hermes log (`~/Library/Logs/k3dm-hermes.log` on m5-air, read-only, 2026-11-13) shows the `ci` sensor flapping:

| Time (UTC) | Status | Evidence |
|---|---|---|
| 08:47:19 | unknown | CI status source unavailable |
| 08:56:58 | degraded | wilddog64/k3d-manager lint failure |
| 09:34:16 | unknown | CI status source unavailable |
| 09:43:46 | degraded | wilddog64/k3d-manager lint failure |
| 09:53:39 | unknown | CI status source unavailable (paged at 10:38Z) |
| 10:47:32 | degraded | wilddog64/k3d-manager lint failure |

The real error is not in the log.

## Root cause

`ci()` in `scripts/lib/hermes/sensors.py:1058-1103` runs every repo inside one `try` block. A bare `except Exception` returns the fixed text `CI status source unavailable` and throws away three things:

- which repo failed;
- what failed: HTTP status, timeout, rate limit, or `ValueError("missing workflow run")`;
- the results already collected for the other repos.

The pager (`scripts/lib/hermes/pager.py:81`) prints that evidence as it is. Only the default repo list `["wilddog64/k3d-manager"]` is in use. The sensor reads `runs[0]`, the newest run of any workflow on any branch. So "ci" means "whatever CI run is newest in k3d-manager", and the page doesn't say that either.

## Fix

All edits in `scripts/lib/hermes/sensors.py`, function `ci()` (lines 1058-1103), plus tests:

1. Move the per-repo body (runs fetch, check-runs fetch, check loop) into its own `try` inside the `for repo_name in repos`
   loop. On exception, append `f"{repo_name}: {cause}"` to a new `failed` list and `continue`; results from other repos stay.
2. Add `_ci_cause(exc)` next to `ci()`: `HTTPError` (has `.code`) gives `GitHub API HTTP <code>`; `TimeoutError` gives `timeout`;
   `URLError` gives `network error`; `ValueError("missing workflow run")` gives `no workflow runs`; any other `ValueError` gives
   `invalid response`; anything else gives the exception class name. Never use `str(exc)`, headers or a response body.
3. In the except branch also write one line to stderr (the launchd log): `Hermes ci unknown: <repo> <ExceptionClass> <code or ->`.
4. Evidence: name the run's workflow and branch. For each bad check use
   `f"{repo_name} {latest.get('name', 'CI')}@{latest.get('head_branch', 'unknown-branch')} {check_name} {conclusion}"`
   (same for `stuck`). Fixtures without `name` or `head_branch` still work through the defaults.
5. Result order: if `bad` is non-empty, return degraded exactly as today (debounce unchanged), appending nothing from `failed`;
   else if `failed` is non-empty, return `unknown` with `"; ".join(failed[:3])` and do not touch the `ci` debounce counter;
   else healthy as today.
6. The rename of the page text in `pager.py:81` is out of scope (operator decision, see open question).

Open question for the operator: rename the page to `CI (GitHub Actions) status unknown 30+ min: <evidence>`? Default in this spec: no;
the repo and cause now come through `{item['evidence']}`.

## Files

- `scripts/lib/hermes/sensors.py`
- `scripts/tests/hermes/test_hermes.py`

## Contract readers

Grep: `grep -rn "\"ci\"\|sensors import.*ci\|ci(" scripts/lib/hermes bin/k3dm-hermes` (2026-11-16).

- `scripts/lib/hermes/sensors.py:1058-1103` — writer of the `ci` record; evidence text changes, `data` keys (`repo`, `run_id`,
  `run_url`, `conclusion`) and statuses do not.
- `bin/k3dm-hermes:259` (`ci(github_fetch, state, token=github)`) and `:232-233` (`github_fetch` over `_http_json`, `:83-88`) — caller and
  fetch; no change, the exceptions it raises (`urllib.error.HTTPError`, `URLError`, timeout) are what `_ci_cause` classifies.
- `scripts/lib/hermes/pager.py:81` — reader; prints `item['evidence']` verbatim, so the new text reaches Slack unchanged in code.
- `scripts/lib/hermes/repairs.py:135-139` (`_r4_precondition`) and `:166-171` (`_r4_command`) — readers of `data.repo`, `data.run_id`,
  `data.conclusion`; unchanged because the `data` shape is kept.
- `scripts/tests/hermes/test_hermes.py:1458-1520` — readers; no assertion on `ci` evidence text (grep), so they must stay green.
- No other reader of the evidence string.

## Acceptance

```yaml
must:
  - id: M1
    text: an unknown ci record's evidence names the repo and a cause class (HTTP status, timeout, no workflow runs, invalid response)
  - id: M2
    text: one repo failing does not hide a degraded result from another repo
  - id: M3
    text: degraded evidence names the workflow and branch of the run checked
must_not:
  - id: N1
    text: the token, Authorization header or a raw response body appears in evidence, stderr or Slack text — test fetch raises an error whose message contains the token; red today only if the new code stringifies it, so the test also asserts the stderr line equals the fixed format
  - id: N2
    text: healthy/degraded classification, debounce counters or data keys change for any existing test scenario — the existing ci tests in test_hermes.py stay green unedited
  - id: N3
    text: every failure is still reported as the bare text "CI status source unavailable" — red today (fixed string)
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: pytest scripts/tests/hermes/test_hermes.py -k ci
    intent: A CI page tells the operator which repo and workflow failed and why, and never leaks the GitHub token.
  - id: E2
    proves: [M1, N2]
    kind: offline
    command: pytest scripts/tests/hermes
    intent: Fixing the CI message does not change any other Hermes alert or auto-repair behaviour.
  - id: E3
    proves: [M1, M3]
    kind: live
    command: after hub-promote, read-only run of the ci sensor on m5-air and the next unknown or degraded log line (Claude or operator)
    intent: The next real CI page on the hub names the repo, workflow, branch and cause.
interface: none
```

Positive control for N1 and M2: in the same test, a healthy second repo and a degraded second repo run through the same fixture, so
a test that never reaches the error path cannot pass. The fetch stub is built from the real shape in `test_hermes.py:1458-1467`
(GitHub `workflow_runs` and `check_runs` payloads); error classes are the real `urllib.error` types raised by `_http_json`.

**Intent approved:** operator, 2026-11-16
**Approval note:** ("Approve all 9")

## Worker definition of done

- Only the two Files edited; `ci()` returns the same `data` keys and statuses for every existing test.
- New tests for M1 (HTTP 502, timeout, no runs), M2 (two repos, one fails, one degraded), M3, N1 (token in exception message);
  N3 shown red on the pre-fix code (stash the sensors.py change).
- `pytest scripts/tests/hermes` green; commit and push verified with `git log origin/<branch>`; no cluster or Slack call.
