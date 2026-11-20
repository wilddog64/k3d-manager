# Bug: the approvals drain is blocked by Cloudflare (Python's default User-Agent), so every Slack Approve is silently lost

**Status:** OPEN — spec written 2026-11-20, dispatch to Flash approved by operator
**Priority:** P1 (operator, 2026-11-20: "approve P1, and dispatch to Flash") — blocks the v1.45.0 release PR
**Introduced by:** pre-existing (`scripts/lib/hermes/approvals.py`, v1.33.0 4b6ce874; Cloudflare UA block first recorded 2026-11-13)
**Should have been caught by:** spec (v1.44.0 `docs/plans/v1.44.0-hermes-slack-config-sensors.md` found the rule, capture 3b, but fixed only the sensors; child B `docs/bugs/2026-11-14-dispatch-stall-b-approval.md` reused `approvals.py` without the header)
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-20
**Approval:** operator 2026-11-20 ("approve P1, and dispatch to Flash"; "go ahead with (a)": spec + dispatch, not a direct edit)
**Intent approved:** operator, 2026-11-20
**Intent approval note:** ("intents approve")
**Prior art:** docs/plans/v1.44.0-hermes-slack-config-sensors.md (exact grep "User-Agent") — same Cloudflare rule, fixed for sensors only; `make find-similar-docs` unavailable (vector store needs the dead M4 k3d context)
**Release:** v1.45.0 (P1 on the open release)

## Symptom (live, Claude, m4-air.local, 2026-11-20 ~15:48Z, Python 3 urllib, relay `https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals`)

During child B E9 the drain posted its card, then its health probe posted "the drain token on this Mac is rejected by the relay".
A read-only probe with the M4 Keychain token (value never printed):

| Request | Result |
|---|---|
| default User-Agent (`Python-urllib/3.x`), real token | **403**, body `error code: 1010`, `server: cloudflare` |
| `User-Agent: k3dm-dispatch-recover/1`, real token | **200** |
| `User-Agent: k3dm-dispatch-recover/1`, wrong 64-char token | **401** `Unauthorized` (the relay's own answer) |

The relay itself never answers 403: `workers/slack-relay/index.js:212-219` returns 401 for a bad token. The 403 is Cloudflare
rejecting the client signature before the Worker runs. Same finding as capture 3b in the v1.44.0 sensor plan (2026-11-13T01:41Z,
"default User-Agent Python-urllib gets 403 ... k3dm-hermes/1 gets 401").

`fetch_approvals` maps every error to `[]` (`scripts/lib/hermes/approvals.py:30-33`), so the drain silently sees an empty queue:
- M4 `bin/k3dm-dispatch-recover`: no dispatch Approve is ever seen (E9 blocked).
- M5 `bin/k3dm-hermes` `_drain_approvals` (`:326-335`) uses the same functions, so Hermes repair approvals from Slack are
  also lost (inferred from the shared code path; not probed on the M5 — over ssh its Keychain reads empty).

## Fix

1. `scripts/lib/hermes/approvals.py`: import `HERMES_USER_AGENT` from `hermes.sensors` (one definition, `sensors.py:31`
   `"k3dm-hermes/1"`; no import cycle: `sensors.py` imports only `hermes.records` and `hermes.e2e_triage`). Add
   `"User-Agent": HERMES_USER_AGENT` to the headers of the GET in `fetch_approvals` (`:28-29`) and the DELETE in
   `delete_approval` (`:49-50`). Authorization header, timeouts, `_usable`, id patterns and fail-closed behaviour unchanged.
2. `bin/k3dm-dispatch-recover` `_health_probe` (`:134-143`): add the same `User-Agent` header (import `HERMES_USER_AGENT` from
   `hermes.sensors` beside `_keychain_secret`, `:24`). Nothing else in the script changes.

Out of scope: `scripts/lib/hermes/slack.py` `post_summary` / `post_interactive` post to the Slack incoming webhook
(hooks.slack.com, not Cloudflare); they work with the default UA today (the E9 card was posted 2026-11-20 15:40Z). Do not touch.

## Contract readers

Contract: requests to the relay drain route `/hermes/approvals` (GET list, DELETE `/<id>`), now with `User-Agent: k3dm-hermes/1`.
- Writers of requests: `scripts/lib/hermes/approvals.py:28-29` (GET), `:49-50` (DELETE); `bin/k3dm-dispatch-recover:136` (`_health_probe` GET). All change.
- Callers (unchanged, gain the header through the functions): `bin/k3dm-hermes:326,330,335`; `bin/k3dm-dispatch-recover:216,221,225,229,236,266`.
- Reader: `workers/slack-relay/index.js:212-244` (`drainAuthorized`, `handleDrain`): reads only `Authorization`; no change. Cloudflare in front: the block is outside the repo.
- Existing constant: `scripts/lib/hermes/sensors.py:31` `HERMES_USER_AGENT`, used at `bin/k3dm-hermes:29,92,104` and by the sensors; unchanged.
- Tests that capture headers: `scripts/tests/hermes/test_approvals.py:34-38` (`fake_opener` records `dict(request.header_items())`; urllib stores the key as `User-agent`), `scripts/tests/hermes/test_dispatch_recover.py:44` (stubs `_health_probe`).

## Acceptance

```yaml
must:
  M1: fetch_approvals sends its GET with header User-Agent k3dm-hermes/1 and the same Authorization Bearer header as today
  M2: delete_approval sends its DELETE with header User-Agent k3dm-hermes/1 and the same Authorization Bearer header as today
  M3: bin/k3dm-dispatch-recover _health_probe sends its GET with header User-Agent k3dm-hermes/1 and the Authorization header
  M4: the value comes from hermes.sensors.HERMES_USER_AGENT (one definition), not a new string literal
must_not:
  N1: any request built by fetch_approvals, delete_approval or _health_probe goes out without a User-Agent header (urllib would then send Python-urllib/3.x, which Cloudflare blocks with 1010)
  N2: the drain token appears in the User-Agent or in any header other than Authorization
  N3: the existing fail-closed, id-pattern and authorization behaviour changes (every existing scripts/tests/hermes test passes unchanged)
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, intent: "You will see tests that capture the request each approvals function builds and check it carries User-Agent k3dm-hermes/1 next to the unchanged Bearer header, and that the token is only in Authorization. On today's code the User-Agent check fails, so the tests are red before the fix."}
  - {id: E2, proves: [M3, N1, N2], kind: offline, intent: "You will see a test that captures the drain's health-probe request through a stub urlopen and finds User-Agent k3dm-hermes/1 and the Bearer header; red on today's code. As a positive control the same stub answering 403 still makes the probe return 403."}
  - {id: E3, proves: [M4, N3], kind: offline, intent: "You will see the whole scripts/tests/hermes suite pass with no existing test edited, and a check that approvals.HERMES_USER_AGENT is the same object as sensors.HERMES_USER_AGENT."}
  - {id: E4, proves: [M1, N1], kind: live, intent: "You will see Claude on the M4, after the fix lands, run fetch_approvals against the real relay with the Keychain token (never printed) and get a list back instead of the silent empty list; the same probe without the header still gets Cloudflare 403 1010, captured beside it. Run by Claude."}
  - {id: E5, proves: [M1, M2], kind: live, intent: "You will see child B E9 rerun on a fresh toy card: you press Approve and the drain resumes the toy once, which today cannot happen. Then on the M5, after a promote, Hermes drains a real r approval. Run by operator and Claude."}
interface:
  - "scripts/lib/hermes/approvals.py: fetch_approvals / delete_approval signatures unchanged; requests gain User-Agent"
  - "bin/k3dm-dispatch-recover: _health_probe(url, token) signature unchanged; request gains User-Agent"
```

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/approvals.py` | import `HERMES_USER_AGENT`; add the header to both requests |
| `bin/k3dm-dispatch-recover` | import `HERMES_USER_AGENT`; add the header in `_health_probe` |
| `scripts/tests/hermes/test_approvals.py` | new tests E1, E3 (existing tests untouched) |
| `scripts/tests/hermes/test_dispatch_recover.py` | new test E2 (existing tests untouched) |

## Worker definition of done

- Change only the files in the table. Offline only: no network, no Keychain, no Slack; stub `urlopen` / the opener. Scratch HOME.
- `/opt/homebrew/bin/python3 -m pytest scripts/tests/hermes -q`: show the new E1/E2 tests red on today's tree first, then green.
- Mutation: in a scratch copy, drop the header from each of the three requests in turn and show the matching test goes red.
- Lint: the pinned ruff the CI uses (`make lint` or the repo's pyflakes step) on the changed files; no unused imports.
- Paste each command, rc and proving lines; list every error seen. Leave changes uncommitted; do not push; no live check (E4, E5 belong to Claude and the operator); do not touch `docs/bugs/`.
