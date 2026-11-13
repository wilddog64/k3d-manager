# Bug: Hermes "ci check unknown 30+ min" page names no repo, workflow or cause

**Status:** OPEN — captured 2026-11-13
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-13
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

## Fix (proposed, not approved)

- Catch errors per repo and keep the other repos' results. Evidence names the repo and the cause class. Examples: `wilddog64/k3d-manager: GitHub API HTTP 502`, `...: no workflow runs`, `...: timeout`. Never include the token or the response body.
- Log the exception class and HTTP status for every unknown, so the cause can be read later.
- Name the workflow and branch of the run that was checked, in both degraded and unknown evidence. Example: `wilddog64/k3d-manager CI@k3d-manager-v1.44.0 lint failure`.
- Optional, for the operator to decide: rename the page to `CI (GitHub Actions) status unknown 30+ min: <repo>: <cause>`.

## Acceptance (draft)

```yaml
must:
  M1: an unknown ci record's evidence names the repo and a cause class (HTTP status, timeout, no runs, invalid response)
  M2: one repo failing does not hide a degraded result from another repo
  M3: degraded and unknown evidence name the workflow and branch of the run checked
must_not:
  N1: the token, Authorization header or a raw response body appears in evidence, logs or Slack text
  N2: healthy/degraded classification or debounce changes for any existing test scenario
```
