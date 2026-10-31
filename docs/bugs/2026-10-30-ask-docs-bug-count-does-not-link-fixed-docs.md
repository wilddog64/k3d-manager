# Bug: ask-docs bug count does not link the fixed docs it counted

**Status:** LIVE-VERIFIED 2026-10-31 — E1 green 2026-10-30 (test_bug_count.py 59/59; the two link tests red on the pre-fix module); E2 live on the M5 webhook (restarted 14:36Z on checkout `4f409ba6`): `/ask-docs how many bugs in v1.43.5` in #acg-automation (job `341fb904`, threaded) listed the open docs, then `Fixed:` Slack links for the fixed docs. The question named the release but no priority, so it proves M1 for a named release rather than the P1-only count E2 names.
**Fix commit:** 88e35118
**Live evidence:** 2026-10-31 · run 341fb904 · env m5-air-webhook · scenario ask-docs-named-release-bug-count-fixed-links · commit 4f409ba6 · proves E2
**Live note:** the reply hit `MAX_REPLY_CHARS` after seven `Fixed:` lines and ended with the wrong "name a release" hint; filed as `docs/bugs/2026-10-31-ask-docs-bug-count-truncation-hides-fixed-cap-and-misadvises.md`.
**Priority:** P3
**Approval:** Claude-owned small defect fix (operator trial week of 10-26: Claude fixes small review defects itself)
**Filed:** 2026-10-30
**Detected by:** operator (`/ask-docs` P1 count for v1.43.5 in Slack)
**Affected:** `scripts/lib/webhook/bug_count.py` `reply()`
**Branch:** `k3d-manager-v1.43.12`

## Observed failure

`/ask-docs` asked for the P1 bug count in v1.43.5. The reply `v1.43.5: 6 P1 bug docs — 6 fixed, 0 open, 0 with no Status line.` was correct, but it named none of the six docs. The only other line was `Sources: none`, so the operator could not open the docs behind the number.

## Root cause

`reply()` listed only `open_paths` and `unknown_paths`, as Slack links. The tally already returns `closed_paths`, including in `--counts-only` mode, but `reply()` never used them. A release where every doc is fixed therefore gave a count with nothing to click.

## Fix

For a named release or a last-N window, when the question does not ask for open bugs only, `reply()` adds a `Fixed: <link>` line per closed doc. The list is filtered by priority when one is asked, and capped at 10 per release with `…and N more fixed.` An all-releases count (`*`) and an open-only question still list no fixed docs, which keeps those replies short.

## Acceptance

```yaml
must:
  M1: A bug-count reply for a named release links each fixed doc of the asked priority as a Slack link.
  M2: More than ten fixed docs are capped at ten links plus an "and N more fixed" line.
must_not:
  N1: Fixed docs of another priority are not linked when a priority is asked.
  N2: An open-only question and an all-releases count list no fixed docs.
evidence:
  E1: {proves: [M1, M2, N1, N2], kind: offline, what: "pytest scripts/tests/bin/test_bug_count.py; the M1/M2 tests red on the pre-fix module"}
  E2: {proves: [M1], kind: live, what: "after make restart-webhook, /ask-docs how many P1 bugs in v1.43.5 in #acg-automation lists six linked Fixed lines"}
interface:
  - webhook.bug_count.reply(CountQuery(release, priority, state))
  - /ask-docs <count question>
```
