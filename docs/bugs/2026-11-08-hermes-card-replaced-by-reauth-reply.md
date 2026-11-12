# Bug: clicking a Hermes card without a fresh `/hermes-auth` replaces the card with the reauth prompt, and its buttons are lost

**Status:** OPEN — filed 2026-11-08
**Priority:** P2 — raised from P3 2026-11-11 (operator: "go ahead with your recommendation"): the Slack Promote button (part 3 of the promote-smoothing idea) needs Hermes buttons to record every press; this bug drops a Deny. Target: v1.44.0, before part 3.
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Clicking a Hermes card without an active re-auth destroys the card's approval buttons, degrading the Slack approval flow, though workarounds exist (running `/hermes-auth` beforehand or approving via CLI on the hub)); Claude proposed P2. Agreed.
**Triage:** carry → v1.44.0 (Hermes relay batch) — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** `4b6ce874` (v1.33.0, Hermes Slack approvals)
**Should have been caught by:** live check
**Severity:** low — a pending repair card can no longer be approved or denied from Slack; workarounds: wait for Hermes
to post the repair again, or `bin/k3dm-hermes approve <id>` on the hub
**Approval:** operator, 2026-11-08 ("approved those two requests")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, Slack `#grafana-notification`, 2026-11-08. The k3d-manager card for `r9-d9add2e2` was posted
at 11:14 PST; the operator pressed Deny before running `/hermes-auth`. The card then read only "🔐 Re-authenticate
first: run `/hermes-auth` (valid for 24h)", with the card's own 11:14 timestamp and no "Only visible to you" label;
after `/hermes-auth` (11:47) the card no longer existed to deny (operator: "the 11:14 does not exist any more").
**Affected:** `workers/slack-relay/index.js`
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)
**Related:** `docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md` (also edits
`workers/slack-relay/index.js`; dispatch the two together); `docs/guides/hermes.md` setup step 3

## Symptom

A Deny (or Approve) click from a user with no `reauth:<user>` key in the approvals KV turns the whole card into the
reauth prompt. The repair's buttons are gone, so after `/hermes-auth` there is nothing left to click.

## Root cause

`handleInteractivity` (`workers/slack-relay/index.js:263-276`) answers the guard cases (approvals not configured,
user not allowlisted, no reauth) through `postResponseUrl` (`index.js:304-313`). That helper sends
`{text, response_type: "ephemeral"}` and no `replace_original`. Posting to a block action's `response_url` without
`replace_original: false` replaced the original message on the live workspace (2026-11-08 above: the reply took the
card's timestamp and is visible in-channel). Only Approve and Deny are meant to replace the card
(`replaceResponseUrl`, `index.js:321-328`, `replace_original: true`).

Proof of the external behaviour: the live 11:14 card above, Slack workspace of the operator, 2026-11-08, k3d-manager
app. The relay sent no `replace_original` key (code above), and the card was replaced.

## Fix

- The three guard replies in `handleInteractivity` send `replace_original: false` with `response_type: "ephemeral"`,
  so the card stays, with its buttons, and only the clicking user sees the prompt.
- Leave `postResponseUrl`'s other callers' bodies as they are, unless they also answer a block action (none does
  today; say so in the report). The simplest form is a `replaceOriginal` argument or a separate helper; the worker
  chooses and reports the choice.
- `replaceResponseUrl` (Approve and Deny) is unchanged.

## Files

- `workers/slack-relay/index.js`
- `workers/slack-relay/test/relay.test.mjs`

Run with `node --test workers/slack-relay/test/relay.test.mjs` (50 tests green on 2026-11-08 before the fix).

## Do not

- Change the reauth, allowlist or approval logic, the KV keys or their TTLs.
- Change the Approve or Deny replies.
- Deploy the worker. The operator runs `make deploy-worker` after the land.

## Acceptance

```yaml
must:
  - id: M1
    text: "a click from an allowlisted user with no reauth key gets the reauth prompt as an ephemeral reply with replace_original false, and no approval is stored"
  - id: M2
    text: "the not-allowlisted and approvals-not-configured replies are also ephemeral with replace_original false"
  - id: M3
    text: "Approve and Deny with a reauth key still replace the card (replace_original true), as today (control)"
must_not:
  - id: N1
    text: "a guard reply to a block action omits replace_original or sets it true (red on pre-fix code, which omits it; paired with M3)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1]
    kind: offline
    intent: "tests click a Hermes card's buttons as a user who has not re-authenticated, as one not on the approver list, and on a relay with no approvals store, and check each reply tells Slack to leave the card in place; a re-authenticated Approve and Deny still replace the card"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the relay is redeployed, the operator lets the 24h reauth lapse (or uses a second approver without one), presses Deny on a k3d-manager card, sees the reauth prompt as a private message while the card and its buttons stay, then runs /hermes-auth and denies the same card"
interface:
  - "workers/slack-relay/index.js default export fetch(req, env, ctx) on POST /slack/interactivity, with the response_url fetch captured"
  - "the approvals KV binding APPROVALS_KV and the APPROVER_ALLOWLIST secret"
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

- Bug and E1/E2 intents approved by the operator on 2026-11-08 ("approved those two requests").
- Batch with `docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md` (same file, both P3; CLAUDE.md
  P3 batching).
- Until it lands: run `/hermes-auth` before pressing a card's button. A reauth lasts 24h.

## Recurrence 2026-11-11: the reply does not say the decision was refused

- The operator pressed **Deny** on `r9-d9add2e2` (values_branch reapply, 11:53 PST) with an expired re-auth. The only reply
  was `🔐 Re-authenticate first: run /hermes-auth (valid for 24h)` (`workers/slack-relay/index.js:268`). Operator:
  "this is confusing as I don't know my denial is working or not".
- Nothing was recorded (the KV write happens only after the re-auth check), so the proposal simply expired after 30 min.
- Add to the fix: the refusal names the action and the outcome, e.g. `🔐 Your Deny of r9-d9add2e2 was NOT recorded:
  re-authenticate with /hermes-auth, then press again (expires HH:MM)`, and keeps the card's buttons (the original bug).
  A successful Deny should also reply as plainly as Approve does (`replaceResponseUrl … denied by <@user>`).
  Acceptance: a test per refusal path (no KV, not allowed, no re-auth) asserting the reply contains the action ID and
  "NOT recorded".
