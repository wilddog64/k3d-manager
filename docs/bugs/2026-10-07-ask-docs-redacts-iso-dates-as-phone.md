# ask-docs redacts ISO dates as phone numbers

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** FIXED in branch; live Slack verification pending
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
