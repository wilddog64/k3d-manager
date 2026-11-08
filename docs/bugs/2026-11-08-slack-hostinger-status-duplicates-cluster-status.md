# Bug: `/hostinger-status` duplicates `/cluster-status hostinger`, and in Slack it does not respond

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** pre-existing (`/hostinger-status` added in v1.7.1, `0c9b2707`; `/cluster-status [provider]` later
covered the same checks)
**Should have been caught by:** live check
**Severity:** low — confusing duplicate command; workaround: `/cluster-status hostinger`
**Approval:** operator, 2026-11-08 ("go ahead to do that, and I will remove hostinger-status")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, Slack, 2026-11-08 (screenshots: `/hostinger-status` → "failed because the app did not
respond"; `/cluster-status hostinger` → HEALTHY, 21 ok / 0 warn / 0 fail)
**Affected:** `workers/slack-relay/index.js`, `scripts/lib/webhook/make_targets.py`, `docs/howto/slack-slash-commands.md`
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-07-01-slack-manifest-drift.md` (CLOSED; same class: live Slack app settings drifted from the
documented manifest); `docs/bugs/2026-11-08-webhook-gemini-ask-has-no-collected-data.md` (reuses the Hostinger
collector behind `/api/v1/hostinger-status`)

## Symptom

On 2026-11-08 the operator ran `/hostinger-status` in Slack and got "/hostinger-status failed because the app did not
respond". A minute later, `/cluster-status hostinger`, sent through the same relay URL, returned the full Hostinger
report. The relay answers `/hostinger-status` at once (`workers/slack-relay/index.js:460-468`), so the Slack app's
own setting for that command is the likely fault. The operator chose to retire the command, not repair it.

## Root cause

Two Slack commands give the same report:
- `/hostinger-status` → `/api/v1/hostinger-status` → `_run_hostinger_status` (`status.py:401`): service smoke checks
  only.
- `/cluster-status hostinger` → `/api/v1/cluster-status` → `_run_cluster_status` (`status.py:141`): the same smoke
  checks plus credential and hub or tunnel checks, and on failure pod state and a Gemini diagnosis.

Nobody used the smaller command, so nothing noticed when its Slack app setting broke.

## Fix

Retire the Slack slash command only.
- `workers/slack-relay/index.js`: remove `/hostinger-status` from `ALLOWED_COMMANDS` (line 1), from the role map
  (line 12), and remove its handler (lines 460-468).
- `scripts/lib/webhook/make_targets.py:69`: remove the `/hostinger-status` row from the `/k3dm help` list.
- `docs/howto/slack-slash-commands.md`: remove it from the command list (line 4), the reader role row (line 70), the
  manifest (lines 167-173) and the command table (line 350). Add one line saying that Hostinger status is
  `/cluster-status hostinger`.
- `scripts/tests/plugins/slack_slash_commands.bats`: the tests that require `/hostinger-status` (lines 13, 39, 75,
  96-105) now require its absence, and `/cluster-status` stays present.

Keep, unchanged: the webhook route `/api/v1/hostinger-status`, `_run_hostinger_status`, `policy.py`, and
`cloud_actions.py`. Cloud sessions call that route (`docs/howto/cloud-session-requests.md:69`), and the Gemini-ask
fix reuses its collector.

## Files

- `workers/slack-relay/index.js`
- `scripts/lib/webhook/make_targets.py`
- `docs/howto/slack-slash-commands.md`
- `scripts/tests/plugins/slack_slash_commands.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "the relay rejects /hostinger-status like any unknown command, and still accepts /cluster-status"
  - id: M2
    text: "the /k3dm help text and the slash-command howto and manifest no longer list /hostinger-status, and the howto names /cluster-status hostinger for Hostinger status"
  - id: M3
    text: "the webhook API route /api/v1/hostinger-status still exists with its reader role (paired control: only the Slack command is retired)"
must_not:
  - id: N1
    text: "the relay, /k3dm help, the howto or its manifest still lists /hostinger-status"
  - id: N2
    text: "/cluster-status, the webhook hostinger-status API route, policy.py or cloud_actions.py changes"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: "tests read the relay's allowed commands and role map, the /k3dm help text and the slash-command howto, and check that /hostinger-status is gone from each while /cluster-status and the webhook's hostinger-status API route remain"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the operator deletes /hostinger-status from the Slack app and the relay is redeployed, /k3dm help no longer shows it and /cluster-status hostinger still returns the Hostinger report"
interface:
  - "workers/slack-relay/index.js ALLOWED_COMMANDS and its command-role map"
  - "scripts/lib/webhook/make_targets.py CLUSTER_COMMANDS (rendered by /k3dm help)"
  - "docs/howto/slack-slash-commands.md (command list, role table, manifest JSON, command table)"
  - "bin/k3dm-webhook route table entry /api/v1/hostinger-status"
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

- Operator step, not part of the dispatch: delete `/hostinger-status` under api.slack.com → the app → Slash Commands.
  The operator said on 2026-11-08 they will do it.
- The relay only changes once it is redeployed. Check
  `reference_deploy_worker_workflow_overwrites_relay_secrets` before any redeploy.
- No file overlap with the open dispatches or with the Gemini-ask P3 (which touches `agent.py`, `status.py` and
  `bin/k3dm-webhook`), so it can go out on its own or batched with another P3 on the relay or the howto.
- First-pass trial dispatch 2 of 3 (`docs/howto/dispatch-first-pass-trial.md`).
