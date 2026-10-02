# `/ask-docs` cannot answer "what's recent": retrieval has no notion of date

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. The answer looks authoritative but is wrong for the question. Asked for recent
Slack/webhook issues, `/ask-docs` cited five docs dated 2026-06-04 to 2026-08-18. The same day it
was asked had three Slack/webhook incidents filed.
**Status:** OPEN
**Related:** `2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`

## Observed (operator, 2026-10-01)

Question: `what's recent issue regarding to slack and webhook issues`. The answer's sources:

```
docs/issues/2026-07-01-slack-cluster-status-no-response.md
docs/issues/2026-08-18-slack-thread-agent-allowlist-missing.md
docs/issues/2026-06-04-slack-slash-commands-wrong-url.md
docs/bugs/2026-06-19-codex-slack-banner-echoes-prompt.md
docs/bugs/2026-06-08-thread-reply-triggers-unknown-command.md
```

Claude reproduced it against the live index:
- `k3dm-vectordb-status`: 1751/1753 rows, last indexed minutes earlier, so the index is current.
- `prior_art.search(question, k=30)`: the top 30 scores sit in a narrow band (0.692–0.752).
- `docs/bugs/2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md` ranks **6th**,
  just outside `k=5`.
- `2026-10-01-no-safe-way-to-set-github-actions-secrets.md`, the Slack outage, does not make
  the top 30.

## Cause

`ask_docs.answer` calls `prior_art.search(question, k=5)`, which is pure cosine similarity. The
excerpt handed to the summary model is `Title: …` plus the first 600 chars, so the model sees no
reliable date either. "Recent" in the question only shifts the embedding slightly; nothing ranks or
filters by date.

## Fix

Only `scripts/lib/webhook/ask_docs.py` and `scripts/tests/bin/test_ask_docs.py` change. Do **not**
touch `CHANGELOG.md` (Claude adds the bullet; parallel Codex runs edit it). Do not touch
`bin/k3dm-webhook`, `prior_art.py`, the index schema, or the relay.

1. **Doc date.** Add `_doc_date(path) -> str | None`, returning an ISO date:
   1. The basename starts with `YYYY-MM-DD-` → that date.
   2. Else, the first 40 lines contain `**Filed:** YYYY-MM-DD` → that date.
   3. Else `None`.
   - Read through the same `REPO_ROOT` resolution and `_allowed_path` check as `_excerpt`, and
     never raise.
2. **Recency intent.** Add `_wants_recent(question) -> bool`, a case-insensitive word match on:
   `recent`, `recently`, `latest`, `newest`, `last week`, `this week`, `today`, `yesterday`,
   `lately`, `new`.
   - Use a module-level precompiled regex with `\b` boundaries, so `renewal` and `newsletter` do
     not match.
3. **Recency retrieval** in `answer`, when `_wants_recent(question)` is true:
   - Call `retrieve(question, k=RECENT_POOL)`, with `RECENT_POOL = 50`.
   - Keep the rows at or above `ASK_DOCS_MIN_SCORE` that pass `_allowed_path`.
   - Sort them by `_doc_date` descending; undated rows go last, ordered by score. Take the first
     `k`, then feed them into the existing `_sources` and summary path unchanged.
   - When it is false, behaviour stays byte-identical to today: `retrieve(question, k=k)`, score
     order.
4. **Dates visible to the model and the reader:**
   - `_excerpt` prefixes `Date: <date>` when it is known: `Title: …\nDate: 2026-10-01\n…`.
   - The `--sources` lines become `<score:.2f>  <date or ->  <path> — <title>`.
   - When recency mode is active, add one line to the prompt: "The user asked for recent items;
     excerpts are ordered newest first — lead with the newest and state each item's date."
5. Floor, allowlist, redaction, the 3000-char cap, and the no-match/unavailable replies are
   unchanged.

## Tests (`scripts/tests/bin/test_ask_docs.py`; stub `retrieve` and `model`, temp repo root)

- `_doc_date`:
  - a dated filename → its date;
  - an undated `v1.40.0-x.md` with a `**Filed:** 2026-09-24` line → `2026-09-24`;
  - neither → `None`;
  - a path outside `RETURNABLE_DIRS` → `None`.
- `_wants_recent`: true for `recent`, `latest`, `this week`; false for `renewal`,
  `newsletter`, and a question with none of the words.
- Recency mode:
  - The stub `retrieve` asserts `k == 50`. It returns old docs with high scores and a
    2026-10-01 doc with a lower but above-floor score.
  - The 2026-10-01 doc is the first source.
  - A below-floor new doc is still excluded.
- Non-recency question: `retrieve` is called with `k=5`, and source order equals score order, the
  same as before.
- The excerpt sent to the model contains `Date: 2026-10-01`. The `--sources` line shows the date.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) skip the date sort → recency test red;
(b) drop the floor filter in recency mode → floor test red;
(c) make `_wants_recent` a substring match → the `renewal` test red.

## Rules

- `pytest scripts/tests/bin/test_ask_docs.py scripts/tests/bin/test_webhook_ask_delivery.py` is
  green.
- `python3 -m py_compile scripts/lib/webhook/ask_docs.py` passes.
- No network and no real model.
- Leave changes uncommitted. Update this doc: Status FIXED and a short Resolution section.

## Operator step after the fix

Run `make restart-webhook`, then ask the same question again; the 2026-10-01 docs should lead.
