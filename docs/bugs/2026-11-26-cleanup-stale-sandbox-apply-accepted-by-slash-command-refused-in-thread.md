# Bug: `apply` confirms stale-sandbox cleanup from the slash command but is refused as a thread command

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** `401e4eca` (v1.43.5, the thread command stopped accepting `apply`); the relay still accepts it since `d48e465f`
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-11-25-cloud-approval-card-wording-with-none-and-repair-dialog.md` (different command); `make find-similar-docs` not run
**Severity:** low — inconsistent vocabulary, no wrong action: the slash command's `apply` maps to `confirm: true` on `/api/v1/cleanup-stale-sandbox`
**Filed:** 2026-11-26, found in the blind reviews of v1.46.0 plan 3 (Fable subagent; Neon dispatch `v1460-plan3-review-neon`), Claude confirmed in code; operator: "File as bugs (Recommended)"
**Component:** `workers/slack-relay/index.js:54-57,515-529`; `bin/k3dm-webhook:1085-1092`

## Symptom (from code)

- `/cleanup-stale-sandbox apply` is accepted and sent as `confirm: true` (`workers/slack-relay/index.js:517-522`); its
  usage text advertises `apply` (`:54-57`).
- In a thread, `cleanup-stale-sandbox apply` replies "`apply` is no longer accepted — use `cleanup-stale-sandbox
  confirm`" (`bin/k3dm-webhook:1088-1090`); usage lists only `[preview|confirm]` (`:1092`).
- `bin/cleanup-stale-sandbox:7` accepts `--apply`.

## Fix options (for triage)

1. Drop `apply` from the relay (and its usage text), matching the thread command's deliberate removal.
2. Accept `apply` in the thread again.
