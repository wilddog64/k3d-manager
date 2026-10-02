# `ask-docs` follow-ups typed in a thread are silently dropped

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. `/ask-docs` now opens a thread (fix `61d6d3fb`). A follow-up typed in that
thread as `ask-docs <question>` gets no reply at all. The same follow-up as `ask <question>`
answers in the thread, so the two commands behave differently.
**Status:** OPEN
**Related:** `2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`

## Observed (operator, 2026-10-01; webhook log)

```
[slack/events] type='message' thread_ts='1790911170.253589' … text="ask-docs what's recent issue regarding to slack and webhook "
[slack/events] thread reply — thread_ts='1790911170.253589' job_id='373d6d74' cmd='ask-docs'
```

Nothing follows. Job `373d6d74` is the `/ask-docs` job that owns the thread, so routing found it.

## Cause

In `bin/k3dm-webhook`, `_handle_thread_command` returns early:

```python
if not command.strip().startswith("/") and cmd not in _THREAD_COMMANDS:
    return
```

- `_THREAD_COMMANDS` has `ask`, but not `ask-docs`.
- There is no `ask-docs` branch either, so a `/ask-docs` typed in the thread falls through to
  "Unknown command".

## Fix

Only `bin/k3dm-webhook` and the tests change. Do **not** touch `CHANGELOG.md`: Claude adds that
bullet, because another Codex run is editing it in parallel. Do not touch the relay,
`scripts/lib/webhook/ask_docs.py`, `render.py` or `agent.py`.

1. Add `"ask-docs"` to `_THREAD_COMMANDS` and to `_STANDALONE_CMDS`. The standalone entry lets a
   top-level `ask-docs …` message in the channel work the same way `ask …` does.
2. In `_handle_thread_command`, add an `elif cmd == "ask-docs":` branch, modelled on the `ask`
   branch:
   - The question is everything after the first word; keep a leading `--sources`/`-s` as part of
     it, since `_run_ask_docs` already handles the flag.
   - Empty question, or only the flag → `_notify_job(job_id, "Usage: \`ask-docs [--sources] <question>\`")`
     and return.
   - Apply the same `_sanitize_question` as `ask`. If it is rejected, send the same rejection
     message.
   - Do **not** prepend job output context. `ask-docs` is retrieval over docs, not a
     cluster investigation.
   - Create a sub-job dir: `status` `queued`, `action` `ask-docs`, and `thread_ts` copied from
     the parent job when it exists.
   - Start `_run_ask_docs(new_job_id, question, "", thread_ts)` with **no** `channel_id`.
     `bot_thread` is then false and `response_url` is empty, so the answer goes through
     `_notify_job(new_job_id, …)`, which posts into the copied `thread_ts`. Do not change
     `_run_ask_docs`.
   - Acknowledge with `_notify_job(job_id, "📚 Searching docs…")`.
3. In `_find_job_by_thread_ts`, skip sub-jobs whose `action` is `ask-docs`, the same way it
   skips `ask` sub-jobs, so routing keeps finding the parent job.
4. Add `ask-docs` to the "Unknown command" help string.
5. Role: `_thread_command_min_role("ask-docs")` already defaults to `reader`, which matches the
   `/api/v1/ask-docs` route. Leave `policy.py` alone; add a test that asserts `reader`.

## Tests

Add to `scripts/tests/bin/test_webhook_ask_delivery.py`, or a new
`scripts/tests/bin/test_webhook_ask_docs_thread.py` that uses the same harness. Use a temporary
`K3DM_JOB_DIR`, stub `_run_ask_docs` / `ask_docs.answer` and `_post_slack_bot`, and run the
started thread synchronously or join it.

- `ask-docs what is X` in a thread whose parent job has `thread_ts=T`:
  - one sub-job with `action=ask-docs` and `thread_ts=T`;
  - `_run_ask_docs` is called with that question and an empty `channel_id`;
  - the answer reaches `_post_slack_bot` with `thread_ts=T`.
- `ask-docs --sources what is X` → `_run_ask_docs` receives `--sources what is X`.
- `ask-docs` with no question, or only `--sources`, → a usage notify and no sub-job.
- `/ask-docs what is X` typed in the thread takes the same path; no "Unknown command".
- `_find_job_by_thread_ts(T)` returns the parent, not the `ask-docs` sub-job.
- `_thread_command_min_role("ask-docs") == "reader"`, and a reader role is allowed.
- The question text appears in no log line (use capsys/caplog). Only `cmd='ask-docs'` may be logged.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) remove `"ask-docs"` from `_THREAD_COMMANDS` → thread test red;
(b) drop the `ask-docs` skip in `_find_job_by_thread_ts` → routing test red;
(c) pass `channel_id=SLACK_CHANNEL_ID` → the answer opens a new top-level header instead of going
    in the thread, so the thread test is red.

## Rules

- `pytest` on the touched test file is green. `pytest scripts/tests/bin/test_webhook_ask_delivery.py`
  and `scripts/tests/bin/test_role_capabilities.py` stay green.
- `python3 -m py_compile bin/k3dm-webhook` passes.
- No network, no real Slack, no live webhook restart.
- Leave changes uncommitted. Update this doc: Status FIXED and a short Resolution section.

## Operator step after the fix

Run `make restart-webhook`. The relay is unchanged: thread replies come in via `/slack/events`.
