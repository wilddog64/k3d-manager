# Bug: a rejected Slack bot post leaves no reason in the webhook log

**Status:** DISPATCHED — 2026-10-23
**Priority:** P3
**Severity:** low — delivery falls back correctly; only the diagnosis is blind
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, after status-channel E3 failed twice with no recorded cause
**Approval:** explicit 2026-10-23. The operator said: "go for your suggestion".
**Related:** `docs/bugs/2026-10-23-api-cluster-status-posts-to-command-channel.md`

**Component:** `scripts/lib/webhook/render.py` (`_post_slack_bot`)

## Problem

`_post_slack_bot` returns `""` when Slack answers `ok: false`, and also on any exception. It records
nothing either way. On 2026-10-23 the status report's post to `K3DM_STATUS_CHANNEL_ID=C4CAEH8HX`
was rejected twice (jobs `c4b35b3c`, `28b9778a`). Both reports fell back to `C0B7ZHG2LR4`, and there
is no way to tell which cause it was: `channel_not_found`, `not_in_channel`, `missing_scope` or a
network error.

## Fix

### F1. Log the rejection

In `_post_slack_bot`, use `webhook.log.get_logger` (the module's logger, e.g. `webhook.render`):

- On `ok: false`, log at warning: `slack chat.postMessage rejected channel=<channel> error=<error>`,
  where `<error>` is Slack's `error` field (`unknown` if absent). If Slack sends a `needed` field
  (missing scope), include `needed=<value>`.
- On an exception, log at warning: `slack chat.postMessage failed channel=<channel> error=<ExceptionClassName>`.
- The return values stay as they are.

The log line must never contain the bot token, the `Authorization` header, the message text or
`thread_ts`. Channel IDs are not secret.

## Tests

`scripts/tests/bin/test_slack_bot_post_logging.py` (new; stub `urllib.request.urlopen`, set a fake
token via monkeypatch; no network):

1. `{"ok": false, "error": "not_in_channel"}` returns `""` and logs one warning naming
   `not_in_channel` and the channel ID.
2. `{"ok": false, "error": "missing_scope", "needed": "chat:write"}` logs `needed=chat:write`.
3. `urlopen` raising `URLError` returns `""` and logs `URLError`.
4. With a fake token `xoxb-TESTTOKEN` and text `SECRET-BODY`, no log record contains either.
5. `{"ok": true, "ts": "1.2"}` returns `"1.2"` and logs no warning.

Show tests 1 and 3 red against the pre-fix `render.py`.

## Files

- `scripts/lib/webhook/render.py`
- `scripts/tests/bin/test_slack_bot_post_logging.py` (new)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A Slack chat.postMessage rejection is logged at warning with the channel ID and Slack's error code (and the needed scope when Slack names one).
  - id: M2
    text: A transport failure is logged at warning with the channel ID and the exception class.
  - id: M3
    text: _post_slack_bot's return values are unchanged (ts on success, empty string on any failure).
must_not:
  - id: N1
    text: No log record may contain the bot token, the Authorization header, the message text or thread_ts.
  - id: N2
    text: Tests must not call Slack or any network endpoint.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2]
    text: pytest test_slack_bot_post_logging.py green; tests 1 and 3 red on the pre-fix render.py.
  - id: E2
    kind: live
    proves: [M1]
    text: After make restart-webhook, Claude files a cluster-status cloud request and reads the Slack error for the status-channel post from the webhook log.
interface:
  - webhook.render._post_slack_bot(text, thread_ts=None, channel_id=None)
  - stderr log records from webhook.log.get_logger (K3DM_LOG_LEVEL)
```

## Definition of Done

- [ ] F1 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_slack_bot_post_logging.py` green, plus the existing webhook status tests (`test_webhook_cluster_status_thread.py`); paste summaries.
- [ ] Tests 1 and 3 shown red on a temp copy of the pre-fix `render.py`.
- [ ] Commit: `fix(webhook): log the Slack error when a bot post is rejected`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT call Slack, read the real bot token, or restart the webhook.
- Do NOT change delivery or fallback behaviour.
- Do NOT modify files outside the Files list.
