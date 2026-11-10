# Bug: a `/hermes-auth` re-auth lasts 24h and covers every decision in that window

**Status:** OPEN — filed 2026-11-09
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-09
**Introduced by:** `4b6ce874` (v1.33.0, Hermes Slack approvals)
**Should have been caught by:** spec
**Prior art:** not run (`make find-similar-docs` could not reach its vector store from the M4, 2026-11-09: context
`k3d-k3d-cluster` does not exist); exact-slug glob found nothing; read
`docs/bugs/2026-11-08-hermes-card-replaced-by-reauth-reply.md`, a different defect in the same handler
**Severity:** low — hygiene: a stale re-auth lets any later Approve or Deny through for up to 24h; the allowlist and
the Slack signature still apply
**Approval:** operator, 2026-11-09 ("go ahead for that": 10 minutes plus one use per grant, dispatched with the
reauth-reply P3; a TOTP second factor goes to `docs/ideas.md`)
**Intent approved:** operator, 2026-11-09, E1 only; E2 not yet approved
**Filed:** 2026-11-09
**Detected by:** operator, 2026-11-09 ("24h is too long")
**Affected:** `workers/slack-relay/index.js`
**Branch:** `k3d-manager-v1.43.16`
**Related:** `docs/bugs/2026-11-08-hermes-card-replaced-by-reauth-reply.md` and
`docs/bugs/2026-11-08-slack-hostinger-status-duplicates-cluster-status.md` (same file, both P3; dispatch the three
together). Land this no earlier than the reauth-reply fix: with a 10-minute re-auth, a lapsed click happens on most
cards, and without that fix it deletes the card.

## Symptom

`/hermes-auth` replies "Re-authenticated for 24h". For the next 24 hours every Approve or Deny click by that user is
accepted without asking again.

## Root cause

`workers/slack-relay/index.js:3` sets `REAUTH_TTL_SECONDS = 86400`, and `:398` writes `reauth:<user>` with it. The
interactivity handler (`:267`) only checks that the key exists and never removes it. The v1.33.0 plan
(`docs/plans/v1.33.0-hermes-slack-approval.md:151`) counted on Slack workspace MFA as the real factor, but Slack MFA
applies at login, not per command, so the re-auth is a confirmation of intent, and 24h is far longer than one
decision needs.

## Fix

1. `REAUTH_TTL_SECONDS = 600`.
2. One use per grant: when an Approve or Deny passes every guard, delete `reauth:<user>` before writing the approval
   or replacing the card. If the delete throws, store no approval and do not replace the card. A refused click
   (not allowlisted, no re-auth, approvals not configured, bad action value) deletes nothing.
3. Texts: the `/hermes-auth` reply says the re-auth lasts 10 minutes and covers the next Approve or Deny; the
   re-auth prompt drops "(valid for 24h)" and says the same.
4. `docs/guides/hermes.md:77`: 10 minutes, one decision per `/hermes-auth`. In
   `docs/bugs/2026-11-08-hermes-card-replaced-by-reauth-reply.md`, change the workaround line ("A reauth lasts 24h")
   and the E2 intent's "24h" to "10 minutes".

## Files

- `workers/slack-relay/index.js`
- `workers/slack-relay/test/relay.test.mjs`
- `docs/guides/hermes.md`
- `docs/bugs/2026-11-08-hermes-card-replaced-by-reauth-reply.md`

Run with `node --test workers/slack-relay/test/relay.test.mjs`.

## Do not

- Change the approver allowlist, the Slack signature check, the `approval:<id>` key or its 3600 s TTL, or the drain
  endpoint.
- Make the TTL configurable, or below 60 s (Cloudflare's minimum).
- Add a second factor (TOTP). That is an idea row, not this fix.
- Deploy the worker. The operator runs `make deploy-worker` after the land (Keychain secrets; not the GitHub
  workflow, which re-uploads stale secrets).

## Contract readers

The `reauth:<slack_user_id>` KV key, found by `git grep "reauth:"`:

- `workers/slack-relay/index.js:398` writes it: changes (TTL 600).
- `workers/slack-relay/index.js:267` reads it: changes (deletes it after a successful decision).
- `workers/slack-relay/test/relay.test.mjs:94,126,136,156-160` seed or assert it: :156-160 changes (600); the seeds
  stay, since one decision per test still passes.
- No other component reads the key: Hermes on the hub polls `approval:<id>` through the drain endpoint, not `reauth:`.

Docs naming 24h: `docs/guides/hermes.md:77` and the reauth-reply bug doc change (Fix 4). The v1.33.0 and v1.43.11
plans and the 2026-09-07 audit are history and stay as written.

## Proof of external behaviour

Cloudflare Workers KV docs, read 2026-11-09 (Write key-value pairs and Delete key-value pairs, updated 2026-06-22;
How KV works, updated 2026-04-21):

- `expirationTtl`: "The minimum value is 60." So 600 is valid.
- Writes are "immediately visible to other requests in the same global network location"; changes "may take up to
  60 seconds or more to be visible in other global network locations", and the docs advise not to rely on same-location
  visibility.

So the one-use delete stops reuse from the same Cloudflare location at once, but a second click served by another
location within about 60 s could still find the key. That is a known limit, below.

## Known limits (not fixed here)

- KV is eventually consistent: a reused grant can pass for about 60 s from another Cloudflare location. Closing that
  needs a Durable Object or a strongly consistent store.
- Anyone with the approver's Slack session can run `/hermes-auth` themselves. Only a real second factor (TOTP idea
  row) addresses that.

## Acceptance

```yaml
must:
  - id: M1
    text: "/hermes-auth from an allowlisted user stores reauth:<user> with expirationTtl 600, and the reply says 10 minutes"
  - id: M2
    text: "an allowlisted user with a reauth key who presses Approve gets the approval stored and the card replaced, and the reauth key is gone afterwards"
  - id: M3
    text: "the same holds for Deny: the card is replaced and the reauth key is gone afterwards"
  - id: M4
    text: "a click refused for any reason (not allowlisted, no reauth key, approvals not configured, malformed action value) leaves an existing reauth key in place"
must_not:
  - id: N1
    text: "/hermes-auth stores the reauth key with expirationTtl 86400 or any value above 600 (red on pre-fix code; paired with M1)"
  - id: N2
    text: "a second Approve or Deny by the same user after one successful decision, with no new /hermes-auth, stores an approval or replaces the card (red on pre-fix code; paired with M2)"
  - id: N3
    text: "an approval is stored or the card replaced when deleting the reauth key fails"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3]
    kind: offline
    intent: "tests run the real relay worker against a fake approvals store: /hermes-auth grants 10 minutes, one Approve or Deny uses the grant up, a second click is refused until /hermes-auth is run again, refused clicks don't use it up, and nothing is approved if the grant can't be removed"
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: "after make deploy-worker, the operator runs /hermes-auth (reply says 10 minutes), approves or denies one Hermes card, then presses a button on a second card and is asked to re-authenticate, with that card left in place"
interface:
  - "workers/slack-relay/index.js default export fetch(req, env, ctx) on POST / with command=/hermes-auth, and on POST /slack/interactivity with the response_url fetch captured"
  - "the approvals KV binding APPROVALS_KV (get, put with expirationTtl, delete) and the APPROVER_ALLOWLIST secret"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (restore 86400, skip the delete, ignore a failed
   delete), run its test, show it red, then restore the guard and show it green. List any `must_not` whose test
   stayed green with the guard broken.
3. No read-only real-data run is possible: the store is Cloudflare KV behind the deployed worker. Say so.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- Dispatch in one batch with the reauth-reply P3 (and the hostinger-status P3, same file) once there is room under
  the WIP limit. Fold the three specs into one dispatch; the reauth-reply guard fix goes first in the diff.
- E2 needs the relay redeployed, so it waits for the operator's `make deploy-worker` after the land.
