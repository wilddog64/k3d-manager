# Bug: `/ask-docs` "latest bugs fixed" misses every recent fix; answers render `**bold**` literally

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.42.0`
**Severity:** low. `/ask-docs` confidently answers a "what's recent" question with week-old
documents, so the reader believes nothing newer was fixed.
**Status:** FIXED — `/ask-docs` now enumerates recent kind-specific documents by date and converts CommonMark bold for Slack.

## Observed (operator, Slack, 2026-10-09)

`/ask-docs what is the latest bugs fixed` answered, in its thread:

1. `2026-10-01-ask-docs-ignores-recency.md` (2026-10-01)
2. `2026-09-24-hostinger-registration-resets-shopping-cart-label.md` (2026-09-24)

and noted two 2026-10-08 v1.43.0 *plans* as "queued, not fixed". Meanwhile `docs/bugs/` holds
dozens of 2026-10-07 … 2026-10-09 docs whose status is `FIXED` or `VERIFIED`, including five
verified live that same day. Every one of them is indexed (`make find-similar-docs` returns
`2026-10-07-ask-docs-redacts-iso-dates-as-phone.md` at 0.881 for its own symptom).

Separately, the answer showed `**FIXED**`, `**Date:**` etc. with literal asterisks: the model
writes CommonMark bold, and Slack mrkdwn bolds with a single `*`.

## Cause

### 1. The recency path only re-orders a semantic pool

`answer()` in `scripts/lib/webhook/ask_docs.py`, when `_wants_recent(question)`:

```python
results = retrieve(question, k=RECENT_POOL if recent else k)   # RECENT_POOL = 50
...
dated.sort(key=lambda result: _doc_date(result[1]), reverse=True)
results = (dated + undated)[:k]
```

The pool is the 50 documents *most similar to the wording of the question*. A question with no
symptom in it ("latest bugs fixed") is closest to retrospectives, which talk about "bugs" and
"fixed" in general. Measured 2026-10-09 against the live store
(`prior_art.search("what is the latest bugs fixed", k=50)`):

| directory | docs in the pool of 50 |
|---|---|
| `docs/retro` | 33 |
| `docs/plans` | 11 |
| `docs/bugs` | 5 |
| `docs/issues` | 1 |

All 50 scored 0.636–0.69, above `ASK_DOCS_MIN_SCORE`. The date sort then picked the newest of
those, and the newest bug doc in the pool was 2026-10-01. Recent bug docs were never candidates,
so no re-ordering could surface them. `2026-10-01-ask-docs-ignores-recency.md` fixed ordering,
not candidate selection; its own tests used a stubbed pool that already contained the newest docs.

### 2. No Slack formatting pass

`_reply()` returns the model prose unchanged apart from redaction, so `**x**` reaches Slack.

## Fix (Codex)

All code changes are in `scripts/lib/webhook/ask_docs.py`.

### A. Enumerate by date when the question names a document kind

1. Add a kind map and a status filter:

   ```python
   _KIND_DIRS = (
       (re.compile(r"\bbugs?\b", re.IGNORECASE), "docs/bugs/"),
       (re.compile(r"\bissues?\b", re.IGNORECASE), "docs/issues/"),
       (re.compile(r"\b(?:plans?|specs?)\b", re.IGNORECASE), "docs/plans/"),
       (re.compile(r"\b(?:retros?|retrospectives?)\b", re.IGNORECASE), "docs/retro/"),
   )
   _DONE_INTENT_RE = re.compile(r"\b(?:fixed|resolved|closed|verified|done)\b", re.IGNORECASE)
   _STATUS_RE = re.compile(r"^\*\*Status:\*\*\s*(.*)$")
   _DONE_STATUS_RE = re.compile(r"^(?:FIXED|VERIFIED|LIVE-VERIFIED|RESOLVED|CLOSED|DONE)\b", re.IGNORECASE)
   ```

2. Add `_recent_docs(question, limit)`:
   - Directories = every `_KIND_DIRS` entry whose regex matches the question. If none match,
     return `[]` (the caller keeps today's semantic behaviour).
   - Enumerate `REPO_ROOT / <dir>` `*.md` files (non-recursive), as repo-relative POSIX paths.
     Keep only paths where `_allowed_path(path)` is true and `_doc_date(path)` is not `None`.
   - If `_DONE_INTENT_RE` matches the question, keep only docs whose first `**Status:**` line in
     the first 40 lines matches `_DONE_STATUS_RE` on its value. A doc with no Status line is dropped
     in this mode.
   - Sort by `(_doc_date(path), path)` descending; return the first `limit` as tuples
     `(None, path, title)`, where `title` is the text of the first `# ` heading line (without the
     `# ` and an optional leading `Bug: `), or the file stem if there is none.
   - Any `OSError` reading a file skips that file; never raises.

3. In `answer()`, when `recent` is true, call `_recent_docs(question, k)` **before** retrieval.
   If it returns a non-empty list, use it as `results` and do **not** call `retrieve` at all
   (the date-enumerated answer does not need the store, so it also works when the store is down).
   If it returns `[]`, keep the existing path exactly.

4. `score is None` means "selected by date". Make it flow through:
   - `_sources`: a `None` score passes the threshold check.
   - `--sources` mode line: print `date` in place of `f"{score:.2f}"` when the score is `None`,
     and apply the same `None`-passes rule in its filter.

5. Prompt: when results came from `_recent_docs`, the recent note becomes:
   `"The user asked for recent items; these are the newest matching documents, newest first. List each with its date and one-line summary. Do not say there are no newer items — only these were provided.\n\n"`

### B. Slack bold

In `_reply()`, after scrubbing and before truncation, when `scrub_prose` is true, convert
CommonMark bold to Slack bold: `re.sub(r"\*\*(\S(?:.*?\S)?)\*\*", r"*\1*", prose)`.
Apply it to the model prose only (the `scrub_prose=True` path); the `--sources` listing is
already plain.

## Tests — `scripts/tests/bin/test_ask_docs.py`

Use a `tmp_path` repo root (follow `test_all_reply_shapes_keep_sources_and_redact_excerpt_and_answer`,
including restoring `ask_docs.REPO_ROOT`), with docs in `docs/bugs/`, `docs/retro/`, `docs/plans/`:

1. **Recent bugs fixed, not in any semantic pool.** Bugs dated 2026-10-09 (`**Status:** VERIFIED live …`),
   2026-10-08 (`**Status:** FIXED`), 2026-10-08 (`**Status:** OPEN`), 2026-10-01 (`FIXED`);
   a 2026-10-09 retro. `retrieve` is a stub that **fails the test if called**.
   `answer("what is the latest bugs fixed", model=capture)`: sources are exactly the 2026-10-09 and
   2026-10-08 FIXED bug and the 2026-10-01 bug, in that order; the OPEN bug and the retro are absent.
2. **Kind without done-intent** keeps OPEN docs: `"latest bugs"` includes the OPEN bug.
3. **No kind word** (`"what changed recently with argocd"`) calls `retrieve` with `k=RECENT_POOL`
   and behaves as before (existing recency test keeps passing).
4. **`--sources` mode** (`summarise=False`) for `"latest bugs fixed"` prints `date` rows, no float score.
5. **Bold**: a model returning `"**FIXED** and **Date:** x"` yields prose containing
   `*FIXED* and *Date:* x` and no `**`.
6. **Mutation check (record in the commit body):** with step A.3 reverted to always call
   `retrieve`, test 1 fails.

## Docs

`docs/guides/slack-corpus-qa.md`: in the recency paragraph, state that a question naming a
document kind (bugs, issues, plans/specs, retros) lists the newest documents of that kind by date,
and that "fixed"/"verified"/"resolved" narrows to done statuses; other recent questions still
rank by similarity then date. One short paragraph, no new section.

CHANGELOG `[Unreleased]` → `### Fixed`: one entry.

## Files

| File | Change |
|---|---|
| `scripts/lib/webhook/ask_docs.py` | A and B |
| `scripts/tests/bin/test_ask_docs.py` | tests 1–5 |
| `docs/guides/slack-corpus-qa.md` | one paragraph |
| `CHANGELOG.md` | one entry |
| this bug doc | Status → `FIXED — <one line>` |

Nothing else.

## Definition of Done

- [ ] `PYTHONPATH=scripts/lib python3 -m pytest scripts/tests/bin/test_ask_docs.py scripts/tests/bin/test_webhook_ask_docs_thread.py -q` passes; paste the summary line.
- [ ] `make test-pytest` passes; paste the summary line.
- [ ] Mutation check from test 6 done and its result in the commit body.
- [ ] Commit message (exact first line):
  ```
  fix(ask-docs): list newest docs by date for "latest bugs" questions; Slack bold

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.42.0`; `git ls-remote origin k3d-manager-v1.42.0` equals `git rev-parse HEAD`.

## What NOT to do

- Do NOT create a PR or merge; do NOT commit to `main`; do NOT use `--no-verify`.
- Do NOT modify files outside the table above. Do NOT change `RECENT_POOL`, `ASK_DOCS_MIN_SCORE`,
  `prior_art.py`, the relay, or `bin/k3dm-webhook`.
- Do NOT start or restart the webhook, call `:7443`, query the vector store, read Keychain items,
  or run any `make` lifecycle target or `make -n`.
- Do NOT update memory-bank.
