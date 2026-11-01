# Bug: ask-docs bug counts read the hub checkout's HEAD, which goes stale, instead of the fetched upstream ref

**Status:** OPEN
**Priority:** P2
**Severity:** medium — the Slack bot gives wrong bug counts whenever the hub checkout is behind; workaround is a manual `git pull` on the hub
**Approval:** operator, 2026-10-31 ("go ahead to file the bug and dispatch it")
**Filed:** 2026-10-31
**Detected by:** operator (Slack screenshot), root cause by Claude
**Affected:** `scripts/lib/webhook/bug_count.py`
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-09-30-vectordb-index-never-refreshes-automatically.md` (Hermes resolves the index ref from `@{upstream}` and fetches it every cycle); `docs/bugs/2026-10-10-ask-docs-bug-count-ignores-release-range.md`

## Observed failure

On 2026-10-31 the Slack ask-docs bot answered "v1.43.13: 0 P2 bug docs" while `origin/k3d-manager-v1.43.13`
held two P2 bugs. The M5 hub's checkout was at `087b87fc`; `origin` was at `85d5e7bb`. After a manual
fast-forward on the M5 the bot answered 2.

## Root cause

`bug_count.reply()` runs `bug-tally.py --ref "$K3DM_INDEX_REF"`, falling back to `HEAD`
(`scripts/lib/webhook/bug_count.py:118`). The webhook never sets `K3DM_INDEX_REF`, so it always counts the
checkout's HEAD. Claude pushes from the M4, and nothing moves the M5's HEAD. Hermes already fetches
`origin/<branch>` every cycle (`bin/k3dm-hermes` `_index_ref`, `git fetch origin <branch>`), so a current ref is on
disk; the bug count just does not use it.

## Fix

1. When `K3DM_INDEX_REF` is unset, `bug_count.reply()` resolves the ref the way Hermes `_index_ref` does:
   `git rev-parse --abbrev-ref @{upstream}` in the repo root (for example `origin/k3d-manager-v1.43.13`). An
   explicit `K3DM_INDEX_REF` still wins.
2. When there is no upstream (detached HEAD, no tracking branch, or git fails or times out), fall back to `HEAD`
   as today, and the reply says so in one line: `Counted at local HEAD (no upstream).`
3. The current-release logic (`_current_release`) keeps working with an `origin/<branch>` ref (it already strips
   `origin/`).
4. No network call in the request path: do not `git fetch` from the webhook. Freshness comes from the Hermes fetch.

## Files

- `scripts/lib/webhook/bug_count.py`
- `scripts/tests/bin/test_bug_count.py`
- `CHANGELOG.md`

## What NOT to do

- Do not fetch, pull or otherwise change the checkout from the webhook.
- Do not change `bin/k3dm-hermes` or `scripts/bug-tally.py` ref defaults.

## Acceptance

```yaml
must:
  M1: with K3DM_INDEX_REF unset and the checkout behind its upstream, the reply counts the bugs at the upstream ref, not at HEAD
  M2: an explicit K3DM_INDEX_REF is used as given
  M3: with no upstream, the reply counts at HEAD and says "Counted at local HEAD (no upstream)."; with an upstream, that line is absent (paired)
must_not:
  N1: a checkout whose HEAD is behind its upstream never produces a count taken from HEAD when K3DM_INDEX_REF is unset
  N2: answering a count never runs git fetch, pull, merge, reset or checkout, and never moves HEAD
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see a scratch upstream with two P2 bugs and a clone whose HEAD is one commit behind with zero P2 bugs,
      its remote-tracking ref already fetched. The fixture first asserts the repo root under test is the scratch clone,
      not the real tree. The reply says 2 P2 at the upstream and 0 only when K3DM_INDEX_REF=HEAD is set explicitly;
      the clone's HEAD and reflog are unchanged after the call, and a git wrapper logs no fetch/pull/merge/reset/checkout.
      N1 is red against the pre-fix code (it answers 0).
    what: pytest -q scripts/tests/bin/test_bug_count.py
  E2:
    proves: [M1]
    kind: live
    intent: >-
      You will see, after a push from the M4 that adds a bug doc and before anyone pulls on the M5, the Slack bot's
      count include the new bug once Hermes has fetched.
    what: operator or Claude, Slack ask-docs on the M5 hub
interface:
  - webhook.bug_count.reply(query) (env K3DM_INDEX_REF; repo root resolved from the module path)
  - scripts/bug-tally.py --ref REF
```
