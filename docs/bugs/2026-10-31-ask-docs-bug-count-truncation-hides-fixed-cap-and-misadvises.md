# Bug: an ask-docs bug count for a named release is cut by the reply limit, losing the "more fixed" line and telling the operator to name a release they already named

**Status:** OPEN
**Priority:** P3
**Severity:** low — the count line is correct; some links are lost and the closing hint is wrong
**Approval:** operator, 2026-10-31 ("go ahead to file a P3 for what you found")
**Filed:** 2026-10-31
**Detected by:** Claude, reading the live E2 reply for `docs/bugs/2026-10-30-ask-docs-bug-count-does-not-link-fixed-docs.md`
**Affected:** `scripts/lib/webhook/ask_docs.py` (`MAX_REPLY_CHARS`, `TRUNCATION_MARKER`), `scripts/lib/webhook/bug_count.py` `reply()`
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-30-ask-docs-bug-count-does-not-link-fixed-docs.md` (added the `Fixed:` lines and the cap of 10); `docs/bugs/2026-10-22-ask-docs-reply-truncated-mid-slack-link.md` (added the line-boundary cut and the marker)

## Observed failure

`/ask-docs how many bugs in v1.43.5` in #acg-automation (job `341fb904`, M5 webhook at `4f409ba6`, 2026-10-31 07:37 PDT) replied with the count, the six `Open:` lines, then seven `Fixed:` lines and:

    …(truncated; name a release to see the full list)

The output was 2868 bytes. The question already named a release, so the hint is wrong. The `…and N more fixed.` line that `bug_count.reply()` writes after its tenth `Fixed:` line never reached Slack, so the operator cannot tell how many fixed docs were dropped.

## Root cause

`bug_count.reply()` caps fixed links at 10 per release, but each line is a full Slack link (`<https://github.com/...|docs/bugs/...>`), roughly 150 characters. Six open plus ten fixed lines exceed `MAX_REPLY_CHARS = 3000` in `ask_docs.py`, so the generic truncation cuts at a line boundary and appends `TRUNCATION_MARKER`. That marker was written for the all-releases tally, where naming a release is the right advice. A named-release count is already as narrow as a release can be.

## Fix

1. `bug_count.reply()` sizes its own list: it keeps whole `Open:`/`Fixed:` lines while they fit the reply budget, and always ends with an exact `…and N more fixed.` (and `…and N more open.` when open lines are dropped). The ask-docs truncation never fires for a bug-count reply.
2. The truncation marker is chosen by the caller. A named-release reply that still has to be cut says `…(truncated; add a priority, e.g. "P2 bugs in v1.43.5", to narrow it)`. The existing marker stays for the all-releases tally.

## Acceptance

```yaml
must:
  - id: M1
    text: a named-release bug count whose full link list exceeds MAX_REPLY_CHARS ends with an exact "…and N more fixed." line, where N equals the fixed docs not listed
  - id: M2
    text: open lines are listed before fixed lines and dropped last; when any are dropped the reply ends with "…and N more open."
  - id: M3
    text: the count line (N bug docs — X fixed, Y open) is unchanged and always present
must_not:
  - id: N1
    text: a reply for a named release never contains "name a release to see the full list"
  - id: N2
    text: no reply exceeds MAX_REPLY_CHARS and no Slack link is cut mid-link
  - id: N3
    text: the all-releases tally still uses "…(truncated; name a release to see the full list)" when it is cut (paired control for N1)
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: pytest in scripts/tests/bin/test_bug_count.py with a v1.43.5-sized fixture (6 open, 81 fixed, real-length link URLs); M1 and N1 red on the pre-fix modules
  - id: E2
    proves: [M1, N1]
    kind: live
    text: after make restart-webhook, /ask-docs how many bugs in v1.43.5 in #acg-automation ends with "…and N more fixed." and no "name a release" hint
interface:
  - webhook.bug_count.reply(CountQuery(release, priority, state))
  - /ask-docs <count question>
```
