# Threaded ArgoCD usage was posted twice

**Filed:** 2026-10-07
**Severity:** Medium — duplicate Slack guidance is confusing
**Status:** VERIFIED live 2026-10-09 — operator ran the Slack check script after relay deploy `b2ce7b54` (webhook restarted on `ef3eadb2`); behaviour confirmed in Slack, webhook job records carry `thread_ts`/`channel_id`.

## Evidence

An invalid threaded `/argocd-upgrade` request produced the same usage message both in the
originating thread and at channel level.

## Root cause and fix

The relay returned an in-channel slash-command acknowledgement while also posting the validation
response through the thread response path. Threaded validation errors now suppress the immediate
message and send one thread-aware `response_url` reply. Top-level validation errors retain one
normal acknowledgement.
