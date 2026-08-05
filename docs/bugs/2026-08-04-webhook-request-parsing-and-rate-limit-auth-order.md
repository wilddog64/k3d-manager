# Webhook request parsing and rate-limit authentication order

## Target

Queue for **v1.23.0**. This is a follow-up to the shipped v1.21.0 webhook
hardening; do not mix it into the OpenLDAP migration.

## Problem

Three security/reliability gaps remain in `bin/k3dm-webhook`:

1. Both the Slack and bearer-authenticated POST paths call
   `int(self.headers.get("Content-Length", 0))` without handling malformed or
   negative values. `ValueError` escapes the request handler before its JSON
   error handling; a negative value also bypasses the maximum-body check.
2. The fixed-window limiter runs before Slack signature or bearer-token
   authentication and shares only `slack`/`api` buckets. Unauthenticated noise
   can exhaust the legitimate request budget for the current minute.
3. The Slack role map currently maps an unknown or missing user to `reader`.
   A signed, unattributed event can therefore dispatch reader-level commands.
   The handler has no end-to-end coverage for this allowlist boundary.

Also guard `_verify_slack_signature`'s integer timestamp conversion. A malformed
timestamp must be rejected as an invalid signature rather than raise.

## Scope

Only these files may change:

| File | Change |
|---|---|
| `bin/k3dm-webhook` | bounded Content-Length reader; auth-ordered limiter; Slack sender gate |
| `scripts/lib/webhook/auth.py` | non-throwing Slack timestamp check and allowlist predicate |
| `scripts/tests/lib/webhook.bats` | raw-header, rate-order, and Slack-attribution regressions |

## Required changes

### 1. Safely parse request body length

Add one shared `_Handler` helper that returns either the raw request body or
`None` after sending the response. It must:

- treat a missing `Content-Length` as zero;
- return `400 {"error":"invalid content length"}` for a non-integer or a
  negative integer;
- return `413 {"error":"request too large"}` when the parsed length exceeds
  `MAX_BODY`;
- call `self.rfile.read(length)` only after those checks.

Use this helper for both `/slack/events` and every authenticated API POST
instead of direct `int(...)` calls. Preserve the existing `bad json` and
`body must be a JSON object` responses.

In `scripts/lib/webhook/auth.py`, wrap `int(timestamp)` and `raw_body.decode()`
inside `_verify_slack_signature`; malformed values return `False`.

### 2. Move rate limiting behind authentication

Remove the top-of-handler calls:

```python
if _rate_limited("slack" if self.path == "/slack/events" else "api"):
```

and:

```python
if _rate_limited("api"):
```

For bearer API POST and GET, authenticate first, then apply the existing `api`
bucket. This prevents unauthenticated traffic from consuming authenticated
capacity without changing bearer-token semantics.

For Slack, verify the signature, parse a valid JSON event, and establish an
allowlisted sender before applying a user-specific bucket:

```python
_rate_limited(f"slack:{ev_user}")
```

Keep URL-verification requests signature-protected and outside command dispatch.

### 3. Require an allowlisted Slack sender for command dispatch

Add `_slack_user_is_allowlisted(user_id)` in `scripts/lib/webhook/auth.py`.
It returns true only for a non-empty user ID present in `SLACK_ROLE_MAP`.

After extracting `ev_user`, but before creating a thread anchor or dispatching
`_handle_thread_command`, return `200 {"ok": true}` for a missing or
unallowlisted sender. Log only the event type, user ID, and that it was ignored;
never log the raw body.

Keep `_slack_user_role`'s reader fallback for defensive role normalization, but
do not use that fallback as authorization to execute a Slack command. A mapped
`reader` remains allowed to issue only reader-level commands.

## Regression gates

`scripts/tests/lib/webhook.bats` must cover all of the following:

1. Raw-socket POSTs with `Content-Length: nope` and `Content-Length: -1` return
   HTTP 400 for both API and Slack routes, and a following valid health request
   succeeds (the server thread survived).
2. `_verify_slack_signature` returns false for a non-numeric timestamp and
   non-UTF-8 body without raising.
3. With a temporary low rate limit, repeated unauthenticated API requests return
   401 but do not cause a following authenticated request to return 429.
4. A correctly signed Slack `/cluster-status` event from an unknown user and a
   correctly signed user-less event both return 200 but create no job/anchor and
   dispatch no command.
5. A correctly signed event from a mapped reader can still execute the existing
   reader-level `/cluster-status` path.

Run before commit:

```bash
python3 -m py_compile bin/k3dm-webhook scripts/lib/webhook/auth.py
bats scripts/tests/lib/webhook.bats
./scripts/k3d-manager _agent_audit
```

## Definition of done

- No direct unguarded `int(self.headers.get("Content-Length", 0))` remains.
- Invalid Content-Length receives a deterministic 400 response on both POST
  routes.
- Unauthenticated traffic cannot consume an authenticated rate-limit bucket.
- Slack commands require a non-empty allowlisted sender; unknown/user-less
  events cannot create jobs or anchors.
- All regression gates pass and the change is deployed with
  `make restart-webhook` only after source review/merge.
