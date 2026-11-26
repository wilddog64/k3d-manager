# Bug: notification routing (v1.46.0 plan 2) — combine-review MINOR findings batch

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** v1.46.0 plan 2 (`496479d7`, `0362cf9d`, `5c0bfc6a`, `dfb2e814`; unreleased)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Fable combine review, 2026-11-26)
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Severity:** low — hygiene, test-control and docs gaps; no spill or leak found (MAJOR M1 and MINOR m1, m2 fixed in p2e)
**Filed:** 2026-11-26, Claude, from the Fable combine review (operator approved "other MINORs as P3 captures")

Each item names file:line and a fix; split by file at triage if dispatched.

1. **m3** `bin/k3dm-cloud-bridge:366` — `_request_body` merges `{**args, **fixed}` for dict-fixed actions; only the args
   allowlist and the webhook's conflict 400 stop an args `channel_id`. Fix: strip `channel_id`, `thread_ts`,
   `response_url` in `_request_body`, plus a `sandbox-up` case in `test_route_fields_and_slack_context`.
2. **m4** `bin/k3dm-cloud-bridge:391` vs `bin/k3dm-webhook:755` — conflict reason is a literal in the bridge. Fix:
   `notify_routes.CONFLICT_REASON` used by both.
3. **m5** `bin/k3dm-webhook-doctor:258-271` — parses raw `security` stdout without stripping; a 512-byte map reads
   `invalid` in the doctor but `ok` in `load_routes`; reads the shell's env, not launchd's. Fix: call `load_routes()`.
4. **m6** — three copies of `&<>` escaping (`notify_routes.escape_label`, `cloud_approval._safe`,
   `render._redact_thread_question`). Fix: one helper.
5. **m7** `bin/k3dm-webhook:2665` — routability hard-coded; upgrade, cluster-resume/refresh, analyze, ask and make
   `help` silently ignore `notify_route`. Fix: reject it on every handler that does not support it.
6. **m8** `bin/k3dm-webhook:2879-2882` — make "queued" header posted via `_start_bot_thread` outside `_notify_job`; a
   failed first post leaves no `delivery.jsonl` line. Fix: record it with `notify_route`.
7. **m9** umbrella spec — "no route = byte for byte" is not literal: unrouted `delivery.jsonl` records now carry
   `"notify_route": null`. Fix: amend the sentence.
8. **m10** `bin/k3dm-webhook:1180-1193`, `scripts/lib/webhook/agent.py:50-59` — a thread `ask` in a routed job's thread
   answers via `SLACK_CHANNEL_ID` with a foreign `thread_ts` (lost or misplaced); `_copy_thread_context` does not copy
   `notify_route`. Fix: document the limit in `docs/howto/webhook-operations.md` (or carry the channel).
9. **m11** docs — `docs/howto/webhook-operations.md:9` channel table omits routed jobs;
   `docs/howto/cloud-session-requests.md:268` omits the local CLI refusal and the execute-time rejection; the
   Notification routes section lacks the alias/channel patterns and no-duplicate rule; umbrella card wording stale.

Related, pre-existing (not routing): unrouted make output is also posted unescaped to `SLACK_CHANNEL_ID`
(`make-find-similar-docs` echoes `Q`); p2e escaped routed jobs only.
