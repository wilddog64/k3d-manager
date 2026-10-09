# ask-docs redacts ISO dates as phone numbers

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** VERIFIED live 2026-10-09 — operator ran the Slack check script after relay deploy `b2ce7b54` (webhook restarted on `ef3eadb2`); behaviour confirmed in Slack, webhook job records carry `thread_ts`/`channel_id`.
**Severity:** Low — dates in sourced answers are obscured, reducing document-triage usefulness
**Component:** `scripts/lib/webhook/ask_docs.py` redaction

## Observed behavior

An ask-docs result displayed a source entry with its date as:

```text
Date: [REDACTED PHONE]
```

The source contained the ordinary ISO date `2026-10-06`. The answer scrubber's phone regex
accepted digit-and-hyphen sequences, so a ten-digit ISO date was incorrectly classified as a
phone number. This is a redaction false positive; the date is not sensitive data.

## Fix

Exclude the exact ISO date shape `YYYY-MM-DD` from phone-number masking while retaining the
existing masking for phone-like values. Credential, IP, and phone redaction behavior outside
this false-positive case is unchanged.

## Acceptance

- [x] `YYYY-MM-DD` remains visible in ask-docs titles, dates, excerpts, and source lists.
- [x] Real phone-number examples remain redacted.
- [x] Existing credential and IP scrubbing remains covered by the existing tests.
- [ ] Live Slack ask-docs response confirms dates are readable after webhook restart.

## Regression test

The ask-docs redaction tests cover an ISO date and a phone number in the same text, proving the
date survives while the phone value is masked.

## Live verification 2026-10-09

`/ask-docs when was the webhook audit log bug filed?` answered `2026-10-08`, not `[REDACTED PHONE]`.
The answer was not threaded because it was run in `#grafana-notification`; `/ask` and `/ask-docs`
open a bot thread only in the webhook's configured `SLACK_CHANNEL_ID` (by design, see
`2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`). Cosmetic: the model's
`**bold**` renders literally in Slack mrkdwn.
